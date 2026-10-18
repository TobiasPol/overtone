import Foundation
@testable import Overtone
import Testing

@Suite("Music type detection")
struct DetectionTests {
    static func scores(_ name: String) -> [String: Double] {
        MeasuredTracks.all.first { $0.name.hasPrefix(name) }!.scores
    }

    @Test(arguments: MeasuredTracks.all.indices)
    func categorizesMeasuredTracks(_ index: Int) {
        let track = MeasuredTracks.all[index]
        #expect(SoundCategory.categorize(track.scores) == track.expected, "\(track.name)")
    }

    @Test func categoryPresetsExistAsBuiltIns() {
        let names = Set(BuiltInPresets.advanced.map(\.name))
        for category in SoundCategory.allCases {
            if let preset = category.presetName { #expect(names.contains(preset), "\(category)") }
        }
        #expect(SoundCategory.music.presetName == nil)
    }

    @Test func voterNeedsEnoughWindowsAndForgetsOldOnes() {
        var voter = MusicTypeVoter(span: 10, minimumWindows: 3)
        let rock = Self.scores("Adrenalize")
        voter.add(ClassificationWindow(time: 0, scores: rock))
        voter.add(ClassificationWindow(time: 1, scores: ["music": 0.01])) // gap: no vote
        voter.add(ClassificationWindow(time: 2, scores: rock))
        #expect(voter.proposal == nil)
        voter.add(ClassificationWindow(time: 3, scores: rock))
        #expect(voter.proposal == .rock)
        let speech = Self.scores("Synthesized speech")
        for time in stride(from: 14.0, through: 20, by: 2) {
            voter.add(ClassificationWindow(time: time, scores: speech))
        }
        #expect(voter.windows.count == 4)
        #expect(voter.proposal == .speech)
    }

    @Test func stabilizerSwitchesFastAtStartAndGapsOnly() {
        var s = DetectionStabilizer<SoundCategory>(holdTime: 6, forceTime: 45, gapWindow: 30)
        var switches: [SoundCategory?] = []
        for (proposal, time) in [(SoundCategory.rock, 0.0), (.rock, 6), (.piano, 10), (.piano, 20), (.piano, 55)] {
            switches.append(s.update(proposal, at: time))
        }
        s.noteGap(at: 60)
        switches.append(s.update(.speech, at: 61))
        switches.append(s.update(.speech, at: 67))
        // First decision and decisions near a gap need the hold time; mid-song ones the force time.
        #expect(switches == [nil, .rock, nil, nil, .piano, nil, .speech])
    }

    @Test func stabilizerRestartsHoldWhenProposalFlickers() {
        var s = DetectionStabilizer<SoundCategory>(holdTime: 6)
        let switches = [s.update(.rock, at: 0), s.update(nil, at: 3), s.update(.rock, at: 6), s.update(.rock, at: 12)]
        #expect(switches == [nil, nil, nil, .rock])
    }

    @Test func fallbackOnlyReplacesThePreviousTracksStyle() {
        var s = DetectionStabilizer<SoundCategory>(fallback: .music)
        var switches = [s.update(.rock, at: 0), s.update(.rock, at: 6)]
        for time in stride(from: 10.0, through: 100, by: 10) {
            switches.append(s.update(.music, at: time)) // a quiet passage in the same track
        }
        s.noteGap(at: 110)
        switches += [s.update(.music, at: 111), s.update(.music, at: 117)] // next track: no clear style
        #expect(switches == [nil, .rock] + Array(repeating: nil, count: 10) + [nil, .music])
    }

    @Test func correctionsStayQuickShortlyAfterAGap() {
        var s = DetectionStabilizer<SoundCategory>(holdTime: 6, forceTime: 45, gapWindow: 45)
        s.noteGap(at: 0)
        let switches = [
            s.update(.electronic, at: 1), s.update(.electronic, at: 7), // misleading intro
            s.update(.jazz, at: 10), s.update(.jazz, at: 16), // corrected within the window
            s.update(.rock, at: 60), s.update(.rock, at: 66), // later: needs the force time
        ]
        #expect(switches == [nil, .electronic, nil, .jazz, nil, nil])
    }

    @Test func silenceGateReportsEachGapOnce() {
        var gate = SilenceGate(thresholdDB: -55, minimumGap: 0.8)
        let blocks: [(rms: Float, duration: TimeInterval)] = [(0.2, 1), (0.0001, 0.5), (0, 0.5), (0, 2), (0.1, 0.1), (0, 1)]
        let gaps = blocks.map { gate.feed(rms: $0.rms, duration: $0.duration) }
        #expect(gaps == [false, false, true, false, false, true])
    }

    @Test func mapsMusicAppGenres() {
        let cases: [String: String?] = [
            "Hip-Hop/Rap": "Hip-Hop", "R&B/Soul": "R&B", "Rhythm & Blues": "R&B", "Alternative": "Rock",
            "Hard Rock": "Rock", "Pop/Rock": "Rock", "Singer/Songwriter": "Acoustic", "Country": "Acoustic",
            "Classical": "Classical", "Classical Crossover": "Classical", "Dance": "Dance", "Latin Pop": "Latin",
            "Electronic": "Electronic", "Deep House": "Electronic", "Jazz": "Jazz", "K-Pop": "Pop", "Pop": "Pop",
            "Podcast": "Spoken Word", "Soundtrack": nil, "World": nil, "Trapeze": nil, "": nil,
        ]
        for (genre, preset) in cases {
            #expect(GenreMapping.presetName(forGenre: genre) == preset, "\(genre)")
        }
        #expect(GenreMapping.presetName(forGenre: nil) == nil)
        let names = Set(BuiltInPresets.advanced.map(\.name))
        for case let preset? in cases.values {
            #expect(names.contains(preset))
        }
    }

    @Test func parsesMusicPlayerInfo() {
        let playing = MusicAppMonitor.NowPlaying(userInfo: [
            "Player State": "Playing", "Genre": " Rock ", "PersistentID": NSNumber(value: 42), "Name": "Song",
        ])
        #expect(playing == .init(userInfo: ["Player State": "Playing", "Genre": "Rock", "PersistentID": NSNumber(value: 42)]))
        #expect(playing.isPlaying && playing.genre == "Rock" && playing.trackID == "42")
        let paused = MusicAppMonitor.NowPlaying(userInfo: ["Player State": "Paused", "Genre": ""])
        #expect(!paused.isPlaying && paused.genre == nil)
    }
}
