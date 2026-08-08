import Foundation

/// One completed plate appearance as the league's official scorer recorded it.
struct OfficialPlay: Identifiable, Hashable, Sendable {
    var index: Int
    var inning: Int
    var half: Half
    var batterExternalID: String?
    var batterName: String
    /// The feed's machine-readable event, e.g. "grounded_into_double_play".
    var eventType: String
    /// The feed's display name, e.g. "Groundout".
    var eventName: String
    /// The prose line, e.g. "Chisholm Jr. grounds out, shortstop to first."
    var summary: String
    var rbi: Int

    var id: Int { index }

    var category: ScoringCategory {
        ScoringCategory(mlbEventType: eventType)
    }
}

/// The common vocabulary both sides get reduced to before being compared.
///
/// Neither the app's `PlayOutcome` nor MLB's event strings can be compared
/// directly — one carries fielding chains the feed doesn't, the other splits
/// hairs the app doesn't. This is the coarse category they agree on, which is
/// the level a scorer actually cares about disagreeing at.
enum ScoringCategory: String, Hashable, Sendable, CaseIterable {
    case single
    case double
    case triple
    case homeRun
    case walk
    case hitByPitch
    case catchersInterference
    case strikeout
    case fieldOut
    case fieldersChoice
    case error
    case doublePlay
    case triplePlay
    case sacrificeFly
    case sacrificeBunt
    case other

    var label: String {
        switch self {
        case .single: "Single"
        case .double: "Double"
        case .triple: "Triple"
        case .homeRun: "Home run"
        case .walk: "Walk"
        case .hitByPitch: "Hit by pitch"
        case .catchersInterference: "Catcher's interference"
        case .strikeout: "Strikeout"
        case .fieldOut: "Out"
        case .fieldersChoice: "Fielder's choice"
        case .error: "Error"
        case .doublePlay: "Double play"
        case .triplePlay: "Triple play"
        case .sacrificeFly: "Sacrifice fly"
        case .sacrificeBunt: "Sacrifice bunt"
        case .other: "Other"
        }
    }

    /// How the app scored it.
    init(_ outcome: PlayOutcome) {
        switch outcome {
        case .hit(let kind, _, _):
            switch kind {
            case .single: self = .single
            case .double: self = .double
            case .triple: self = .triple
            case .homeRun: self = .homeRun
            }
        case .walk: self = .walk
        case .hitByPitch: self = .hitByPitch
        case .catchersInterference: self = .catchersInterference
        case .strikeout: self = .strikeout
        case .fieldOut: self = .fieldOut
        case .fieldersChoice: self = .fieldersChoice
        case .error: self = .error
        case .doublePlay: self = .doublePlay
        case .triplePlay: self = .triplePlay
        case .sacrificeFly: self = .sacrificeFly
        case .sacrificeBunt: self = .sacrificeBunt
        }
    }

    /// True when going from `self` to `other` needs someone to have fielded the
    /// ball — so the correction can reuse the fielders the scorer already
    /// entered rather than inventing a chain.
    var needsFielders: Bool {
        switch self {
        case .fieldOut, .fieldersChoice, .error, .doublePlay, .triplePlay,
             .sacrificeFly, .sacrificeBunt:
            return true
        default:
            return false
        }
    }

    /// How MLB's feed scored it. Their vocabulary is finer than this app's —
    /// a force out and a fielder's choice are one thing to a scorebook, and a
    /// strikeout that doubled off a runner is still a strikeout for the batter.
    init(mlbEventType: String) {
        switch mlbEventType {
        case "single": self = .single
        case "double": self = .double
        case "triple": self = .triple
        case "home_run": self = .homeRun
        case "walk", "intent_walk": self = .walk
        case "hit_by_pitch": self = .hitByPitch
        case "catcher_interf": self = .catchersInterference
        case "strikeout", "strikeout_double_play", "strikeout_triple_play": self = .strikeout
        case "field_out", "fielders_choice_out", "other_out": self = .fieldOut
        case "force_out", "fielders_choice": self = .fieldersChoice
        case "field_error", "error": self = .error
        case "grounded_into_double_play", "double_play": self = .doublePlay
        case "triple_play": self = .triplePlay
        case "sac_fly", "sac_fly_double_play": self = .sacrificeFly
        case "sac_bunt", "sac_bunt_double_play": self = .sacrificeBunt
        default: self = .other
        }
    }
}

extension PlayOutcome {
    /// The fielders this play credited, in order — the chain a scorer would
    /// reuse when correcting the call to something else the fielders still
    /// touched (a "hit" that was really an error off the same glove).
    var fieldingChain: [Position] {
        switch self {
        case .hit(_, _, let fielder): return fielder.map { [$0] } ?? []
        case .fieldOut(let fielders, _): return fielders
        case .error(let fielder, _, _): return [fielder]
        case .fieldersChoice(let fielders, _): return fielders
        case .doublePlay(let fielders, _): return fielders
        case .triplePlay(let fielders, _): return fielders
        case .sacrificeFly(let fielder): return [fielder]
        case .sacrificeBunt(let fielders): return fielders
        case .strikeout, .walk, .hitByPitch, .catchersInterference: return []
        }
    }

    /// Builds the outcome the official scorer's call implies, reusing as much of
    /// the play the scorer already entered as still applies.
    ///
    /// The feed's category is coarser than a full play — it knows "error" but
    /// not off whose glove — so anything needing fielders borrows them from the
    /// `original` call when it had them, and falls back to a plausible default
    /// otherwise. Returns nil for categories the app can't represent as a single
    /// batted-ball outcome.
    static func matching(_ category: ScoringCategory, reusing original: PlayOutcome?) -> PlayOutcome? {
        let chain = original?.fieldingChain ?? []
        let batted = original?.battedBall
        let first = chain.first

        switch category {
        case .single: return .hit(.single, batted: batted, fielder: first)
        case .double: return .hit(.double, batted: batted, fielder: first)
        case .triple: return .hit(.triple, batted: batted, fielder: first)
        case .homeRun: return .hit(.homeRun, batted: nil, fielder: nil)
        case .walk: return .walk(intentional: false)
        case .hitByPitch: return .hitByPitch
        case .catchersInterference: return .catchersInterference
        case .strikeout: return .strikeout(looking: false, uncaught: false)
        case .fieldOut:
            return .fieldOut(
                fielders: chain.isEmpty ? [.shortstop, .firstBase] : chain,
                batted: batted ?? BattedBall(trajectory: .grounder)
            )
        case .fieldersChoice:
            return .fieldersChoice(
                fielders: chain.isEmpty ? [.shortstop, .secondBase] : chain,
                batted: batted ?? BattedBall(trajectory: .grounder)
            )
        case .error:
            return .error(
                fielder: first ?? .shortstop,
                batted: batted ?? BattedBall(trajectory: .grounder),
                basesAwarded: 1
            )
        case .doublePlay:
            return .doublePlay(
                fielders: chain.count >= 2 ? chain : [.shortstop, .secondBase, .firstBase],
                batted: batted ?? BattedBall(trajectory: .grounder)
            )
        case .triplePlay:
            return .triplePlay(
                fielders: chain.count >= 2 ? chain : [.shortstop, .secondBase, .firstBase],
                batted: batted ?? BattedBall(trajectory: .grounder)
            )
        case .sacrificeFly:
            return .sacrificeFly(fielder: first ?? .centerField)
        case .sacrificeBunt:
            return .sacrificeBunt(fielders: chain.isEmpty ? [.pitcher, .firstBase] : chain)
        case .other:
            return nil
        }
    }
}
