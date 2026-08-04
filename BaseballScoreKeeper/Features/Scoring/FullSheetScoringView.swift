import SwiftUI

/// The dense layout: one scrolling sheet with every control visible at once.
///
/// The opposite trade from the one-handed screen — nothing is hidden behind a
/// gesture, so it needs two hands and a look, but a scorer who wants to record
/// a rare play never has to go hunting for it.
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
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ScoreBar(state: store.state, teams: store.teams)

                BatterCard(
                    batter: store.currentBatter,
                    position: store.currentBatterPosition,
                    pitches: store.state.currentAtBatPitches,
                    bases: store.state.bases,
                    runnerName: { store.runnerOnBase($0)?.shortName },
                    headline: store.lastHeadline
                )

                pitchButtons

                if let pitch = store.challengeablePitch {
                    ChallengePrompt(pitch: pitch) { showsChallengeSheet = true }
                        .frame(maxWidth: .infinity, alignment: .center)
                }

                if settings.trackPitchVelocity || settings.trackPitchType {
                    detailCard
                }

                if settings.trackBallLocation {
                    fieldSection
                }

                fieldingSection
                resultSection
                baserunningSection
            }
            .padding(.horizontal, Theme.Metrics.screenMargin)
            .padding(.bottom, 28)
        }
        .background(Theme.background)
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

    private static let velocityPresets = [82, 88, 92, 95, 98, 102]

    // MARK: - Pitch buttons

    private var pitchButtons: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                pitchButton(.ball)
                pitchButton(.calledStrike)
                pitchButton(.swingingStrike)
            }
            HStack(spacing: 8) {
                pitchButton(.foul)
                pitchButton(.hitByPitch)
                pitchButton(.wildPitch)
            }
        }
    }

    private func pitchButton(_ outcome: PitchOutcome) -> some View {
        Button {
            record(pitch: outcome)
        } label: {
            Text(outcome.shortLabel)
                .font(Theme.Typeface.label(16, weight: .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Metrics.tightRadius, style: .continuous)
                        .fill(Theme.color(for: outcome))
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Pitch detail

    private var detailCard: some View {
        VStack(alignment: .leading, spacing: 10) {
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
                    items: PitchType.allCases.map { ($0.abbreviation, $0) },
                    selection: pendingPitchType,
                    onSelect: { pendingPitchType = (pendingPitchType == $0) ? nil : $0 }
                )
            }
        }
        .padding(Theme.Metrics.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .scorecardSurface()
    }

    // MARK: - Field

    private var fieldSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Overline("Ball in play — tap where it went")

            FieldPlotView(
                selectedPosition: chain.last,
                onPick: { location, fielder in
                    pickedLocation = location
                    append(fielder)
                }
            )
            .frame(maxHeight: 240)
        }
        .padding(Theme.Metrics.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .scorecardSurface()
    }

    // MARK: - Fielding chain

    /// The whole point of this section: every fielder who touched the ball, in
    /// order. Tapping 6 then 4 then 3 gives `6-4-3`; tapping 3 then 1 gives
    /// `3-1`; a rundown can run as long as it actually ran.
    private var fieldingSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Overline("Who handled it")
                Spacer()
                if !chain.isEmpty {
                    Button("Clear") { clearPick() }
                        .font(Theme.Typeface.caption())
                        .foregroundStyle(Theme.accent)
                }
            }

            HStack(spacing: 10) {
                Text(chain.isEmpty ? "—" : ChainFormatter.text(chain))
                    .font(Theme.Typeface.notation(24, weight: .heavy))
                    .foregroundStyle(chain.isEmpty ? Theme.tertiaryText : Theme.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)

                Spacer(minLength: 0)

                if !chain.isEmpty {
                    Button {
                        _ = chain.popLast()
                    } label: {
                        Image(systemName: "delete.left.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Theme.secondaryText)
                            .frame(width: 40, height: 36)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Remove last fielder"))
                }
            }

            fielderChips

            if settings.notationDetail == .full, !chain.isEmpty {
                trajectoryPicker
            }
        }
        .padding(Theme.Metrics.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .scorecardSurface()
    }

    private var fielderChips: some View {
        HStack(spacing: 6) {
            ForEach(Position.fielders) { position in
                Button {
                    append(position)
                } label: {
                    Text("\(position.rawValue)")
                        .font(Theme.Typeface.label(14, weight: .bold))
                        .frame(width: 32, height: 32)
                        .background(
                            Circle().fill(
                                chain.contains(position) ? Theme.accent : Theme.surfaceRaised
                            )
                        )
                        .foregroundStyle(
                            chain.contains(position) ? Theme.background : Theme.primaryText
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(position.fullName))
            }
        }
    }

    private var trajectoryPicker: some View {
        HStack(spacing: 6) {
            ForEach(Trajectory.allCases) { option in
                Button {
                    trajectory = option
                } label: {
                    Text(option.label)
                        .font(Theme.Typeface.label(11, weight: .bold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule().fill(option == trajectory ? Theme.accent : Theme.surfaceRaised)
                        )
                        .foregroundStyle(
                            option == trajectory ? Theme.background : Theme.secondaryText
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Results

    private var resultSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Overline("Result")

            FlowRow(spacing: 8) {
                ForEach(BallInPlayChoice.allCases) { choice in
                    resultButton(choice)
                }
                directButton("BB", tint: Theme.ball) {
                    store.recordPlay(.walk(intentional: false))
                }
                directButton("K", tint: Theme.miss) {
                    store.recordPlay(.strikeout(looking: false, uncaught: false))
                }
                directButton("ꓘ", tint: Theme.calledStrike) {
                    store.recordPlay(.strikeout(looking: true, uncaught: false))
                }
            }

            if chain.isEmpty {
                Text("Hits and home runs don't need a fielder. Everything else does.")
                    .font(Theme.Typeface.caption())
                    .foregroundStyle(Theme.tertiaryText)
            }
        }
        .padding(Theme.Metrics.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .scorecardSurface()
    }

    private func resultButton(_ choice: BallInPlayChoice) -> some View {
        let enabled = !choice.requiresFielder || !chain.isEmpty
        return Button {
            commit(choice)
        } label: {
            Text(choice.title)
                .font(Theme.Typeface.label(14, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .frame(height: 40)
                .background(Capsule().fill(choice.tint.opacity(enabled ? 1 : 0.25)))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private func directButton(_ title: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(Theme.Typeface.label(14, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .frame(height: 40)
                .background(Capsule().fill(tint))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Baserunning

    private var baserunningSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Overline("Baserunning")

            FlowRow(spacing: 8) {
                ForEach(store.state.bases.occupied) { base in
                    directButton("SB \(base.label)", tint: Theme.ball) {
                        store.record(.stolenBase(from: base))
                    }
                    directButton("CS \(base.label)", tint: Theme.miss) {
                        store.record(.caughtStealing(from: base))
                    }
                }
                directButton("WP", tint: Theme.neutral) {
                    store.record(.wildPitchAdvance)
                }
                directButton("PB", tint: Theme.neutral) {
                    store.record(.passedBallAdvance)
                }
                directButton("Balk", tint: Theme.neutral) {
                    store.record(.balk)
                }
            }
        }
        .padding(Theme.Metrics.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .scorecardSurface()
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
                location: pickedLocation
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

/// Minimal wrapping row. `Layout` rather than a stack of stacks so the buttons
/// reflow cleanly at any Dynamic Type size.
struct FlowRow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var totalWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if rowWidth + size.width > maxWidth, rowWidth > 0 {
                totalHeight += rowHeight + spacing
                totalWidth = max(totalWidth, rowWidth - spacing)
                rowWidth = 0
                rowHeight = 0
            }
            rowWidth += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }

        totalHeight += rowHeight
        totalWidth = max(totalWidth, rowWidth - spacing)
        return CGSize(width: min(totalWidth, maxWidth), height: totalHeight)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(
                at: CGPoint(x: x, y: y),
                proposal: ProposedViewSize(size)
            )
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
