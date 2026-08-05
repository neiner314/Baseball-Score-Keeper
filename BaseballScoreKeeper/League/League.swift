import Foundation

/// A league the app can score, and what it knows about getting rosters for it.
///
/// The honest state of play as of the 2026 season: MLB publishes a free,
/// key-less stats API that carries rosters, posted lineups and official
/// scoring. NPB and KBO publish nothing equivalent — there are community
/// scrapers and paid feeds, but no official free endpoint. So those leagues
/// import from a file instead of a URL, which still beats typing a lineup in
/// by hand and doesn't pretend an API exists.
enum League: String, Codable, CaseIterable, Identifiable, Sendable {
    case mlb
    case npb
    case kbo
    case other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .mlb: "Major League Baseball"
        case .npb: "Nippon Professional Baseball"
        case .kbo: "KBO League"
        case .other: "Other / custom"
        }
    }

    var shortName: String {
        switch self {
        case .mlb: "MLB"
        case .npb: "NPB"
        case .kbo: "KBO"
        case .other: "Custom"
        }
    }

    /// Whether rosters can be pulled straight off the wire for this league.
    var hasLiveProvider: Bool { self == .mlb || self == .npb }

    /// Whether the official scoring can be fetched back and compared.
    var hasOfficialScoring: Bool { self == .mlb }

    /// Shown on the import screen so the limitation is stated rather than
    /// discovered.
    var sourceNote: String {
        switch self {
        case .mlb:
            "Rosters, posted lineups and official scoring come from MLB's public Stats API. No account needed."
        case .npb:
            "Pick a date to pull both rosters (lineups aren't in the data, so you set the nine). "
                + "NPB publishes no official feed — this uses data sourced from the Nippon Baseball Data "
                + "Repository, which can be accessed here: "
                + "https://github.com/armstjc/Nippon-Baseball-Data-Repository"
        case .kbo:
            "The KBO publishes no free API. Import a roster file once per team and it's reusable all season."
        case .other:
            "Enter or import rosters yourself."
        }
    }
}
