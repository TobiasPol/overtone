import AppKit
import CoreAudio

/// Forwards Core Audio hardware notifications (and system wake) to the engine.
@MainActor
final class AudioSystemMonitor {
    var onDevicesChanged: (() -> Void)?
    var onDefaultOutputChanged: (() -> Void)?
    var onProcessesChanged: (() -> Void)?
    var onOutputFormatChanged: (() -> Void)?
    var onWake: (() -> Void)?

    private var systemListeners: [AudioPropertyListener] = []
    private var outputListeners: [AudioPropertyListener] = []
    private var wakeObserver: NSObjectProtocol?

    func start() {
        systemListeners = [
            listen(.system, kAudioHardwarePropertyDevices) { $0.onDevicesChanged?() },
            listen(.system, kAudioHardwarePropertyDefaultOutputDevice) { $0.onDefaultOutputChanged?() },
            listen(.system, kAudioHardwarePropertyProcessObjectList) { $0.onProcessesChanged?() },
        ].compactMap(\.self)
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
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
