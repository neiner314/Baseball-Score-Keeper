import SwiftUI

/// The dense layout: one scrolling sheet with every control visible at once.
///
/// The opposite trade from the one-handed screen — nothing is hidden behind a
/// gesture, so it needs two hands and a look, but a scorer who wants to record
/// a rare play never has to go hunting for it.
struct FullSheetScoringView: View {
    @Environment(GameStore.self) private var store

    @State private var pickedFielder: Position?
    @State private var pickedLocation: FieldLocation?
    @State private var trajectory: Trajectory = .grounder
    @State private var pendingVelocity: Int?
    @State private var pendingPitchType: PitchType?
    @State private var showsChallengeSheet = false

    private var settings: TrackingSettings { store.settings }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                headerCard
                pitchButtons

                if let pitch = store.challengeablePitch {
                    ChallengePrompt(pitch: pitch) { showsChallengeSheet = true }
                        .frame(maxWidth: .infinity, alignment: .center)
                }

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
                        items: PitchType.allCases.map { ($0.abbreviation, $0) },
                        selection: pendingPitchType,
                        onSelect: { pendingPitchType = (pendingPitchType == $0) ? nil : $0 }
                    )
                }

                if settings.trackBallLocation {
                    fieldSection
                }

                resultSection
                baserunningSection
                PitchSequenceStrip(pitches: store.state.currentAtBatPitches)
            }
            .padding(16)
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

    // MARK: - Header

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            CompactScoreHeader(
                state: store.state,
                teams: store.teams,
                batter: store.currentBatter,
                batterPosition: store.currentBatterPosition,
                foulCount: store.state.currentAtBatPitches.filter { $0.outcome == .foul }.count,
                showsFoulCount: settings.trackFoulAndPitchCounts
            )

            if !store.lastHeadline.isEmpty {
                Text(store.lastHeadline)
                    .font(Theme.Typeface.caption())
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .padding(Theme.Metrics.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .scorecardSurface()
    }

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
                .frame(height: 46)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Theme.color(for: outcome))
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Field

    private var fieldSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("BALL IN PLAY — TAP THE FIELD")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .tracking(1.1)
                    .foregroundStyle(Theme.secondaryText)
                Spacer()
                if pickedFielder != nil {
                    Button("Clear") { clearPick() }
                        .font(Theme.Typeface.caption())
                }
            }

            FieldPlotView(
                selectedPosition: pickedFielder,
                onPick: { location, fielder in
                    pickedLocation = location
                    pickedFielder = fielder
                    trajectory = BallInPlayChoice.defaultTrajectory(for: fielder)
                    Haptics.shared.tap(enabled: settings.hapticsEnabled)
                }
            )
            .frame(maxHeight: 240)

            HStack {
                Text(pickedFielder.map { "\($0.rawValue) · \($0.fullName)" } ?? "—")
                    .font(Theme.Typeface.caption())
                    .foregroundStyle(Theme.secondaryText)
                Spacer()
                if settings.notationDetail == .full, pickedFielder != nil {
                    trajectoryPicker
                }
            }
        }
        .padding(Theme.Metrics.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .scorecardSurface()
    }

    private var trajectoryPicker: some View {
        HStack(spacing: 6) {
            ForEach(Trajectory.allCases) { option in
                Button {
                    trajectory = option
                } label: {
                    Text(option.notationPrefix.isEmpty ? "G" : option.notationPrefix)
                        .font(Theme.Typeface.label(11, weight: .bold))
                        .frame(width: 26, height: 26)
                        .background(
                            Circle().fill(option == trajectory ? Theme.inPlay : Theme.surfaceRaised)
                        )
                        .foregroundStyle(option == trajectory ? .white : Theme.primaryText)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Results

    private var resultSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("RESULT")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .tracking(1.1)
                .foregroundStyle(Theme.secondaryText)

            // With ball location turned off there's no field to tap, so the
            // fielder still has to be pickable or every out would be blocked.
            if !settings.trackBallLocation {
                fielderChips
            }

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
        }
        .padding(Theme.Metrics.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .scorecardSurface()
    }

    private var fielderChips: some View {
        HStack(spacing: 6) {
            ForEach(Position.fielders) { position in
                Button {
                    pickedFielder = (pickedFielder == position) ? nil : position
                    trajectory = BallInPlayChoice.defaultTrajectory(for: position)
                } label: {
                    Text("\(position.rawValue)")
                        .font(Theme.Typeface.label(13, weight: .bold))
                        .frame(width: 30, height: 30)
                        .background(
                            Circle().fill(
                                pickedFielder == position ? Theme.inPlay : Theme.surfaceRaised
                            )
                        )
                        .foregroundStyle(pickedFielder == position ? .white : Theme.primaryText)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(position.fullName))
            }
        }
    }

    private func resultButton(_ choice: BallInPlayChoice) -> some View {
        let enabled = isEnabled(choice)
        return Button {
            commit(choice)
        } label: {
            Text(choice.title)
                .font(Theme.Typeface.label(14, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .frame(height: 40)
                .background(Capsule().fill(choice.tint.opacity(enabled ? 1 : 0.3)))
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

    /// Outs need a fielder to be meaningful; hits don't.
    private func isEnabled(_ choice: BallInPlayChoice) -> Bool {
        switch choice {
        case .single, .double, .triple, .homeRun:
            return true
        default:
            return pickedFielder != nil
        }
    }

    // MARK: - Baserunning

    private var baserunningSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("BASERUNNING")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .tracking(1.1)
                .foregroundStyle(Theme.secondaryText)

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

    private func record(pitch outcome: PitchOutcome) {
        store.recordPitch(outcome: outcome, velocity: pendingVelocity, type: pendingPitchType)
        pendingVelocity = nil
        pendingPitchType = nil
    }

    private func commit(_ choice: BallInPlayChoice) {
        let batted = pickedFielder.map { _ in
            BattedBall(trajectory: trajectory, location: pickedLocation)
        }

        store.beginGroup()
        record(pitch: .inPlay)

        if let fielder = pickedFielder {
            store.recordPlay(
                choice.outcome(fielder: fielder, trajectory: trajectory, location: pickedLocation)
            )
        } else if let kind = hitKind(for: choice) {
            store.recordPlay(.hit(kind, batted: batted, fielder: nil))
        }
        store.endGroup()

        clearPick()
    }

    private func hitKind(for choice: BallInPlayChoice) -> HitKind? {
        switch choice {
        case .single: .single
        case .double: .double
        case .triple: .triple
        case .homeRun: .homeRun
        default: nil
        }
    }

    private func clearPick() {
        pickedFielder = nil
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
