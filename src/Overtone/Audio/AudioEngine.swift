import CoreAudio
import Foundation
import Observation
import OvertoneDSP

/// What the parameter builder needs to know about the running pipeline.
struct EngineContext: Equatable {
    var sampleRate: Double
    var tapKeys: [String]
    var outputLeft: Int
    var outputRight: Int

    static let idle = EngineContext(
        sampleRate: 48_000, tapKeys: [ProcessTap.globalKey], outputLeft: 0, outputRight: 1
    )
}

/// Owns the capture pipeline lifecycle: permission, device following,
/// debounced rebuilds and health checks. All state changes happen on the main actor.
@MainActor @Observable
final class AudioEngine {
    enum Status: Equatable {
        case off, starting, running, awaitingPermission, permissionDenied, failed(String)
    }

    private(set) var status: Status = .off {
        didSet {
            let current = String(describing: status)
            if status != oldValue { Log.engine.notice("Status: \(current, privacy: .public)") }
        }
    }
    private(set) var isEnabled = false
    private(set) var context = EngineContext.idle
    var devices: [AudioDevice] = []
    var outputDevice: AudioDevice?

    @ObservationIgnored let dsp = DSPCore()
    /// Builds a full parameter snapshot for the given pipeline context.
    @ObservationIgnored var paramsProvider: ((EngineContext) -> ot_params)?
    /// Apps that currently need their own tap (custom per-app volume).
    @ObservationIgnored var appTapProvider: (() -> [AppTapRequest])?
    /// Called with the new sample rate after the DSP is prepared, before IO starts.
    @ObservationIgnored var willStart: ((Double) -> Void)?
    @ObservationIgnored var outputDeviceChanged: ((AudioDevice) -> Void)?

    @ObservationIgnored private var pipeline: AudioPipeline?
    @ObservationIgnored private let monitor = AudioSystemMonitor()
    @ObservationIgnored private var rebuildWork: DispatchWorkItem?
    @ObservationIgnored private var processWork: DispatchWorkItem?
    @ObservationIgnored private var ownProcessRetries = 0
    @ObservationIgnored private var healthRetries = 0
    /// Incremented per launched pipeline so stale health checks can't tear down a newer one.
    @ObservationIgnored private var generation = 0

