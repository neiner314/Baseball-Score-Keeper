import Foundation

struct ScoringDifference: Identifiable, Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        /// Both scored the plate appearance, differently.
        case differentCall(mine: ScoringCategory, official: ScoringCategory)
        /// Same call, different runs batted in.
        case differentRBI(mine: Int, official: Int)
        /// The official scorer has a plate appearance the scorer doesn't.
        case missed(official: ScoringCategory)
        /// The scorer has one the official scorer doesn't.
        case extra(mine: ScoringCategory)
    }

    var id: UUID
    var inning: Int
    var half: Half
    var batter: String
    var kind: Kind
    var officialSummary: String
    /// The event that resolved the scorer's plate appearance, when they have one
    /// (a wrong call, an RBI disagreement, or a play the official doesn't share).
    /// This is the single event a correction rewrites or removes.
    var myTerminalEventIndex: Int?
    /// Where to insert a play the scorer missed — right after the previous plate
    /// appearance, so it lands on the batter who was actually skipped.
    var insertionEventIndex: Int?
    /// What the scorer scored, kept so a correction can reuse the fielders.
    var myOutcome: PlayOutcome?

    init(
        id: UUID = UUID(),
        inning: Int,
        half: Half,
        batter: String,
        kind: Kind,
        officialSummary: String = "",
        myTerminalEventIndex: Int? = nil,
        insertionEventIndex: Int? = nil,
        myOutcome: PlayOutcome? = nil
    ) {
        self.id = id
        self.inning = inning
        self.half = half
        self.batter = batter
        self.kind = kind
        self.officialSummary = officialSummary
        self.myTerminalEventIndex = myTerminalEventIndex
        self.insertionEventIndex = insertionEventIndex
        self.myOutcome = myOutcome
    }

    /// The category the official scorer has — the call a correction moves toward.
    var officialCategory: ScoringCategory? {
        switch kind {
        case .differentCall(_, let official): official
        case .missed(let official): official
        case .differentRBI, .extra: nil
        }
    }

    /// Whether this difference can be turned into an edit of the log.
    var isFixable: Bool {
        switch kind {
        case .differentCall: myTerminalEventIndex != nil && officialCategory != .other
        case .differentRBI: myTerminalEventIndex != nil
        case .extra: myTerminalEventIndex != nil
        case .missed: insertionEventIndex != nil && officialCategory != .other
        }
    }

    var inningLabel: String { "\(half.label) \(inning)" }

    var headline: String {
        switch kind {
        case .differentCall(let mine, let official):
            "You scored \(mine.label.lowercased()); official is \(official.label.lowercased())"
        case .differentRBI(let mine, let official):
            "Same call, \(mine) RBI to their \(official)"
        case .missed:
            "Not scored"
        case .extra:
            "No official play here"
        }
    }
}

struct ScoringReport: Sendable {
    var comparedPlays: Int
    var agreements: Int
    var differences: [ScoringDifference]
    var myPlayCount: Int
    var officialPlayCount: Int

    var accuracy: Double {
        comparedPlays > 0 ? Double(agreements) / Double(comparedPlays) : 0
    }

    var accuracyPercent: String {
        guard comparedPlays > 0 else { return "—" }
        return "\(Int((accuracy * 100).rounded()))%"
    }

    /// True when both sides have the same number of plate appearances, so the
    /// comparison lined up cleanly the whole way through.
    var isAligned: Bool { myPlayCount == officialPlayCount }

    var summary: String {
        guard comparedPlays > 0 else { return "Nothing to compare yet" }
        return "\(agreements) of \(comparedPlays) plays match"
    }
}

/// Diffs the scorer's plate appearances against the league's official scoring.
///
/// Plays are lined up within each half-inning rather than globally, so one
/// missed play throws off that half and nothing after it. Only the coarse
/// category is compared: disagreeing about whether a ball was a hit or an
/// error is worth flagging, disagreeing about whether the chain was 6-3 or
/// 6-4-3 is not what this is for.
enum ScoringComparator {

    private struct HalfKey: Hashable, Comparable {
        var inning: Int
        var half: Half

        static func < (lhs: HalfKey, rhs: HalfKey) -> Bool {
            if lhs.inning != rhs.inning { return lhs.inning < rhs.inning }
            return lhs.half == .top && rhs.half == .bottom
        }
    }

