import Foundation

/// The nine defensive positions, numbered the way a scorebook numbers them.
/// The raw value *is* the scorekeeping number, so `Position.shortstop.rawValue == 6`
/// and notation like `6-3` falls out of the model for free.
enum Position: Int, Codable, CaseIterable, Identifiable, Sendable {
    case pitcher = 1
    case catcher
    case firstBase
    case secondBase
    case thirdBase
    case shortstop
    case leftField
    case centerField
    case rightField
    case designatedHitter

    var id: Int { rawValue }

    /// Positions that actually stand on the field. The DH does not.
    static var fielders: [Position] {
        allCases.filter(\.isFielder)
    }

    var isFielder: Bool { rawValue <= 9 }

    var isOutfielder: Bool { (7...9).contains(rawValue) }

    var isInfielder: Bool { (3...6).contains(rawValue) }

    var abbreviation: String {
        switch self {
        case .pitcher: "P"
        case .catcher: "C"
        case .firstBase: "1B"
        case .secondBase: "2B"
        case .thirdBase: "3B"
        case .shortstop: "SS"
        case .leftField: "LF"
        case .centerField: "CF"
        case .rightField: "RF"
        case .designatedHitter: "DH"
        }
    }

    var fullName: String {
        switch self {
        case .pitcher: "Pitcher"
        case .catcher: "Catcher"
        case .firstBase: "First Base"
        case .secondBase: "Second Base"
        case .thirdBase: "Third Base"
        case .shortstop: "Shortstop"
        case .leftField: "Left Field"
        case .centerField: "Center Field"
        case .rightField: "Right Field"
        case .designatedHitter: "Designated Hitter"
        }
    }

    /// What the announcer says out loud when this position is selected on the
    /// fielder dial. Spoken as the scorekeeping number, the way a scorer thinks.
    var spokenName: String {
        guard isFielder else { return fullName }
        return "\(rawValue), \(fullName)"
    }

    /// The scorekeeping number, or nil for the DH which never records an out.
    var scorebookNumber: Int? { isFielder ? rawValue : nil }
}
