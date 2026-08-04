import SwiftUI

/// What happened once the ball reached the fielders. Deliberately short — the
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
    case triplePlay
    case sacrificeFly
    case sacrificeBunt

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
        case .triplePlay: "TP"
        case .sacrificeFly: "SF"
        case .sacrificeBunt: "SH"
        }
    }

    var tint: Color {
        switch self {
        case .out, .doublePlay, .triplePlay: Theme.miss
        case .single, .double, .triple: Theme.ball
        case .homeRun: Theme.hitByPitch
        case .error: Theme.foul
        case .fieldersChoice, .sacrificeFly, .sacrificeBunt: Theme.neutral
        }
    }

    /// A ball nobody fielded can only have been a hit — over the wall, into the
    /// gap, or dropped in front of an outfielder the scorer doesn't care to
    /// name. Every other outcome needs someone to have touched it.
    var requiresFielder: Bool {
        switch self {
        case .single, .double, .triple, .homeRun: false
        default: true
        }
    }

    var hitKind: HitKind? {
        switch self {
        case .single: .single
        case .double: .double
        case .triple: .triple
        case .homeRun: .homeRun
        default: nil
        }
    }

    /// Builds the real outcome from the fielding chain the scorer entered.
    ///
    /// A chain of two or more is taken literally — `3-1`, `6-4-3`, and yes,
    /// `6-4-3-2-5-1-6` if that's genuinely what happened. A chain of one is
    /// completed with the throw a scorer would assume: a grounder to short is
    /// `6-3`, a fly to centre stays `F8`, a grounder the first baseman handled
    /// himself stays `3U`.
    func outcome(
        chain: [Position],
        trajectory: Trajectory,
        location: FieldLocation?
    ) -> PlayOutcome? {
        let batted = BattedBall(trajectory: trajectory, location: location)

        if let kind = hitKind {
            return .hit(kind, batted: chain.isEmpty ? nil : batted, fielder: chain.first)
        }

        guard let first = chain.first else { return nil }

        switch self {
        case .out:
            return .fieldOut(fielders: Self.completed(chain, trajectory: trajectory), batted: batted)
        case .error:
            return .error(fielder: first, batted: batted, basesAwarded: 1)
        case .fieldersChoice:
            return .fieldersChoice(fielders: Self.completedChoice(chain), batted: batted)
        case .doublePlay:
            return .doublePlay(fielders: Self.completedDoublePlay(chain), batted: batted)
        case .triplePlay:
            return .triplePlay(fielders: Self.completedTriplePlay(chain), batted: batted)
        case .sacrificeFly:
            return .sacrificeFly(fielder: first)
        case .sacrificeBunt:
            return .sacrificeBunt(fielders: Self.completed(chain, trajectory: .bunt))
        case .single, .double, .triple, .homeRun:
            return nil
        }
    }

    // MARK: - Filling in what the scorer didn't type

    /// An explicit chain is never second-guessed. A single fielder gets the
    /// throw to first added, unless the ball was caught in the air or the first
    /// baseman made the play unassisted.
    private static func completed(_ chain: [Position], trajectory: Trajectory) -> [Position] {
        guard chain.count == 1, let only = chain.first else { return chain }
        if trajectory.isInAir { return chain }
        if only == .firstBase { return chain }
        return [only, .firstBase]
    }

    private static func completedChoice(_ chain: [Position]) -> [Position] {
        guard chain.count == 1, let only = chain.first else { return chain }
        return only == .secondBase ? [only, .shortstop] : [only, .secondBase]
    }

    private static func completedDoublePlay(_ chain: [Position]) -> [Position] {
        guard chain.count == 1, let only = chain.first else { return chain }
        switch only {
        case .secondBase: return [.secondBase, .shortstop, .firstBase]
        case .firstBase: return [.firstBase, .shortstop, .firstBase]
        default: return [only, .secondBase, .firstBase]
        }
    }

    private static func completedTriplePlay(_ chain: [Position]) -> [Position] {
        guard chain.count == 1, let only = chain.first else { return chain }
        return [only, .secondBase, .firstBase]
    }

    /// A fly ball to the outfield reads as a fly; anything on the infield dirt
    /// reads as a grounder until told otherwise.
    static func defaultTrajectory(for fielder: Position) -> Trajectory {
        fielder.isOutfielder ? .flyBall : .grounder
    }

    /// The ring is context-aware: a double play is only offered with someone to
    /// erase, a sacrifice fly only when one is actually possible, and with no
    /// fielder entered at all only the hits remain.
    static func choices(for state: GameState, chain: [Position]) -> [BallInPlayChoice] {
        let hits: [BallInPlayChoice] = [.single, .double, .triple, .homeRun]
        guard let first = chain.first else { return hits }

        var choices: [BallInPlayChoice] = hits + [.error, .fieldersChoice]

        let runners = state.bases.runnerCount
        if runners > 0 && state.outs < 2 {
            choices.append(.doublePlay)
        }
        if runners > 1 && state.outs == 0 {
            choices.append(.triplePlay)
        }
        if state.bases.third != nil, state.outs < 2, first.isOutfielder || chain.count == 1 {
            choices.append(.sacrificeFly)
        }
        if runners > 0, state.outs < 2 {
            choices.append(.sacrificeBunt)
        }
        return choices
    }
}

