import SwiftUI

struct FieldMarker: Identifiable, Hashable {
    enum Kind: Hashable {
        case hit(HitKind)
        case out
        case error

        var tint: Color {
            switch self {
            case .hit: Theme.ball
            case .out: Theme.miss
            case .error: Theme.foul
            }
        }
    }

    var id: UUID
    var location: FieldLocation
    var kind: Kind

    init(id: UUID = UUID(), location: FieldLocation, kind: Kind) {
        self.id = id
        self.location = location
        self.kind = kind
    }
}

/// A drawn field that can be tapped to say where a ball went.
///
/// Used two ways: as the input surface in the full sheet layout, and as a
/// read-only spray chart in the post-game summary.
struct FieldPlotView: View {
    var markers: [FieldMarker] = []
    var selectedPosition: Position?
    /// The fielding chain entered so far, drawn on the field in order. Each
    /// fielder picks up a numbered badge, so a long rundown stays readable.
    var chain: [Position] = []
    var showsPositionNumbers: Bool = true
    /// Fills the space it is given rather than holding a square aspect. The
    /// fixed two-handed layout hands it whatever height is left over.
    var fillsAvailableSpace: Bool = false
    var onPick: ((FieldLocation, Position) -> Void)?

    @ViewBuilder
    var body: some View {
        if fillsAvailableSpace {
            field
        } else {
            field.aspectRatio(1.05, contentMode: .fit)
        }
    }

    private var field: some View {
        GeometryReader { geo in
            let size = geo.size

            ZStack {
                FairTerritoryShape()
                    .fill(Theme.fieldGrass)
                FairTerritoryShape()
                    .stroke(Theme.hairline, lineWidth: 1)
                InfieldShape()
                    .fill(Theme.fieldDirt.opacity(0.8))
                BasePathsShape()
                    .stroke(Color.white.opacity(0.4), lineWidth: 1.5)

                chainPath(size: size)

                if showsPositionNumbers {
                    positionNumbers(size: size)
                }

                markerLayer(size: size)
            }
            .contentShape(Rectangle())
            .gesture(tapGesture(size: size))
        }
    }

    /// Plate to the first fielder, then fielder to fielder — the way the ball
    /// actually travelled.
    private func chainPath(size: CGSize) -> some View {
        Path { path in
            guard !chain.isEmpty, size.width > 0 else { return }
            path.move(to: FieldGeometry.homePlate(in: size))
            for position in chain {
                path.addLine(to: FieldGeometry.point(for: position, in: size))
            }
        }
        .stroke(
            Theme.accent,
            style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round)
        )
        .allowsHitTesting(false)
    }

    private func positionNumbers(size: CGSize) -> some View {
        ForEach(Position.fielders) { position in
            let order = chain.lastIndex(of: position).map { $0 + 1 }
            let isLit = order != nil || selectedPosition == position

            Text("\(position.rawValue)")
                .font(Theme.Typeface.label(12, weight: .bold))
                .foregroundStyle(isLit ? .white : Theme.primaryText.opacity(0.75))
                .frame(width: 30, height: 30)
                .background(
                    Circle().fill(isLit ? Theme.accent : Color.white.opacity(0.55))
                )
                .overlay(alignment: .topTrailing) {
                    if let order {
                        Text("\(order)")
                            .font(Theme.Typeface.label(9, weight: .heavy))
                            .foregroundStyle(Theme.background)
                            .frame(width: 15, height: 15)
                            .background(Circle().fill(Theme.foul))
                            .offset(x: 4, y: -4)
                    }
                }
                .position(FieldGeometry.point(for: position, in: size))
        }
    }

    private func markerLayer(size: CGSize) -> some View {
        ForEach(markers) { marker in
            Circle()
                .fill(marker.kind.tint)
                .frame(width: 9, height: 9)
                .overlay(Circle().strokeBorder(.white.opacity(0.8), lineWidth: 1))
                .position(
                    x: marker.location.x * size.width,
                    y: marker.location.y * size.height
                )
        }
    }

    private func tapGesture(size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onEnded { value in
                guard let onPick else { return }
                let point = value.location
                guard let fielder = FieldGeometry.nearestPosition(to: point, in: size) else { return }
                let location = FieldLocation(
                    x: min(max(point.x / max(size.width, 1), 0), 1),
                    y: min(max(point.y / max(size.height, 1), 0), 1)
                )
                onPick(location, fielder)
            }
    }
}

/// Every ball a player put in play, plotted. Built straight off the event log.
struct SprayChartView: View {
    var document: GameDocument
    var playerID: UUID?

    var body: some View {
        FieldPlotView(
            markers: markers,
            showsPositionNumbers: false,
            onPick: nil
        )
    }

    private var markers: [FieldMarker] {
        var results: [FieldMarker] = []
        var state = ScoringEngine.initialState(document: document)

        for recorded in document.events {
            let batterID = state.currentBatterID
            let result = ScoringEngine.apply(recorded.event, to: state, document: document)
            state = result.state

            guard
                case .play(let outcome, _) = recorded.event,
                let batted = outcome.battedBall,
                let location = batted.location
            else { continue }

            if let playerID, playerID != batterID { continue }

            let kind: FieldMarker.Kind
            if let hit = outcome.hitKind {
                kind = .hit(hit)
            } else if outcome.isErrorPlay {
                kind = .error
            } else {
                kind = .out
            }

            results.append(FieldMarker(location: location, kind: kind))
        }

        return results
    }
}