    func activate() {
        monitor.onDevicesChanged = { [weak self] in self?.refreshDevices() }
        monitor.onDefaultOutputChanged = { [weak self] in self?.refreshDevices() }
        monitor.onProcessesChanged = { [weak self] in self?.scheduleProcessSync() }
        monitor.onOutputFormatChanged = { [weak self] in self?.scheduleRebuild() }
        monitor.onWake = { [weak self] in self?.scheduleRebuild(delay: 1.5) }
        monitor.start()
        refreshDevices()
    }

    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        if enabled {
            resetRetries()
            startWithPermission()
        } else {
            teardown()
            status = .off
        }
    }

    /// Screenshot support (`--snapshot`): presents a running state without starting audio.
    func showSnapshotState(device: AudioDevice, sampleRate: Double) {
        outputDevice = device
        devices = [device]
        context.sampleRate = sampleRate
        status = .running
    }

    func retry() {
        guard isEnabled else { return }
        resetRetries()
        startWithPermission()
    }

    private func resetRetries() {
        ownProcessRetries = 0
        healthRetries = 0
    }

    /// Re-sends the current settings to the audio thread.
    func publishParameters() {
        guard let paramsProvider else { return }
        dsp.publish(paramsProvider(context))
    }

    func scheduleRebuild(delay: TimeInterval = 0.25) {
        guard isEnabled, status != .permissionDenied, status != .awaitingPermission else { return }
        rebuildWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.rebuild() }
        rebuildWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    /// Re-evaluates which processes belong to which tap (apps launched, quit, or changed volume).
    func syncProcesses() {
        guard let pipeline, status == .running else { return }
        if !pipeline.update(appTaps: currentAppTaps()) {
            scheduleRebuild()
        }
    }

    // MARK: - Devices

    func refreshDevices() {
        devices = AudioDevice.outputDevices()
        let defaultID = AudioDevice.defaultOutputID()
        let current = devices.first { $0.id == defaultID } ?? AudioDevice.make(defaultID)
        guard current?.id != outputDevice?.id || current?.uid != outputDevice?.uid else { return }
        outputDevice = current
        healthRetries = 0
        if let current { outputDeviceChanged?(current) }
        scheduleRebuild()
    }

    /// Makes `device` the system output; the default-device listener then moves the pipeline.
    func selectOutput(_ device: AudioDevice) {
        do {
            try AudioDevice.setDefaultOutput(device)
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    // MARK: - Pipeline

    private func startWithPermission() {
        switch AudioCapturePermission.state {
        case .authorized:
            rebuild()
        case .denied:
            status = .permissionDenied
        case .undetermined:
            status = .awaitingPermission
            AudioCapturePermission.request { [weak self] granted in
                guard let self, isEnabled else { return }
                if granted { rebuild() } else { status = .permissionDenied }
            }
        }
    }

    private func rebuild() {
        rebuildWork?.cancel()
        teardown()
        guard isEnabled else { return }
        // Re-read the device: its channel layout can change under the same ID (e.g. Bluetooth profiles).
        guard let output = outputDevice.flatMap({ AudioDevice.make($0.id) }) ?? AudioDevice.defaultOutput() else {
            status = .failed("No output device available")
            return
        }
        outputDevice = output
        // Without our own process object the global tap would capture our output (feedback),
        // so wait for the HAL to register us rather than start unsafely.
        let own = AudioProcessCatalog.ownProcessObject()
        guard own != .unknown else {
            ownProcessRetries += 1
            status = ownProcessRetries > 5 ? .failed("Could not identify Overtone's own audio process") : .starting
            if ownProcessRetries <= 5 { scheduleRebuild(delay: 0.5) }
            return
        }
        ownProcessRetries = 0
        status = .starting
        do {
            try launch(output: output, ownProcess: own)
            status = .running
            monitor.watchOutput(output.id)
            scheduleHealthCheck()
        } catch {
            teardown()
            status = .failed(error.localizedDescription)
        }
    }

    private func launch(output: AudioDevice, ownProcess: AudioObjectID) throws {
        let pipe = try AudioPipeline(output: output, ownProcess: ownProcess, appTaps: currentAppTaps(), dsp: dsp)
        pipeline = pipe
        generation += 1
        context = EngineContext(
            sampleRate: pipe.sampleRate, tapKeys: pipe.tapKeys,
            outputLeft: pipe.outputChannels.left, outputRight: pipe.outputChannels.right
        )
        dsp.prepare(sampleRate: pipe.sampleRate)
        willStart?(pipe.sampleRate)
        publishParameters()
        try pipe.start()
    }

    private func teardown() {
        pipeline?.stop()
        pipeline = nil
        monitor.watchOutput(nil)
    }

    private func currentAppTaps() -> [AppTapRequest] {
        (appTapProvider?() ?? []).filter { !$0.processes.isEmpty }
    }

    private func scheduleProcessSync() {
        processWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.syncProcesses() }
        processWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    /// The aggregate uses tap auto-start: IO only begins once an app actually plays, so a
    /// pipeline with no cycles is only broken if something is playing. Outputs such as AirPlay
    /// accept the aggregate but never run it; slow devices (Bluetooth after wake) get retries.
    private func scheduleHealthCheck(after delay: TimeInterval = 2.5, stalledBefore: Bool = false) {
        let baseline = dsp.cycleCount
        let expected = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, expected == generation, status == .running else { return }
            guard dsp.cycleCount == baseline else {
                healthRetries = 0
                let cycles = dsp.cycleCount
                Log.engine.notice("Audio is flowing (\(cycles) IO cycles)")
                return
            }
            guard AudioProcessCatalog.isAnyOtherProcessPlaying() else {
                scheduleHealthCheck(after: 3) // idle: waiting for the first audio is expected
                return
            }
            if stalledBefore {
                handleStalledPipeline()
            } else {
                scheduleHealthCheck(after: 1.5, stalledBefore: true) // playback may have just begun
            }
        }
    }

    private func handleStalledPipeline() {
        teardown()
        if healthRetries < 2 {
            healthRetries += 1
            status = .starting
            scheduleRebuild(delay: Double(healthRetries) * 2)
        } else {
            healthRetries = 0
            let name = outputDevice?.name ?? "This output"
            status = .failed("\(name) didn't start processing. Try another output device.")
        }
    }
}