/// The result ring: `OUT` sits under the thumb where it was released, and
/// everything else fans out around it. The common case costs one tap and no
/// travel; the rare cases are one short reach away.
struct ResultRing: View {
    var choices: [BallInPlayChoice]
    /// The fielding chain entered so far. Empty means nobody touched it, and
    /// the ring offers hits only.
    var chain: [Position]
    var trajectory: Trajectory
    var showsTrajectoryPicker: Bool
    /// Shifts the ring toward the scoring thumb so `OUT` lands roughly where
    /// the finger already was when it left the dial.
    var thumbBias: CGFloat = 0
    var onPick: (BallInPlayChoice) -> Void
    var onChangeTrajectory: (Trajectory) -> Void
    var onCancel: () -> Void

    private var radius: CGFloat { choices.count > 6 ? 104 : 86 }
    private var hasFielder: Bool { !chain.isEmpty }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.62)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { onCancel() }

            VStack(spacing: 16) {
                header

                if showsTrajectoryPicker && hasFielder {
                    trajectoryPicker
                }

                ring
            }
            .offset(x: thumbBias)
            .padding(.horizontal, 16)
            .padding(.bottom, 28)
        }
        .transition(.opacity)
    }

    private var header: some View {
        VStack(spacing: 5) {
            Text(hasFielder ? ChainFormatter.text(chain) : "NO FIELDER")
                .font(Theme.Typeface.notation(30, weight: .heavy))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text(hasFielder ? trajectory.label : "Hit or home run")
                .font(Theme.Typeface.caption())
                .foregroundStyle(.white.opacity(0.55))
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
                        .padding(.horizontal, 11)
                        .padding(.vertical, 7)
                        .background(
                            Capsule().fill(
                                option == trajectory ? Theme.accent : Color.white.opacity(0.14)
                            )
                        )
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// With a fielder entered, `OUT` is the centre default. Without one there
    /// is no sensible default, so the ring is drawn as a plain fan.
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

            if hasFielder {
                ChoiceButton(choice: .out, isPrimary: true) { onPick(.out) }
            } else {
                Text("TAP\nONE")
                    .font(Theme.Typeface.label(12, weight: .bold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.35))
            }
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
                .frame(width: isPrimary ? 84 : 56, height: isPrimary ? 84 : 56)
                .background(Circle().fill(choice.tint))
                .shadow(color: .black.opacity(0.45), radius: 8, y: 3)
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
        case .triplePlay: "Triple play"
        case .sacrificeFly: "Sacrifice fly"
        case .sacrificeBunt: "Sacrifice bunt"
        }
    }
}

/// Renders a fielding chain the way it's written in a book: `6-4-3`.
enum ChainFormatter {
    static func text(_ chain: [Position]) -> String {
        chain.map { String($0.rawValue) }.joined(separator: "-")
    }

    static func spoken(_ chain: [Position]) -> String {
        chain.map { String($0.rawValue) }.joined(separator: " ")
    }
}
