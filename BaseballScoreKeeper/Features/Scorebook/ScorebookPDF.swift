import SwiftUI
import CoreGraphics

/// A whole scorebook page laid out at its natural size, without the scroll views
/// the on-screen version needs. This is the thing that goes into the PDF — every
/// box on one sheet, the way a printed scorecard reads.
struct ScorebookPDFPage: View {
    var page: ScorebookPage
    var teamName: String
    /// A full name for a batter id, since the PDF has no store to reach into.
    var name: (UUID) -> String

    private let rowHeight: CGFloat = 60
    private let cellWidth: CGFloat = 66
    private let nameWidth: CGFloat = 150
    private let headerHeight: CGFloat = 26

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(teamName.uppercased())
                .font(Theme.Typeface.label(20, weight: .heavy))
                .foregroundStyle(Theme.primaryText)
                .padding(.bottom, 12)

            grid
        }
        .padding(28)
        .background(Theme.background)
    }

    private var grid: some View {
        HStack(alignment: .top, spacing: 0) {
            nameColumn
            ForEach(page.innings, id: \.self) { inning in
                inningColumn(inning)
            }
            totalsColumn
        }
    }

    private var nameColumn: some View {
        VStack(spacing: 0) {
            cellFrame(width: nameWidth, height: headerHeight) {
                Text(teamName)
                    .font(Theme.Typeface.overline(9))
                    .tracking(1)
                    .foregroundStyle(Theme.tertiaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            ForEach(page.rows) { row in
                cellFrame(width: nameWidth, height: rowHeight) {
                    Text(slotLabel(row))
                        .font(Theme.Typeface.label(13, weight: .bold))
                        .foregroundStyle(Theme.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func inningColumn(_ inning: Int) -> some View {
        let width = columnWidth(inning)
        return VStack(spacing: 0) {
            cellFrame(width: width, height: headerHeight) {
                Text("\(inning)")
                    .font(Theme.Typeface.overline(10))
                    .tracking(1)
                    .foregroundStyle(Theme.tertiaryText)
            }
            ForEach(page.rows) { row in
                let cells = row.cells(inning: inning)
                cellFrame(width: width, height: rowHeight) {
                    HStack(spacing: 0) {
                        ForEach(cells) { cell in
                            ScorebookBox(cell: cell)
                                .frame(width: cellWidth, height: rowHeight)
                        }
                    }
                }
            }
        }
    }

    private var totalsColumn: some View {
        VStack(spacing: 0) {
            cellFrame(width: cellWidth * 1.6, height: headerHeight) {
                HStack(spacing: 10) {
                    Text("R").frame(maxWidth: .infinity)
                    Text("H").frame(maxWidth: .infinity)
                    Text("LOB").frame(maxWidth: .infinity)
                }
                .font(Theme.Typeface.overline(9))
                .foregroundStyle(Theme.tertiaryText)
            }
            cellFrame(width: cellWidth * 1.6, height: rowHeight) {
                HStack(spacing: 10) {
                    Text("\(page.totalRuns)").frame(maxWidth: .infinity)
                    Text("\(page.totalHits)").frame(maxWidth: .infinity)
                    Text("\(page.totalLeftOnBase)").frame(maxWidth: .infinity)
                }
                .font(Theme.Typeface.score(15))
                .foregroundStyle(Theme.primaryText)
            }
            Spacer(minLength: 0)
        }
    }

    private func cellFrame<Content: View>(
        width: CGFloat,
        height: CGFloat,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .frame(width: width, height: height)
            .overlay(
                Rectangle().stroke(Theme.hairline, lineWidth: 0.5)
            )
    }

    private func columnWidth(_ inning: Int) -> CGFloat {
        let deepest = page.rows.map { $0.cells(inning: inning).count }.max() ?? 1
        return cellWidth * CGFloat(max(1, deepest))
    }

    private func slotLabel(_ row: ScorebookRow) -> String {
        guard let first = row.playerIDs.first else { return "\(row.slot + 1)." }
        return "\(row.slot + 1). \(name(first))"
    }
}

/// Renders a game's scorebook — both teams, one page each — into a PDF the
/// scorer can save or share.
///
/// It draws with `ImageRenderer` into a Core Graphics PDF context, so text and
/// diamonds stay crisp vectors rather than a screenshot. The look matches the
/// app's own dark page, which is what the scorer already knows.
enum ScorebookPDF {

    @MainActor
    static func makePDF(for document: GameDocument) -> URL? {
        let scorebook = ScorebookBuilder.build(document: document)
        let lookup: (UUID) -> String = { document.player(id: $0)?.name ?? "—" }

        let pages: [ScorebookPDFPage] = [
            ScorebookPDFPage(page: scorebook.away, teamName: document.teams.away.name, name: lookup),
            ScorebookPDFPage(page: scorebook.home, teamName: document.teams.home.name, name: lookup)
        ]

        // Measure first, so one shared media box comfortably holds both pages.
        var renderers: [(ImageRenderer<ScorebookPDFPage>, CGSize)] = []
        for page in pages {
            let renderer = ImageRenderer(content: page)
            var size: CGSize = .zero
            renderer.render { measured, _ in size = measured }
            renderers.append((renderer, size))
        }

        let pageSize = CGSize(
            width: max(612, renderers.map(\.1.width).max() ?? 612),
            height: max(792, renderers.map(\.1.height).max() ?? 792)
        )
        var mediaBox = CGRect(origin: .zero, size: pageSize)

        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName(for: document))
        guard
            let consumer = CGDataConsumer(url: url as CFURL),
            let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil)
        else { return nil }

        for (renderer, _) in renderers {
            renderer.render { _, drawInContext in
                context.beginPDFPage(nil)
                drawInContext(context)
                context.endPDFPage()
            }
        }
        context.closePDF()
        return url
    }

    private static func fileName(for document: GameDocument) -> String {
        let matchup = "\(document.teams.away.abbreviation)-\(document.teams.home.abbreviation)"
        return "\(matchup) Scorebook.pdf"
    }
}
