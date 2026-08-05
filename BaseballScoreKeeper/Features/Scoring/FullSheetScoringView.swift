import SwiftUI

/// The two-handed layout: everything reachable at once, on one fixed screen.
///
/// The trade against the one-handed screen is the opposite one. Nothing is
/// hidden behind a gesture and nothing scrolls — a rare play is always visible,
/// at the cost of needing two hands and a look. Since it needs a look anyway,
/// controls are free to spread out across the whole screen rather than staying
/// in a thumb's arc.
///
/// The layout is deliberately fixed-height: the field takes whatever is left
/// over after the fixed rows, so the screen composes on any phone without a
/// scroll view. If something has to give, it's the size of the field, not the
/// reachability of a button.
struct FullSheetScoringView: View {
    @Environment(GameStore.self) private var store

    /// The fielding chain being built, in the order the ball was handled.
    @State private var chain: [Position] = []
    @State private var pickedLocation: FieldLocation?
    @State private var trajectory: Trajectory = .grounder
    @State private var pendingVelocity: Int?
    @State private var pendingPitchType: PitchType?
    @State private var showsChallengeSheet = false

    private var settings: TrackingSettings { store.settings }

    var body: some View {
        VStack(spacing: 8) {
            header
            pitchRow
            fieldPanel
            resultPanel
            bottomRail
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .appBackground()
        .overlay {
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
    }

    // MARK: - Header

    /// Score, count, bases, batter and the last call, in one card. The
    /// one-handed screen can afford two cards; this one can't.
    private var header: some View {
        VStack(spacing: 8) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 1) {
                    teamLine(.away)
                    teamLine(.home)
                }

                Spacer(minLength: 4)

                VStack(alignment: .trailing, spacing: 5) {
                    Text(inningText)
                        .font(Theme.Typeface.label(11, weight: .heavy))
                        .tracking(1)
                        .foregroundStyle(Theme.secondaryText)
                    CountPips(balls: store.state.balls, strikes: store.state.strikes, dotSize: 6)
                    OutsPips(outs: store.state.outs, dotSize: 6)
                }

                BaseDiamond(bases: store.state.bases, size: 50)
            }

            batterLine
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .scorecardSurface(cornerRadius: 16)
    }

    private func teamLine(_ side: Side) -> some View {
        let isBatting = store.state.battingSide == side && !store.state.isFinal
        return HStack(spacing: 7) {
            Text(store.teams[side].abbreviation)
                .font(Theme.Typeface.label(13, weight: .heavy))
                .foregroundStyle(isBatting ? Theme.primaryText : Theme.secondaryText)
                .frame(width: 38, alignment: .leading)
            Text("\(store.state.runs(for: side))")
                .font(Theme.Typeface.display(24))
                .foregroundStyle(isBatting ? Theme.primaryText : Theme.secondaryText)
                .contentTransition(.numericText())
                .animation(.easeOut(duration: 0.2), value: store.state.runs(for: side))
        }
    }

