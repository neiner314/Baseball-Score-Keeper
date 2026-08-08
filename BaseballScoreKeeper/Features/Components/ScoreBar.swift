import SwiftUI

/// The scoreboard strip that sits at the top of every scoring layout.
///
/// One glance has to answer four questions: who's winning, what inning it is,
/// what the count is, and who's on. The old header answered the first two in
/// eleven-point grey and never answered the fourth at all.
struct ScoreBar: View {
    var state: GameState
    var teams: SideValues<TeamRoster>

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                teamRow(.away)
                teamRow(.home)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 7) {
                Text(inningText)
                    .font(Theme.Typeface.label(12, weight: .heavy))
                    .tracking(1.1)
                    .foregroundStyle(Theme.secondaryText)
                CountPips(balls: state.balls, strikes: state.strikes)
                OutsPips(outs: state.outs)
            }

            BaseDiamond(bases: state.bases, size: 62)
        }
        .padding(.horizontal, Theme.Metrics.cardPadding)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .scorecardSurface()
    }

    /// The batting side is the lit one — a dot beside it and a faint bloom on
    /// the number. That alone tells you the half without reading the inning.
    private func teamRow(_ side: Side) -> some View {
        let isBatting = state.battingSide == side && !state.isFinal
        return HStack(spacing: 7) {
            Circle()
                .fill(isBatting ? Theme.accent : Color.clear)
                .frame(width: 5, height: 5)
                .glow(isBatting ? Theme.accent : .clear, radius: 5, opacity: 0.9)

            Text(teams[side].abbreviation)
                .font(Theme.Typeface.label(15, weight: .heavy))
                .foregroundStyle(isBatting ? Theme.primaryText : Theme.secondaryText)
                .frame(width: 42, alignment: .leading)

            Text("\(state.runs(for: side))")
                .font(Theme.Typeface.display(34))
                .foregroundStyle(isBatting ? Theme.primaryText : Theme.secondaryText)
                .glow(isBatting ? Color.white : .clear, radius: 14, opacity: 0.25)
                .contentTransition(.numericText())
                .animation(.easeOut(duration: 0.25), value: state.runs(for: side))
        }
        .accessibilityElement(children: .combine)
    }

    private var inningText: String {
        state.isFinal ? "FINAL" : "\(state.half == .top ? "▲" : "▼") \(state.inning)"
    }
}

