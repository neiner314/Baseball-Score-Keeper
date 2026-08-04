import Foundation

enum Base: Int, Codable, CaseIterable, Identifiable, Sendable {
    case first = 1
    case second
    case third

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .first: "1st"
        case .second: "2nd"
        case .third: "3rd"
        }
    }

    /// The base one step further along, or nil when the next stop is home.
    var next: Base? {
        switch self {
        case .first: .second
        case .second: .third
        case .third: nil
        }
    }

    static func advancing(from base: Base?, by bases: Int) -> AdvanceTarget {
        let start = base?.rawValue ?? 0
        let destination = start + bases
        switch destination {
        case ..<1: return .held
        case 1: return .first
        case 2: return .second
        case 3: return .third
        default: return .home
        }
    }
}

/// A runner on base. Carries the bookkeeping earned-run accounting needs:
/// who is responsible for them and whether they only reached because of a
/// defensive miscue.
struct Runner: Codable, Hashable, Identifiable, Sendable {
    var playerID: UUID
    var responsiblePitcherID: UUID
    var reachedOnError: Bool

    var id: UUID { playerID }

    init(playerID: UUID, responsiblePitcherID: UUID, reachedOnError: Bool = false) {
        self.playerID = playerID
        self.responsiblePitcherID = responsiblePitcherID
        self.reachedOnError = reachedOnError
    }
}

struct Bases: Codable, Hashable, Sendable {
    var first: Runner?
    var second: Runner?
    var third: Runner?

    init(first: Runner? = nil, second: Runner? = nil, third: Runner? = nil) {
        self.first = first
        self.second = second
        self.third = third
    }

    subscript(base: Base) -> Runner? {
        get {
            switch base {
            case .first: first
            case .second: second
            case .third: third
            }
        }
        set {
            switch base {
            case .first: first = newValue
            case .second: second = newValue
            case .third: third = newValue
            }
        }
    }

    var occupied: [Base] {
        Base.allCases.filter { self[$0] != nil }
    }

    var runnerCount: Int { occupied.count }

    var areLoaded: Bool { first != nil && second != nil && third != nil }

    var isEmpty: Bool { runnerCount == 0 }

    /// Runners who are forced to move if the batter reaches first.
    var forcedBases: [Base] {
        var forced: [Base] = []
        guard first != nil else { return forced }
        forced.append(.first)
        guard second != nil else { return forced }
        forced.append(.second)
        guard third != nil else { return forced }
        forced.append(.third)
        return forced
    }

    /// Lead runner, furthest along the basepaths.
    var leadOccupied: Base? {
        occupied.last
    }

    mutating func clear() {
        first = nil
        second = nil
        third = nil
    }

    /// Compact scoreboard shorthand: "1st & 3rd", "Bases loaded".
    var summary: String {
        if areLoaded { return "Bases loaded" }
        let bases = occupied
        if bases.isEmpty { return "Bases empty" }
        return bases.map(\.label).joined(separator: " & ")
    }
}

struct InningScore: Codable, Hashable, Sendable {
    /// nil means the half was never played — the "X" cell in a line score.
    var away: Int?
    var home: Int?

    subscript(side: Side) -> Int? {
        get { side == .away ? away : home }
        set {
            switch side {
            case .away: away = newValue
            case .home: home = newValue
            }
        }
    }
}

/// The live lineup for one team.
///
/// Batting order and defensive alignment are kept separately on purpose: with
/// a DH the pitcher never appears in the order, and a double switch moves a
/// player between them independently.
struct LineupState: Codable, Hashable, Sendable {
    struct Slot: Codable, Hashable, Sendable {
        var playerID: UUID
        /// What this batter plays in the field, or `.designatedHitter`.
        var position: Position
    }

    struct FieldAssignment: Codable, Hashable, Sendable {
        var position: Position
        var playerID: UUID
    }

    /// The batting order — always nine slots.
    var slots: [Slot]
    var battingIndex: Int
    /// Who is standing at each of the nine defensive positions.
    var fieldAssignments: [FieldAssignment]
    var benchPlayerIDs: [UUID]
    /// Everyone who has appeared, in order. A player who leaves may not return
    /// and the box score still owes them a line.
    var appearedPlayerIDs: [UUID]

    init(
        slots: [Slot],
        fieldAssignments: [FieldAssignment],
        battingIndex: Int = 0,
        benchPlayerIDs: [UUID] = []
    ) {
        self.slots = slots
        self.fieldAssignments = fieldAssignments
        self.battingIndex = battingIndex
        self.benchPlayerIDs = benchPlayerIDs
        var appeared = slots.map(\.playerID)
        for assignment in fieldAssignments where !appeared.contains(assignment.playerID) {
            appeared.append(assignment.playerID)
        }
        self.appearedPlayerIDs = appeared
    }

    var currentBatterID: UUID? {
        guard !slots.isEmpty else { return nil }
        return slots[battingIndex % slots.count].playerID
    }

