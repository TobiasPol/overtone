import AppKit

/// Follows what Music.app is playing through the `com.apple.Music.playerInfo` distributed
/// notification it posts on every track or play-state change. Unlike AppleScript this needs no
/// Automation permission, but it only reports changes: the first update arrives with the next
/// track, pause or play after monitoring starts.
@MainActor
final class MusicAppMonitor {
    static let bundleID = "com.apple.Music"
    private static let notification = Notification.Name("com.apple.Music.playerInfo")

    struct NowPlaying: Equatable, Sendable {
        var trackID: String?
        var genre: String?
        var isPlaying: Bool

        /// Reads the notification's userInfo ("Player State", "Genre", "PersistentID").
        init(userInfo: [AnyHashable: Any]) {
            isPlaying = userInfo["Player State"] as? String == "Playing"
            let genre = (userInfo["Genre"] as? String)?.trimmingCharacters(in: .whitespaces)
            self.genre = genre?.isEmpty == false ? genre : nil
            trackID = (userInfo["PersistentID"] as? NSNumber)?.stringValue ?? userInfo["Name"] as? String
        }
    }

    private(set) var nowPlaying: NowPlaying?
    var onChange: ((NowPlaying) -> Void)?
    private var token: NSObjectProtocol?

    func start() {
        guard token == nil else { return }
        token = DistributedNotificationCenter.default().addObserver(
            forName: Self.notification, object: nil, queue: .main
        ) { [weak self] note in
            let info = NowPlaying(userInfo: note.userInfo ?? [:])
            MainActor.assumeIsolated { self?.update(info) }
        }
    }

    func stop() {
        if let token { DistributedNotificationCenter.default().removeObserver(token) }
        token = nil
        nowPlaying = nil
    }

    private func update(_ info: NowPlaying) {
        guard info != nowPlaying else { return }
        nowPlaying = info
        onChange?(info)
    }

    /// Whether Music.app is the only app producing sound right now, so its genre describes
    /// everything Overtone hears (and not, say, a video playing over it).
    static func isSoleAudioSource() -> Bool {
        let playing = AudioProcessCatalog.apps().filter(\.isPlaying)
        return playing.count == 1 && playing.first?.bundleID == bundleID
    }
}