/// Who's up, what they've seen this at-bat, and who's standing where.
struct BatterCard: View {
    var batter: Player?
    var position: Position?
    var pitches: [Pitch]
    var battingLine: BattingLine?
    /// The batter's season line from the league feed. When present it's shown
    /// instead of this game's line, tagged "SZN" so it's clear which it is.
    var seasonStats: SeasonHittingStats? = nil
    var headline: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                // Name and this game's line on the left; the pitches flow to the
                // right of them and wrap, so a long at-bat grows down by a row
                // rather than stretching the card off the screen.
                VStack(alignment: .leading, spacing: 6) {
                    if let batter {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(batter.number.isEmpty ? "—" : batter.number)
                                .font(Theme.Typeface.score(15))
                                .foregroundStyle(Theme.tertiaryText)
                                .frame(minWidth: 20, alignment: .trailing)
                            Text(batter.shortName.uppercased())
                                .font(Theme.Typeface.label(20, weight: .heavy))
                                .foregroundStyle(Theme.primaryText)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                            if let position {
                                Text(position.abbreviation)
                                    .font(Theme.Typeface.caption())
                                    .foregroundStyle(Theme.tertiaryText)
                            }
                        }

                        if let seasonStats {
                            statGrid(
                                tag: "SZN",
                                average: seasonStats.average,
                                homeRuns: seasonStats.homeRuns,
                                rbis: seasonStats.rbis,
                                onBase: seasonStats.onBase
                            )
                        } else if let battingLine {
                            statGrid(
                                tag: nil,
                                average: battingLine.average,
                                homeRuns: battingLine.homeRuns,
                                rbis: battingLine.rbis,
                                onBase: Self.onBase(battingLine)
                            )
                        }
                    } else {
                        Text("LINEUP DUE UP")
                            .font(Theme.Typeface.label(16, weight: .heavy))
                            .foregroundStyle(Theme.tertiaryText)
                    }
                }
                .layoutPriority(1)

                if !pitches.isEmpty {
                    FlowLayout(spacing: 5, lineSpacing: 5) {
                        ForEach(pitches) { pitch in
                            PitchMark(pitch: pitch)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Spacer(minLength: 0)
                }
            }

            if !headline.isEmpty {
                Text(headline)
                    .font(Theme.Typeface.label(12, weight: .medium))
                    .foregroundStyle(Theme.tertiaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .transition(.opacity)
            }
        }
        .padding(Theme.Metrics.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .scorecardSurface()
    }

    /// The slash line under the name: average and home runs on top, runs batted
    /// in and on-base percentage stacked beneath. Two narrow columns rather than
    /// one long row, so the pitch marks have the whole right side of the card to
    /// flow into. `tag` marks it as the season line when it isn't this game's.
    private func statGrid(
        tag: String?,
        average: Double,
        homeRuns: Int,
        rbis: Int,
        onBase: Double
    ) -> some View {
        HStack(alignment: .top, spacing: 8) {
            if let tag {
                Text(tag)
                    .font(Theme.Typeface.overline(8))
                    .tracking(0.5)
                    .foregroundStyle(Theme.accent)
                    .padding(.top, 1)
            }
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 3) {
                GridRow {
                    inlineStat("AVG", Self.rate(average))
                    inlineStat("HR", "\(homeRuns)")
                }
                GridRow {
                    inlineStat("RBI", "\(rbis)")
                    inlineStat("OBP", Self.rate(onBase))
                }
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }

    private func inlineStat(_ label: String, _ value: String) -> some View {
        HStack(spacing: 3) {
            Text(label)
                .font(Theme.Typeface.overline(8))
                .tracking(0.5)
                .foregroundStyle(Theme.tertiaryText)
                .frame(width: 24, alignment: .leading)
            Text(value)
                .font(Theme.Typeface.score(12))
                .foregroundStyle(Theme.secondaryText)
                .contentTransition(.numericText())
        }
    }

    /// On-base percentage from the game line. No hit-by-pitch or sac flies are
    /// tracked per batter, so this is (H + BB) / (AB + BB) — the same shape,
    /// exact for the overwhelming majority of plate appearances.
    private static func onBase(_ line: BattingLine) -> Double {
        let denominator = line.atBats + line.walks
        guard denominator > 0 else { return 0 }
        return Double(line.hits + line.walks) / Double(denominator)
    }

    /// Baseball's leading-zero-less rate: ".333", or "1.000" when it's perfect.
    private static func rate(_ value: Double) -> String {
        let text = String(format: "%.3f", value)
        return value < 1 ? String(text.dropFirst()) : text
    }
}

/// A slim strip under the at-bat card naming the next two hitters due up:
/// who's on deck and who's in the hole. No stats — just the order coming, so
/// the scorer can see it without opening the lineup.
struct OnDeckBar: View {
    var onDeck: Player?
    var inTheHole: Player?

    var body: some View {
        HStack(spacing: 12) {
            slot(label: "ON DECK", player: onDeck)

            Rectangle()
                .fill(Theme.tertiaryText.opacity(0.35))
                .frame(width: 1, height: 16)

            slot(label: "IN HOLE", player: inTheHole)
        }
        .padding(.horizontal, Theme.Metrics.cardPadding)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .scorecardSurface()
    }

    private func slot(label: String, player: Player?) -> some View {
        HStack(spacing: 7) {
            Text(label)
                .font(Theme.Typeface.overline(9))
                .tracking(1.1)
                .foregroundStyle(Theme.tertiaryText)

            if let player {
                Text(player.number.isEmpty ? "—" : player.number)
                    .font(Theme.Typeface.score(11))
                    .foregroundStyle(Theme.tertiaryText)
                Text(player.shortName.uppercased())
                    .font(Theme.Typeface.label(13, weight: .heavy))
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            } else {
                Text("—")
                    .font(Theme.Typeface.label(13, weight: .heavy))
                    .foregroundStyle(Theme.tertiaryText)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// A floating panel for the pitcher currently on the mound: who he is, his
/// live pitch count, and the line he's thrown so far this game.
///
/// The numbers are the scorer's own — everything here is folded out of the
/// event log, not fetched — so it stays honest with no signal and reads the
/// same for a sandlot game as for a big-league one.
struct PitcherPanel: View {
    var pitcher: Player?
    var line: PitchingLine?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("ON THE MOUND")
                    .font(Theme.Typeface.overline(9))
                    .tracking(1.4)
                    .foregroundStyle(Theme.tertiaryText)

                Spacer(minLength: 0)

                if let line {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(line.pitches)")
                            .font(Theme.Typeface.score(18))
                            .foregroundStyle(Theme.accent)
                            .contentTransition(.numericText())
                        Text("P")
                            .font(Theme.Typeface.overline(10))
                            .tracking(1.1)
                            .foregroundStyle(Theme.tertiaryText)
                    }
                }
            }

            if let pitcher {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(pitcher.number.isEmpty ? "—" : pitcher.number)
                        .font(Theme.Typeface.score(14))
                        .foregroundStyle(Theme.tertiaryText)
                        .frame(minWidth: 20, alignment: .trailing)
                    Text(pitcher.shortName.uppercased())
                        .font(Theme.Typeface.label(18, weight: .heavy))
                        .foregroundStyle(Theme.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(pitcher.throwsWith == .left ? "LHP" : "RHP")
                        .font(Theme.Typeface.caption())
                        .foregroundStyle(Theme.tertiaryText)
                    Spacer(minLength: 0)
                }
            } else {
                Text("NO PITCHER SET")
                    .font(Theme.Typeface.label(16, weight: .heavy))
                    .foregroundStyle(Theme.tertiaryText)
            }

            if let line {
                HStack(spacing: 0) {
                    stat("IP", line.inningsPitched)
                    stat("H", "\(line.hits)")
                    stat("R", "\(line.runs)")
                    stat("ER", "\(line.earnedRuns)")
                    stat("BB", "\(line.walks)")
                    stat("K", "\(line.strikeouts)")
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(Text(statSummary(line)))
            }
        }
        .padding(Theme.Metrics.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .scorecardSurface()
        .animation(.easeOut(duration: 0.2), value: line)
    }

    /// One column of the stat line: the number over its label. The value is
    /// held to a single line and allowed to shrink, so a decimal like "0.2"
    /// stays on one row in a narrow column instead of stacking digit by digit.
    private func stat(_ label: String, _ value: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(Theme.Typeface.score(14))
                .foregroundStyle(Theme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .contentTransition(.numericText())
            Text(label)
                .font(Theme.Typeface.overline(9))
                .tracking(0.8)
                .foregroundStyle(Theme.tertiaryText)
        }
        .frame(maxWidth: .infinity)
    }

    private func statSummary(_ line: PitchingLine) -> String {
        "\(line.inningsPitched) innings, \(line.hits) hits, \(line.runs) runs, "
            + "\(line.earnedRuns) earned, \(line.walks) walks, \(line.strikeouts) strikeouts, "
            + "\(line.pitches) pitches"
    }
}

/// Lays subviews out left to right, wrapping onto a new line whenever the next
/// one would overflow the width it's given. Used for the at-bat's pitch marks
/// so a long battle flows downward instead of pushing its card wider.
struct FlowLayout: Layout {
    var spacing: CGFloat = 5
    var lineSpacing: CGFloat = 5

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var widest: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                widest = max(widest, x - spacing)
                x = 0
                y += rowHeight + lineSpacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        widest = max(widest, x - spacing)

        let width = maxWidth == .infinity ? widest : min(widest, maxWidth)
        return CGSize(width: max(0, width), height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + lineSpacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

/// One pitch in the current at-bat's sequence.
struct PitchMark: View {
    var pitch: Pitch

    var body: some View {
        VStack(spacing: 2) {
            Text(pitch.outcome.mark)
                .font(Theme.Typeface.label(11, weight: .heavy))
                .foregroundStyle(Theme.color(for: pitch.outcome))
                .frame(width: 24, height: 24)
                .luminousCircle(Theme.color(for: pitch.outcome))
                // A reviewed call carries a flag, so a corrected mark never
                // looks like it was simply entered that way.
                .overlay(alignment: .topTrailing) {
                    if let challenge = pitch.challengeResult {
                        Image(systemName: "flag.fill")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(2)
                            .background(
                                Circle().fill(
                                    challenge == .overturned ? Theme.hitByPitch : Theme.neutral
                                )
                            )
                            .offset(x: 4, y: -4)
                    }
                }

            if let velocity = pitch.velocity {
                Text("\(velocity)")
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.tertiaryText)
            }
        }
        .accessibilityLabel(Text(accessibilityDescription))
    }

    private var accessibilityDescription: String {
        guard let challenge = pitch.challengeResult else { return pitch.outcome.spokenLabel }
        switch challenge {
        case .overturned: return "\(pitch.outcome.spokenLabel), overturned on challenge"
        case .stands: return "\(pitch.outcome.spokenLabel), challenge failed"
        }
    }
}
