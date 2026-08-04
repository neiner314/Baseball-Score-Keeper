import SwiftUI

/// Count as lights rather than digits: three balls, two strikes, two outs.
/// A scorer glancing down reads dots faster than they read "2-1".
struct CountLights: View {
    enum Style {
        case compact
        case scoreboard
    }

    var balls: Int
    var strikes: Int
    var outs: Int
    var style: Style = .compact
    var showsLabels: Bool = false

    private var dotSize: CGFloat { style == .scoreboard ? 15 : 8 }
    private var spacing: CGFloat { style == .scoreboard ? 10 : 4 }

    var body: some View {
        HStack(spacing: style == .scoreboard ? 30 : 10) {
            group(title: "BALLS", filled: balls, total: 3, tint: Theme.ball)
            group(title: "STRIKES", filled: strikes, total: 2, tint: Theme.miss)
            group(title: "OUTS", filled: outs, total: 2, tint: Theme.foul)
        }
    }

    private func group(title: String, filled: Int, total: Int, tint: Color) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: spacing) {
                ForEach(0..<total, id: \.self) { index in
                    Circle()
                        .fill(index < filled ? tint : Theme.secondaryText.opacity(0.25))
                        .frame(width: dotSize, height: dotSize)
                        .animation(.easeOut(duration: 0.15), value: filled)
                }
            }
            if showsLabels {
                Text(title)
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .tracking(1.2)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
    }
}

/// The tight header from the refined layout: score line, batter, count.
struct CompactScoreHeader: View {
    var state: GameState
    var teams: SideValues<TeamRoster>
    var batter: Player?
    var batterPosition: Position?
    var foulCount: Int
    var showsFoulCount: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(state.scoreLine(teams: teams)) · \(state.inningLabel)")
                .font(Theme.Typeface.caption())
                .foregroundStyle(Theme.secondaryText)

            HStack(alignment: .firstTextBaseline) {
                if let batter {
                    HStack(spacing: 6) {
                        Text(batter.displayNumber)
                            .font(Theme.Typeface.label(17, weight: .bold))
                        Text(batter.shortName)
                            .font(Theme.Typeface.label(17, weight: .bold))
                        if let batterPosition {
                            Text(batterPosition.abbreviation)
                                .font(Theme.Typeface.caption())
                                .foregroundStyle(Theme.secondaryText)
                        }
                    }
                    .foregroundStyle(Theme.primaryText)
                } else {
                    Text("Lineup due up")
                        .font(Theme.Typeface.label(17, weight: .bold))
                        .foregroundStyle(Theme.secondaryText)
                }

                Spacer(minLength: 8)

                Text(state.countLabel)
                    .font(Theme.Typeface.score(26))
                    .foregroundStyle(Theme.primaryText)
            }

            HStack(spacing: 10) {
                CountLights(balls: state.balls, strikes: state.strikes, outs: state.outs)
                if showsFoulCount {
                    Text("\(foulCount) foul\(foulCount == 1 ? "" : "s")")
                        .font(Theme.Typeface.caption())
                        .foregroundStyle(Theme.secondaryText)
                }
                Spacer(minLength: 0)
                Text(state.bases.summary)
                    .font(Theme.Typeface.caption())
                    .foregroundStyle(Theme.secondaryText)
            }
        }
    }
}

/// The big scoreboard treatment used by the one-handed layout, where the
/// screen exists to be glanced at rather than read.
struct ScoreboardHeader: View {
    var state: GameState
    var teams: SideValues<TeamRoster>
    var batter: Player?
    var lastVelocity: Int?
    var showsVelocity: Bool

    var body: some View {
        VStack(spacing: 14) {
            Text("\(state.inningLabel)  ·  \(state.countLabel)")
                .font(Theme.Typeface.caption())
                .tracking(1.4)
                .foregroundStyle(Theme.secondaryText)

            Text(batter.map { "\($0.displayNumber) \($0.name.uppercased())" } ?? "—")
                .font(Theme.Typeface.label(19, weight: .bold))
                .foregroundStyle(Theme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            CountLights(
                balls: state.balls,
                strikes: state.strikes,
                outs: state.outs,
                style: .scoreboard,
                showsLabels: true
            )

            if showsVelocity {
                velocityReadout
            }

            Text(state.scoreLine(teams: teams))
                .font(Theme.Typeface.score(22))
                .foregroundStyle(Theme.primaryText)
        }
    }

    @ViewBuilder
    private var velocityReadout: some View {
        if let lastVelocity {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(lastVelocity)")
                    .font(Theme.Typeface.score(44))
                Text("mph")
                    .font(Theme.Typeface.label(13, weight: .medium))
                    .foregroundStyle(Theme.secondaryText)
            }
            .foregroundStyle(Theme.primaryText)
        } else {
            Text("—")
                .font(Theme.Typeface.score(44))
                .foregroundStyle(Theme.secondaryText.opacity(0.4))
        }
    }
}

/// The running pitch sequence for the current at-bat: B C S F X.
struct PitchSequenceStrip: View {
    var pitches: [Pitch]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("THIS AT-BAT")
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .tracking(1.4)
                .foregroundStyle(Theme.secondaryText)

            if pitches.isEmpty {
                Text("First pitch")
                    .font(Theme.Typeface.caption())
                    .foregroundStyle(Theme.secondaryText.opacity(0.6))
            } else {
                HStack(spacing: 6) {
                    ForEach(pitches) { pitch in
                        PitchMark(pitch: pitch)
                    }
                }
            }
        }
    }
}

private struct PitchMark: View {
    var pitch: Pitch

    var body: some View {
        VStack(spacing: 2) {
            Text(pitch.outcome.mark)
                .font(Theme.Typeface.label(11, weight: .heavy))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Circle().fill(Theme.color(for: pitch.outcome)))

            if let velocity = pitch.velocity {
                Text("\(velocity)")
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.secondaryText)
            }
        }
    }
}
