import Foundation
@testable import Overtone
import Testing

@Suite("AutoEQ")
struct AutoEQTests {
    private let hd650 = """
    Preamp: -6.1 dB
    Filter 1: ON LSC Fc 105 Hz Gain 6.4 dB Q 0.70
    Filter 2: ON PK Fc 8800 Hz Gain 5.1 dB Q 1.42
    Filter 3: OFF PK Fc 118 Hz Gain -3.1 dB Q 0.50
    Filter 4: ON HSC Fc 10000 Hz Gain -2.1 dB Q 0.70
    Filter 5: ON HP Fc 20 Hz
    """

    @Test func parsesParametricProfile() {
        let profile = ParametricEQFormat.parse(hd650)
        #expect(profile.preamp == -6.1)
        #expect(profile.bands.count == 5)
        #expect(profile.bands[0].type == .lowShelf)
        #expect(profile.bands[0].frequency == 105 && profile.bands[0].gain == 6.4 && profile.bands[0].q == 0.7)
        #expect(profile.bands[2].isEnabled == false)
        #expect(profile.bands[3].type == .highShelf)
        #expect(profile.bands[4].type == .highPass && abs(profile.bands[4].q - 0.71) < 0.001)
    }

    @Test func renderRoundTrips() {
        let profile = ParametricEQFormat.parse(hd650)
        let again = ParametricEQFormat.parse(ParametricEQFormat.render(profile))
        #expect(again.preamp == profile.preamp)
        #expect(again.bands.map(\.type) == profile.bands.map(\.type))
        #expect(again.bands.map(\.frequency) == profile.bands.map(\.frequency))
    }

    @Test func bandwidthInOctavesConvertsToQ() {
        let profile = ParametricEQFormat.parse("Filter: ON PK Fc 1000 Hz Gain 3 dB BW Oct 1")
        #expect(abs(profile.bands[0].q - 1.414) < 0.01)
    }

    @Test func indexLineWithParenthesesAndRig() throws {
        let line = "- [1MORE Aero (ANC Off)](./HypetheSonics/GRAS%20RA0045%20in-ear/1MORE%20Aero%20(ANC%20Off)) by HypetheSonics on GRAS RA0045"
        let entry = try #require(AutoEQIndex.parseLine(line))
        #expect(entry.name == "1MORE Aero (ANC Off)")
        #expect(entry.path == "HypetheSonics/GRAS%20RA0045%20in-ear/1MORE%20Aero%20(ANC%20Off)")
        #expect(entry.source == "HypetheSonics")
        #expect(entry.rig == "GRAS RA0045")
    }

    @Test func indexLineWithoutRigAndNonEntries() {
        let entry = AutoEQIndex.parseLine("- [Model X](./oratory1990/over-ear/Model%20X) by oratory1990")
        #expect(entry?.rig == nil)
        #expect(AutoEQIndex.parseLine("# Index") == nil)
        #expect(AutoEQIndex.parseLine("This is a list of all equalization profiles.") == nil)
    }

    @Test func profileURLIsStrictlyEncoded() throws {
        let entry = AutoEQEntry(
            name: "AAW 4+2 (bass)", path: "crinacle/711%20in-ear/AAW%204+2%20(bass)", source: "crinacle", rig: "711"
        )
        let url = try #require(AutoEQIndex.profileURL(for: entry))
        #expect(url.absoluteString.hasSuffix(
            "results/crinacle/711%20in-ear/AAW%204%2B2%20%28bass%29/AAW%204%2B2%20%28bass%29%20ParametricEQ.txt"
        ))
    }

    @Test func searchRanksPrefixAndPreferredSource() {
        let entries = [
            AutoEQEntry(name: "Sennheiser HD 650", path: "a", source: "Rtings", rig: nil),
            AutoEQEntry(name: "Sennheiser HD 650", path: "b", source: "oratory1990", rig: nil),
            AutoEQEntry(name: "Drop + Sennheiser HD 6XX", path: "c", source: "crinacle", rig: nil),
            AutoEQEntry(name: "Sony WH-1000XM4", path: "d", source: "oratory1990", rig: nil),
        ]
        let results = AutoEQIndex.search("sennheiser hd", in: entries)
        #expect(results.map(\.path) == ["b", "a", "c"])
        #expect(AutoEQIndex.search("   ", in: entries).isEmpty)
    }
}
