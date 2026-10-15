import Foundation

/// Reads and writes the Equalizer APO "ParametricEQ.txt" format used by AutoEQ:
///
///     Preamp: -6.1 dB
///     Filter 1: ON LSC Fc 105 Hz Gain 6.4 dB Q 0.70
enum ParametricEQFormat {
    struct Profile: Equatable {
        var preamp: Double
        var bands: [EQBand]
    }

    static func parse(_ text: String) -> Profile {
        var preamp = 0.0
        var bands: [EQBand] = []
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.lowercased().hasPrefix("preamp:") {
                preamp = number(after: "Preamp:", in: line) ?? preamp
            } else if line.lowercased().hasPrefix("filter"), let band = parseFilter(line) {
                bands.append(band)
            }
        }
        return Profile(preamp: preamp, bands: bands)
    }

    static func render(_ profile: Profile) -> String {
        var lines = [String(format: "Preamp: %.1f dB", profile.preamp)]
        for (index, band) in profile.bands.enumerated() {
            let state = band.isEnabled ? "ON" : "OFF"
            lines.append(String(
                format: "Filter %d: %@ %@ Fc %.0f Hz Gain %.1f dB Q %.2f",
                index + 1, state, band.type.code, band.frequency, band.gain, band.q
            ))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func parseFilter(_ line: String) -> EQBand? {
        let tokens = line.split(separator: " ").map(String.init)
        guard let stateIndex = tokens.firstIndex(where: { $0 == "ON" || $0 == "OFF" }),
              stateIndex + 1 < tokens.count,
              let type = filterType(tokens[stateIndex + 1]),
              let frequency = value(following: "Fc", in: tokens) else { return nil }
        let gain = value(following: "Gain", in: tokens) ?? 0
        var q = value(following: "Q", in: tokens) ?? 0.71
        if let octaves = value(following: "BW", in: tokens, skipping: "Oct") {
            q = qFromBandwidth(octaves)
        }
        let band = EQBand(type: type, frequency: frequency, gain: gain, q: q, isEnabled: tokens[stateIndex] == "ON")
        return band.clamped()
    }

    private static func filterType(_ code: String) -> FilterType? {
        switch code.uppercased() {
        case "PK", "PEQ", "MODAL": return .peak
        case "LS", "LSC", "LSQ": return .lowShelf
        case "HS", "HSC", "HSQ": return .highShelf
        case "LP", "LPQ": return .lowPass
        case "HP", "HPQ": return .highPass
        case "BP": return .bandPass
        case "NO": return .notch
        case "AP": return .allPass
        default: return nil
        }
    }

    private static func value(following key: String, in tokens: [String], skipping unit: String? = nil) -> Double? {
        guard let index = tokens.firstIndex(of: key) else { return nil }
        var next = index + 1
        if let unit, next < tokens.count, tokens[next] == unit { next += 1 }
        guard next < tokens.count else { return nil }
        return Double(tokens[next].replacingOccurrences(of: ",", with: "."))
    }

    private static func number(after prefix: String, in line: String) -> Double? {
        let rest = line.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
        return rest.split(separator: " ").first.flatMap { Double($0.replacingOccurrences(of: ",", with: ".")) }
    }

    /// Converts a bandwidth in octaves to Q.
    static func qFromBandwidth(_ octaves: Double) -> Double {
        let power = pow(2, octaves)
        return sqrt(power) / (power - 1)
    }
}
