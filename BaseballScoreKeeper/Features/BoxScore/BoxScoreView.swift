import SwiftUI

/// The post-game summary: line score, batting lines with per-at-bat notation,
/// and pitching lines with decisions.
struct BoxScoreView: View {
    @Environment(GameStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var boxScore: BoxScore?

    var body: some View {
        NavigationStack {
            ScrollView {
                if let boxScore {
                    VStack(alignment: .leading, spacing: 22) {
                        titleBlock
                        LineScoreTable(boxScore: boxScore)

                        if !boxScore.challenges.isEmpty {
                            challengeSection(boxScore: boxScore)
                        }

                        if store.settings.trackBallLocation {
                            sprayChartSection
                        }

                        ForEach(Side.allCases) { side in
                            battingSection(side: side, boxScore: boxScore)
                            pitchingSection(side: side, boxScore: boxScore)
                        }
                    }
                    .padding(16)
                } else {
                    ProgressView()
                        .padding(.top, 60)
                }
            }
            .appBackground()
            .navigationTitle("Box Score")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                boxScore = store.buildBoxScore()
            }
        }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(store.document.title)
                .font(Theme.Typeface.label(20, weight: .bold))
                .foregroundStyle(Theme.primaryText)
            Text(subtitle)
                .font(Theme.Typeface.caption())
                .foregroundStyle(Theme.secondaryText)
        }
    }

    private var subtitle: String {
        let date = store.document.startedAt.formatted(date: .abbreviated, time: .omitted)
        let venue = store.document.venue
        return venue.isEmpty ? date : "\(date) · \(venue)"
    }

    // MARK: - Challenges

    private func challengeSection(boxScore: BoxScore) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("CHALLENGES")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .tracking(1.2)
                .foregroundStyle(Theme.secondaryText)

            VStack(spacing: 0) {
                ForEach(Side.allCases) { side in
                    let record = boxScore.challengeRecord(for: side)
                    HStack {
                        Text(boxScore.teams[side].abbreviation)
                            .font(Theme.Typeface.label(13, weight: .bold))
                            .foregroundStyle(Theme.primaryText)
                            .frame(width: 44, alignment: .leading)

                        Text("\(record.won) of \(record.used) overturned")
                            .font(Theme.Typeface.caption())
                            .foregroundStyle(Theme.secondaryText)

                        Spacer()

                        ChallengePips(
                            remaining: boxScore.challengesRemaining[side],
                            total: max(boxScore.challengesRemaining[side], record.used)
                        )
                    }
                    .padding(.horizontal, Theme.Metrics.cardPadding)
                    .padding(.vertical, 8)

                    Divider().overlay(Theme.hairline)
                }

                ForEach(boxScore.challenges) { challenge in
                    ChallengeRow(
                        challenge: challenge,
                        team: boxScore.teams[challenge.side].abbreviation
                    )
                }
            }
            .padding(.vertical, 4)
            .scorecardSurface()
        }
    }

    // MARK: - Spray chart

    private var sprayChartSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("EVERY BALL IN PLAY")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .tracking(1.2)
                .foregroundStyle(Theme.secondaryText)

            SprayChartView(document: store.document)
                .padding(8)

            HStack(spacing: 14) {
                SprayLegend(tint: Theme.ball, label: "Hit")
                SprayLegend(tint: Theme.miss, label: "Out")
                SprayLegend(tint: Theme.foul, label: "Error")
            }
            .padding(.horizontal, Theme.Metrics.cardPadding)
            .padding(.bottom, 6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .scorecardSurface()
    }

    // MARK: - Batting

    private func battingSection(side: Side, boxScore: BoxScore) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(boxScore.teams[side].name.uppercased()) BATTING")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .tracking(1.2)
                .foregroundStyle(Theme.secondaryText)

            VStack(spacing: 0) {
                ForEach(boxScore.batting[side]) { line in
                    BattingRow(line: line)
                    if line.id != boxScore.batting[side].last?.id {
                        Divider().overlay(Theme.hairline)
                    }
                }
            }
            .padding(.vertical, 4)
            .scorecardSurface()
        }
    }

    // MARK: - Pitching

    private func pitchingSection(side: Side, boxScore: BoxScore) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(boxScore.teams[side].name.uppercased()) PITCHING")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .tracking(1.2)
                .foregroundStyle(Theme.secondaryText)

            VStack(spacing: 0) {
                PitchingHeaderRow()
                ForEach(boxScore.pitching[side]) { line in
                    Divider().overlay(Theme.hairline)
                    PitchingRow(line: line)
                }
            }
            .padding(.vertical, 4)
            .scorecardSurface()
        }
    }
}

private struct ChallengeRow: View {
    var challenge: ChallengeRecord
    var team: String

    var body: some View {
        HStack(spacing: 10) {
            Text(challenge.inningLabel)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.secondaryText)
                .frame(width: 52, alignment: .leading)

            VStack(alignment: .leading, spacing: 1) {
                Text("\(team) \(challenge.role.label.lowercased())")
                    .font(Theme.Typeface.label(12, weight: .semibold))
                    .foregroundStyle(Theme.primaryText)
                Text(challenge.summary)
                    .font(.system(size: 10, weight: .regular, design: .rounded))
                    .foregroundStyle(Theme.secondaryText)
            }

            Spacer()

            Text(challenge.result == .overturned ? "WON" : "LOST")
                .font(.system(size: 9, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(
                    Capsule().fill(challenge.result == .overturned ? Theme.ball : Theme.miss)
                )
        }
        .padding(.horizontal, Theme.Metrics.cardPadding)
        .padding(.vertical, 7)
    }
}

private struct SprayLegend: View {
    var tint: Color
    var label: String

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(tint)
                .frame(width: 8, height: 8)
            Text(label)
                .font(Theme.Typeface.caption())
                .foregroundStyle(Theme.secondaryText)
        }
    }
}

