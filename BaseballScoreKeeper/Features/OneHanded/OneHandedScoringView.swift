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
    /// When non-empty, the "who booted it?" picker is up for an error, holding
    /// the fielders that could be charged.
    var errorCandidates: [Position] = []
    /// Set while the "where did the runners end up?" prompt is up, holding the
    /// play waiting to be recorded and the chosen destination per runner.
    var pendingOutcome: PlayOutcome?
    var advanceTargets: [Base: AdvanceTarget] = [:]

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
        errorCandidates = []
        pendingOutcome = nil
        advanceTargets = [:]
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

    private let space = "scoringSpace"

    private var settings: TrackingSettings { store.settings }
    private var mirror: CGFloat { settings.handedness == .right ? 1 : -1 }
    private var clusterAlignment: Alignment {
        settings.handedness == .right ? .bottomTrailing : .bottomLeading
    }

    /// How far up the screen the PITCH pad's bottom floats. Roughly a third of
    /// the way up on a modern phone, which keeps it in the thumb's arc while
    /// leaving the line score room to sit along the very bottom edge.
    private let pitchPadBottom: CGFloat = 230

    /// The whole cluster is bottom-pinned then raised. When the pitch-type pad
    /// is showing it hangs below the PITCH pad inside the same column, so the
    /// raise is reduced by its height to keep the PITCH pad itself parked in the
    /// same spot for everyone.
    private var padRaise: CGFloat {
        let belowPitch: CGFloat = (settings.trackPitchType || settings.trackPitchVelocity) ? 102 : 0
        return pitchPadBottom - belowPitch
    }

    var body: some View {
        ZStack(alignment: clusterAlignment) {
            AppBackground()

            topReadout

            lineScoreFooter

            actionRow

            if flow.isDialActive {
                dialOverlay
            }

            if flow.showsRing {
                ResultRing(
                    choices: BallInPlayChoice.choices(for: store.state, chain: flow.chain),
                    chain: flow.chain,
                    trajectory: flow.trajectory,
                    // Always offered: the trajectory is what tells a ground out
                    // from a line out from a pop, which the scorer needs whether
                    // or not they've turned on full notation detail.
                    showsTrajectoryPicker: true,
                    thumbBias: 36 * mirror,
                    onPick: { pick($0) },
                    onChangeTrajectory: { flow.trajectory = $0 },
                    onCancel: { flow.reset() }
                )
            }

            if !flow.errorCandidates.isEmpty {
                errorPickerOverlay
            }

            if flow.pendingOutcome != nil {
                advanceOverlay
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
        .task(id: store.currentPitcher?.id) {
            if let pitcher = store.currentPitcher {
                await store.loadArsenal(for: pitcher)
            }
        }
        .task(id: store.currentBatter?.id) {
            if let batter = store.currentBatter {
                await store.loadSeasonStats(for: batter)
            }
        }
    }

    // MARK: - Read-only top half

    /// The scoreboard and the current at-bat, pinned to the top. This is the
    /// glance you take between pitches; nothing here takes a touch.
    private var topReadout: some View {
        VStack(spacing: 10) {
            ScoreBar(state: store.state, teams: store.teams)

            BatterCard(
                batter: store.currentBatter,
                position: store.currentBatterPosition,
                pitches: store.state.currentAtBatPitches,
                battingLine: store.currentBatterLine,
                seasonStats: store.currentBatter.flatMap { store.seasonStats(for: $0) },
                headline: store.lastHeadline
            )

            challengePrompt
        }
        .padding(.horizontal, Theme.Metrics.screenMargin)
        .padding(.top, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.easeOut(duration: 0.2), value: store.lastHeadline)
    }

    /// The runs-per-inning bar, along the very bottom edge under the pitch pad.
    private var lineScoreFooter: some View {
        LineScoreRibbon(state: store.state, teams: store.teams)
            .padding(.horizontal, Theme.Metrics.screenMargin)
            .padding(.bottom, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }

    // MARK: - Action row

    /// The one region you actually touch: the pitcher's live line floated up
    /// the far side from the thumb, and the thumb column — undo, the pitch pad,
    /// and the pitch-type/velocity pad — on the near side. The whole cluster is
    /// floated a third of the way up so it lands in the thumb's arc rather than
    /// the corner. Tops of the pitcher card and the undo button line up.
    private var actionRow: some View {
        HStack(alignment: .top, spacing: 12) {
            if settings.handedness == .right {
                pitcherPanel
                Spacer(minLength: 0)
                thumbColumn
            } else {
                thumbColumn
                Spacer(minLength: 0)
                pitcherPanel
            }
        }
        .padding(.horizontal, Theme.Metrics.screenMargin)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .offset(y: -padRaise)
    }

    /// The mound box, with the base runners drawn on a small field right under
    /// it. Tapping a runner records a steal or a caught stealing.
    private var pitcherPanel: some View {
        VStack(spacing: 10) {
            PitcherPanel(
                pitcher: store.currentPitcher,
                line: store.currentPitcherLine
            )

            RunnerField(
                bases: store.state.bases,
                runnerNumber: { store.runnerOnBase($0)?.number },
                onSteal: { store.record(.stolenBase(from: $0)) },
                onCaught: { store.record(.caughtStealing(from: $0)) }
            )
            .frame(maxWidth: 150)
        }
        .frame(maxWidth: 178, alignment: .top)
    }

    /// Undo on top, the pitch pad under it, and the pitch-type/velocity pad
    /// below that — nudged toward the centre of the screen so its arc of pitch
    /// labels fans into open space. The inset on the edge the pitch pad sits
    /// against keeps its outermost flick chip on screen.
    private var thumbColumn: some View {
        VStack(alignment: thumbEdgeAlignment, spacing: 0) {
            undoPad
            Spacer().frame(height: 34)
            pitchPad
            if settings.trackPitchType || settings.trackPitchVelocity {
                Spacer().frame(height: 26)
                pitchTypePad
                    .offset(x: 44 * -mirror)
            }
        }
        .padding(settings.handedness == .right ? .trailing : .leading, 44)
    }

    private var thumbEdgeAlignment: HorizontalAlignment {
        settings.handedness == .right ? .trailing : .leading
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

    // MARK: - Pads

    /// The pitch type and its speed in one gesture: swipe to the pitch, hold to
    /// scrub the velocity. Labelled with this pitcher's real arsenal when the
    /// league feed has it, a generic mix otherwise. Only the tracked halves are
    /// live — a scorer logging type but not velocity just picks and lifts.
    private var pitchTypePad: some View {
        PitchTypeVelocityPad(
            arsenal: store.currentPitcher.map { store.arsenal(for: $0) } ?? PitchType.defaultArsenal,
            tracksType: settings.trackPitchType,
            tracksVelocity: settings.trackPitchVelocity,
            mirror: mirror,
            hapticsEnabled: settings.hapticsEnabled,
            armedType: pendingPitchType,
            armedVelocity: pendingVelocity,
            onCommit: { type, velocity in
                if settings.trackPitchType, let type { pendingPitchType = type }
                if settings.trackPitchVelocity, let velocity { pendingVelocity = velocity }
            },
            onClear: {
                pendingPitchType = nil
                pendingVelocity = nil
            }
        )
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

    private var undoPad: some View {
        Button {
            store.undo()
        } label: {
            Image(systemName: "arrow.uturn.backward")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Theme.secondaryText)
                .frame(width: 52, height: 52)
                .luminousCircle(Theme.neutral)
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
                .luminousFill(
                    flow.chain.isEmpty ? Theme.hitByPitch : Theme.accent,
                    cornerRadius: 16,
                    isProminent: true
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

    // MARK: - Runner advancement

    /// "Where did the runners end up?" — each runner already aboard, with the
    /// automatic destination pre-selected so the scorer only taps the ones that
    /// went somewhere else (held at second, took the extra base, thrown out).
    private var advanceOverlay: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.62)
                .ignoresSafeArea()
                .contentShape(Rectangle())

            VStack(spacing: 16) {
                Text("WHERE DID THE RUNNERS END UP?")
                    .font(Theme.Typeface.overline(11))
                    .tracking(1.4)
                    .foregroundStyle(.white.opacity(0.7))

                VStack(spacing: 12) {
                    ForEach(advanceBases) { base in
                        advanceRow(base)
                    }
                }

                HStack(spacing: 10) {
                    Button {
                        cancelAdvance()
                    } label: {
                        Text("BACK")
                            .font(Theme.Typeface.label(14, weight: .heavy))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(Capsule().fill(.white.opacity(0.14)))
                    }
                    .buttonStyle(.plain)

                    Button {
                        commitAdvances()
                    } label: {
                        Text("SCORE IT")
                            .font(Theme.Typeface.label(15, weight: .heavy))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .luminousFill(Theme.accent, cornerRadius: 25, isProminent: true)
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: 380)
            .padding(.horizontal, 18)
            .padding(.bottom, 40)
        }
        .transition(.opacity)
    }

    private var advanceBases: [Base] {
        flow.advanceTargets.keys.sorted { $0.rawValue > $1.rawValue }
    }

    private func advanceRow(_ base: Base) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(base.label)
                    .font(Theme.Typeface.overline(9))
                    .foregroundStyle(.white.opacity(0.5))
                Text(store.runnerOnBase(base)?.shortName ?? "Runner")
                    .font(Theme.Typeface.label(14, weight: .heavy))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(width: 78, alignment: .leading)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    ForEach(Self.targetOptions(for: base), id: \.self) { target in
                        advanceChip(base: base, target: target)
                    }
                }
                .padding(.vertical, 1)
            }
        }
    }

    private func advanceChip(base: Base, target: AdvanceTarget) -> some View {
        let selected = flow.advanceTargets[base] == target
        let tint = Self.advanceTint(target)
        return Button {
            Haptics.shared.zoneChanged(enabled: settings.hapticsEnabled)
            flow.advanceTargets[base] = target
        } label: {
            Text(Self.advanceLabel(target))
                .font(Theme.Typeface.label(13, weight: .bold))
                .foregroundStyle(selected ? .white : tint)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(
                    Capsule().fill(selected ? tint : .white.opacity(0.12))
                )
        }
        .buttonStyle(.plain)
    }

    /// Forward stops only — a runner can hold, take a base ahead, score, or be
    /// thrown out, but never retreat.
    private static func targetOptions(for base: Base) -> [AdvanceTarget] {
        switch base {
        case .first: [.held, .second, .third, .home, .out]
        case .second: [.held, .third, .home, .out]
        case .third: [.held, .home, .out]
        }
    }

    private static func advanceLabel(_ target: AdvanceTarget) -> String {
        switch target {
        case .held: "Hold"
        case .first: "1st"
        case .second: "2nd"
        case .third: "3rd"
        case .home: "Score"
        case .out: "Out"
        }
    }

    private static func advanceTint(_ target: AdvanceTarget) -> Color {
        switch target {
        case .out: Theme.miss
        case .home: Theme.ball
        default: Theme.accent
        }
    }

    private func commitAdvances() {
        guard let outcome = flow.pendingOutcome else { return }
        let advances = flow.advanceTargets.map { ManualAdvance(from: $0.key, to: $0.value) }
        Haptics.shared.commit(enabled: settings.hapticsEnabled)
        record(outcome, manualAdvances: advances)
    }

    private func cancelAdvance() {
        withAnimation(.easeOut(duration: 0.16)) {
            flow.pendingOutcome = nil
            flow.advanceTargets = [:]
            flow.showsRing = true
        }
    }

    /// "Who booted it?" — the fielders from the play, laid out for a thumb, so
    /// the error goes to the right glove rather than always the first one.
    private var errorPickerOverlay: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.62)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { cancelErrorPicker() }

            VStack(spacing: 14) {
                Text("WHO COMMITTED THE ERROR?")
                    .font(Theme.Typeface.overline(11))
                    .tracking(1.4)
                    .foregroundStyle(.white.opacity(0.7))

                HStack(spacing: 12) {
                    ForEach(flow.errorCandidates) { fielder in
                        Button {
                            Haptics.shared.commit(enabled: settings.hapticsEnabled)
                            commit(choice: .error, errorFielder: fielder)
                        } label: {
                            VStack(spacing: 2) {
                                Text("\(fielder.rawValue)")
                                    .font(Theme.Typeface.score(26))
                                    .foregroundStyle(.white)
                                Text(fielder.abbreviation)
                                    .font(Theme.Typeface.caption())
                                    .foregroundStyle(.white.opacity(0.7))
                            }
                            .frame(width: 74, height: 74)
                            .luminousCircle(Theme.foul, isProminent: true)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text("Error on \(fielder.fullName)"))
                    }
                }

                Text("Tap away to go back")
                    .font(Theme.Typeface.caption())
                    .foregroundStyle(.white.opacity(0.5))
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 44)
        }
        .transition(.opacity)
    }

    private func cancelErrorPicker() {
        withAnimation(.easeOut(duration: 0.16)) {
            flow.errorCandidates = []
            flow.showsRing = true
        }
    }

    /// Routes a ring pick: an error with more than one fielder in the play
    /// opens the "who booted it?" picker first; everything else commits.
    private func pick(_ choice: BallInPlayChoice) {
        if choice == .error, uniqueFielders.count > 1 {
            Haptics.shared.tap(enabled: settings.hapticsEnabled)
            withAnimation(.easeOut(duration: 0.16)) {
                flow.showsRing = false
                flow.errorCandidates = uniqueFielders
            }
        } else {
            commit(choice: choice)
        }
    }

    /// The chain's fielders, de-duplicated in the order they touched the ball.
    private var uniqueFielders: [Position] {
        var seen: Set<Position> = []
        return flow.chain.filter { seen.insert($0).inserted }
    }

    private func commit(choice: BallInPlayChoice, errorFielder: Position? = nil) {
        let location: FieldLocation? = {
            guard settings.trackBallLocation, let fielder = flow.chain.first else { return nil }
            let unit = FieldGeometry.unitPoint(for: fielder)
            return FieldLocation(x: unit.x, y: unit.y)
        }()

        guard
            let outcome = choice.outcome(
                chain: flow.chain,
                trajectory: flow.trajectory,
                location: location,
                errorFielder: errorFielder
            )
        else {
            flow.reset()
            return
        }

        finalize(outcome)
    }

    /// A play that moves existing runners in more than one plausible way opens
    /// the advancement prompt first; everything else records straight away.
    private func finalize(_ outcome: PlayOutcome) {
        let occupied = store.state.bases.occupied
        guard !occupied.isEmpty, Self.allowsAdvancePrompt(outcome) else {
            record(outcome, manualAdvances: nil)
            return
        }

        var targets: [Base: AdvanceTarget] = [:]
        for base in occupied {
            targets[base] = ScoringEngine.defaultAdvance(
                for: outcome,
                runnerOn: base,
                bases: store.state.bases
            )
        }

        Haptics.shared.tap(enabled: settings.hapticsEnabled)
        withAnimation(.easeOut(duration: 0.16)) {
            flow.showsRing = false
            flow.errorCandidates = []
            flow.advanceTargets = targets
            flow.pendingOutcome = outcome
        }
    }

    /// Plays where a runner already aboard has a real choice of where to stop.
    /// A walk moves only forced runners, a strikeout moves nobody, and a home
    /// run scores everyone — none of those need asking.
    private static func allowsAdvancePrompt(_ outcome: PlayOutcome) -> Bool {
        switch outcome {
        case .hit(let kind, _, _): return kind != .homeRun
        case .error, .fieldOut, .fieldersChoice, .sacrificeFly: return true
        default: return false
        }
    }

    /// The pitch and its result are one action to the scorer, so they are
    /// recorded together and undone together.
    private func record(_ outcome: PlayOutcome, manualAdvances: [ManualAdvance]?) {
        store.beginGroup()
        recordPitch(.inPlay)
        store.recordPlay(outcome, manualAdvances: manualAdvances)
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
