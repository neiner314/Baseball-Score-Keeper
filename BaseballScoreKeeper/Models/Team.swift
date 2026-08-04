import Foundation

enum Side: String, Codable, CaseIterable, Identifiable, Sendable {
    case away
    case home

    var id: String { rawValue }
    var opponent: Side { self == .away ? .home : .away }
}

enum Half: String, Codable, CaseIterable, Sendable {
    case top
    case bottom

    /// The side holding the bat during this half.
    var battingSide: Side { self == .top ? .away : .home }
    /// The side in the field during this half.
    var fieldingSide: Side { battingSide.opponent }
    var next: Half { self == .top ? .bottom : .top }

    var label: String { self == .top ? "Top" : "Bot" }
}

enum Handedness: String, Codable, CaseIterable, Identifiable, Sendable {
    case right
    case left

    var id: String { rawValue }
    var label: String { self == .right ? "Right thumb" : "Left thumb" }
}

enum BatterSide: String, Codable, CaseIterable, Sendable {
    case right
    case left
    case switchHitter

    var abbreviation: String {
        switch self {
        case .right: "R"
        case .left: "L"
        case .switchHitter: "S"
        }
    }
}

/// A small container for anything that exists once per team. Beats a
/// `[Side: T]` dictionary because it can't be missing a side and it encodes
/// to clean JSON.
///
/// Codable and Sendable are conditional so this can hold view-model values
/// (box score lines) as happily as it holds persisted ones.
struct SideValues<Value: Hashable>: Hashable {
    var away: Value
    var home: Value

    init(away: Value, home: Value) {
        self.away = away
        self.home = home
    }

    init(repeating value: Value) {
        self.away = value
        self.home = value
    }

    subscript(side: Side) -> Value {
        get { side == .away ? away : home }
        set {
            switch side {
            case .away: away = newValue
            case .home: home = newValue
            }
        }
    }
}

extension SideValues: Sendable where Value: Sendable {}

extension SideValues: Codable where Value: Codable {
    private enum CodingKeys: String, CodingKey {
        case away
        case home
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        away = try container.decode(Value.self, forKey: .away)
        home = try container.decode(Value.self, forKey: .home)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(away, forKey: .away)
        try container.encode(home, forKey: .home)
    }
}

struct Player: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var number: String
    var name: String
    /// Where this player started the game. Live position lives in `LineupState`.
    var primaryPosition: Position
    var bats: BatterSide
    var throwsWith: Handedness

    init(
        id: UUID = UUID(),
        number: String,
        name: String,
        primaryPosition: Position,
        bats: BatterSide = .right,
        throwsWith: Handedness = .right
    ) {
        self.id = id
        self.number = number
        self.name = name
        self.primaryPosition = primaryPosition
        self.bats = bats
        self.throwsWith = throwsWith
    }

    /// "Chisholm Jr." — the surname portion, used in the dense box score rows.
    var shortName: String {
        let parts = name.split(separator: " ")
        guard parts.count > 1 else { return name }
        let suffixes: Set<String> = ["Jr.", "Sr.", "II", "III", "IV"]
        if let last = parts.last, suffixes.contains(String(last)), parts.count > 2 {
            return parts.suffix(2).joined(separator: " ")
        }
        return String(parts.last ?? "")
    }

    var displayNumber: String { "#\(number)" }
}

struct TeamRoster: Codable, Hashable, Sendable {
    var name: String
    var abbreviation: String
    var players: [Player]

    func player(id: UUID) -> Player? {
        players.first { $0.id == id }
    }
}