    private var batterLine: some View {
        HStack(spacing: 7) {
            if let batter = store.currentBatter {
                Text(batter.number.isEmpty ? "—" : batter.number)
                    .font(Theme.Typeface.score(11))
                    .foregroundStyle(Theme.tertiaryText)
                Text(batter.shortName.uppercased())
                    .font(Theme.Typeface.label(14, weight: .heavy))
                    .foregroundStyle(Theme.primaryText)
                if let position = store.currentBatterPosition {
                    Text(position.abbreviation)
                        .font(Theme.Typeface.overline(9))
                        .foregroundStyle(Theme.tertiaryText)
                }
            }

            if !store.state.currentAtBatPitches.isEmpty {
                Text(store.currentAtBatMarks.joined(separator: " "))
                    .font(Theme.Typeface.notation(11))
                    .foregroundStyle(Theme.secondaryText)
            }

            Spacer(minLength: 0)

            if store.challengeablePitch != nil {
                Button {
                    showsChallengeSheet = true
                } label: {
                    Text("CHALLENGE")
                        .font(Theme.Typeface.overline(9))
                        .tracking(0.8)
                        .foregroundStyle(Theme.background)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Theme.foul))
                }
                .buttonStyle(.plain)
            } else if !store.lastHeadline.isEmpty {
                Text(store.lastHeadline)
                    .font(Theme.Typeface.label(11, weight: .medium))
                    .foregroundStyle(Theme.tertiaryText)
                    .lineLimit(1)
            }
        }
        .frame(height: 20)
    }

    private var inningText: String {
        store.state.isFinal ? "FINAL" : "\(store.state.half == .top ? "▲" : "▼") \(store.state.inning)"
    }

    // MARK: - Pitches

    private var pitchRow: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                pitchButton(.ball)
                pitchButton(.calledStrike)
                pitchButton(.swingingStrike)
            }
            HStack(spacing: 6) {
                pitchButton(.foul)
                pitchButton(.hitByPitch)
                pitchButton(.wildPitch)
            }
        }
    }

    private func pitchButton(_ outcome: PitchOutcome) -> some View {
        let tint = Theme.color(for: outcome)
        return Button {
            record(pitch: outcome)
        } label: {
            Text(outcome.shortLabel)
                .font(Theme.Typeface.label(15, weight: .heavy))
                .foregroundStyle(tint)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .luminousFill(tint, cornerRadius: 13)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Field

    /// The only flexible row. Everything else is fixed, so this absorbs the
    /// difference between a Pro Max and an SE.
    private var fieldPanel: some View {
        FieldPlotView(
            selectedPosition: chain.last,
            chain: chain,
            fillsAvailableSpace: true,
            onPick: { location, fielder in
                pickedLocation = location
                append(fielder)
            }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Theme.hairline, lineWidth: 1)
        )
        .overlay(alignment: .topLeading) { chainBadge }
        .layoutPriority(1)
    }

    /// Sits on the field itself rather than taking a row of its own.
    private var chainBadge: some View {
        HStack(spacing: 8) {
            Text(chain.isEmpty ? "TAP WHO HANDLED IT" : ChainFormatter.text(chain))
                .font(
                    chain.isEmpty
                        ? Theme.Typeface.overline(9)
                        : Theme.Typeface.notation(18, weight: .heavy)
                )
                .tracking(chain.isEmpty ? 1 : 0)
                .foregroundStyle(chain.isEmpty ? Theme.secondaryText : Theme.primaryText)

            if !chain.isEmpty {
                Button {
                    _ = chain.popLast()
                } label: {
                    Image(systemName: "delete.left.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.secondaryText)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Remove last fielder"))

                Button {
                    clearPick()
                } label: {
                    Text("CLEAR")
                        .font(Theme.Typeface.overline(9))
                        .foregroundStyle(Theme.accent)
                }
                .buttonStyle(.plain)
            }

            if !chain.isEmpty {
                trajectoryMenu
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Capsule().fill(Theme.background.opacity(0.82)))
        .padding(8)
    }

    private var trajectoryMenu: some View {
        Menu {
            ForEach(Trajectory.allCases) { option in
                Button(option.label) { trajectory = option }
            }
        } label: {
            Text(trajectory.label.uppercased())
                .font(Theme.Typeface.overline(9))
                .foregroundStyle(Theme.accent)
        }
    }

    // MARK: - Results

    /// Two rows, grouped the way a scorer thinks: reached on top, retired
    /// below. Fourteen outcomes with nothing hidden and nothing to scroll.
    private var resultPanel: some View {
        VStack(spacing: 6) {
            HStack(spacing: 5) {
                ForEach(Self.reachedChoices) { choice in
                    resultButton(choice)
                }
                directButton("BB", tint: Theme.ball) {
                    store.recordPlay(.walk(intentional: false))
                }
            }
            HStack(spacing: 5) {
                ForEach(Self.retiredChoices) { choice in
                    resultButton(choice)
                }
                directButton("K", tint: Theme.miss) {
                    store.recordPlay(.strikeout(looking: false, uncaught: false))
                }
                // The called-strikeout's backwards K is the app's own "K" glyph
                // flipped, so it's the same rounded typeface as everything else
                // rather than a stray character borrowed from another font.
                directButton(tint: Theme.calledStrike) {
                    store.recordPlay(.strikeout(looking: true, uncaught: false))
                } label: {
                    Text("K")
                        .font(Theme.Typeface.label(14, weight: .heavy))
                        .foregroundStyle(Theme.calledStrike)
                        .scaleEffect(x: -1, y: 1)
                }
                .accessibilityLabel(Text("Called strikeout"))
            }
        }
    }

    private static let reachedChoices: [BallInPlayChoice] =
        [.single, .double, .triple, .homeRun, .error, .fieldersChoice]
    private static let retiredChoices: [BallInPlayChoice] =
        [.out, .doublePlay, .triplePlay, .sacrificeFly, .sacrificeBunt]

    @ViewBuilder
    private func resultButton(_ choice: BallInPlayChoice) -> some View {
        let enabled = !choice.requiresFielder || !chain.isEmpty

        // An error has to be charged to someone. With more than one fielder in
        // the play, tapping E first asks which of them booted it.
        if choice == .error, enabled, uniqueFielders.count > 1 {
            Menu {
                ForEach(uniqueFielders) { fielder in
                    Button("\(fielder.rawValue)  ·  \(fielder.abbreviation)") {
                        commitError(fielder: fielder)
                    }
                }
            } label: {
                resultLabel(choice.title, tint: choice.tint, enabled: true)
            }
        } else {
            Button {
                commit(choice)
            } label: {
                resultLabel(choice.title, tint: choice.tint, enabled: enabled)
            }
            .buttonStyle(.plain)
            .disabled(!enabled)
            .opacity(enabled ? 1 : 0.5)
        }
    }

    private func resultLabel(_ title: String, tint: Color, enabled: Bool) -> some View {
        Text(title)
            .font(Theme.Typeface.label(14, weight: .heavy))
            .foregroundStyle(enabled ? tint : Theme.tertiaryText)
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .luminousFill(enabled ? tint : Theme.neutral.opacity(0.4), cornerRadius: 11)
    }

    /// The fielders in the current chain, de-duplicated but kept in the order
    /// they touched the ball — the choices when charging an error.
    private var uniqueFielders: [Position] {
        var seen: Set<Position> = []
        return chain.filter { seen.insert($0).inserted }
    }

    private func directButton(_ title: String, tint: Color, action: @escaping () -> Void) -> some View {
        directButton(tint: tint, action: action) {
            Text(title)
                .font(Theme.Typeface.label(14, weight: .heavy))
                .foregroundStyle(tint)
        }
    }

    /// Same pill as above, but with a custom label — used for the mirrored-K
    /// called strikeout, which can't be expressed as a plain string.
    private func directButton<Label: View>(
        tint: Color,
        action: @escaping () -> Void,
        @ViewBuilder label: () -> Label
    ) -> some View {
        Button(action: action) {
            label()
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .luminousFill(tint, cornerRadius: 11)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Bottom rail

    private static let velocities = Array(55...106)
    private var showsWheels: Bool { settings.trackPitchVelocity || settings.trackPitchType }

    /// Baserunning on the left, and the pitch-detail wheels sitting right there
    /// on the right — no window to open. You spin MPH and type to what you saw
    /// and they stay set for the next pitch.
    private var bottomRail: some View {
        HStack(alignment: .center, spacing: 8) {
            // Only this strip can ever scroll, and only with the bases loaded.
            // A rail that reflowed to two rows would move every button below it.
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(store.state.bases.occupied) { base in
                        railButton("SB\(base.rawValue)", tint: Theme.ball, label: "Stolen base from \(base.label)") {
                            store.record(.stolenBase(from: base))
                        }
                        railButton("CS\(base.rawValue)", tint: Theme.miss, label: "Caught stealing from \(base.label)") {
                            store.record(.caughtStealing(from: base))
                        }
                    }
                    railButton("PB", tint: Theme.neutral, label: "Passed ball, runners advance") {
                        store.record(.passedBallAdvance)
                    }
                    railButton("BK", tint: Theme.neutral, label: "Balk") {
                        store.record(.balk)
                    }
                }
            }

            Spacer(minLength: 0)

            if settings.trackPitchVelocity {
                velocityWheel
            }
            if settings.trackPitchType {
                typeWheel
            }
        }
        .frame(height: showsWheels ? 78 : 34)
    }

    /// A compact wheel that keeps its own "—" for "not set". Narrow and clipped
    /// so two of them and the baserunning strip all sit on one line.
    private var velocityWheel: some View {
        wheelColumn("MPH") {
            Picker("MPH", selection: $pendingVelocity) {
                Text("—").tag(Int?.none)
                ForEach(Self.velocities, id: \.self) { value in
                    Text("\(value)").tag(Int?.some(value))
                }
            }
        }
    }

    private var typeWheel: some View {
        wheelColumn("TYPE") {
            Picker("TYPE", selection: $pendingPitchType) {
                Text("—").tag(PitchType?.none)
                ForEach(PitchType.allCases) { pitch in
                    Text(pitch.abbreviation).tag(PitchType?.some(pitch))
                }
            }
        }
    }

    private func wheelColumn<Content: View>(
        _ title: String,
        @ViewBuilder picker: () -> Content
    ) -> some View {
        VStack(spacing: 0) {
            Text(title)
                .font(Theme.Typeface.overline(8))
                .tracking(1)
                .foregroundStyle(Theme.tertiaryText)
            picker()
                .pickerStyle(.wheel)
                .labelsHidden()
                .frame(width: 62, height: 62)
                .clipped()
        }
    }

    private func railButton(
        _ title: String,
        tint: Color,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(Theme.Typeface.label(12, weight: .bold))
                .foregroundStyle(tint)
                .padding(.horizontal, 11)
                .frame(height: 30)
                .luminousCapsule(tint)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
    }

    // MARK: - Actions

    private func append(_ fielder: Position) {
        if chain.isEmpty {
            trajectory = BallInPlayChoice.defaultTrajectory(for: fielder)
        }
        chain.append(fielder)
        Haptics.shared.tap(enabled: settings.hapticsEnabled)
    }

    private func record(pitch outcome: PitchOutcome) {
        store.recordPitch(outcome: outcome, velocity: pendingVelocity, type: pendingPitchType)
        pendingVelocity = nil
        pendingPitchType = nil
    }

    private func commit(_ choice: BallInPlayChoice) {
        guard
            let outcome = choice.outcome(
                chain: chain,
                trajectory: trajectory,
                location: settings.trackBallLocation ? pickedLocation : nil
            )
        else { return }

        store.beginGroup()
        record(pitch: .inPlay)
        store.recordPlay(outcome)
        store.endGroup()

        clearPick()
    }

    /// Commits an error charged to a specific fielder, chosen from the play.
    private func commitError(fielder: Position) {
        guard
            let outcome = BallInPlayChoice.error.outcome(
                chain: chain,
                trajectory: trajectory,
                location: settings.trackBallLocation ? pickedLocation : nil,
                errorFielder: fielder
            )
        else { return }

        store.beginGroup()
        record(pitch: .inPlay)
        store.recordPlay(outcome)
        store.endGroup()

        clearPick()
    }

    private func clearPick() {
        chain = []
        pickedLocation = nil
    }
}
