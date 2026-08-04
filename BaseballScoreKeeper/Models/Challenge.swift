import Foundation

/// Who tapped their helmet. Under the automated ball-strike rules only three
/// people on the field may challenge, and no one in the dugout can help.
enum ChallengeRole: String, Codable, CaseIterable, Identifiable, Sendable {
    case batter
    case pitcher
    case catcher

    var id: String { rawValue }

    var label: String {
        switch self {
        case .batter: "Batter"
        case .pitcher: "Pitcher"
        case .catcher: "Catcher"
        }
    }

    /// The batter challenges on behalf of the team at bat; the battery
    /// challenges for the team in the field.
    func side(battingSide: Side) -> Side {
        self == .batter ? battingSide : battingSide.opponent
    }
}

enum ChallengeResult: String, Codable, CaseIterable, Identifiable, Sendable {
    /// The call was wrong. The pitch is corrected and the team keeps the
    /// challenge.
    case overturned
    /// The call was right. The team is charged with the challenge.
    case stands

    var id: String { rawValue }

    var label: String {
        switch self {
        case .overturned: "Overturned"
        case .stands: "Call stands"
        }
    }

    var detail: String {
        switch self {
        case .overturned: "keeps the challenge"
        case .stands: "loses the challenge"
        }
    }
}

struct Challenge: Codable, Hashable, Identifiable, Sendable {
    var id: UUID
    var role: ChallengeRole
    var result: ChallengeResult
    /// The call as the umpire made it. Kept so the event describes itself —
    /// once an overturned challenge has been resolved, the pitch it points at
    /// carries the corrected call instead.
    var originalOutcome: PitchOutcome

    init(
        id: UUID = UUID(),
        role: ChallengeRole,
        result: ChallengeResult,
        originalOutcome: PitchOutcome
    ) {
        self.id = id
        self.role = role
        self.result = result
        self.originalOutcome = originalOutcome
    }

    /// What the call becomes when the challenge succeeds.
    var correctedOutcome: PitchOutcome? {
        result == .overturned ? originalOutcome.challengeReversal : nil
    }
}

/// One challenge as it reads in the box score.
struct ChallengeRecord: Identifiable, Hashable, Sendable {
    var id: UUID
    var side: Side
    var role: ChallengeRole
    var result: ChallengeResult
    var originalOutcome: PitchOutcome
    var inning: Int
    var half: Half

    var summary: String {
        let call = originalOutcome.shortLabel
        switch result {
        case .overturned:
            let corrected = originalOutcome.challengeReversal?.shortLabel ?? "—"
            return "\(call) → \(corrected)"
        case .stands:
            return "\(call) confirmed"
        }
    }

    var inningLabel: String {
        "\(half.label) \(inning)"
    }
}
