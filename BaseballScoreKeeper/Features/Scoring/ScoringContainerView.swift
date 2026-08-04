import SwiftUI

/// Hosts whichever scoring layout is active and owns the chrome around it.
///
/// The controls live at the top on purpose: they're between-innings actions,
/// and keeping them out of the thumb's arc means they can't be hit by accident
/// while scoring one-handed.
struct ScoringContainerView: View {
    @Environment(GameStore.self) private var store

    @State private var showsScorebook = false
    @State private var showsBoxScore = false
    @State private var showsSettings = false
    @State private var showsSubstitution = false
    @State private var showsAccuracy = false

    var body: some View {
        ZStack(alignment: .top) {
            layoutView
                .padding(.top, 40)

            controlStrip

            if store.state.isFinal {
                finalBanner
            }
        }
        .background(Theme.background)
        .sheet(isPresented: $showsScorebook) {
            ScorebookView().environment(store)
        }
        .sheet(isPresented: $showsBoxScore) {
            BoxScoreView().environment(store)
        }
        .sheet(isPresented: $showsSettings) {
            TrackingSettingsView().environment(store)
        }
        .sheet(isPresented: $showsSubstitution) {
            SubstitutionView(defaultSide: store.state.fieldingSide).environment(store)
        }
        .sheet(isPresented: $showsAccuracy) {
            AccuracyReportView().environment(store)
        }
    }

    @ViewBuilder
    private var layoutView: some View {
        switch store.settings.preferredLayout {
        case .singleSheet:
            FullSheetScoringView()
        case .pitchFirst, .thumbCluster:
            OneHandedScoringView(layout: store.settings.preferredLayout)
        }
    }

    private var controlStrip: some View {
        HStack(spacing: 4) {
            controlButton(store.settings.preferredLayout.symbolName, label: "Switch layout") {
                cycleLayout()
            }

            Spacer(minLength: 0)

            controlButton("arrow.left.arrow.right", label: "Substitution") {
                showsSubstitution = true
            }
            controlButton("square.grid.3x3", label: "Scorebook") {
                showsScorebook = true
            }
            controlButton("list.number", label: "Box score") {
                showsBoxScore = true
            }
            if store.document.supportsAccuracyCheck {
                controlButton("checkmark.seal", label: "Compare with official scoring") {
                    showsAccuracy = true
                }
            }
            controlButton("slider.horizontal.3", label: "Settings") {
                showsSettings = true
            }
        }
        .padding(.horizontal, Theme.Metrics.screenMargin - 6)
        .padding(.top, 4)
    }

    private func controlButton(
        _ symbol: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.secondaryText)
                .frame(width: 38, height: 34)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
    }

    private var finalBanner: some View {
        Text("FINAL")
            .font(Theme.Typeface.label(11, weight: .heavy))
            .tracking(2)
            .foregroundStyle(Theme.background)
            .padding(.horizontal, 14)
            .padding(.vertical, 5)
            .background(Capsule().fill(Theme.miss))
            .padding(.top, 44)
    }

    /// Cycles through the three layouts so the scorer can flip between the
    /// dense sheet and the one-handed cluster without opening settings.
    private func cycleLayout() {
        let layouts = ScoringLayout.allCases
        guard let index = layouts.firstIndex(of: store.settings.preferredLayout) else { return }
        store.settings.preferredLayout = layouts[(index + 1) % layouts.count]
        Haptics.shared.commit(enabled: store.settings.hapticsEnabled)
    }
}
