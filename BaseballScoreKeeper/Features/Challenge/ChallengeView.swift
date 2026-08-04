import SwiftUI

/// The contextual prompt that appears only while a call is open to review.
///
/// Challenges have to be immediate, so this is deliberately not a permanent
/// control — it shows up the moment a ball or called strike is recorded and
/// disappears as soon as the next pitch is. If it isn't on screen, the window
/// has closed, which is exactly the rule.
struct ChallengePrompt: View {
    var pitch: Pitch
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: "flag.fill")
                    .font(.system(size: 11, weight: .bold))
                Text("Challenge the \(pitch.outcome.shortLabel.lowercased())")
                    .font(Theme.Typeface.label(13, weight: .bold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(Capsule().fill(Theme.hitByPitch))
            .shadow(color: .black.opacity(0.3), radius: 6, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Challenge the \(pitch.outcome.spokenLabel)"))
    }
}

/// Recording a challenge: who asked for it, and how it came back.
///
/// Anchored to the bottom so it stays inside the thumb's arc, like every other
/// decision surface in the one-handed flow.
struct ChallengeSheet: View {
    var pitch: Pitch
    var teams: SideValues<TeamRoster>
    var battingSide: Side
    var challengesRemaining: SideValues<Int>
    var onCommit: (ChallengeRole, ChallengeResult) -> Void
    var onCancel: () -> Void

    @State private var role: ChallengeRole

    init(
        pitch: Pitch,
        teams: SideValues<TeamRoster>,
        battingSide: Side,
        challengesRemaining: SideValues<Int>,
        suggestedRole: ChallengeRole,
        onCommit: @escaping (ChallengeRole, ChallengeResult) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.pitch = pitch
        self.teams = teams
        self.battingSide = battingSide
        self.challengesRemaining = challengesRemaining
        self.onCommit = onCommit
        self.onCancel = onCancel
        _role = State(initialValue: suggestedRole)
    }

    private var challengingSide: Side {
        role.side(battingSide: battingSide)
    }

    private var remaining: Int {
        challengesRemaining[challengingSide]
    }

    private var hasChallengeLeft: Bool { remaining > 0 }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { onCancel() }

            VStack(spacing: 16) {
                header
                rolePicker
                resultButtons
                remainingLine

                Button("Cancel", action: onCancel)
                    .font(Theme.Typeface.label(14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
            }
            .padding(18)
            .frame(maxWidth: 420)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Theme.surface)
            )
            .padding(.horizontal, 12)
            .padding(.bottom, 26)
        }
        .transition(.opacity)
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 6) {
            Text("CHALLENGE")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .tracking(1.6)
                .foregroundStyle(Theme.secondaryText)

            HStack(spacing: 10) {
                CallChip(label: pitch.outcome.shortLabel, tint: Theme.color(for: pitch.outcome))
                Image(systemName: "arrow.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.secondaryText)
                if let reversal = pitch.outcome.challengeReversal {
                    CallChip(label: reversal.shortLabel, tint: Theme.color(for: reversal))
                }
            }

            Text("if overturned")
                .font(Theme.Typeface.caption())
                .foregroundStyle(Theme.secondaryText)
        }
    }

    // MARK: - Who

    private var rolePicker: some View {
        VStack(spacing: 6) {
            Text("WHO CHALLENGED")
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .tracking(1.3)
                .foregroundStyle(Theme.secondaryText)

            HStack(spacing: 8) {
                ForEach(ChallengeRole.allCases) { option in
                    Button {
                        role = option
                    } label: {
                        VStack(spacing: 2) {
                            Text(option.label)
                                .font(Theme.Typeface.label(13, weight: .bold))
                            Text(teams[option.side(battingSide: battingSide)].abbreviation)
                                .font(.system(size: 9, weight: .semibold, design: .rounded))
                                .opacity(0.75)
                        }
                        .foregroundStyle(role == option ? .white : Theme.primaryText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(role == option ? Theme.inPlay : Theme.surfaceRaised)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Result

    private var resultButtons: some View {
        VStack(spacing: 6) {
            Text("HOW DID IT COME BACK?")
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .tracking(1.3)
                .foregroundStyle(Theme.secondaryText)

            HStack(spacing: 10) {
                ForEach(ChallengeResult.allCases) { result in
                    Button {
                        onCommit(role, result)
                    } label: {
                        VStack(spacing: 3) {
                            Text(result.label)
                                .font(Theme.Typeface.label(15, weight: .heavy))
                            Text(result.detail)
                                .font(.system(size: 9, weight: .medium, design: .rounded))
                                .opacity(0.85)
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(result == .overturned ? Theme.ball : Theme.miss)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(!hasChallengeLeft)
                    .opacity(hasChallengeLeft ? 1 : 0.35)
                }
            }
        }
    }

    // MARK: - Remaining

    private var remainingLine: some View {
        VStack(spacing: 3) {
            if hasChallengeLeft {
                Text("\(teams[challengingSide].abbreviation) has \(remaining) challenge\(remaining == 1 ? "" : "s") left")
                    .font(Theme.Typeface.caption())
                    .foregroundStyle(Theme.secondaryText)
            } else {
                Text("\(teams[challengingSide].abbreviation) has no challenges left")
                    .font(Theme.Typeface.caption())
                    .foregroundStyle(Theme.miss)
            }

            Text(
                "\(teams.away.abbreviation) \(challengesRemaining.away)  ·  "
                    + "\(teams.home.abbreviation) \(challengesRemaining.home)"
            )
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .foregroundStyle(Theme.secondaryText.opacity(0.75))
        }
    }
}

private struct CallChip: View {
    var label: String
    var tint: Color

    var body: some View {
        Text(label)
            .font(Theme.Typeface.label(15, weight: .heavy))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(Capsule().fill(tint))
    }
}

/// Remaining-challenge pips for the live header — two dots per team, dimmed as
/// they're spent.
struct ChallengePips: View {
    var remaining: Int
    var total: Int
    var tint: Color = Theme.hitByPitch

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<max(total, remaining), id: \.self) { index in
                Image(systemName: "flag.fill")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(index < remaining ? tint : Theme.secondaryText.opacity(0.28))
            }
        }
        .accessibilityLabel(Text("\(remaining) challenges left"))
    }
}
