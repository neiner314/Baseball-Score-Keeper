import SwiftUI

/// The scorebook page — the thing this app is for.
///
/// Rows are batting-order slots, columns are innings, and each box carries the
/// notation plus the diamond shaded as far as that runner got. It is the paper
/// scorebook, read the way a scorer reads one: down a column to see an inning,
/// across a row to see a hitter's day.
struct ScorebookView: View {
    @Environment(GameStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var side: Side = .away

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Team", selection: $side) {
                    Text(store.teams.away.abbreviation).tag(Side.away)
                    Text(store.teams.home.abbreviation).tag(Side.home)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, Theme.Metrics.screenMargin)
                .padding(.vertical, 10)

                // Built once per render rather than once per sub-view: this is
                // a full replay of the log, cheap but not free.
                ScorebookPageView(
                    page: store.buildScorebook()[side],
                    teamAbbreviation: store.teams[side].abbreviation
                )
            }
            .appBackground()
            .navigationTitle("Scorebook")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

/// One team's page. Split out so the page is computed once and handed down,
/// rather than recomputed by every column that needs to measure itself.
struct ScorebookPageView: View {
    @Environment(GameStore.self) private var store

    var page: ScorebookPage
    var teamAbbreviation: String

    @State private var selected: ScorebookCell?

    private let rowHeight: CGFloat = 58
    private let cellWidth: CGFloat = 62
    private let nameWidth: CGFloat = 104

    var body: some View {
        VStack(spacing: 0) {
            lineScore
            Divider().overlay(Theme.hairline)

            if page.rows.allSatisfy({ $0.cellsByInning.isEmpty }) {
                emptyState
            } else {
                grid
            }
        }
        .sheet(item: $selected) { cell in
            ScorebookCellDetail(cell: cell, playerName: name(of: cell.batterID))
                .presentationDetents([.height(280)])
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "square.grid.3x3")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(Theme.tertiaryText)
            Text("No plate appearances yet")
                .font(Theme.Typeface.label(14))
                .foregroundStyle(Theme.secondaryText)
            Text("Boxes fill in as batters resolve.")
                .font(Theme.Typeface.caption())
                .foregroundStyle(Theme.tertiaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Line score

    /// Runs by inning across the top, so the page reads like a scoreboard
    /// before you look at a single box.
    private var lineScore: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                Text(teamAbbreviation)
                    .font(Theme.Typeface.label(12, weight: .heavy))
                    .foregroundStyle(Theme.secondaryText)
                    .frame(width: nameWidth, alignment: .leading)

                ForEach(page.innings, id: \.self) { inning in
                    Text(page.runsByInning[inning].map(String.init) ?? "0")
                        .font(Theme.Typeface.score(15))
                        .foregroundStyle(
                            (page.runsByInning[inning] ?? 0) > 0 ? Theme.ball : Theme.tertiaryText
                        )
                        .frame(width: columnWidth(inning))
                }

                totalsCell("R", "\(page.totalRuns)", tint: Theme.ball)
                totalsCell("H", "\(page.totalHits)", tint: Theme.primaryText)
                totalsCell("LOB", "\(page.totalLeftOnBase)", tint: Theme.secondaryText)
            }
            .padding(.horizontal, Theme.Metrics.screenMargin)
        }
        .padding(.vertical, 8)
    }

    private func totalsCell(_ label: String, _ value: String, tint: Color) -> some View {
        VStack(spacing: 1) {
            Text(label)
                .font(Theme.Typeface.overline(8))
                .tracking(0.8)
                .foregroundStyle(Theme.tertiaryText)
            Text(value)
                .font(Theme.Typeface.score(15))
                .foregroundStyle(tint)
        }
        .frame(width: 44)
    }

    // MARK: - Grid

    private var grid: some View {
        ScrollView(.vertical, showsIndicators: false) {
            HStack(alignment: .top, spacing: 0) {
                nameColumn

                ScrollView(.horizontal, showsIndicators: false) {
                    VStack(spacing: 0) {
                        inningHeader
                        ForEach(page.rows) { row in
                            HStack(spacing: 0) {
                                ForEach(page.innings, id: \.self) { inning in
                                    cellGroup(row: row, inning: inning)
                                }
                            }
                            .frame(height: rowHeight)
                            Divider().overlay(Theme.hairline)
                        }
                    }
                }
            }
            .padding(.horizontal, Theme.Metrics.screenMargin)
            .padding(.bottom, 24)
        }
    }

    private var nameColumn: some View {
        VStack(spacing: 0) {
            Color.clear.frame(width: nameWidth, height: 28)

            ForEach(page.rows) { row in
                VStack(alignment: .leading, spacing: 1) {
                    Text(slotLabel(row))
                        .font(Theme.Typeface.label(13, weight: .bold))
                        .foregroundStyle(Theme.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    if row.playerIDs.count > 1 {
                        Text(subsLabel(row))
                            .font(Theme.Typeface.overline(9))
                            .foregroundStyle(Theme.tertiaryText)
                            .lineLimit(1)
                    }
                }
                .frame(width: nameWidth, height: rowHeight, alignment: .leading)
                Divider().overlay(Theme.hairline)
            }
        }
    }

    private var inningHeader: some View {
        HStack(spacing: 0) {
            ForEach(page.innings, id: \.self) { inning in
                Text("\(inning)")
                    .font(Theme.Typeface.overline(10))
                    .tracking(1)
                    .foregroundStyle(Theme.tertiaryText)
                    .frame(width: columnWidth(inning), height: 28)
            }
        }
    }

    /// A slot that bats around gets two boxes in the same inning, so the column
    /// widens rather than the boxes shrinking.
    private func cellGroup(row: ScorebookRow, inning: Int) -> some View {
        let cells = row.cells(inning: inning)
        return HStack(spacing: 0) {
            ForEach(cells) { cell in
                ScorebookBox(cell: cell)
                    .frame(width: cellWidth, height: rowHeight)
                    .contentShape(Rectangle())
                    .onTapGesture { selected = cell }
            }
            if cells.isEmpty {
                Color.clear.frame(width: cellWidth, height: rowHeight)
            }
        }
        .frame(width: columnWidth(inning), alignment: .leading)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Theme.hairline)
                .frame(width: 1)
        }
    }

    private func columnWidth(_ inning: Int) -> CGFloat {
        let deepest = page.rows.map { $0.cells(inning: inning).count }.max() ?? 1
        return cellWidth * CGFloat(max(1, deepest))
    }

    // MARK: - Labels

    private func slotLabel(_ row: ScorebookRow) -> String {
        guard let first = row.playerIDs.first, let player = store.player(id: first) else {
            return "\(row.slot + 1)."
        }
        return "\(row.slot + 1). \(player.shortName)"
    }

    private func subsLabel(_ row: ScorebookRow) -> String {
        row.playerIDs.dropFirst()
            .compactMap { store.player(id: $0)?.shortName }
            .joined(separator: ", ")
    }

    private func name(of playerID: UUID) -> String {
        store.player(id: playerID)?.name ?? "—"
    }
}

