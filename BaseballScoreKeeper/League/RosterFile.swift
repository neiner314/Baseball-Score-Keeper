import Foundation

/// Roster import for leagues with no API.
///
/// NPB and the KBO publish rosters on the web but not as a feed, so the
/// realistic path is: assemble a team's players once, paste them in, and reuse
/// the file all season. A two-minute copy-paste per team beats typing a lineup
/// before every game, and it doesn't depend on scraping a site that will
/// change.
enum RosterFile {

    enum ParseError: LocalizedError {
        case empty
        case noUsableRows

        var errorDescription: String? {
            switch self {
            case .empty: "There's nothing to import."
            case .noUsableRows:
                "Couldn't read any players. Expected one player per line as: number, name, position"
            }
        }
    }

    /// Accepts the app's own JSON roster, or CSV/TSV as
    /// `number, name, position` — one player per line, header optional.
    static func parse(
        _ text: String,
        teamName: String,
        abbreviation: String
    ) throws -> TeamRoster {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ParseError.empty }

        if trimmed.hasPrefix("{"), let data = trimmed.data(using: .utf8) {
            if let roster = try? JSONDecoder().decode(TeamRoster.self, from: data) {
                return roster
            }
        }

        let players = trimmed
            .split(whereSeparator: \.isNewline)
            .compactMap { parseRow(String($0)) }

        guard !players.isEmpty else { throw ParseError.noUsableRows }

        return TeamRoster(
            name: teamName.isEmpty ? "Imported" : teamName,
            abbreviation: abbreviation.isEmpty ? "IMP" : abbreviation,
            players: players
        )
    }

    private static func parseRow(_ line: String) -> Player? {
        let separator: Character = line.contains("\t") ? "\t" : ","
        let fields = line
            .split(separator: separator, omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }

        guard fields.count >= 2 else { return nil }

        // Skip a header row.
        let lowered = fields.map { $0.lowercased() }
        if lowered.contains("name") && (lowered.contains("number") || lowered.contains("#")) {
            return nil
        }

        let number = fields[0].filter(\.isNumber)
        let name = fields[1]
        guard !name.isEmpty else { return nil }

        let position = fields.count >= 3 ? position(from: fields[2]) : nil

        return Player(
            number: number,
            name: name,
            primaryPosition: position ?? .designatedHitter
        )
    }

    private static func position(from text: String) -> Position? {
        let cleaned = text.trimmingCharacters(in: .whitespaces).uppercased()
        guard !cleaned.isEmpty else { return nil }

        if let number = Int(cleaned), let position = Position(rawValue: number) {
            return position
        }
        return Position.allCases.first { $0.abbreviation == cleaned }
    }

    /// Round-trips a roster back out, so a team assembled once can be saved
    /// and shared.
    static func csv(for roster: TeamRoster) -> String {
        let header = "number,name,position"
        let rows = roster.players.map { player in
            "\(player.number),\(player.name),\(player.primaryPosition.abbreviation)"
        }
        return ([header] + rows).joined(separator: "\n")
    }
}
