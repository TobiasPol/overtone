import Foundation
import Observation

/// Downloads and caches the AutoEQ index, and fetches individual correction profiles.
@MainActor @Observable
final class AutoEQCatalog {
    enum LoadState: Equatable { case idle, loading, loaded, failed(String) }

    private(set) var state: LoadState = .idle
    private(set) var entries: [AutoEQEntry] = []
    private(set) var results: [AutoEQEntry] = []
    var query = "" {
        didSet { results = AutoEQIndex.search(query, in: entries) }
    }

    @ObservationIgnored private let cacheURL = SettingsStore.directory.appendingPathComponent("autoeq-index.md")
    @ObservationIgnored private let maxCacheAge: TimeInterval = 7 * 24 * 3_600

    func loadIfNeeded() async {
        guard state == .idle || isFailed else { return }
        if let cached = cachedIndex() {
            apply(cached)
            if cacheAge() > maxCacheAge { await download(silently: true) }
        } else {
            await download(silently: false)
        }
    }

    func refresh() async {
        await download(silently: false)
    }

    func fetchProfile(_ entry: AutoEQEntry) async throws -> ParametricEQFormat.Profile {
        guard let url = AutoEQIndex.profileURL(for: entry) else { throw URLError(.badURL) }
        let (data, response) = try await URLSession.shared.data(from: url)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw URLError(.fileDoesNotExist)
        }
        let profile = ParametricEQFormat.parse(String(decoding: data, as: UTF8.self))
        guard !profile.bands.isEmpty else { throw URLError(.cannotParseResponse) }
        return profile
    }

    private var isFailed: Bool {
        if case .failed = state { return true }
        return false
    }

    private func download(silently: Bool) async {
        if !silently { state = .loading }
        do {
            let url = AutoEQIndex.baseURL.appendingPathComponent("INDEX.md")
            let (data, _) = try await URLSession.shared.data(from: url)
            let markdown = String(decoding: data, as: UTF8.self)
            guard markdown.contains("](./") else { throw URLError(.cannotParseResponse) }
            try? data.write(to: cacheURL, options: .atomic)
            apply(markdown)
        } catch {
            if !silently || entries.isEmpty { state = .failed(error.localizedDescription) }
        }
    }

    private func apply(_ markdown: String) {
        entries = AutoEQIndex.parse(markdown)
        results = AutoEQIndex.search(query, in: entries)
        state = .loaded
    }

    private func cachedIndex() -> String? {
        guard let data = try? Data(contentsOf: cacheURL) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    private func cacheAge() -> TimeInterval {
        let attributes = try? FileManager.default.attributesOfItem(atPath: cacheURL.path)
        let modified = attributes?[.modificationDate] as? Date ?? .distantPast
        return Date().timeIntervalSince(modified)
    }
}