/// One box on the page: the diamond, the notation, and the marks in the corners
/// a scorer uses for outs and runs batted in.
struct ScorebookBox: View {
    var cell: ScorebookCell

    var body: some View {
        ZStack {
            ScorebookDiamond(
                basesAdvanced: cell.basesAdvanced,
                isOut: cell.batterWasRetired || cell.wasRetiredOnBases,
                size: 42
            )

            Text(cell.notation)
                .font(Theme.Typeface.notation(cell.notation.count > 5 ? 9 : 11))
                .foregroundStyle(textTint)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                // A flat translucent backing, not a material: this is drawn
                // once per box and a full page has ninety of them.
                .background(Theme.controlBody, in: Capsule())
        }
        .overlay(alignment: .topLeading) {
            if let outNumber = cell.outNumber {
                Text("\(outNumber)")
                    .font(Theme.Typeface.label(8, weight: .heavy))
                    .foregroundStyle(Theme.background)
                    .frame(width: 14, height: 14)
                    .background(Circle().fill(Theme.miss))
                    .padding(2)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if cell.rbis > 0 {
                Text("\(cell.rbis)")
                    .font(Theme.Typeface.label(8, weight: .heavy))
                    .foregroundStyle(Theme.background)
                    .frame(width: 14, height: 14)
                    .background(Circle().fill(Theme.foul))
                    .padding(2)
            }
        }
        .overlay(alignment: .bottomLeading) {
            if cell.wasLeftOnBase {
                Circle()
                    .strokeBorder(Theme.tertiaryText, lineWidth: 1)
                    .frame(width: 7, height: 7)
                    .padding(4)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(Text(accessibilityText))
    }

    private var textTint: Color {
        if cell.didScore { return Theme.ball }
        if cell.batterWasRetired { return Theme.secondaryText }
        return Theme.primaryText
    }

    private var accessibilityText: String {
        var parts = [cell.notation]
        if cell.didScore { parts.append("scored") }
        if cell.rbis > 0 { parts.append("\(cell.rbis) RBI") }
        if cell.wasLeftOnBase { parts.append("left on base") }
        return parts.joined(separator: ", ")
    }
}

/// Tapping a box explains it in words, which is where a scorer settles an
/// argument about what they wrote three innings ago.
private struct ScorebookCellDetail: View {
    var cell: ScorebookCell
    var playerName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 14) {
                ScorebookDiamond(
                    basesAdvanced: cell.basesAdvanced,
                    isOut: cell.batterWasRetired || cell.wasRetiredOnBases,
                    size: 54
                )
                VStack(alignment: .leading, spacing: 3) {
                    Text(cell.notation)
                        .font(Theme.Typeface.notation(26, weight: .heavy))
                        .foregroundStyle(Theme.primaryText)
                    Text(playerName)
                        .font(Theme.Typeface.label(13))
                        .foregroundStyle(Theme.secondaryText)
                }
                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: 8) {
                detailRow("Inning", "\(cell.inning)")
                detailRow("Pitches", "\(cell.pitchCount)")
                if cell.rbis > 0 { detailRow("RBI", "\(cell.rbis)") }
                detailRow("Result", summary)
            }

            Spacer(minLength: 0)
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appBackground()
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(Theme.Typeface.caption())
                .foregroundStyle(Theme.tertiaryText)
            Spacer()
            Text(value)
                .font(Theme.Typeface.label(13))
                .foregroundStyle(Theme.primaryText)
                .multilineTextAlignment(.trailing)
        }
    }

    private var summary: String {
        if cell.didScore { return "Reached and scored" }
        if cell.wasRetiredOnBases { return "Reached, retired on the bases" }
        if cell.wasLeftOnBase { return "Left on base" }
        if let outNumber = cell.outNumber { return "Out number \(outNumber)" }
        if let reached = cell.reached { return "Safe at \(reached.label)" }
        return "—"
    }
}
