import SwiftUI

/// Transient state for a ball in play, from the moment the thumb leaves the
/// in-play pad until a result is committed.
private struct BallInPlayState {
    var isDialActive = false
    /// The dial was opened by a tap and stays up until something is chosen,
    /// rather than following a finger that's still down.
    var isLatched = false
    var finger: CGPoint?
    /// Whether the current drag has travelled far enough to be a drag at all.
    /// A press that never moves is a tap, and a tap latches the dial.
    var didMove = false
    var selection: Position?
    /// The fielding chain being built, in the order the ball was handled.
    var chain: [Position] = []
    var trajectory: Trajectory = .grounder
    var showsRing = false

    mutating func closeDial() {
        isDialActive = false
        isLatched = false
        finger = nil
        didMove = false
        selection = nil
    }

    mutating func reset() {
        closeDial()
        chain = []
        showsRing = false
    }
}

/// The one-handed scoring screen.
///
/// Everything you touch lives in one thumb's arc of the bottom corner. The top
/// of the screen is read-only — it exists for the glance you take between
/// pitches, not for input.
struct OneHandedScoringView: View {
    @Environment(GameStore.self) private var store

    @State private var flow = BallInPlayState()
    @State private var pendingVelocity: Int?
    @State private var pendingPitchType: PitchType?
    @State private var showsChallengeSheet = false
    @State private var showsDetailRail = false

    private let space = "scoringSpace"

    private var settings: TrackingSettings { store.settings }
    private var mirror: CGFloat { settings.handedness == .right ? 1 : -1 }
    private var clusterAlignment: Alignment {
        settings.handedness == .right ? .bottomTrailing : .bottomLeading
    }

    var body: some View {
        ZStack(alignment: clusterAlignment) {
            Theme.background.ignoresSafeArea()

            readout

            thumbCluster

            if flow.isDialActive {
                dialOverlay
            }

            if flow.showsRing {
                ResultRing(
                    choices: BallInPlayChoice.choices(for: store.state, chain: flow.chain),
                    chain: flow.chain,
                    trajectory: flow.trajectory,
                    showsTrajectoryPicker: settings.notationDetail == .full,
                    thumbBias: 36 * mirror,
                    onPick: { commit(choice: $0) },
                    onChangeTrajectory: { flow.trajectory = $0 },
                    onCancel: { flow.reset() }
                )
            }

            if showsChallengeSheet, let pitch = store.challengeablePitch {
                ChallengeSheet(
                    pitch: pitch,
                    teams: store.teams,
                    battingSide: store.state.battingSide,
                    challengesRemaining: store.challengesRemaining,
                    suggestedRole: store.suggestedChallengeRole,
                    onCommit: { role, result in
                        store.recordChallenge(role: role, result: result)
                        showsChallengeSheet = false
                    },
                    onCancel: { showsChallengeSheet = false }
                )
            }
        }
        .coordinateSpace(name: space)
        .onAppear { Haptics.shared.prepare() }
    }

    // MARK: - Read-only top half

