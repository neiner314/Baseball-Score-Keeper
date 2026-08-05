import SwiftUI

/// The live base diamond: which bases have runners on them right now.
///
/// This is the thing a scorer's eye goes to first and the app had no version
/// of. Bases are drawn as outlined squares that fill in when occupied, laid out
/// the way a diamond actually sits — second at the top, first to the right.
struct BaseDiamond: View {
    var bases: Bases
    var size: CGFloat = 74
    /// Draws the home plate marker at the bottom. Off in tight spaces.
    var showsHome: Bool = true

    private var baseSize: CGFloat { size * 0.30 }

    var body: some View {
        ZStack {
            paths
            base(.second, at: CGPoint(x: 0.5, y: 0.10))
            base(.third, at: CGPoint(x: 0.10, y: 0.5))
            base(.first, at: CGPoint(x: 0.90, y: 0.5))
            if showsHome { homePlate }
        }
        .frame(width: size, height: size)
        .animation(.spring(response: 0.28, dampingFraction: 0.8), value: bases)
        .accessibilityElement()
        .accessibilityLabel(Text(bases.summary))
    }

    private var paths: some View {
        Path { path in
            let second = point(CGPoint(x: 0.5, y: 0.10))
            let third = point(CGPoint(x: 0.10, y: 0.5))
            let first = point(CGPoint(x: 0.90, y: 0.5))
            let home = point(CGPoint(x: 0.5, y: 0.90))
            path.move(to: home)
            path.addLine(to: first)
            path.addLine(to: second)
            path.addLine(to: third)
            path.closeSubpath()
        }
        .stroke(Theme.hairline, lineWidth: 1)
    }

    /// An occupied base is lit from inside — a bright core, a soft halo, and a
    /// rim. Empty bases are a thin outline and nothing else, so a full glance
    /// costs no reading at all.
    private func base(_ base: Base, at unit: CGPoint) -> some View {
        let occupied = bases[base] != nil
        return ZStack {
            if occupied {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Theme.ball)
                    .frame(width: baseSize, height: baseSize)
                    .blur(radius: baseSize * 0.42)
                    .opacity(0.85)
            }

            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(occupied ? Theme.ball : Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .strokeBorder(
                            occupied ? Color.white.opacity(0.85) : Theme.secondaryText.opacity(0.4),
                            lineWidth: occupied ? 1 : 1.5
                        )
                )
                .frame(width: baseSize, height: baseSize)
        }
        .rotationEffect(.degrees(45))
        .position(point(unit))
    }

    private var homePlate: some View {
        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
            .strokeBorder(Theme.tertiaryText, lineWidth: 1.5)
            .frame(width: baseSize * 0.72, height: baseSize * 0.72)
            .rotationEffect(.degrees(45))
            .position(point(CGPoint(x: 0.5, y: 0.90)))
    }

    private func point(_ unit: CGPoint) -> CGPoint {
        CGPoint(x: unit.x * size, y: unit.y * size)
    }
}

/// The scorebook cell's diamond, which works the opposite way to the live one:
/// it shades the *path travelled*, one leg per base, all four when the run
/// scores. Exactly what gets pencilled into a paper book.
struct ScorebookDiamond: View {
    /// 0...4. Four means they came all the way around.
    var basesAdvanced: Int
    var isOut: Bool
    var size: CGFloat = 30

    private var scored: Bool { basesAdvanced >= 4 }

    var body: some View {
        ZStack {
            outline
            travelled
            if scored { filled }
        }
        .frame(width: size, height: size)
    }

    private var outline: some View {
        diamondPath
            .stroke(Theme.hairline, lineWidth: 1)
    }

    /// One stroked leg per base reached, going home → first → second → third.
    private var travelled: some View {
        Path { path in
            let corners = self.corners
            guard basesAdvanced > 0 else { return }
            path.move(to: corners[0])
            for leg in 1...min(4, basesAdvanced) {
                path.addLine(to: corners[leg % 4])
            }
        }
        .stroke(
            isOut ? Theme.secondaryText : Theme.ball,
            style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
        )
    }

    private var filled: some View {
        diamondPath
            .fill(Theme.ball.opacity(0.22))
    }

    private var diamondPath: Path {
        Path { path in
            let corners = self.corners
            path.move(to: corners[0])
            path.addLine(to: corners[1])
            path.addLine(to: corners[2])
            path.addLine(to: corners[3])
            path.closeSubpath()
        }
    }

    /// home, first, second, third — the order a runner touches them.
    private var corners: [CGPoint] {
        let inset: CGFloat = 3
        let mid = size / 2
        return [
            CGPoint(x: mid, y: size - inset),
            CGPoint(x: size - inset, y: mid),
            CGPoint(x: mid, y: inset),
            CGPoint(x: inset, y: mid)
        ]
    }
}

/// Outs as three pips. Reads faster than the word at a glance, and matches the
/// count lights so the whole strip scans as one thing.
struct OutsPips: View {
    var outs: Int
    var dotSize: CGFloat = 7

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { index in
                Pip(isLit: index < outs, tint: Theme.miss, size: dotSize)
            }
        }
        .animation(.easeOut(duration: 0.15), value: outs)
        .accessibilityElement()
        .accessibilityLabel(Text("\(outs) out"))
    }
}

/// A count light. Lit ones bloom; unlit ones are barely there. Same idea as the
/// bases — the state should be readable without counting.
struct Pip: View {
    var isLit: Bool
    var tint: Color
    var size: CGFloat

    var body: some View {
        Circle()
            .fill(isLit ? tint : Theme.secondaryText.opacity(0.20))
            .frame(width: size, height: size)
            .glow(isLit ? tint : .clear, radius: size * 0.7, opacity: 0.8)
    }
}

/// Balls and strikes as pips, laid out balls-left strikes-right the way a
/// stadium board writes the count.
struct CountPips: View {
    var balls: Int
    var strikes: Int
    var dotSize: CGFloat = 7

    var body: some View {
        HStack(spacing: 10) {
            pips(filled: balls, total: 3, tint: Theme.ball)
            pips(filled: strikes, total: 2, tint: Theme.miss)
        }
        .accessibilityElement()
        .accessibilityLabel(Text("Count \(balls) and \(strikes)"))
    }

    private func pips(filled: Int, total: Int, tint: Color) -> some View {
        HStack(spacing: 4) {
            ForEach(0..<total, id: \.self) { index in
                Pip(isLit: index < filled, tint: tint, size: dotSize)
            }
        }
        .animation(.easeOut(duration: 0.15), value: filled)
    }
}
