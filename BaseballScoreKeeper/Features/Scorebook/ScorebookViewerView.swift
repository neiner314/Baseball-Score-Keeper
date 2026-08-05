import SwiftUI

/// A read-only look at a game's scorebook — the same page you keep during
/// scoring, but here to be read rather than written, with both teams a tap
/// apart, room to turn the phone sideways, and a PDF to take away.
///
/// It stands up its own store from the saved document, so opening the book
/// never disturbs a game in progress or drops you into the scoring interface.
struct ScorebookViewerView: View {
    let document: GameDocument

    @State private var store: GameStore
    @State private var side: Side = .away
    @State private var pdfURL: URL?

    init(document: GameDocument) {
        self.document = document
        _store = State(initialValue: GameStore(document: document))
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Team", selection: $side) {
                Text(store.teams.away.abbreviation).tag(Side.away)
                Text(store.teams.home.abbreviation).tag(Side.home)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, Theme.Metrics.screenMargin)
            .padding(.vertical, 10)

            ScorebookPageView(
                page: store.buildScorebook()[side],
                teamAbbreviation: store.teams[side].abbreviation
            )
            .environment(store)
        }
        .appBackground()
        .navigationTitle(document.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if let pdfURL {
                    ShareLink(item: pdfURL) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel(Text("Share as PDF"))
                }
            }
        }
        .allowsLandscape()
        .task {
            if pdfURL == nil {
                pdfURL = ScorebookPDF.makePDF(for: document)
            }
        }
    }
}
