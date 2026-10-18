import Foundation

struct AppVolume: Codable, Equatable, Sendable {
    var volume = 1.0
    var isMuted = false

    var gain: Double { isMuted ? 0 : volume }
}

struct MixerSettings: Codable, Equatable, Sendable {
    /// Keyed by app bundle identifier.
    var apps: [String: AppVolume] = [:]
}

/// A hosted Audio Unit as it is persisted between launches.
struct PluginSlotConfig: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    var componentType: UInt32
    var componentSubType: UInt32
    var manufacturer: UInt32
    var name: String
    var manufacturerName: String
    var isBypassed = false
    var state: Data?
}

enum AppSection: String, Codable, CaseIterable, Identifiable, Sendable {
    case equalizer, effects, headphones, mixer, plugins

    var id: String { rawValue }

    var label: String {
        switch self {
        case .equalizer: return "Equalizer"
        case .effects: return "Effects"
        case .headphones: return "Headphones"
        case .mixer: return "Mixer"
        case .plugins: return "Plugins"
        }
    }

    var symbolName: String {
        switch self {
        case .equalizer: return "slider.vertical.3"
        case .effects: return "cube.transparent"
        case .headphones: return "headphones"
        case .mixer: return "square.stack.3d.up"
        case .plugins: return "puzzlepiece.extension"
        }
    }
}

enum AccentChoice: String, Codable, CaseIterable, Identifiable, Sendable {
    case system, blue, purple, pink, red, orange, yellow, green, mint, teal

    var id: String { rawValue }
}

struct GeneralSettings: Codable, Equatable, Sendable {
    var rememberPerDevice = true
    var showAnalyzer = true
    var accent: AccentChoice = .system
    var hiddenSections: Set<AppSection> = []
    var selectedSection: AppSection = .equalizer
}

/// Auto mode: picks a built-in preset for what is playing.
struct AutoPresetSettings: Codable, Equatable, Sendable {
    var isEnabled = false
    /// Trust Music.app's genre tag while Music is the only app playing.
    var useMusicAppGenre = true
}

/// Equalizer and headphone correction remembered for one output device.
struct DeviceProfile: Codable, Equatable, Sendable {
    var equalizer: EqualizerSettings
    var correction: HeadphoneCorrection
}
