import SwiftUI
import UniformTypeIdentifiers

/// The defensive half of substitutions, done the way a manager actually thinks
/// about it: a field with the nine gloves on it and a bench underneath.
///
/// Two on-field players swap by tapping one then the other (or dragging one onto
/// the other). A bench player comes in by tapping-then-tapping a position, or by
/// dragging them onto it — whoever was there leaves the game. Everything routes
/// through the substitution events the engine already understands, so undo and
/// the box score come along for free.
struct DefensiveAlignmentView: View {
    @Environment(GameStore.self) private var store

    var side: Side

    /// The on-field position the scorer has armed for a swap, if any.
    @State private var armedPosition: Position?
    /// The bench player armed to come in, if any.
    @State private var armedBenchID: UUID?

    private let space = "alignmentSpace"

    private var lineup: LineupState { store.state.lineups[side] }
    private var roster: TeamRoster { store.teams[side] }

    /// Anyone on the roster who hasn't appeared yet — a player who has left the
    /// game can't come back, so the bench is exactly the un-appeared.
    private var bench: [Player] {
        roster.players.filter { !lineup.appearedPlayerIDs.contains($0.id) }
    }

    var body: some View {
        VStack(spacing: 12) {
            hint
            diamond
            benchStrip
        }
        .coordinateSpace(name: space)
        .animation(.easeOut(duration: 0.15), value: armedPosition)
        .animation(.easeOut(duration: 0.15), value: armedBenchID)
    }

    // MARK: - Hint

    private var hint: some View {
        Text(hintText)
            .font(Theme.Typeface.caption())
            .foregroundStyle(Theme.secondaryText)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .lineLimit(2)
            .minimumScaleFactor(0.8)
    }

    private var hintText: String {
        if let armedBenchID, let player = store.player(id: armedBenchID) {
            return "Tap a position to bring \(player.shortName) in"
        }
        if let armedPosition {
            return "Tap another position to swap with \(armedPosition.abbreviation), or tap it again to cancel"
        }
        return "Tap two positions to swap them, or arm a bench player. Dragging works too."
    }

    // MARK: - Diamond

