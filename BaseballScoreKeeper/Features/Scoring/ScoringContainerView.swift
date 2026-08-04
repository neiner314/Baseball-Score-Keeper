import SwiftUI

/// Hosts whichever scoring layout is active and owns the chrome around it.
///
/// The controls live at the top on purpose: they're between-innings actions,
/// and keeping them out of the thumb's arc means they can't be hit by accident
/// while scoring one-handed.
struct ScoringContainerView: View {
    @Environment(GameStore.self) private var store

    @State private var showsBoxScore = false
    @State private var showsSettings = false
    @State private var showsSubstitution = false
    @State private var showsAccuracy = false

    var body: some View {
        ZStack(alignment: .top) {
            layoutView
                .padding(.top, 34)

            controlStrip

            if store.state.isFinal {
                finalBanner
            }
        }
        .background(Theme.background)
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
        HStack(spacing: 14) {
            Button {
                cycleLayout()
            } label: {
                Image(systemName: store.settings.preferredLayout.symbolName)
            }
            .accessibilityLabel(Text("Switch layout"))

            Spacer()

            Button {
                showsSubstitution = true
            } label: {
                Image(systemName: "arrow.left.arrow.right")
            }
            .accessibilityLabel(Text("Substitution"))

            Button {
                showsBoxScore = true
            } label: {
                Image(systemName: "list.number")
            }
            .accessibilityLabel(Text("Box score"))

            if store.document.supportsAccuracyCheck {
                Button {
                    showsAccuracy = true
                } label: {
                    Image(systemName: "checkmark.seal")
                }
                .accessibilityLabel(Text("Compare with official scoring"))
            }

            Button {
                showsSettings = true
            } label: {
                Image(systemName: "slider.horizontal.3")
            }
            .accessibilityLabel(Text("Settings"))
        }
        .font(.system(size: 15, weight: .semibold))
        .foregroundStyle(Theme.secondaryText)
        .padding(.horizontal, 20)
        .padding(.top, 6)
    }

    private var finalBanner: some View {
        Text("FINAL")
            .font(Theme.Typeface.label(12, weight: .heavy))
            .tracking(2)
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(Capsule().fill(Theme.miss))
            .padding(.top, 40)
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
