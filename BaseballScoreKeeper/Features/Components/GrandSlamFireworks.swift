import SwiftUI

/// A small, purely decorative firework show drawn over the diamond when a grand
/// slam clears the bases — the app's one little easter egg.
///
/// It watches a trigger token and, each time it changes, sets off a few
/// staggered bursts at spots over the infield, then clears itself. Nothing here
/// touches game state, and it never takes a tap.
struct GrandSlamFireworks: View {
    /// A fresh value the moment a slam lands; a change sets the show off.
    var trigger: UUID?

    @State private var bursts: [Burst] = []

    /// A rotating handful of bright colours, led by the ball green so the
    /// celebration still reads as part of this app.
    private static let palette: [Color] = [Theme.ball, Theme.inPlay, .yellow, .pink, Theme.hitByPitch]

    /// Where the bursts pop, in unit coordinates over the diamond frame — a
    /// tight cluster around the infield rather than the corners.
    private static let spots: [CGPoint] = [
        CGPoint(x: 0.50, y: 0.40),
        CGPoint(x: 0.30, y: 0.54),
        CGPoint(x: 0.70, y: 0.54),
        CGPoint(x: 0.50, y: 0.66)
    ]

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(bursts) { burst in
                    BurstView(burst: burst)
                        .position(
                            x: burst.unit.x * geo.size.width,
                            y: burst.unit.y * geo.size.height
                        )
                }
            }
        }
        .allowsHitTesting(false)
        .onChange(of: trigger) { _, newValue in
            guard newValue != nil else { return }
            launch()
        }
    }

    private func launch() {
        for (index, spot) in Self.spots.enumerated() {
            let delay = Double(index) * 0.16
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                let burst = Burst(unit: spot, color: Self.palette[index % Self.palette.count])
                bursts.append(burst)
                DispatchQueue.main.asyncAfter(deadline: .now() + Burst.lifetime) {
                    bursts.removeAll { $0.id == burst.id }
                }
            }
        }
    }
}

/// One firework: a ring of sparks shot outward from a single point. Its spark
/// angles and distances are fixed at birth so the burst animates the same way
/// from first frame to last.
private struct Burst: Identifiable {
    let id = UUID()
    let unit: CGPoint
    let color: Color
    let sparks: [Spark]

    static let lifetime: Double = 0.9

    init(unit: CGPoint, color: Color) {
        self.unit = unit
        self.color = color
        let count = 11
        self.sparks = (0..<count).map { i in
            Spark(
                angle: Double(i) / Double(count) * 2 * .pi,
                distance: CGFloat.random(in: 16...28),
                size: CGFloat.random(in: 3...5)
            )
        }
    }
}

private struct Spark {
    let angle: Double
    let distance: CGFloat
    let size: CGFloat
}

/// Animates a single burst: every spark rides out from the centre while fading
/// and shrinking, so the whole thing reads as a quick pop-and-sparkle.
private struct BurstView: View {
    let burst: Burst
    @State private var exploded = false

    var body: some View {
        ZStack {
            ForEach(Array(burst.sparks.enumerated()), id: \.offset) { _, spark in
                Circle()
                    .fill(burst.color)
                    .frame(width: spark.size, height: spark.size)
                    .offset(
                        x: cos(spark.angle) * (exploded ? spark.distance : 0),
                        y: sin(spark.angle) * (exploded ? spark.distance : 0)
                    )
                    .opacity(exploded ? 0 : 1)
                    .scaleEffect(exploded ? 0.3 : 1)
            }
        }
        .glow(burst.color, radius: 4, opacity: 0.85)
        .onAppear {
            withAnimation(.easeOut(duration: Burst.lifetime)) {
                exploded = true
            }
        }
    }
}
