import AppKit
import CoreAudio

/// Forwards Core Audio hardware notifications (and system wake) to the engine.
@MainActor
final class AudioSystemMonitor {
    var onDevicesChanged: (() -> Void)?
    var onDefaultOutputChanged: (() -> Void)?
    var onProcessesChanged: (() -> Void)?
    var onOutputFormatChanged: (() -> Void)?
    var onSleep: (() -> Void)?
    var onWake: (() -> Void)?

    private var systemListeners: [AudioPropertyListener] = []
    private var outputListeners: [AudioPropertyListener] = []
    private var sleepObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?

    deinit {
        let nc = NSWorkspace.shared.notificationCenter
        if let sleepObserver { nc.removeObserver(sleepObserver) }
        if let wakeObserver { nc.removeObserver(wakeObserver) }
    }

    func start() {
        systemListeners = [
            listen(.system, kAudioHardwarePropertyDevices) { $0.onDevicesChanged?() },
            listen(.system, kAudioHardwarePropertyDefaultOutputDevice) { $0.onDefaultOutputChanged?() },
            listen(.system, kAudioHardwarePropertyProcessObjectList) { $0.onProcessesChanged?() },
        ].compactMap(\.self)
        let nc = NSWorkspace.shared.notificationCenter
        sleepObserver = nc.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.onSleep?() }
        }
        wakeObserver = nc.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.onWake?() }
        }
    }

    /// Watches the device currently used for playback for format changes or removal.
    func watchOutput(_ device: AudioObjectID?) {
        outputListeners = []
        guard let device else { return }
        outputListeners = [
            listen(device, kAudioDevicePropertyNominalSampleRate) { $0.onOutputFormatChanged?() },
            listen(device, kAudioDevicePropertyDeviceIsAlive) { $0.onOutputFormatChanged?() },
            listen(device, kAudioDevicePropertyStreamConfiguration, scope: kAudioObjectPropertyScopeOutput) {
                $0.onOutputFormatChanged?()
            },
            listen(device, kAudioDevicePropertyPreferredChannelsForStereo, scope: kAudioObjectPropertyScopeOutput) {
                $0.onOutputFormatChanged?()
            },
        ].compactMap(\.self)
    }

    private func listen(
        _ object: AudioObjectID, _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
        _ action: @escaping (AudioSystemMonitor) -> Void
    ) -> AudioPropertyListener? {
        AudioPropertyListener(object: object, selector: selector, scope: scope) { [weak self] in
            MainActor.assumeIsolated {
                if let self { action(self) }
            }
        }
    }
}
