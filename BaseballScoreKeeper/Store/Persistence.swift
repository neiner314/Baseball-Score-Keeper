import Foundation

/// File-backed storage for saved games.
///
/// Games are small (an event log of a few hundred entries), so each one is a
/// single JSON file. An actor keeps writes off the main thread and serialized.
actor GameArchive {
    static let shared = GameArchive()

    private let directory: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(directory: URL? = nil) {
        let base = directory ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Games", isDirectory: true)
        self.directory = base

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder

        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    }

    private func url(for id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).json")
    }

    func save(_ document: GameDocument) throws {
        let data = try encoder.encode(document)
        try data.write(to: url(for: document.id), options: .atomic)
    }

    func load(id: UUID) throws -> GameDocument {
        let data = try Data(contentsOf: url(for: id))
        return try decoder.decode(GameDocument.self, from: data)
    }

    func delete(id: UUID) throws {
        try FileManager.default.removeItem(at: url(for: id))
    }

    /// Every saved game, newest first.
    func allGames() -> [GameDocument] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )) ?? []

        return urls
            .filter { $0.pathExtension == "json" }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? decoder.decode(GameDocument.self, from: data)
            }
            .sorted { $0.startedAt > $1.startedAt }
    }
}

/// Preferences that outlive any single game — the layout and handedness the
/// scorer picked last time. `UserDefaults` is thread-safe, so this needs no
/// actor isolation of its own.
enum AppPreferences {
    private static let defaultsKey = "trackingSettings.default"
    private static let lastGameKey = "game.last"

    static var defaultTrackingSettings: TrackingSettings {
        get {
            guard
                let data = UserDefaults.standard.data(forKey: defaultsKey),
                let settings = try? JSONDecoder().decode(TrackingSettings.self, from: data)
            else { return .default }
            return settings
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue) else { return }
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }

    static var lastGameID: UUID? {
        get {
            guard let string = UserDefaults.standard.string(forKey: lastGameKey) else { return nil }
            return UUID(uuidString: string)
        }
        set {
            UserDefaults.standard.set(newValue?.uuidString, forKey: lastGameKey)
        }
    }
}