    private var readout: some View {
        VStack(spacing: 10) {
            ScoreBar(state: store.state, teams: store.teams)

            BatterCard(
                batter: store.currentBatter,
                position: store.currentBatterPosition,
                pitches: store.state.currentAtBatPitches,
                bases: store.state.bases,
                runnerName: { store.runnerOnBase($0)?.shortName },
                headline: store.lastHeadline
            )

            challengePrompt

            Spacer(minLength: 0)

            detailRail
        }
        .padding(.horizontal, Theme.Metrics.screenMargin)
        .padding(.top, 6)
        .padding(.bottom, 296)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.easeOut(duration: 0.2), value: store.lastHeadline)
    }

    /// Only on screen while the call is actually reviewable, which is the rule
    /// the challenge system already works by.
    @ViewBuilder
    private var challengePrompt: some View {
        if let pitch = store.challengeablePitch, !showsChallengeSheet {
            ChallengePrompt(pitch: pitch) {
                Haptics.shared.tap(enabled: settings.hapticsEnabled)
                withAnimation(.easeOut(duration: 0.16)) {
                    showsChallengeSheet = true
                }
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    // MARK: - Detail rail

    /// Velocity and pitch type, collapsed to a single quiet line until asked
    /// for. They used to sit open in the middle of the screen shouting at a
    /// scorer who mostly doesn't log them — now they're one tap away and
    /// nowhere near the eye.
    @ViewBuilder
    private var detailRail: some View {
        if settings.trackPitchVelocity || settings.trackPitchType {
            VStack(alignment: .trailing, spacing: 8) {
                if showsDetailRail {
                    if settings.trackPitchVelocity {
                        QuickChipRow(
                            title: "MPH",
                            items: Self.velocityPresets.map { ("\($0)", $0) },
                            selection: pendingVelocity,
                            onSelect: { pendingVelocity = (pendingVelocity == $0) ? nil : $0 }
                        )
                    }
                    if settings.trackPitchType {
                        QuickChipRow(
                            title: "TYPE",
                            items: PitchType.common.map { ($0.abbreviation, $0) },
                            selection: pendingPitchType,
                            onSelect: { pendingPitchType = (pendingPitchType == $0) ? nil : $0 }
                        )
                    }
                }

                Button {
                    withAnimation(.easeOut(duration: 0.18)) {
                        showsDetailRail.toggle()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(railSummary)
                            .font(Theme.Typeface.label(11, weight: .semibold))
                        Image(systemName: showsDetailRail ? "chevron.down" : "chevron.up")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .foregroundStyle(railIsSet ? Theme.accent : Theme.tertiaryText)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(Theme.surface))
                    .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var railIsSet: Bool { pendingVelocity != nil || pendingPitchType != nil }

    /// Collapsed, the rail still shows what's armed for the next pitch — the
    /// one thing you'd need to know without opening it.
    private var railSummary: String {
        var parts: [String] = []
        if let pendingVelocity { parts.append("\(pendingVelocity)") }
        if let pendingPitchType { parts.append(pendingPitchType.abbreviation) }
        return parts.isEmpty ? "Pitch detail" : parts.joined(separator: " · ")
    }

    private static let velocityPresets = [82, 88, 92, 95, 98, 102]

    // MARK: - Thumb cluster

    /// The three pads sit on the arc a thumb actually sweeps, not jammed into
    /// the corner: the pitch pad needs room around it for its flick chips, and
    /// a pad flush against the edge would push half of them off screen.
    private var thumbCluster: some View {
        ZStack(alignment: clusterAlignment) {
            pitchPad
                .offset(x: -72 * mirror, y: -58)

            inPlayPad
                .offset(x: -177 * mirror, y: -113)

            undoPad
                .offset(x: -78 * mirror, y: -186)
        }
        .frame(width: 300, height: 280, alignment: clusterAlignment)
    }

    /// Ball left, strike right — the way the count is written. See
    /// `PitchPadLayout` for why that mapping ignores handedness.
    private var pitchPad: some View {
        FlickPad(
            title: "PITCH",
            diameter: Theme.Metrics.primaryPad,
            options: PitchPadLayout.options,
            holdOption: PitchPadLayout.holdOption,
            holdDuration: PitchPadLayout.holdDuration,
            showsDirectionHints: true,
            hapticsEnabled: settings.hapticsEnabled,
            onCommit: { direction in
                guard let outcome = PitchPadLayout.outcome(for: direction) else { return }
                if outcome == .inPlay {
                    latchDialOpen()
                } else {
                    recordPitch(outcome)
                }
            },
            onHold: {
                recordPitch(PitchPadLayout.heldOutcome)
            }
        )
    }

    private var inPlayPad: some View {
        ZStack {
            Circle()
                .fill(Theme.inPlay.opacity(flow.isDialActive ? 0.34 : 0.14))
                .overlay(Circle().strokeBorder(Theme.inPlay, lineWidth: 2))
            Text("IN\nPLAY")
                .font(Theme.Typeface.label(13, weight: .bold))
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.inPlay)
        }
        .frame(width: Theme.Metrics.secondaryPad, height: Theme.Metrics.secondaryPad)
        .scaleEffect(flow.isDialActive ? 1.1 : 1)
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: flow.isDialActive)
        .contentShape(Circle())
        .gesture(inPlayGesture)
        .accessibilityElement()
        .accessibilityLabel(Text("Ball in play"))
        .accessibilityHint(Text("Tap to open the fielder dial, or drag straight onto a fielder"))
        .accessibilityActions {
            ForEach(Position.fielders) { position in
                Button(position.fullName) { beginResult(chain: [position], fromDrag: false) }
            }
            Button("Nobody fielded it") { beginResult(chain: [], fromDrag: false) }
        }
    }

    private var undoPad: some View {
        Button {
            store.undo()
        } label: {
            Image(systemName: "arrow.uturn.backward")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Theme.primaryText)
                .frame(width: 52, height: 52)
                .background(Circle().fill(Theme.surfaceRaised))
                .overlay(Circle().strokeBorder(Theme.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(!store.canUndo)
        .opacity(store.canUndo ? 1 : 0.35)
        .accessibilityLabel(Text("Undo last event"))
    }

    // MARK: - Dial

    /// The dial deliberately does not fill the screen. It sits in the lower
    /// third, centred on where the thumb already is, because a field drawn up
    /// by the status bar would put centre field somewhere no thumb can reach.
    private var dialOverlay: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.66)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { cancelDial() }

            VStack(spacing: 8) {
                Text(dialTitle)
                    .font(Theme.Typeface.label(18, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)

                FielderDial(
                    fingerLocation: flow.finger,
                    coordinateSpace: space,
                    hapticsEnabled: settings.hapticsEnabled,
                    isInteractive: flow.isLatched,
                    chain: flow.chain,
                    onSelectionChange: { flow.selection = $0 },
                    onTapPosition: { appendToChain($0) }
                )
                .frame(height: 290)

                if flow.isLatched {
                    chainBar
                } else {
                    Text("Release to score · drag away to cancel")
                        .font(Theme.Typeface.caption())
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            .frame(maxWidth: 360)
            .padding(.horizontal, 18)
            .padding(.bottom, 40)
        }
        // While a finger is still down the overlay must stay transparent to
        // touches, or it would steal the drag from the in-play pad.
        .allowsHitTesting(flow.isLatched)
        .transition(.opacity)
    }

    /// The chain being built, plus the one button that takes it to a result.
    /// With nothing tapped that button is the way to score a ball nobody
    /// touched — which is the only way a home run can honestly be entered.
    private var chainBar: some View {
        VStack(spacing: 10) {
            if !flow.chain.isEmpty {
                HStack(spacing: 10) {
                    Text(ChainFormatter.text(flow.chain))
                        .font(Theme.Typeface.notation(26, weight: .heavy))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)

                    Spacer(minLength: 0)

                    Button {
                        Haptics.shared.undo(enabled: settings.hapticsEnabled)
                        _ = flow.chain.popLast()
                    } label: {
                        Image(systemName: "delete.left.fill")
                            .font(.system(size: 19, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.75))
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Remove last fielder"))
                }
            }

            Button {
                Haptics.shared.commit(enabled: settings.hapticsEnabled)
                beginResult(chain: flow.chain, fromDrag: false)
            } label: {
                HStack(spacing: 8) {
                    Text(primaryChainLabel)
                        .font(Theme.Typeface.label(15, weight: .heavy))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .heavy))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(flow.chain.isEmpty ? Theme.hitByPitch : Theme.accent)
                )
            }
            .buttonStyle(.plain)

            Text(
                flow.chain.isEmpty
                    ? "Or tap the fielders in the order they handled it"
                    : "Tap more fielders to extend the chain"
            )
            .font(Theme.Typeface.caption())
            .foregroundStyle(.white.opacity(0.55))
        }
    }

    private var primaryChainLabel: String {
        flow.chain.isEmpty ? "NOBODY FIELDED IT — HIT OR HR" : "RESULT"
    }

    private var dialTitle: String {
        if !flow.chain.isEmpty {
            return ChainFormatter.text(flow.chain)
        }
        if let selection = flow.selection {
            return "\(selection.rawValue) · \(selection.fullName)"
        }
        return flow.isLatched ? "Who handled it?" : "Slide to a fielder"
    }

    private var inPlayGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(space))
            .onChanged { value in
                if !flow.isDialActive {
                    flow.isDialActive = true
                    flow.isLatched = false
                    flow.didMove = false
                    flow.chain = []
                    Haptics.shared.tap(enabled: settings.hapticsEnabled)
                }
                let travel = (
                    value.translation.width * value.translation.width
                        + value.translation.height * value.translation.height
                ).squareRoot()
                if travel > 8 {
                    flow.didMove = true
                }
                flow.finger = value.location
            }
            .onEnded { _ in
                let fielder = flow.selection
                let moved = flow.didMove
                flow.closeDial()

                // One gesture, no looking: released on a fielder, that's the
                // play. This is the path that has to stay fast.
                if let fielder {
                    Haptics.shared.commit(enabled: settings.hapticsEnabled)
                    beginResult(chain: [fielder], fromDrag: true)
                    return
                }

                // A press that never moved is a tap: leave the dial up so it
                // can be answered with deliberate taps.
                if !moved {
                    latchDialOpen()
                    return
                }
                Haptics.shared.cancelled(enabled: settings.hapticsEnabled)
            }
    }

    // MARK: - Dial modes

    /// Opens the dial and leaves it up. Nothing is recorded yet — a stray tap
    /// costs a dismissal, not an undo.
    private func latchDialOpen() {
        Haptics.shared.tap(enabled: settings.hapticsEnabled)
        withAnimation(.easeOut(duration: 0.16)) {
            flow.isDialActive = true
            flow.isLatched = true
        }
        flow.finger = nil
        flow.selection = nil
        flow.didMove = false
        flow.chain = []
    }

    /// Latched taps build the chain rather than committing, so a rundown can be
    /// entered exactly as it happened.
    private func appendToChain(_ position: Position) {
        withAnimation(.easeOut(duration: 0.14)) {
            flow.chain.append(position)
        }
        if settings.spokenConfirmations {
            Announcer.shared.say(ChainFormatter.spoken(flow.chain))
        }
    }

    private func cancelDial() {
        guard flow.isLatched else { return }
        Haptics.shared.cancelled(enabled: settings.hapticsEnabled)
        withAnimation(.easeOut(duration: 0.16)) {
            flow.reset()
        }
    }

    // MARK: - Committing

    private func beginResult(chain: [Position], fromDrag: Bool) {
        flow.closeDial()
        flow.chain = chain
        flow.trajectory = chain.first.map { BallInPlayChoice.defaultTrajectory(for: $0) } ?? .flyBall

        // The no-look shortcut only applies to the one-gesture drag. Someone
        // who deliberately tapped out 6-4-3 wants to say what it was.
        if settings.assumeOutOnDialRelease, fromDrag, !chain.isEmpty {
            commit(choice: .out)
        } else {
            withAnimation(.easeOut(duration: 0.18)) {
                flow.showsRing = true
            }
        }
    }

    private func commit(choice: BallInPlayChoice) {
        let location: FieldLocation? = {
            guard settings.trackBallLocation, let fielder = flow.chain.first else { return nil }
            let unit = FieldGeometry.unitPoint(for: fielder)
            return FieldLocation(x: unit.x, y: unit.y)
        }()

        guard
            let outcome = choice.outcome(
                chain: flow.chain,
                trajectory: flow.trajectory,
                location: location
            )
        else {
            flow.reset()
            return
        }

        // The pitch and its result are one action to the scorer, so they are
        // recorded together and undone together.
        store.beginGroup()
        recordPitch(.inPlay)
        store.recordPlay(outcome)
        store.endGroup()

        flow.reset()
    }

    private func recordPitch(_ outcome: PitchOutcome) {
        store.recordPitch(
            outcome: outcome,
            velocity: pendingVelocity,
            type: pendingPitchType
        )
        pendingVelocity = nil
        pendingPitchType = nil
    }
}

/// Compact single-line picker used for velocity and pitch type.
struct QuickChipRow<Value: Hashable>: View {
    var title: String
    var items: [(String, Value)]
    var selection: Value?
    var onSelect: (Value) -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(Theme.Typeface.overline(9))
                .tracking(1.2)
                .foregroundStyle(Theme.tertiaryText)
                .frame(width: 30, alignment: .leading)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    ForEach(items.indices, id: \.self) { index in
                        let item = items[index]
                        Button {
                            onSelect(item.1)
                        } label: {
                            Text(item.0)
                                .font(Theme.Typeface.label(13, weight: .semibold))
                                .foregroundStyle(
                                    selection == item.1 ? Theme.background : Theme.secondaryText
                                )
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(
                                    Capsule().fill(
                                        selection == item.1 ? Theme.accent : Theme.surfaceRaised
                                    )
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 1)
            }
        }
    }
}
