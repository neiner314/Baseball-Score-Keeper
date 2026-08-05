import SwiftUI

/// The lit ground every screen sits on.
///
/// A gradient plus one soft pool of light near the top. That's the whole trick:
/// frosted panels need something with depth underneath them or they read as
/// grey rectangles on a grey rectangle.
struct AppBackground: View {
    var body: some View {
        ZStack {
            Theme.backgroundGradient
            Theme.stadiumGlow
        }
        .ignoresSafeArea()
    }
}

extension View {
    func appBackground() -> some View {
        background(AppBackground())
    }
}

/// The line score, inning by inning — the closest thing scorekeeping has to a
/// shape you'd want to look at.
///
/// It earns its place twice: it's the one view that shows the game's whole arc
/// at a glance, and it's the only thing on the live screen that changes shape
/// as the game goes on.
struct LineScoreRibbon: View {
    var state: GameState
    var teams: SideValues<TeamRoster>

    private var innings: [Int] {
        let played = max(state.lineScore.count, state.inning)
        return Array(1...max(1, played))
    }

    var body: some View {
        HStack(spacing: 0) {
            labels

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 3) {
                    ForEach(innings, id: \.self) { inning in
                        column(inning)
                    }
                }
            }

            totals
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .scorecardSurface(cornerRadius: 16)
    }

    private var labels: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("")
                .font(Theme.Typeface.overline(8))
                .frame(height: 10)
            teamLabel(.away)
            teamLabel(.home)
        }
        .padding(.trailing, 8)
    }

    private func teamLabel(_ side: Side) -> some View {
        Text(teams[side].abbreviation)
            .font(Theme.Typeface.label(10, weight: .heavy))
            .foregroundStyle(
                state.battingSide == side && !state.isFinal
                    ? Theme.primaryText
                    : Theme.tertiaryText
            )
            .frame(width: 34, height: 20, alignment: .leading)
    }

    /// One inning: the number on top, then each team's runs. The half in
    /// progress is lit, so your eye lands on now.
    private func column(_ inning: Int) -> some View {
        let isCurrent = inning == state.inning && !state.isFinal
        return VStack(spacing: 3) {
            Text("\(inning)")
                .font(Theme.Typeface.overline(8))
                .foregroundStyle(isCurrent ? Theme.accent : Theme.tertiaryText)
                .frame(height: 10)

            cell(inning: inning, side: .away, isCurrent: isCurrent)
            cell(inning: inning, side: .home, isCurrent: isCurrent)
        }
        .frame(width: 22)
    }

    private func cell(inning: Int, side: Side, isCurrent: Bool) -> some View {
        let runs = state.lineScore.indices.contains(inning - 1)
            ? state.lineScore[inning - 1][side]
            : nil
        let isLive = isCurrent && state.battingSide == side && !state.isFinal

        return Text(runs.map(String.init) ?? "·")
            .font(Theme.Typeface.score(13))
            .foregroundStyle(runsTint(runs, isLive: isLive))
            .frame(width: 22, height: 20)
            .background {
                if (runs ?? 0) > 0 {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Theme.ball.opacity(0.18))
                        .glow(Theme.ball, radius: 6, opacity: 0.35)
                } else if isLive {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Theme.accent.opacity(0.7), lineWidth: 1)
                }
            }
    }

    private func runsTint(_ runs: Int?, isLive: Bool) -> Color {
        guard let runs else { return Theme.tertiaryText.opacity(0.5) }
        if runs > 0 { return Theme.ball }
        return isLive ? Theme.primaryText : Theme.secondaryText
    }

    private var totals: some View {
        HStack(spacing: 0) {
            totalColumn("R", away: state.awayRuns, home: state.homeRuns, tint: Theme.ball)
            totalColumn("H", away: state.hits.away, home: state.hits.home, tint: Theme.primaryText)
            totalColumn("E", away: state.errors.away, home: state.errors.home, tint: Theme.foul)
        }
        .padding(.leading, 8)
    }

    private func totalColumn(_ label: String, away: Int, home: Int, tint: Color) -> some View {
        VStack(spacing: 3) {
            Text(label)
                .font(Theme.Typeface.overline(8))
                .foregroundStyle(Theme.tertiaryText)
                .frame(height: 10)
            Text("\(away)")
                .font(Theme.Typeface.score(13))
                .foregroundStyle(tint)
                .frame(height: 20)
            Text("\(home)")
                .font(Theme.Typeface.score(13))
                .foregroundStyle(tint)
                .frame(height: 20)
        }
        .frame(width: 22)
    }
}
