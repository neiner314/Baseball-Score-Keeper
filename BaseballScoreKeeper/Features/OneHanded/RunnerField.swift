import SwiftUI

/// A compact base diamond, drawn on the same field as the box-score spray
/// chart, that shows who's on and turns each runner into a tap target.
///
/// It lives under the pitcher panel in the one-handed layout. Tap a lit base
/// and a menu offers the two things that happen between pitches — a stolen base
/// or a caught stealing — so baserunning no longer needs a rail of buttons and
/// the at-bat card no longer has to spell the runners out in text.
struct RunnerField: View {
    var bases: Bases
    var runnerNumber: (Base) -> String?
    /// The batting team's bench, offered as pinch runners on a lit base.
    var availableRunners: [Player] = []
    var onSteal: (Base) -> Void
    var onCaught: (Base) -> Void
    var onPinchRun: (Base, Player) -> Void = { _, _ in }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack {
                FairTerritoryShape().fill(Theme.fieldGrass)
                FairTerritoryShape().stroke(Theme.hairline, lineWidth: 1)
                InfieldShape().fill(Theme.fieldDirt.opacity(0.85))
                BasePathsShape().stroke(Color.white.opacity(0.32), lineWidth: 1.5)

                baseNode(.first, unit: DrawnField.firstBag, size: size)
                baseNode(.second, unit: DrawnField.secondBag, size: size)
                baseNode(.third, unit: DrawnField.thirdBag, size: size)
                homePlate(size: size)
            }
        }
        .aspectRatio(1.2, contentMode: .fit)
        .accessibilityElement()
        .accessibilityLabel(Text(bases.summary))
    }

    @ViewBuilder
    private func baseNode(_ base: Base, unit: CGPoint, size: CGSize) -> some View {
        let point = FieldGeometry.scaled(unit, in: size)
        if bases[base] != nil {
            Menu {
                Button {
                    onSteal(base)
                } label: {
                    Label("Stole \(stealDestination(base))", systemImage: "figure.run")
                }
                Button(role: .destructive) {
                    onCaught(base)
                } label: {
                    Label("Caught stealing", systemImage: "xmark.circle")
                }
                if !availableRunners.isEmpty {
                    Menu {
                        ForEach(availableRunners) { runner in
                            Button {
                                onPinchRun(base, runner)
                            } label: {
                                Text("\(runner.displayNumber) \(runner.name)")
                            }
                        }
                    } label: {
                        Label("Pinch runner", systemImage: "arrow.left.arrow.right")
                    }
                }
            } label: {
                marker(occupied: true, number: runnerNumber(base))
            }
            .accessibilityLabel(Text("Runner on \(base.label)"))
            .position(point)
        } else {
            marker(occupied: false, number: nil)
                .position(point)
        }
    }

    private func marker(occupied: Bool, number: String?) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(occupied ? Theme.ball : Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .strokeBorder(
                            occupied ? Color.white.opacity(0.85) : Theme.secondaryText.opacity(0.5),
                            lineWidth: 1.5
                        )
                )
                .frame(width: 22, height: 22)
                .rotationEffect(.degrees(45))
                .glow(occupied ? Theme.ball : .clear, radius: 6, opacity: 0.7)

            if occupied, let number, !number.isEmpty {
                Text(number)
                    .font(Theme.Typeface.score(11))
                    .foregroundStyle(Theme.background)
            }
        }
        // A comfortable tap target regardless of the little bag's size.
        .frame(width: 44, height: 44)
        .contentShape(Rectangle())
    }

    private func homePlate(size: CGSize) -> some View {
        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
            .strokeBorder(Theme.tertiaryText, lineWidth: 1.5)
            .frame(width: 14, height: 14)
            .rotationEffect(.degrees(45))
            .position(FieldGeometry.scaled(DrawnField.plate, in: size))
    }

    /// The base a runner on `base` would take on a steal.
    private func stealDestination(_ base: Base) -> String {
        base.next?.label ?? "Home"
    }
}
