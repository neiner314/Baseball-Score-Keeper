import SwiftUI

/// Transient state for a ball in play, from the moment the thumb leaves the
/// in-play pad until a result is committed.
private struct BallInPlayState {
    var isDialActive = false
    var finger: CGPoint?
    var selection: Position?
    var pendingFielder: Position?
    var trajectory: Trajectory = .grounder
    var showsRing = false

    mutating func reset() {
        isDialActive = false
        finger = nil
        selection = nil
        pendingFielder = nil
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
    var layout: ScoringLayout

    @State private var flow = BallInPlayState()
    @State private var pendingVelocity: Int?
    @State private var pendingPitchType: PitchType?

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

            if flow.showsRing, let fielder = flow.pendingFielder {
                ResultRing(
                    choices: BallInPlayChoice.choices(for: store.state, fielder: fielder),
                    fielder: fielder,
                    trajectory: flow.trajectory,
                    showsTrajectoryPicker: settings.notationDetail == .full,
                    thumbBias: 36 * mirror,
                    onPick: { commit(choice: $0) },
                    onChangeTrajectory: { flow.trajectory = $0 },
                    onCancel: { flow.reset() }
                )
            }
        }
        .coordinateSpace(name: space)
        .onAppear { Haptics.shared.prepare() }
    }

    // MARK: - Read-only top half

    private var readout: some View {
        VStack(spacing: 0) {
            if layout == .thumbCluster {
                ScoreboardHeader(
                    state: store.state,
                    teams: store.teams,
                    batter: store.currentBatter,
                    lastVelocity: store.state.currentAtBatPitches.last?.velocity,
                    showsVelocity: settings.trackPitchVelocity
                )
                .padding(.top, 12)
            } else {
                CompactScoreHeader(
                    state: store.state,
                    teams: store.teams,
                    batter: store.currentBatter,
                    batterPosition: store.currentBatterPosition,
                    foulCount: foulCount,
                    showsFoulCount: settings.trackFoulAndPitchCounts
                )
                .padding(.horizontal, 18)
                .padding(.top, 8)
            }

            headline

            Spacer(minLength: 0)

            trackingChips

            PitchSequenceStrip(pitches: store.state.currentAtBatPitches)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 18)
                .padding(.bottom, 250)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private var headline: some View {
        if !store.lastHeadline.isEmpty {
            Text(store.lastHeadline)
                .font(Theme.Typeface.label(13, weight: .semibold))
                .foregroundStyle(Theme.secondaryText)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Capsule().fill(Theme.surfaceRaised))
                .padding(.top, 10)
                .transition(.opacity)
                .animation(.easeOut(duration: 0.2), value: store.lastHeadline)
        }
    }

    /// Velocity and pitch type sit directly above the cluster rather than at
    /// the top of the screen — a one-handed grip can't reach the top.
    @ViewBuilder
    private var trackingChips: some View {
        VStack(spacing: 8) {
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
                    title: "PITCH",
                    items: PitchType.common.map { ($0.abbreviation, $0) },
                    selection: pendingPitchType,
                    onSelect: { pendingPitchType = (pendingPitchType == $0) ? nil : $0 }
                )
            }
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 10)
    }

    private static let velocityPresets = [82, 88, 92, 95, 98, 102]

    private var foulCount: Int {
        store.state.currentAtBatPitches.filter { $0.outcome == .foul }.count
    }

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

    private var pitchPad: some View {
        FlickPad(
            title: "Ball",
            diameter: Theme.Metrics.primaryPad,
            options: pitchOptions,
            hapticsEnabled: settings.hapticsEnabled,
            onCommit: { direction in
                guard let outcome = pitchOutcome(for: direction) else { return }
                recordPitch(outcome)
            }
        )
    }

    /// Ball rests under the thumb because it is the single most common pitch
    /// outcome. Strikes are a flick up or outward, foul is down.
    private var pitchOptions: [FlickDirection: FlickOption] {
        let outward: FlickDirection = settings.handedness == .right ? .right : .left
        let inward: FlickDirection = settings.handedness == .right ? .left : .right

        return [
            .center: FlickOption("Ball", tint: Theme.ball),
            .up: FlickOption("Call", tint: Theme.calledStrike),
            outward: FlickOption("Miss", tint: Theme.miss),
            .down: FlickOption("Foul", tint: Theme.foul),
            inward: FlickOption("HBP", tint: Theme.hitByPitch)
        ]
    }

    private func pitchOutcome(for direction: FlickDirection) -> PitchOutcome? {
        let outward: FlickDirection = settings.handedness == .right ? .right : .left

        switch direction {
        case .center: return .ball
        case .up: return .calledStrike
        case .down: return .foul
        case .left, .right: return direction == outward ? .swingingStrike : .hitByPitch
        }
    }

    private var inPlayPad: some View {
        ZStack {
            Circle()
                .fill(Theme.inPlay.opacity(flow.isDialActive ? 0.35 : 0.16))
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
        .accessibilityHint(Text("Drag onto a fielder, then choose the result"))
        .accessibilityActions {
            ForEach(Position.fielders) { position in
                Button(position.fullName) { beginResult(for: position) }
            }
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
            Color.black.opacity(0.6).ignoresSafeArea()

            VStack(spacing: 8) {
                Text(flow.selection.map { "\($0.rawValue) · \($0.fullName)" } ?? "Slide to a fielder")
                    .font(Theme.Typeface.label(19, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                FielderDial(
                    fingerLocation: flow.finger,
                    coordinateSpace: space,
                    hapticsEnabled: settings.hapticsEnabled,
                    onSelectionChange: { flow.selection = $0 }
                )
                .frame(height: 300)

                Text("Release to score · drag away to cancel")
                    .font(Theme.Typeface.caption())
                    .foregroundStyle(.white.opacity(0.65))
            }
            .frame(maxWidth: 340)
            .padding(.horizontal, 18)
            .padding(.bottom, 44)
        }
        .allowsHitTesting(false)
        .transition(.opacity)
    }

    private var inPlayGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(space))
            .onChanged { value in
                if !flow.isDialActive {
                    flow.isDialActive = true
                    Haptics.shared.tap(enabled: settings.hapticsEnabled)
                }
                flow.finger = value.location
            }
            .onEnded { _ in
                let fielder = flow.selection
                flow.isDialActive = false
                flow.finger = nil
                flow.selection = nil

                guard let fielder else {
                    Haptics.shared.cancelled(enabled: settings.hapticsEnabled)
                    return
                }
                Haptics.shared.commit(enabled: settings.hapticsEnabled)
                beginResult(for: fielder)
            }
    }

    // MARK: - Committing

    private func beginResult(for fielder: Position) {
        flow.pendingFielder = fielder
        flow.trajectory = BallInPlayChoice.defaultTrajectory(for: fielder)

        if settings.assumeOutOnDialRelease {
            commit(choice: .out)
        } else {
            withAnimation(.easeOut(duration: 0.18)) {
                flow.showsRing = true
            }
        }
    }

    private func commit(choice: BallInPlayChoice) {
        guard let fielder = flow.pendingFielder else { return }

        let location: FieldLocation? = settings.trackBallLocation
            ? FieldLocation(
                x: FieldGeometry.unitPoint(for: fielder).x,
                y: FieldGeometry.unitPoint(for: fielder).y
            )
            : nil

        // The pitch and its result are one action to the scorer, so they are
        // recorded together and undone together.
        store.beginGroup()
        recordPitch(.inPlay)
        store.recordPlay(
            choice.outcome(fielder: fielder, trajectory: flow.trajectory, location: location)
        )
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
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .tracking(1.2)
                .foregroundStyle(Theme.secondaryText)
                .frame(width: 34, alignment: .leading)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    ForEach(items.indices, id: \.self) { index in
                        let item = items[index]
                        Button {
                            onSelect(item.1)
                        } label: {
                            Text(item.0)
                                .font(Theme.Typeface.label(13, weight: .semibold))
                                .foregroundStyle(selection == item.1 ? .white : Theme.primaryText)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(
                                    Capsule().fill(
                                        selection == item.1 ? Theme.inPlay : Theme.surfaceRaised
                                    )
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}
