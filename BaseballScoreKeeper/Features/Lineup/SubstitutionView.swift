import SwiftUI

/// Substitutions and pitching changes.
///
/// The available players are whoever hasn't appeared yet — a player who has
/// left the game can't come back, so they never show up in the list.
struct SubstitutionView: View {
    @Environment(GameStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var side: Side
    @State private var kind: SubstitutionKind = .pinchHitter
    @State private var incomingID: UUID?
    @State private var position: Position = .pitcher
    @State private var battingSlot: Int = 0
    @State private var runnerBase: Base = .first

    init(defaultSide: Side) {
        _side = State(initialValue: defaultSide)
    }

    private var lineup: LineupState { store.state.lineups[side] }
    private var roster: TeamRoster { store.teams[side] }

    /// Anyone who hasn't appeared yet — a player who has left can't come back.
    /// A pitching change narrows it to pitchers, which is the whole point of
    /// importing a roster: pick the arm, don't type the name.
    private var availablePlayers: [Player] {
        let unused = roster.players.filter { !lineup.appearedPlayerIDs.contains($0.id) }
        guard kind == .pitchingChange else { return unused }

        let pitchers = unused.filter { $0.primaryPosition == .pitcher }
        return pitchers.isEmpty ? unused : pitchers
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Team") {
                    Picker("Team", selection: $side) {
                        Text(store.teams.away.abbreviation).tag(Side.away)
                        Text(store.teams.home.abbreviation).tag(Side.home)
                    }
                    .pickerStyle(.segmented)
                }

                Section("Type") {
                    Picker("Type", selection: $kind) {
                        ForEach(SubstitutionKind.allCases) { option in
                            Text(option.label).tag(option)
                        }
                    }
                }

                Section {
                    if availablePlayers.isEmpty {
                        Text("No one left on the bench")
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("Player", selection: $incomingID) {
                            Text("Select").tag(UUID?.none)
                            ForEach(availablePlayers) { player in
                                Text("\(player.displayNumber) \(player.name) · \(player.primaryPosition.abbreviation)")
                                    .tag(UUID?.some(player.id))
                            }
                        }
                    }
                } header: {
                    Text("Coming in")
                } footer: {
                    Text("\(availablePlayers.count) available\(kind == .pitchingChange ? " · pitchers only" : "")")
                }

                if kind != .pitchingChange {
                    Section("Batting slot") {
                        Picker("Slot", selection: $battingSlot) {
                            ForEach(lineup.slots.indices, id: \.self) { index in
                                Text(slotLabel(index)).tag(index)
                            }
                        }
                    }
                }

                if kind != .pinchHitter && kind != .pinchRunner {
                    Section("Position") {
                        Picker("Position", selection: $position) {
                            ForEach(Position.fielders) { option in
                                Text("\(option.rawValue) · \(option.fullName)").tag(option)
                            }
                        }
                    }
                }

                if kind == .pinchRunner {
                    Section("Running for") {
                        Picker("Base", selection: $runnerBase) {
                            ForEach(store.state.bases.occupied) { base in
                                Text(runnerLabel(base)).tag(base)
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Substitution")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Make change") { commit() }
                        .disabled(incomingID == nil)
                }
            }
            .onChange(of: kind) { _, newValue in
                if newValue == .pitchingChange {
                    position = .pitcher
                }
            }
        }
    }

    private func slotLabel(_ index: Int) -> String {
        let slot = lineup.slots[index]
        let name = store.player(id: slot.playerID)?.shortName ?? "—"
        return "\(index + 1). \(name) (\(slot.position.abbreviation))"
    }

    private func runnerLabel(_ base: Base) -> String {
        let name = store.runnerOnBase(base)?.shortName ?? "—"
        return "\(base.label) — \(name)"
    }

    private func commit() {
        guard let incomingID else { return }

        let outgoingID: UUID?
        switch kind {
        case .pitchingChange:
            outgoingID = lineup.currentPitcherID
        case .pinchRunner:
            outgoingID = store.state.bases[runnerBase]?.playerID
        default:
            outgoingID = lineup.slots.indices.contains(battingSlot)
                ? lineup.slots[battingSlot].playerID
                : nil
        }

        // A pitching change only touches the batting order when the pitcher
        // actually bats — with a DH the order is untouched.
        let slot: Int?
        switch kind {
        case .pitchingChange:
            slot = lineup.usesDesignatedHitter
                ? nil
                : lineup.currentPitcherID.flatMap { lineup.slotIndex(of: $0) }
        default:
            slot = battingSlot
        }

        let resolvedPosition: Position
        switch kind {
        case .pitchingChange:
            resolvedPosition = .pitcher
        case .pinchHitter, .pinchRunner:
            resolvedPosition = lineup.slots.indices.contains(battingSlot)
                ? lineup.slots[battingSlot].position
                : .designatedHitter
        default:
            resolvedPosition = position
        }

        store.substitute(
            Substitution(
                side: side,
                kind: kind,
                incomingPlayerID: incomingID,
                outgoingPlayerID: outgoingID,
                battingSlot: slot,
                position: resolvedPosition,
                runnerBase: kind == .pinchRunner ? runnerBase : nil
            )
        )
        dismiss()
    }
}
