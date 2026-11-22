import SwiftUI

extension AccentChoice {
    var color: Color? {
        switch self {
        case .system: return nil
        case .blue: return .blue
        case .purple: return .purple
        case .pink: return .pink
        case .red: return .red
        case .orange: return .orange
        case .yellow: return .yellow
        case .green: return .green
        case .mint: return .mint
        case .teal: return .teal
        }
    }

    var label: String { rawValue.capitalized }
}

/// Distinct colours for Expert EQ band handles.
enum BandPalette {
    static let colors: [Color] = [.orange, .yellow, .green, .mint, .cyan, .blue, .indigo, .purple, .pink, .red]

    static func color(_ index: Int) -> Color {
        colors[index % colors.count]
    }
}

enum Format {
    static func frequency(_ hz: Double) -> String {
        if hz >= 10_000 { return String(format: "%.0fk", hz / 1_000) }
        if hz >= 1_000 { return String(format: "%.1fk", hz / 1_000).replacingOccurrences(of: ".0k", with: "k") }
        return String(format: "%.0f", hz)
    }

    static func gain(_ db: Double, decimals: Int = 1) -> String {
        let threshold = 0.5 * pow(10.0, -Double(decimals))
        let clean = abs(db) < threshold ? 0.0 : db
        let value = String(format: "%.\(decimals)f", clean)
        return clean > 0 ? "+" + value : value
    }

    static func percent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }

    static func sampleRate(_ hz: Double) -> String {
        hz.truncatingRemainder(dividingBy: 1_000) == 0
            ? "\(Int(hz / 1_000)) kHz" : String(format: "%.1f kHz", hz / 1_000)
    }
}

extension View {
    /// Small secondary caption style used for control labels.
    func captionStyle() -> some View {
        font(.system(size: 11)).foregroundStyle(.secondary)
    }
}
