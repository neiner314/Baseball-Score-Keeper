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
    /// play waiting to be recorded and the runners still to be placed.
    var pendingOutcome: PlayOutcome?
    var advancePrompts: [RunnerAdvancePrompt] = []

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
        advancePrompts = []
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

            batterCardMenu

            if !store.state.isFinal {
                OnDeckBar(onDeck: store.onDeckBatter, inTheHole: store.inTheHoleBatter)
            }

            challengePrompt
        }
        .padding(.horizontal, Theme.Metrics.screenMargin)
        .padding(.top, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.easeOut(duration: 0.2), value: store.lastHeadline)
    }

    private var batterCard: some View {
        BatterCard(
            batter: store.currentBatter,
            position: store.currentBatterPosition,
            pitches: store.state.currentAtBatPitches,
            battingLine: store.currentBatterLine,
            seasonStats: store.currentBatter.flatMap { store.seasonStats(for: $0) },
            headline: store.lastHeadline
        )
    }

    /// The at-bat card doubles as the pinch-hitter control: with a bench to
    /// pick from, tapping it swaps a hitter into the slot due up. With an empty
    /// bench it's the plain read-only card.
    @ViewBuilder
    private var batterCardMenu: some View {
        if battingBench.isEmpty {
            batterCard
        } else {
            Menu {
                Section("Pinch hitter") {
                    ForEach(battingBench) { player in
                        Button {
                            pinchHit(player)
                        } label: {
                            Text("\(player.displayNumber) \(player.name)")
                        }
                    }
                }
            } label: {
                batterCard
            }
        }
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
            moundBoxMenu

            RunnerField(
                bases: store.state.bases,
                runnerNumber: { store.runnerOnBase($0)?.number },
                availableRunners: battingBench,
                onSteal: { store.record(.stolenBase(from: $0)) },
                onCaught: { store.record(.caughtStealing(from: $0)) },
                onPinchRun: { base, runner in pinchRun(base, runner) }
            )
            .frame(maxWidth: 150)
            .overlay {
                GrandSlamFireworks(trigger: store.grandSlamCelebration)
            }
        }
        .frame(maxWidth: 178, alignment: .top)
    }

    private var moundBox: some View {
        PitcherPanel(
            pitcher: store.currentPitcher,
            line: store.currentPitcherLine
        )
    }

    /// The mound box doubles as the pitching-change control: with an arm on the
    /// bench, tapping it brings a reliever in. With nobody left it's read-only.
    @ViewBuilder
    private var moundBoxMenu: some View {
        if availablePitchers.isEmpty {
            moundBox
        } else {
            Menu {
                Section("Pitching change") {
                    ForEach(availablePitchers) { pitcher in
                        Button {
                            changePitcher(to: pitcher)
                        } label: {
                            Text("\(pitcher.displayNumber) \(pitcher.name)")
                        }
                    }
                }
            } label: {
                moundBox
            }
        }
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

    /// The runners the hit put in motion, asked about one at a time on a small
    /// diamond: tap the base they reached, then Safe or Out.
    private var advanceOverlay: some View {
        RunnerAdvanceView(
            prompts: flow.advancePrompts,
            hapticsEnabled: settings.hapticsEnabled,
            onComplete: { advances in
                guard let outcome = flow.pendingOutcome else { return }
                record(outcome, manualAdvances: advances)
            },
            onCancel: { cancelAdvance() }
        )
    }

    private func cancelAdvance() {
        withAnimation(.easeOut(duration: 0.16)) {
            flow.pendingOutcome = nil
            flow.advancePrompts = []
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
        if choice == .intentionalWalk {
            recordNonBattedPlay(.walk(intentional: true))
            return
        }
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

    /// A play where the runners already aboard genuinely might go different
    /// places — or be thrown out — opens the advancement prompt first.
    /// Everything else records straight away on the automatic rules.
    private func finalize(_ outcome: PlayOutcome) {
        let bases = store.state.bases
        guard !bases.occupied.isEmpty, Self.allowsAdvancePrompt(outcome) else {
            record(outcome, manualAdvances: nil)
            return
        }

        // Lead runner first — the one the defense is usually playing.
        let prompts: [RunnerAdvancePrompt] = bases.occupied.sorted { $0.rawValue > $1.rawValue }.map { base in
            RunnerAdvancePrompt(
                base: base,
                name: store.runnerOnBase(base)?.shortName ?? "Runner",
                number: store.runnerOnBase(base)?.number ?? "",
                forced: outcome.batterReachesBase && bases.forcedBases.contains(base),
                defaultTarget: ScoringEngine.defaultAdvance(for: outcome, runnerOn: base, bases: bases)
            )
        }

        Haptics.shared.tap(enabled: settings.hapticsEnabled)
        withAnimation(.easeOut(duration: 0.16)) {
            flow.showsRing = false
            flow.errorCandidates = []
            flow.advancePrompts = prompts
            flow.pendingOutcome = outcome
        }
    }

    /// Any ball put in play with runners aboard can move them somewhere the
    /// automatic rules won't guess — a runner tagging up, taking an extra base
    /// on an out, or thrown out trying. So every batted-ball outcome asks,
    /// seeded with the sensible default so the common case is a single confirm.
    /// Only the plays that can't move a standing runner past their forced base
    /// skip it: a strikeout, a free pass, and the home run that scores everyone.
    private static func allowsAdvancePrompt(_ outcome: PlayOutcome) -> Bool {
        switch outcome {
        case .hit(let kind, _, _): return kind != .homeRun
        case .strikeout, .walk, .hitByPitch, .catchersInterference: return false
        default: return true
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

    /// A play that never was a batted ball — an intentional walk picked off the
    /// no-fielder ring — is recorded on its own, with no in-play pitch in front
    /// of it, since nothing was actually put in play.
    private func recordNonBattedPlay(_ outcome: PlayOutcome) {
        Haptics.shared.commit(enabled: settings.hapticsEnabled)
        store.recordPlay(outcome, manualAdvances: nil)
        flow.reset()
    }

    // MARK: - Substitutions

    /// The batting team's bench: anyone who hasn't appeared yet, offered as a
    /// pinch hitter on the at-bat card or a pinch runner on a lit base.
    private var battingBench: [Player] {
        let lineup = store.state.battingLineup
        return store.teams[store.state.battingSide].players
            .filter { !lineup.appearedPlayerIDs.contains($0.id) }
    }

    /// The fielding team's available arms for a pitching change — unused
    /// pitchers, or the whole bench if no true pitcher is left to bring in.
    private var availablePitchers: [Player] {
        let lineup = store.state.fieldingLineup
        let unused = store.teams[store.state.fieldingSide].players
            .filter { !lineup.appearedPlayerIDs.contains($0.id) }
        let pitchers = unused.filter { $0.primaryPosition == .pitcher }
        return pitchers.isEmpty ? unused : pitchers
    }

    private func changePitcher(to pitcher: Player) {
        let lineup = store.state.fieldingLineup
        // The batting order is only touched when the pitcher actually hits —
        // with a DH the change is defense-only.
        let slot = lineup.usesDesignatedHitter
            ? nil
            : lineup.currentPitcherID.flatMap { lineup.slotIndex(of: $0) }
        store.substitute(
            Substitution(
                side: store.state.fieldingSide,
                kind: .pitchingChange,
                incomingPlayerID: pitcher.id,
                outgoingPlayerID: lineup.currentPitcherID,
                battingSlot: slot,
                position: .pitcher,
                runnerBase: nil
            )
        )
    }

    private func pinchHit(_ player: Player) {
        let lineup = store.state.battingLineup
        guard !lineup.slots.isEmpty else { return }
        let slotIndex = lineup.battingIndex % lineup.slots.count
        let slot = lineup.slots[slotIndex]
        store.substitute(
            Substitution(
                side: store.state.battingSide,
                kind: .pinchHitter,
                incomingPlayerID: player.id,
                outgoingPlayerID: slot.playerID,
                battingSlot: slotIndex,
                position: slot.position,
                runnerBase: nil
            )
        )
    }

    private func pinchRun(_ base: Base, _ player: Player) {
        let lineup = store.state.battingLineup
        guard let outgoing = store.state.bases[base]?.playerID else { return }
        let slot = lineup.slotIndex(of: outgoing)
        let position = slot.map { lineup.slots[$0].position } ?? .designatedHitter
        store.substitute(
            Substitution(
                side: store.state.battingSide,
                kind: .pinchRunner,
                incomingPlayerID: player.id,
                outgoingPlayerID: outgoing,
                battingSlot: slot,
                position: position,
                runnerBase: base
            )
        )
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
