import Foundation

/// A batter's season line, shown under their name in the at-bat card. Unlike
/// the game `BattingLine`, which is folded out of this game's event log, these
/// come from the league feed (MLB) or are aggregated from per-game files (NPB),
/// so they read the same in the first inning as the ninth.
struct SeasonHittingStats: Hashable, Sendable {
    var average: Double
    var homeRuns: Int
    var rbis: Int
    var onBase: Double

    init(average: Double, homeRuns: Int, rbis: Int, onBase: Double) {
        self.average = average
        self.homeRuns = homeRuns
        self.rbis = rbis
        self.onBase = onBase
    }

    /// Built from raw counting stats, computing the two rate stats. Returns nil
    /// when the player has no plate appearances yet, so an 0-for-0 shows nothing
    /// rather than a hollow ".000".
    init?(atBats: Int, hits: Int, homeRuns: Int, rbis: Int, walks: Int, hitByPitch: Int, sacFlies: Int) {
        let onBaseDenominator = atBats + walks + hitByPitch + sacFlies
        guard atBats > 0 || onBaseDenominator > 0 else { return nil }

        self.average = atBats > 0 ? Double(hits) / Double(atBats) : 0
        self.onBase = onBaseDenominator > 0
            ? Double(hits + walks + hitByPitch) / Double(onBaseDenominator)
            : 0
        self.homeRuns = homeRuns
        self.rbis = rbis
    }
}
