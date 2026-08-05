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
    var bases: Bases
    var runnerName: (Base) -> String?
    var headline: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if let batter {
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
                } else {
                    Text("LINEUP DUE UP")
                        .font(Theme.Typeface.label(16, weight: .heavy))
                        .foregroundStyle(Theme.tertiaryText)
                }
                Spacer(minLength: 0)
            }

            if !pitches.isEmpty {
                HStack(spacing: 5) {
                    ForEach(pitches) { pitch in
                        PitchMark(pitch: pitch)
                    }
                }
            }

            if !runnersText.isEmpty {
                Text(runnersText)
                    .font(Theme.Typeface.caption())
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
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

    /// "1st Judge · 3rd Soto" — names, not just base labels, because the point
    /// of knowing who's on is knowing whether to expect them to run.
    private var runnersText: String {
        let parts = bases.occupied.compactMap { base -> String? in
            guard let name = runnerName(base) else { return base.label }
            return "\(base.label) \(name)"
        }
        return parts.joined(separator: "  ·  ")
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