private struct BattingRow: View {
    var line: BattingLine

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    if line.isSubstitute {
                        Text("↳")
                            .font(Theme.Typeface.caption())
                            .foregroundStyle(Theme.secondaryText)
                    }
                    Text(line.player.shortName)
                        .font(Theme.Typeface.label(14, weight: .semibold))
                        .foregroundStyle(Theme.primaryText)
                    Text(line.position.abbreviation)
                        .font(Theme.Typeface.caption())
                        .foregroundStyle(Theme.secondaryText)
                }

                Text(line.detailLine)
                    .font(.system(size: 11, weight: .regular, design: .rounded))
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 4)

            HStack(spacing: 12) {
                StatCell(value: line.runs, label: "R")
                StatCell(value: line.rbis, label: "RBI")
            }
        }
        .padding(.horizontal, Theme.Metrics.cardPadding)
        .padding(.vertical, 9)
    }
}

private struct StatCell: View {
    var value: Int
    var label: String

    var body: some View {
        VStack(spacing: 1) {
            Text("\(value)")
                .font(Theme.Typeface.score(15))
                .foregroundStyle(Theme.primaryText)
            Text(label)
                .font(.system(size: 8, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.secondaryText)
        }
        .frame(minWidth: 22)
    }
}

private struct PitchingHeaderRow: View {
    var body: some View {
        HStack(spacing: 0) {
            Text("PITCHER")
                .frame(maxWidth: .infinity, alignment: .leading)
            ForEach(["IP", "H", "R", "ER", "BB", "K", "P"], id: \.self) { column in
                Text(column).frame(width: 30)
            }
        }
        .font(.system(size: 9, weight: .semibold, design: .rounded))
        .foregroundStyle(Theme.secondaryText)
        .padding(.horizontal, Theme.Metrics.cardPadding)
        .padding(.vertical, 6)
    }
}

private struct PitchingRow: View {
    var line: PitchingLine

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 5) {
                Text(line.player.shortName)
                    .font(Theme.Typeface.label(13, weight: .semibold))
                    .foregroundStyle(Theme.primaryText)
                if let decision = line.decision {
                    Text(decision.abbreviation)
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(decisionTint(decision)))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            numberCell(line.inningsPitched)
            numberCell("\(line.hits)")
            numberCell("\(line.runs)")
            numberCell("\(line.earnedRuns)")
            numberCell("\(line.walks)")
            numberCell("\(line.strikeouts)")
            numberCell("\(line.pitches)")
        }
        .padding(.horizontal, Theme.Metrics.cardPadding)
        .padding(.vertical, 8)
    }

    private func numberCell(_ text: String) -> some View {
        Text(text)
            .font(Theme.Typeface.score(12))
            .foregroundStyle(Theme.primaryText)
            .frame(width: 30)
    }

    private func decisionTint(_ decision: PitcherDecision) -> Color {
        switch decision {
        case .win: Theme.ball
        case .loss: Theme.miss
        case .save: Theme.inPlay
        }
    }
}

/// The classic grid: innings across, runs / hits / errors on the right.
struct LineScoreTable: View {
    var boxScore: BoxScore

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            VStack(spacing: 0) {
                headerRow
                Divider().overlay(Theme.hairline)
                teamRow(.away)
                teamRow(.home)
            }
            .padding(.vertical, 6)
        }
        .scorecardSurface()
    }

    private var headerRow: some View {
        HStack(spacing: 0) {
            Text("")
                .frame(width: 44, alignment: .leading)
            ForEach(boxScore.lineScore.indices, id: \.self) { index in
                Text("\(index + 1)")
                    .frame(width: 26)
            }
            ForEach(["R", "H", "E"], id: \.self) { column in
                Text(column).frame(width: 28)
            }
        }
        .font(.system(size: 10, weight: .semibold, design: .rounded))
        .foregroundStyle(Theme.secondaryText)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private func teamRow(_ side: Side) -> some View {
        HStack(spacing: 0) {
            Text(boxScore.teams[side].abbreviation)
                .font(Theme.Typeface.label(13, weight: .bold))
                .frame(width: 44, alignment: .leading)

            ForEach(boxScore.lineScore.indices, id: \.self) { index in
                Text(cellText(side: side, inning: index))
                    .font(Theme.Typeface.score(13))
                    .frame(width: 26)
                    .foregroundStyle(
                        (boxScore.lineScore[index][side] ?? 0) > 0 ? Theme.primaryText : Theme.secondaryText
                    )
            }

            totalCell(boxScore.totals[side].runs, emphasized: true)
            totalCell(boxScore.totals[side].hits)
            totalCell(boxScore.totals[side].errors)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }

    /// A half that was never played shows X, the way a real line score does.
    private func cellText(side: Side, inning: Int) -> String {
        guard let runs = boxScore.lineScore[inning][side] else { return "X" }
        return "\(runs)"
    }

    private func totalCell(_ value: Int, emphasized: Bool = false) -> some View {
        Text("\(value)")
            .font(Theme.Typeface.score(emphasized ? 15 : 13))
            .foregroundStyle(Theme.primaryText)
            .frame(width: 28)
    }
}
