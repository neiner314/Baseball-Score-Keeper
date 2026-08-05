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

    private static let velocityPresets = [78, 82, 85, 88, 90, 92, 94, 95, 96, 98, 100, 102]

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

            if settings.notationDetail == .full, !chain.isEmpty {
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
                directButton("ꓘ", tint: Theme.calledStrike) {
                    store.recordPlay(.strikeout(looking: true, uncaught: false))
                }
            }
        }
    }

    private static let reachedChoices: [BallInPlayChoice] =
        [.single, .double, .triple, .homeRun, .error, .fieldersChoice]
    private static let retiredChoices: [BallInPlayChoice] =
        [.out, .doublePlay, .triplePlay, .sacrificeFly, .sacrificeBunt]

    private func resultButton(_ choice: BallInPlayChoice) -> some View {
        let enabled = !choice.requiresFielder || !chain.isEmpty
        return Button {
            commit(choice)
        } label: {
            Text(choice.title)
                .font(Theme.Typeface.label(14, weight: .heavy))
                .foregroundStyle(enabled ? choice.tint : Theme.tertiaryText)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .luminousFill(enabled ? choice.tint : Theme.neutral.opacity(0.4), cornerRadius: 11)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.5)
    }

    private func directButton(_ title: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(Theme.Typeface.label(14, weight: .heavy))
                .foregroundStyle(tint)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .luminousFill(tint, cornerRadius: 11)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Bottom rail

    /// Baserunning and pitch detail on one line. Velocity and type are menus
    /// rather than chip rows — two taps instead of one, for the two things
    /// nobody logs on every pitch, and ninety points of screen back.
    private var bottomRail: some View {
        HStack(spacing: 6) {
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
                detailMenu(
                    title: pendingVelocity.map(String.init) ?? "MPH",
                    isSet: pendingVelocity != nil
                ) {
                    Button("Clear") { pendingVelocity = nil }
                    ForEach(Self.velocityPresets, id: \.self) { value in
                        Button("\(value)") { pendingVelocity = value }
                    }
                }
            }

            if settings.trackPitchType {
                detailMenu(
                    title: pendingPitchType?.abbreviation ?? "TYPE",
                    isSet: pendingPitchType != nil
                ) {
                    Button("Clear") { pendingPitchType = nil }
                    ForEach(PitchType.allCases) { type in
                        Button(type.abbreviation) { pendingPitchType = type }
                    }
                }
            }
        }
        .frame(height: 34)
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

    private func detailMenu<Content: View>(
        title: String,
        isSet: Bool,
        @ViewBuilder content: () -> Content
    ) -> some View {
        Menu {
            content()
        } label: {
            HStack(spacing: 4) {
                Text(title)
                    .font(Theme.Typeface.label(12, weight: .bold))
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8, weight: .bold))
            }
            .foregroundStyle(isSet ? Theme.accent : Theme.secondaryText)
            .padding(.horizontal, 10)
            .frame(height: 30)
            .luminousCapsule(isSet ? Theme.accent : Theme.neutral, isProminent: isSet)
        }
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

    private func clearPick() {
        chain = []
        pickedLocation = nil
    }
}
