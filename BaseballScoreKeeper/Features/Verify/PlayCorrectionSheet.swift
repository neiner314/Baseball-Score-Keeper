import SwiftUI

/// Fixes one play the scorer got wrong, using the official call as the target.
///
/// The whole point of the accuracy report is finding the one or two plays you
/// scored differently from the league. This turns that finding into a fix: tap
/// the difference, see exactly what will change, and apply it — nothing else you
/// scored is touched, because the correction is a single edit to the event log
/// that the engine then replays.
struct PlayCorrectionSheet: View {
    @Environment(GameStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var difference: ScoringDifference
    /// Called after the edit is applied, so the report can be re-checked.
    var onDone: () -> Void

    @State private var showsAdvanceEditor = false

    var body: some View {
        NavigationStack {
            ZStack {
                content
                if showsAdvanceEditor {
                    RunnerAdvanceView(
                        prompts: advancePrompts,
                        hapticsEnabled: store.settings.hapticsEnabled,
                        onComplete: { advances in apply(advances: advances) },
                        onCancel: { showsAdvanceEditor = false }
                    )
                }
            }
            .appBackground()
            .navigationTitle("Fix Play")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    // MARK: - Content

    private var content: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            comparisonCard
            explanation
            Spacer(minLength: 0)
            actions
        }
        .padding(20)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(difference.inningLabel.uppercased())
                .font(Theme.Typeface.overline(9))
                .tracking(1.4)
                .foregroundStyle(Theme.tertiaryText)
            Text(difference.batter)
                .font(Theme.Typeface.label(20, weight: .heavy))
                .foregroundStyle(Theme.primaryText)
        }
    }

    private var comparisonCard: some View {
        VStack(spacing: 0) {
            row("YOU SCORED", myLabel, tint: Theme.miss)
            Divider().overlay(Theme.hairline)
            row("OFFICIAL", officialLabel, tint: Theme.ball)
        }
        .scorecardSurface()
    }

    private func row(_ label: String, _ value: String, tint: Color) -> some View {
        HStack {
            Text(label)
                .font(Theme.Typeface.overline(9))
                .tracking(1.2)
                .foregroundStyle(Theme.tertiaryText)
            Spacer()
            Text(value)
                .font(Theme.Typeface.label(16, weight: .heavy))
                .foregroundStyle(tint)
        }
        .padding(.horizontal, Theme.Metrics.cardPadding)
        .padding(.vertical, 14)
    }

    @ViewBuilder
    private var explanation: some View {
        if !difference.officialSummary.isEmpty {
            Text(difference.officialSummary)
                .font(Theme.Typeface.caption())
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Actions

    @ViewBuilder
    private var actions: some View {
        switch difference.kind {
        case .extra:
            primaryButton("Remove this play", tint: Theme.miss) {
                if let index = difference.myTerminalEventIndex {
                    store.removePlateAppearance(terminalEventIndex: index)
                }
                onDone()
            }

        case .differentRBI:
            if advancePrompts.isEmpty {
                disabledNote("No runners were on base, so the RBI can't be adjusted here.")
            } else {
                primaryButton("Place runners…", tint: Theme.accent) {
                    showsAdvanceEditor = true
                }
            }

        default:
            primaryButton("Apply official call", tint: Theme.accent) {
                apply(advances: nil)
            }
            if difference.myTerminalEventIndex != nil, !advancePrompts.isEmpty {
                secondaryButton("Adjust runners…") {
                    showsAdvanceEditor = true
                }
            }
        }
    }

    private func primaryButton(_ title: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(Theme.Typeface.label(16, weight: .heavy))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .luminousFill(tint, cornerRadius: 16, isProminent: true)
        }
        .buttonStyle(.plain)
    }

    private func secondaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(Theme.Typeface.label(15, weight: .bold))
                .foregroundStyle(Theme.accent)
                .frame(maxWidth: .infinity)
                .frame(height: 46)
        }
        .buttonStyle(.plain)
    }

    private func disabledNote(_ text: String) -> some View {
        Text(text)
            .font(Theme.Typeface.caption())
            .foregroundStyle(Theme.tertiaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Applying

    private func apply(advances: [ManualAdvance]?) {
        switch difference.kind {
        case .differentCall, .differentRBI:
            if let index = difference.myTerminalEventIndex, let outcome = resolvedOutcome {
                store.correctPlay(atEventIndex: index, to: outcome, manualAdvances: advances)
            }
        case .missed:
            if let index = difference.insertionEventIndex, let outcome = resolvedOutcome {
                store.insertPlay(atEventIndex: index, outcome: outcome, manualAdvances: advances)
            }
        case .extra:
            if let index = difference.myTerminalEventIndex {
                store.removePlateAppearance(terminalEventIndex: index)
            }
        }
        onDone()
    }

    /// The play the correction will write. An RBI-only fix keeps the same call
    /// and only re-routes the runners; everything else adopts the official
    /// category, reusing the fielders the scorer already entered.
    private var resolvedOutcome: PlayOutcome? {
        switch difference.kind {
        case .differentRBI:
            return difference.myOutcome
        default:
            guard let category = difference.officialCategory else { return nil }
            return PlayOutcome.matching(category, reusing: difference.myOutcome)
        }
    }

    // MARK: - Labels & runners

    private var myLabel: String {
        switch difference.kind {
        case .differentCall(let mine, _): mine.label
        case .differentRBI(let mine, _): "\(mine) RBI"
        case .missed: "Not scored"
        case .extra(let mine): mine.label
        }
    }

    private var officialLabel: String {
        switch difference.kind {
        case .differentCall(_, let official): official.label
        case .differentRBI(_, let official): "\(official) RBI"
        case .missed(let official): official.label
        case .extra: "No official play"
        }
    }

    /// The runners aboard just before this plate appearance, ready for the
    /// advancement prompt with the corrected call's automatic result pre-picked.
    private var advancePrompts: [RunnerAdvancePrompt] {
        guard
            let index = difference.myTerminalEventIndex,
            let outcome = resolvedOutcome
        else { return [] }

        let bases = store.stateBeforePlay(terminalEventIndex: index).bases
        return bases.occupied.sorted { $0.rawValue > $1.rawValue }.map { base in
            let player = bases[base].flatMap { store.player(id: $0.playerID) }
            return RunnerAdvancePrompt(
                base: base,
                name: player?.shortName ?? "Runner",
                number: player?.number ?? "",
                forced: outcome.batterReachesBase && bases.forcedBases.contains(base),
                defaultTarget: ScoringEngine.defaultAdvance(for: outcome, runnerOn: base, bases: bases)
            )
        }
    }
}
