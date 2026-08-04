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

    init(
        id: UUID = UUID(),
        inning: Int,
        half: Half,
        batter: String,
        kind: Kind,
        officialSummary: String = ""
    ) {
        self.id = id
        self.inning = inning
        self.half = half
        self.batter = batter
        self.kind = kind
        self.officialSummary = officialSummary
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
        mine: [PlateAppearanceResult],
        official: [OfficialPlay],
        document: GameDocument
    ) -> ScoringReport {
        var mineByHalf: [HalfKey: [PlateAppearanceResult]] = [:]
        for appearance in mine {
            mineByHalf[HalfKey(inning: appearance.inning, half: appearance.half), default: []]
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

        for key in keys {
            let mineHalf = mineByHalf[key] ?? []
            let officialHalf = officialByHalf[key] ?? []
            let shared = min(mineHalf.count, officialHalf.count)

            for index in 0..<shared {
                let appearance = mineHalf[index]
                let play = officialHalf[index]
                let mineCategory = ScoringCategory(appearance.outcome)
                compared += 1

                let name = batterName(for: appearance, in: document, fallback: play.batterName)

                if mineCategory != play.category {
                    differences.append(
                        ScoringDifference(
                            inning: key.inning,
                            half: key.half,
                            batter: name,
                            kind: .differentCall(mine: mineCategory, official: play.category),
                            officialSummary: play.summary
                        )
                    )
                    continue
                }

                if appearance.rbis != play.rbi {
                    differences.append(
                        ScoringDifference(
                            inning: key.inning,
                            half: key.half,
                            batter: name,
                            kind: .differentRBI(mine: appearance.rbis, official: play.rbi),
                            officialSummary: play.summary
                        )
                    )
                    continue
                }

                agreements += 1
            }

            if officialHalf.count > shared {
                for play in officialHalf[shared...] {
                    differences.append(
                        ScoringDifference(
                            inning: key.inning,
                            half: key.half,
                            batter: play.batterName,
                            kind: .missed(official: play.category),
                            officialSummary: play.summary
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
                            batter: batterName(for: appearance, in: document, fallback: ""),
                            kind: .extra(mine: ScoringCategory(appearance.outcome))
                        )
                    )
                }
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
