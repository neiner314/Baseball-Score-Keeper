import Foundation

/// One reusable team the scorer has saved, with when they last touched it.
struct SavedTeam: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var roster: TeamRoster
    var savedAt: Date

    init(id: UUID = UUID(), roster: TeamRoster, savedAt: Date = Date()) {
        self.id = id
        self.roster = roster
        self.savedAt = savedAt
    }
}

/// File-backed storage for the "My Teams" library.
///
/// Building a team's roster is the tedious part of setting up a non-league
/// game, and it doesn't change much over a season — so a team assembled once is
/// worth keeping. Same shape as `GameArchive`: one JSON file each, behind an
/// actor so writes stay off the main thread.
actor TeamStore {
    static let shared = TeamStore()

    private let directory: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(directory: URL? = nil) {
        let base = directory ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Teams", isDirectory: true)
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

    func save(_ team: SavedTeam) throws {
        let data = try encoder.encode(team)
        try data.write(to: url(for: team.id), options: .atomic)
    }

    func delete(id: UUID) throws {
        try FileManager.default.removeItem(at: url(for: id))
    }

    /// Every saved team, most recently saved first.
    func allTeams() -> [SavedTeam] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )) ?? []

        return urls
            .filter { $0.pathExtension == "json" }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? decoder.decode(SavedTeam.self, from: data)
            }
            .sorted { $0.savedAt > $1.savedAt }
    }
}
