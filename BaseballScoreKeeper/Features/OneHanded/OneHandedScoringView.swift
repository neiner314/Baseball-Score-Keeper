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
    var pendingFielder: Position?
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
        .accessibilityHint(Text("Tap to open the fielder dial, or drag straight onto a fielder"))
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
    /// The dial deliberately does not fill the screen. It sits in the lower
    /// third, centred on where the thumb already is, because a field drawn up
    /// by the status bar would put centre field somewhere no thumb can reach.
    private var dialOverlay: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.6)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { cancelDial() }

            VStack(spacing: 8) {
                Text(dialTitle)
                    .font(Theme.Typeface.label(19, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                FielderDial(
                    fingerLocation: flow.finger,
                    coordinateSpace: space,
                    hapticsEnabled: settings.hapticsEnabled,
                    isInteractive: flow.isLatched,
                    onSelectionChange: { flow.selection = $0 },
                    onTapPosition: { selectFromLatchedDial($0) }
                )
                .frame(height: 300)

                Text(dialHint)
                    .font(Theme.Typeface.caption())
                    .foregroundStyle(.white.opacity(0.65))
            }
            .frame(maxWidth: 340)
            .padding(.horizontal, 18)
            .padding(.bottom, 44)
        }
        // While a finger is still down the overlay must stay transparent to
        // touches, or it would steal the drag from the in-play pad.
        .allowsHitTesting(flow.isLatched)
        .transition(.opacity)
    }

    private var dialTitle: String {
        if let selection = flow.selection {
            return "\(selection.rawValue) · \(selection.fullName)"
        }
        return flow.isLatched ? "Who fielded it?" : "Slide to a fielder"
    }

    private var dialHint: String {
        flow.isLatched
            ? "Tap a fielder · tap anywhere else to cancel"
            : "Release to score · drag away to cancel"
    }

    private var inPlayGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(space))
            .onChanged { value in
                if !flow.isDialActive {
                    flow.isDialActive = true
                    flow.isLatched = false
                    flow.didMove = false
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

                if let fielder {
                    Haptics.shared.commit(enabled: settings.hapticsEnabled)
                    beginResult(for: fielder)
                    return
                }

                // A press that never moved is a tap: leave the dial up so it
                // can be answered with a second, deliberate tap.
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
    }

    private func selectFromLatchedDial(_ position: Position) {
        flow.closeDial()
        beginResult(for: position)
    }

    private func cancelDial() {
        guard flow.isLatched else { return }
        Haptics.shared.cancelled(enabled: settings.hapticsEnabled)
        withAnimation(.easeOut(duration: 0.16)) {
            flow.closeDial()
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
