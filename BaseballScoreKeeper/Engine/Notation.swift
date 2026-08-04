import Foundation

/// Turns a `PlayOutcome` into the marks a scorer would actually write in a
/// book: `K`, `ꓘ`, `6-3`, `F8`, `4-6-3 DP`.
enum Notation {

    /// The traditional backwards K for a called third strike. Pulled out as a
    /// constant because not every font ships the glyph — swap it for "Kc" if
    /// yours doesn't.
    static let calledStrikeoutMark = "ꓘ"
    static let swingingStrikeoutMark = "K"

    static func text(for outcome: PlayOutcome, detail: NotationDetail, rbis: Int = 0) -> String {
        var mark = core(for: outcome, detail: detail)
        if rbis > 0 {
            mark += "+\(rbis)"
        }
        return mark
    }

    private static func core(for outcome: PlayOutcome, detail: NotationDetail) -> String {
        switch outcome {
        case .strikeout(let looking, let uncaught):
            let base = looking ? calledStrikeoutMark : swingingStrikeoutMark
            return uncaught ? "\(base) SAFE" : base

        case .walk(let intentional):
            return intentional ? "IBB" : "BB"

        case .hitByPitch:
            return "HBP"

        case .catchersInterference:
            return "CI"

        case .hit(let kind, let batted, let fielder):
            guard detail == .full else { return kind.abbreviation }
            let where_ = locationSuffix(batted: batted, fielder: fielder)
            return where_.isEmpty ? kind.abbreviation : "\(kind.abbreviation) \(where_)"

        case .fieldOut(let fielders, let batted):
            return fieldOutMark(fielders: fielders, batted: batted, detail: detail)

        case .error(let fielder, _, _):
            return "E\(fielder.rawValue)"

        case .fieldersChoice(let fielders, _):
            let chain = numberChain(fielders)
            return chain.isEmpty ? "FC" : "FC \(chain)"

        case .doublePlay(let fielders, let batted):
            let chain = numberChain(fielders)
            let prefix = detail == .full ? (batted?.trajectory.notationPrefix ?? "") : ""
            return chain.isEmpty ? "DP" : "\(prefix)\(chain) DP"

        case .triplePlay(let fielders, _):
            let chain = numberChain(fielders)
            return chain.isEmpty ? "TP" : "\(chain) TP"

        case .sacrificeFly(let fielder):
            return "SF\(fielder.rawValue)"

        case .sacrificeBunt(let fielders):
            let chain = numberChain(fielders)
            return chain.isEmpty ? "SH" : "SH \(chain)"
        }
    }

    /// A ball fielded and thrown reads `6-3`. One fielder alone reads `F8` for
    /// a catch or `3U` for an unassisted ground out.
    private static func fieldOutMark(fielders: [Position], batted: BattedBall?, detail: NotationDetail) -> String {
        guard let first = fielders.first else { return "OUT" }

        if fielders.count == 1 {
            let trajectory = batted?.trajectory ?? .flyBall
            switch trajectory {
            case .flyBall:
                return "F\(first.rawValue)"
            case .popup:
                return "P\(first.rawValue)"
            case .liner:
                return "L\(first.rawValue)"
            case .grounder, .bunt:
                // Fielded and stepped on the bag himself.
                return "\(first.rawValue)U"
            }
        }

        let chain = numberChain(fielders)
        guard detail == .full, let trajectory = batted?.trajectory else { return chain }
        return "\(trajectory.notationPrefix)\(chain)"
    }

    private static func numberChain(_ fielders: [Position]) -> String {
        fielders.compactMap(\.scorebookNumber)
            .map(String.init)
            .joined(separator: "-")
    }

    private static func locationSuffix(batted: BattedBall?, fielder: Position?) -> String {
        guard let fielder, let number = fielder.scorebookNumber else { return "" }
        guard let batted else { return "\(number)" }
        return "\(batted.trajectory.notationPrefix)\(number)"
    }

    /// Compact batting summary for a box score row: "2-for-4".
    static func battingLine(hits: Int, atBats: Int) -> String {
        "\(hits)-for-\(atBats)"
    }

    /// Innings pitched are recorded in thirds: 5.2 means five and two-thirds.
    static func inningsPitched(outs: Int) -> String {
        "\(outs / 3).\(outs % 3)"
    }
}