    var currentPitcherID: UUID? {
        playerID(playing: .pitcher)
    }

    func playerID(playing position: Position) -> UUID? {
        fieldAssignments.first { $0.position == position }?.playerID
    }

    func position(of playerID: UUID) -> Position? {
        fieldAssignments.first { $0.playerID == playerID }?.position
            ?? slots.first { $0.playerID == playerID }?.position
    }

    func slotIndex(of playerID: UUID) -> Int? {
        slots.firstIndex { $0.playerID == playerID }
    }

    /// True when the pitcher is not one of the nine batters.
    var usesDesignatedHitter: Bool {
        slots.contains { $0.position == .designatedHitter }
    }

    mutating func advanceBatter() {
        guard !slots.isEmpty else { return }
        battingIndex = (battingIndex + 1) % slots.count
    }

    /// Steps the batting order back one slot. Used by undo.
    mutating func rewindBatter() {
        guard !slots.isEmpty else { return }
        battingIndex = (battingIndex + slots.count - 1) % slots.count
    }

    mutating func assign(_ playerID: UUID, to position: Position) {
        guard position.isFielder else { return }
        if let index = fieldAssignments.firstIndex(where: { $0.position == position }) {
            fieldAssignments[index].playerID = playerID
        } else {
            fieldAssignments.append(FieldAssignment(position: position, playerID: playerID))
        }
        noteAppearance(playerID)
    }

    mutating func noteAppearance(_ playerID: UUID) {
        benchPlayerIDs.removeAll { $0 == playerID }
        if !appearedPlayerIDs.contains(playerID) {
            appearedPlayerIDs.append(playerID)
        }
    }
}

struct GameRules: Codable, Hashable, Sendable {
    var regulationInnings: Int = 9
    var usesDesignatedHitter: Bool = true
    /// Runner starts on second in extras (the "ghost runner").
    var extraInningRunnerOnSecond: Bool = false
    var mercyRuleDifference: Int?

    static let standard = GameRules()
}

/// Everything derived by replaying the event log. Never edited directly by
/// the UI — the UI appends events and this comes back out of the engine.
struct GameState: Codable, Hashable, Sendable {
    var inning: Int = 1
    var half: Half = .top
    var outs: Int = 0
    var balls: Int = 0
    var strikes: Int = 0
    var bases = Bases()
    var lineScore: [InningScore] = [InningScore()]
    var hits = SideValues(repeating: 0)
    var errors = SideValues(repeating: 0)
    var leftOnBase = SideValues(repeating: 0)
    var lineups: SideValues<LineupState>
    var isFinal: Bool = false
    /// Pitches thrown in the current plate appearance, for the sequence strip.
    var currentAtBatPitches: [Pitch] = []
    /// Outs that *would* have been recorded this half-inning but for an error.
    /// Runs scoring past three real-plus-phantom outs are unearned.
    var phantomOuts: Int = 0

    init(lineups: SideValues<LineupState>) {
        self.lineups = lineups
    }

    var battingSide: Side { half.battingSide }
    var fieldingSide: Side { half.fieldingSide }

    var battingLineup: LineupState { lineups[battingSide] }
    var fieldingLineup: LineupState { lineups[fieldingSide] }

    var currentBatterID: UUID? { battingLineup.currentBatterID }
    var currentPitcherID: UUID? { fieldingLineup.currentPitcherID }

    func runs(for side: Side) -> Int {
        lineScore.reduce(0) { $0 + ($1[side] ?? 0) }
    }

    var awayRuns: Int { runs(for: .away) }
    var homeRuns: Int { runs(for: .home) }

    var countLabel: String { "\(balls)-\(strikes)" }

    var inningLabel: String { "\(half.label) \(inning)" }

    var isFullCount: Bool { balls == 3 && strikes == 2 }

    /// "TB 2 · NYY 3" style summary used in the compact header.
    func scoreLine(teams: SideValues<TeamRoster>) -> String {
        "\(teams.away.abbreviation) \(awayRuns) · \(teams.home.abbreviation) \(homeRuns)"
    }

    mutating func addRuns(_ count: Int, to side: Side) {
        guard count > 0 else { return }
        ensureLineScoreDepth()
        let index = inning - 1
        lineScore[index][side] = (lineScore[index][side] ?? 0) + count
    }

    /// Marks the current half as played, so an unplayed bottom of the ninth
    /// shows "X" instead of "0".
    mutating func markHalfPlayed() {
        ensureLineScoreDepth()
        let index = inning - 1
        if lineScore[index][battingSide] == nil {
            lineScore[index][battingSide] = 0
        }
    }

    mutating func ensureLineScoreDepth() {
        while lineScore.count < inning {
            lineScore.append(InningScore())
        }
    }

    mutating func resetCount() {
        balls = 0
        strikes = 0
        currentAtBatPitches = []
    }
}
