import Foundation

/// Maps a track's genre tag (as Music.app reports it) to a built-in Advanced preset.
enum GenreMapping {
    /// Checked in order; a genre matches when it contains one of the keywords as whole words.
    private static let rules: [(preset: String, keywords: [String])] = [
        ("Spoken Word", ["podcast", "podcasts", "spoken word", "audiobook", "audiobooks", "comedy"]),
        ("Hip-Hop", ["hip hop", "rap", "trap", "grime", "drill"]),
        ("R&B", ["r&b", "rnb", "rhythm & blues", "rhythm and blues", "soul", "funk"]),
        ("Classical", ["classical", "opera", "orchestral", "baroque", "chamber music", "choral"]),
        ("Piano", ["piano"]),
        ("Jazz", ["jazz", "bebop", "swing", "big band"]),
        ("Latin", ["latin", "reggaeton", "salsa", "bachata", "bossa nova", "samba", "tango", "flamenco"]),
        ("Rock", ["rock", "metal", "punk", "grunge", "alternative", "blues", "emo", "hardcore"]),
        ("Electronic", ["electronic", "electronica", "house", "techno", "trance", "edm", "dubstep", "drum & bass"]),
        ("Dance", ["dance", "disco"]),
        ("Acoustic", ["acoustic", "folk", "singer songwriter", "country", "bluegrass", "americana"]),
        ("Lounge", ["lounge", "easy listening", "chill", "chillout"]),
        ("Pop", ["pop"]),
    ]

    /// Preset name for `genre`, or nil when the tag is missing or too vague ("Soundtrack", "World").
    static func presetName(forGenre genre: String?) -> String? {
        guard let genre else { return nil }
        let words = normalized(genre)
        guard !words.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return rules.first { rule in rule.keywords.contains { words.contains(" \($0) ") } }?.preset
    }

    /// Lowercased, with separators turned into spaces and padded so " word " matches whole words.
    private static func normalized(_ genre: String) -> String {
        let separators = CharacterSet(charactersIn: "/-_,;:|()+").union(.whitespacesAndNewlines)
        let words = genre.lowercased().components(separatedBy: separators).filter { !$0.isEmpty }
        return " " + words.joined(separator: " ") + " "
    }
}
