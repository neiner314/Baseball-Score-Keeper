import SwiftUI

/// Scores your scorecard against the league's.
///
/// The interesting output isn't the percentage — it's the list of plays where
/// you and the official scorer saw it differently, which is how you find out
/// you've been calling something a hit that the league calls an error.
struct AccuracyReportView: View {
    @Environment(GameStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var report: ScoringReport?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var editing: ScoringDifference?

    var body: some View {
        NavigationStack {
            Group {
                if let report {
                    reportBody(report)
                } else if isLoading {
                    ProgressView("Fetching official scoring…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let errorMessage {
                    messageState(
                        symbol: "exclamationmark.triangle",
                        title: "Couldn't check",
                        detail: errorMessage
                    )
                } else {
                    messageState(
                        symbol: "checkmark.seal",
                        title: "Compare with the official scorer",
                        detail: unsupportedReason ?? "Pull the league's scoring and see where it differs from yours."
                    )
                }
            }
            .appBackground()
            .navigationTitle("Accuracy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Check") { Task { await run() } }
                        .disabled(isLoading || !store.document.supportsAccuracyCheck)
                }
            }
            .task {
                if store.document.supportsAccuracyCheck, report == nil {
                    await run()
                }
            }
            .sheet(item: $editing) { difference in
                PlayCorrectionSheet(difference: difference) {
                    editing = nil
                    Task { await run() }
                }
                .environment(store)
            }
        }
    }

    private var unsupportedReason: String? {
        guard !store.document.supportsAccuracyCheck else { return nil }
        guard let league = store.document.league else {
            return "This game wasn't imported from a league feed, so there's no official scoring to compare against."
        }
        return "\(league.shortName) doesn't publish official scoring in a form this app can read."
    }

    // MARK: - Report

    private func reportBody(_ report: ScoringReport) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                scoreCard(report)

                if report.differences.isEmpty {
                    messageState(
                        symbol: "checkmark.circle.fill",
                        title: "Every play matches",
                        detail: "All \(report.comparedPlays) plate appearances agree with the official scorer."
                    )
                    .frame(height: 200)
                } else {
                    Text("DIFFERENCES")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .tracking(1.2)
                        .foregroundStyle(Theme.secondaryText)

                    VStack(spacing: 0) {
                        ForEach(report.differences) { difference in
                            Button {
                                guard difference.isFixable else { return }
                                editing = difference
                            } label: {
                                DifferenceRow(difference: difference)
                            }
                            .buttonStyle(.plain)
                            .disabled(!difference.isFixable)

                            if difference.id != report.differences.last?.id {
                                Divider().overlay(Theme.hairline)
                            }
                        }
                    }
                    .scorecardSurface()

                    Text("Tap a difference to fix how you scored it.")
                        .font(Theme.Typeface.caption())
                        .foregroundStyle(Theme.tertiaryText)
                }
            }
            .padding(16)
        }
    }

    private func scoreCard(_ report: ScoringReport) -> some View {
        VStack(spacing: 8) {
            Text(report.accuracyPercent)
                .font(Theme.Typeface.score(52))
                .foregroundStyle(Theme.primaryText)

            Text(report.summary)
                .font(Theme.Typeface.label(14, weight: .semibold))
                .foregroundStyle(Theme.secondaryText)

            if !report.isAligned {
                Text("You scored \(report.myPlayCount) plate appearances; the official has \(report.officialPlayCount).")
                    .font(Theme.Typeface.caption())
                    .foregroundStyle(Theme.foul)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .scorecardSurface()
    }

    private func messageState(symbol: String, title: String, detail: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Theme.secondaryText)
            Text(title)
                .font(Theme.Typeface.label(17, weight: .bold))
                .foregroundStyle(Theme.primaryText)
            Text(detail)
                .font(Theme.Typeface.caption())
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Fetch

    private func run() async {
        guard
            let league = store.document.league,
            let gameID = store.document.externalGameID,
            let provider = LeagueDirectory.officialScoringProvider(for: league)
        else {
            errorMessage = unsupportedReason
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let official = try await provider.officialPlays(gameID: gameID)
            let mine = ScoringEngine.indexedPlateAppearances(document: store.document)
            report = ScoringComparator.compare(
                mine: mine,
                official: official,
                document: store.document
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct DifferenceRow: View {
    var difference: ScoringDifference

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(difference.inningLabel)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.secondaryText)
                .frame(width: 52, alignment: .leading)

            VStack(alignment: .leading, spacing: 3) {
                Text(difference.batter)
                    .font(Theme.Typeface.label(13, weight: .semibold))
                    .foregroundStyle(Theme.primaryText)

                Text(difference.headline)
                    .font(.system(size: 11, weight: .regular, design: .rounded))
                    .foregroundStyle(tint)

                if !difference.officialSummary.isEmpty {
                    Text(difference.officialSummary)
                        .font(.system(size: 10, weight: .regular, design: .rounded))
                        .foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 0)

            if difference.isFixable {
                Image(systemName: "pencil.circle")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.accent)
            }
        }
        .padding(.horizontal, Theme.Metrics.cardPadding)
        .padding(.vertical, 9)
        .contentShape(Rectangle())
    }

    private var tint: Color {
        switch difference.kind {
        case .differentCall: Theme.miss
        case .differentRBI: Theme.foul
        case .missed: Theme.calledStrike
        case .extra: Theme.neutral
        }
    }
}
