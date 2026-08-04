import SwiftUI

/// What happened once the ball reached the fielder. Deliberately short — the
/// ring has to be readable at arm's length in a stadium.
enum BallInPlayChoice: String, CaseIterable, Identifiable, Hashable, Sendable {
    case out
    case single
    case double
    case triple
    case homeRun
    case error
    case fieldersChoice
    case doublePlay
    case sacrificeFly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .out: "OUT"
        case .single: "1B"
        case .double: "2B"
        case .triple: "3B"
        case .homeRun: "HR"
        case .error: "E"
        case .fieldersChoice: "FC"
        case .doublePlay: "DP"
        case .sacrificeFly: "SF"
        }
    }

    var tint: Color {
        switch self {
        case .out, .doublePlay: Theme.miss
        case .single, .double, .triple, .homeRun: Theme.ball
        case .error: Theme.foul
        case .fieldersChoice, .sacrificeFly: Theme.neutral
        }
    }

    /// Builds the real outcome, filling in the fielding chain a scorer would
    /// assume: a grounder to short is 6-3, a fly to centre is F8.
    func outcome(fielder: Position, trajectory: Trajectory, location: FieldLocation?) -> PlayOutcome {
        let batted = BattedBall(trajectory: trajectory, location: location)

        switch self {
        case .out:
            return .fieldOut(fielders: Self.outChain(fielder: fielder, trajectory: trajectory), batted: batted)
        case .single:
            return .hit(.single, batted: batted, fielder: fielder)
        case .double:
            return .hit(.double, batted: batted, fielder: fielder)
        case .triple:
            return .hit(.triple, batted: batted, fielder: fielder)
        case .homeRun:
            return .hit(.homeRun, batted: batted, fielder: fielder)
        case .error:
            return .error(fielder: fielder, batted: batted, basesAwarded: 1)
        case .fieldersChoice:
            return .fieldersChoice(fielders: [fielder, .secondBase], batted: batted)
        case .doublePlay:
            return .doublePlay(fielders: Self.doublePlayChain(fielder: fielder), batted: batted)
        case .sacrificeFly:
            return .sacrificeFly(fielder: fielder)
        }
    }

    /// A ball caught in the air is one fielder. A grounder is fielded and
    /// thrown to first — unless the first baseman fielded it himself.
    private static func outChain(fielder: Position, trajectory: Trajectory) -> [Position] {
        if trajectory.isInAir {
            return [fielder]
        }
        if fielder == .firstBase {
            return [.firstBase]
        }
        return [fielder, .firstBase]
    }

    private static func doublePlayChain(fielder: Position) -> [Position] {
        switch fielder {
        case .secondBase: [.secondBase, .shortstop, .firstBase]
        case .firstBase: [.firstBase, .shortstop, .firstBase]
        default: [fielder, .secondBase, .firstBase]
        }
    }

    /// A fly ball to the outfield reads as a fly; anything on the infield dirt
    /// reads as a grounder until told otherwise.
    static func defaultTrajectory(for fielder: Position) -> Trajectory {
        fielder.isOutfielder ? .flyBall : .grounder
    }

    /// The ring is context-aware: a sacrifice fly is only offered when one is
    /// actually possible, and a double play only with someone to erase.
    static func choices(for state: GameState, fielder: Position) -> [BallInPlayChoice] {
        var choices: [BallInPlayChoice] = [.single, .double, .triple, .homeRun, .error, .fieldersChoice]

        let hasRunners = !state.bases.isEmpty
        if hasRunners && state.outs < 2 {
            choices.append(.doublePlay)
        }
        if fielder.isOutfielder, state.bases.third != nil, state.outs < 2 {
            choices.append(.sacrificeFly)
        }
        return choices
    }
}

/// The result ring: `OUT` sits under the thumb where it was released, and
/// everything else fans out around it. The common case costs one tap and no
/// travel; the rare cases are one short reach away.
struct ResultRing: View {
    var choices: [BallInPlayChoice]
    var fielder: Position
    var trajectory: Trajectory
    var showsTrajectoryPicker: Bool
    /// Shifts the ring toward the scoring thumb so `OUT` lands roughly where
    /// the finger already was when it left the dial.
    var thumbBias: CGFloat = 0
    var onPick: (BallInPlayChoice) -> Void
    var onChangeTrajectory: (Trajectory) -> Void
    var onCancel: () -> Void

    private let radius: CGFloat = 96

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { onCancel() }

            VStack(spacing: 14) {
                header

                if showsTrajectoryPicker {
                    trajectoryPicker
                }

                ring
            }
            .offset(x: thumbBias)
            .padding(.horizontal, 16)
            .padding(.bottom, 30)
        }
        .transition(.opacity)
    }

    private var header: some View {
        VStack(spacing: 4) {
            Text("\(fielder.rawValue) · \(fielder.abbreviation)")
                .font(Theme.Typeface.score(30))
                .foregroundStyle(.white)
            Text(trajectory.label)
                .font(Theme.Typeface.caption())
                .foregroundStyle(.white.opacity(0.6))
        }
    }

    private var trajectoryPicker: some View {
        HStack(spacing: 8) {
            ForEach(Trajectory.allCases) { option in
                Button {
                    onChangeTrajectory(option)
                } label: {
                    Text(option.label)
                        .font(Theme.Typeface.label(12, weight: .bold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(
                            Capsule().fill(
                                option == trajectory ? Theme.inPlay : Color.white.opacity(0.12)
                            )
                        )
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var ring: some View {
        ZStack {
            ForEach(choices.indices, id: \.self) { index in
                let choice = choices[index]
                let angle = Angle.degrees(Double(index) / Double(max(choices.count, 1)) * 360 - 90)
                ChoiceButton(choice: choice) { onPick(choice) }
                    .offset(
                        x: radius * cos(angle.radians),
                        y: radius * sin(angle.radians)
                    )
            }

            // The default under the thumb.
            ChoiceButton(choice: .out, isPrimary: true) { onPick(.out) }
        }
        .frame(width: radius * 2 + 88, height: radius * 2 + 88)
    }
}

private struct ChoiceButton: View {
    var choice: BallInPlayChoice
    var isPrimary: Bool = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(choice.title)
                .font(Theme.Typeface.label(isPrimary ? 20 : 15, weight: .heavy))
                .foregroundStyle(.white)
                .frame(width: isPrimary ? 86 : 58, height: isPrimary ? 86 : 58)
                .background(Circle().fill(choice.tint))
                .shadow(color: .black.opacity(0.4), radius: 8, y: 3)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(accessibilityName))
    }

    private var accessibilityName: String {
        switch choice {
        case .out: "Out"
        case .single: "Single"
        case .double: "Double"
        case .triple: "Triple"
        case .homeRun: "Home run"
        case .error: "Error"
        case .fieldersChoice: "Fielder's choice"
        case .doublePlay: "Double play"
        case .sacrificeFly: "Sacrifice fly"
        }
    }
}