    private var diamond: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack {
                FairTerritoryShape().fill(Theme.fieldGrass)
                FairTerritoryShape().stroke(Theme.hairline, lineWidth: 1)
                InfieldShape().fill(Theme.fieldDirt.opacity(0.85))
                BasePathsShape().stroke(Color.white.opacity(0.3), lineWidth: 1.5)

                ForEach(Position.fielders) { position in
                    positionNode(position, at: FieldGeometry.point(for: position, in: size))
                }
            }
        }
        .aspectRatio(1.1, contentMode: .fit)
    }

    @ViewBuilder
    private func positionNode(_ position: Position, at point: CGPoint) -> some View {
        let playerID = lineup.playerID(playing: position)
        let player = playerID.flatMap { store.player(id: $0) }
        let isArmed = armedPosition == position

        Button {
            tapPosition(position)
        } label: {
            VStack(spacing: 1) {
                Text(position.abbreviation)
                    .font(Theme.Typeface.label(11, weight: .heavy))
                    .foregroundStyle(isArmed ? .white : Theme.accent)
                Text(player?.shortName ?? "—")
                    .font(Theme.Typeface.caption())
                    .foregroundStyle(isArmed ? .white : Theme.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if let number = player?.number, !number.isEmpty {
                    Text("#\(number)")
                        .font(Theme.Typeface.overline(8))
                        .foregroundStyle(isArmed ? .white.opacity(0.8) : Theme.tertiaryText)
                }
            }
            .frame(width: 62, height: 46)
            .padding(.horizontal, 2)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(isArmed ? Theme.accent : Theme.surfaceHigh)
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(Color.white.opacity(isArmed ? 0.85 : 0.25), lineWidth: 1)
                    )
            )
            .shadow(color: .black.opacity(0.35), radius: 4, y: 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .position(point)
        // Drag an on-field player off their spot, and accept a drop onto it.
        .draggable(FielderToken(position: position)) {
            dragPreview(position.abbreviation)
        }
        .dropDestination(for: FielderToken.self) { tokens, _ in
            guard let token = tokens.first else { return false }
            handleDrop(token, onto: position)
            return true
        }
        .accessibilityLabel(Text("\(position.fullName), \(player?.name ?? "empty")"))
    }

    // MARK: - Bench

    @ViewBuilder
    private var benchStrip: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("BENCH")
                .font(Theme.Typeface.overline(9))
                .tracking(1.4)
                .foregroundStyle(Theme.tertiaryText)

            if bench.isEmpty {
                Text("No one left on the bench")
                    .font(Theme.Typeface.caption())
                    .foregroundStyle(Theme.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(bench) { player in
                            benchRow(player)
                        }
                    }
                }
                .frame(maxHeight: 180)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func benchRow(_ player: Player) -> some View {
        let isArmed = armedBenchID == player.id
        return Button {
            tapBench(player.id)
        } label: {
            HStack(spacing: 8) {
                Text(player.number.isEmpty ? "—" : player.number)
                    .font(Theme.Typeface.score(13))
                    .foregroundStyle(isArmed ? .white.opacity(0.85) : Theme.tertiaryText)
                    .frame(minWidth: 24, alignment: .trailing)
                Text(player.name)
                    .font(Theme.Typeface.label(14, weight: .semibold))
                    .foregroundStyle(isArmed ? .white : Theme.primaryText)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text(player.primaryPosition.abbreviation)
                    .font(Theme.Typeface.caption())
                    .foregroundStyle(isArmed ? .white.opacity(0.85) : Theme.tertiaryText)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isArmed ? Theme.accent : Theme.surface)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .draggable(FielderToken(benchPlayerID: player.id)) {
            dragPreview(player.number.isEmpty ? player.shortName : "#\(player.number)")
        }
    }

    private func dragPreview(_ text: String) -> some View {
        Text(text)
            .font(Theme.Typeface.label(13, weight: .heavy))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Capsule().fill(Theme.accent))
    }

    // MARK: - Interaction

    private func tapPosition(_ position: Position) {
        // A bench player is waiting to come in.
        if let benchID = armedBenchID {
            substituteIn(benchID, at: position)
            clearArmed()
            return
        }

        switch armedPosition {
        case .none:
            Haptics.shared.tap(enabled: store.settings.hapticsEnabled)
            armedPosition = position
        case .some(position):
            // Tapping the armed position again cancels.
            clearArmed()
        case .some(let other):
            swap(other, position)
            clearArmed()
        }
    }

    private func tapBench(_ playerID: UUID) {
        armedPosition = nil
        if armedBenchID == playerID {
            armedBenchID = nil
        } else {
            Haptics.shared.tap(enabled: store.settings.hapticsEnabled)
            armedBenchID = playerID
        }
    }

    private func handleDrop(_ token: FielderToken, onto position: Position) {
        if let benchID = token.benchPlayerID {
            substituteIn(benchID, at: position)
        } else if let from = token.position, from != position {
            swap(from, position)
        }
        clearArmed()
    }

    private func clearArmed() {
        armedPosition = nil
        armedBenchID = nil
    }

    // MARK: - Committing

    /// Swaps the two players standing at these positions. Two grouped
    /// position-switch events: each player is reassigned to the other's spot, so
    /// the second event doesn't clobber the first.
    private func swap(_ a: Position, _ b: Position) {
        guard
            let playerA = lineup.playerID(playing: a),
            let playerB = lineup.playerID(playing: b)
        else { return }

        Haptics.shared.commit(enabled: store.settings.hapticsEnabled)
        store.beginGroup()
        store.substitute(
            Substitution(
                side: side,
                kind: .positionSwitch,
                incomingPlayerID: playerA,
                outgoingPlayerID: nil,
                battingSlot: nil,
                position: b,
                runnerBase: nil
            )
        )
        store.substitute(
            Substitution(
                side: side,
                kind: .positionSwitch,
                incomingPlayerID: playerB,
                outgoingPlayerID: nil,
                battingSlot: nil,
                position: a,
                runnerBase: nil
            )
        )
        store.endGroup()
    }

    /// Brings a bench player onto the field at a position, retiring whoever was
    /// there. Their batting slot is inherited so the order is unbroken.
    private func substituteIn(_ benchID: UUID, at position: Position) {
        let outgoing = lineup.playerID(playing: position)
        let slot = outgoing.flatMap { lineup.slotIndex(of: $0) }

        Haptics.shared.commit(enabled: store.settings.hapticsEnabled)
        store.substitute(
            Substitution(
                side: side,
                kind: .defensive,
                incomingPlayerID: benchID,
                outgoingPlayerID: outgoing,
                battingSlot: slot,
                position: position,
                runnerBase: nil
            )
        )
    }
}

/// The thing that moves during a drag on the alignment field: either an on-field
/// player (identified by the position they hold) or a bench player.
struct FielderToken: Codable, Transferable {
    var position: Position?
    var benchPlayerID: UUID?

    init(position: Position? = nil, benchPlayerID: UUID? = nil) {
        self.position = position
        self.benchPlayerID = benchPlayerID
    }

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .json)
    }
}