    static func compare(
        mine: [ScoringEngine.IndexedPlateAppearance],
        official: [OfficialPlay],
        document: GameDocument
    ) -> ScoringReport {
        var mineByHalf: [HalfKey: [ScoringEngine.IndexedPlateAppearance]] = [:]
        for appearance in mine {
            mineByHalf[HalfKey(inning: appearance.result.inning, half: appearance.result.half), default: []]
                .append(appearance)
        }

        var officialByHalf: [HalfKey: [OfficialPlay]] = [:]
        for play in official.sorted(by: { $0.index < $1.index }) {
            officialByHalf[HalfKey(inning: play.inning, half: play.half), default: []]
                .append(play)
        }

        var agreements = 0
        var compared = 0
        var differences: [ScoringDifference] = []

        let keys = Set(mineByHalf.keys).union(officialByHalf.keys).sorted()

        // The last event index of any plate appearance in an earlier half, so a
        // missed play in a half where the scorer logged nothing still knows
        // where to slot in.
        var priorHalvesLastIndex: Int?

        for key in keys {
            let mineHalf = mineByHalf[key] ?? []
            let officialHalf = officialByHalf[key] ?? []
            let shared = min(mineHalf.count, officialHalf.count)

            for index in 0..<shared {
                let appearance = mineHalf[index]
                let play = officialHalf[index]
                let mineCategory = ScoringCategory(appearance.result.outcome)
                compared += 1

                let name = batterName(for: appearance.result, in: document, fallback: play.batterName)

                if mineCategory != play.category {
                    differences.append(
                        ScoringDifference(
                            inning: key.inning,
                            half: key.half,
                            batter: name,
                            kind: .differentCall(mine: mineCategory, official: play.category),
                            officialSummary: play.summary,
                            myTerminalEventIndex: appearance.eventIndex,
                            myOutcome: appearance.result.outcome
                        )
                    )
                    continue
                }

                if appearance.result.rbis != play.rbi {
                    differences.append(
                        ScoringDifference(
                            inning: key.inning,
                            half: key.half,
                            batter: name,
                            kind: .differentRBI(mine: appearance.result.rbis, official: play.rbi),
                            officialSummary: play.summary,
                            myTerminalEventIndex: appearance.eventIndex,
                            myOutcome: appearance.result.outcome
                        )
                    )
                    continue
                }

                agreements += 1
            }

            // A play the official has but the scorer skipped: insert it right
            // after the scorer's last plate appearance in this half (or the
            // previous half, if they logged none here), so it records for the
            // batter who was actually passed over.
            if officialHalf.count > shared {
                let insertAfter = mineHalf.last?.eventIndex ?? priorHalvesLastIndex
                for play in officialHalf[shared...] {
                    differences.append(
                        ScoringDifference(
                            inning: key.inning,
                            half: key.half,
                            batter: play.batterName,
                            kind: .missed(official: play.category),
                            officialSummary: play.summary,
                            insertionEventIndex: (insertAfter ?? -1) + 1
                        )
                    )
                }
            }

            if mineHalf.count > shared {
                for appearance in mineHalf[shared...] {
                    differences.append(
                        ScoringDifference(
                            inning: key.inning,
                            half: key.half,
                            batter: batterName(for: appearance.result, in: document, fallback: ""),
                            kind: .extra(mine: ScoringCategory(appearance.result.outcome)),
                            myTerminalEventIndex: appearance.eventIndex,
                            myOutcome: appearance.result.outcome
                        )
                    )
                }
            }

            if let last = mineHalf.last?.eventIndex {
                priorHalvesLastIndex = max(priorHalvesLastIndex ?? last, last)
            }
        }

        return ScoringReport(
            comparedPlays: compared,
            agreements: agreements,
            differences: differences,
            myPlayCount: mine.count,
            officialPlayCount: official.count
        )
    }

    private static func batterName(
        for appearance: PlateAppearanceResult,
        in document: GameDocument,
        fallback: String
    ) -> String {
        document.player(id: appearance.batterID)?.shortName
            ?? (fallback.isEmpty ? "—" : fallback)
    }
}
