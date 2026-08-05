import SwiftUI

/// Where things live on a drawn baseball field, in normalized 0...1
/// coordinates with home plate at the bottom centre and the outfield at the
/// top. Shared by the spray chart and the no-look fielder dial so a position
/// sits in the same place in both.
enum FieldGeometry {

    static func unitPoint(for position: Position) -> CGPoint {
        switch position {
        case .pitcher: CGPoint(x: 0.50, y: 0.66)
        case .catcher: CGPoint(x: 0.50, y: 0.955)
        case .firstBase: CGPoint(x: 0.755, y: 0.625)
        case .secondBase: CGPoint(x: 0.635, y: 0.495)
        case .thirdBase: CGPoint(x: 0.245, y: 0.625)
        case .shortstop: CGPoint(x: 0.365, y: 0.495)
        case .leftField: CGPoint(x: 0.205, y: 0.235)
        case .centerField: CGPoint(x: 0.50, y: 0.135)
        case .rightField: CGPoint(x: 0.795, y: 0.235)
        case .designatedHitter: CGPoint(x: 0.50, y: 0.50)
        }
    }

    static func point(for position: Position, in size: CGSize) -> CGPoint {
        let unit = unitPoint(for: position)
        return CGPoint(x: unit.x * size.width, y: unit.y * size.height)
    }

    /// Closest fielder to a touch. Returns nil when the finger is nowhere near
    /// anyone, so a stray drag doesn't silently pick a position.
    static func nearestPosition(
        to point: CGPoint,
        in size: CGSize,
        maximumDistance: CGFloat = .greatestFiniteMagnitude
    ) -> Position? {
        var best: Position?
        var bestDistance = CGFloat.greatestFiniteMagnitude

        for position in Position.fielders {
            let candidate = self.point(for: position, in: size)
            let dx = candidate.x - point.x
            let dy = candidate.y - point.y
            let distance = (dx * dx + dy * dy).squareRoot()
            if distance < bestDistance {
                bestDistance = distance
                best = position
            }
        }

        return bestDistance <= maximumDistance ? best : nil
    }

    static func homePlate(in size: CGSize) -> CGPoint {
        scaled(DrawnField.plate, in: size)
    }

    static func scaled(_ unit: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(x: unit.x * size.width, y: unit.y * size.height)
    }
}

/// The one set of anchors every piece of the drawn field is built from, in
/// normalized 0...1 coordinates with home plate at the bottom centre.
///
/// Before this existed the grass wedge, the dirt and the base paths each had
/// their own hand-tuned numbers that didn't agree — the foul lines ran off the
/// sides and the two diamonds sat slightly askew of each other. Deriving them
/// all from the same plate and bases is what makes the field read as one thing.
enum DrawnField {
    static let plate = CGPoint(x: 0.50, y: 0.90)
    static let firstBag = CGPoint(x: 0.725, y: 0.675)
    static let secondBag = CGPoint(x: 0.50, y: 0.45)
    static let thirdBag = CGPoint(x: 0.275, y: 0.675)

    /// Foul poles and the control point that bows the outfield fence up to a
    /// deep centre. Kept inside the frame so nothing clips at the corners.
    static let leftFoulPole = CGPoint(x: 0.06, y: 0.46)
    static let rightFoulPole = CGPoint(x: 0.94, y: 0.46)
    static let fenceControl = CGPoint(x: 0.50, y: 0.02)

    /// The dirt is the base diamond pushed out a little from its centre, so the
    /// bags sit on the infield rather than on its very edge.
    static func infieldCorners(outset: CGFloat = 1.18) -> [CGPoint] {
        let bags = [plate, firstBag, secondBag, thirdBag]
        let center = CGPoint(
            x: bags.map(\.x).reduce(0, +) / 4,
            y: bags.map(\.y).reduce(0, +) / 4
        )
        return bags.map { bag in
            CGPoint(
                x: center.x + (bag.x - center.x) * outset,
                y: center.y + (bag.y - center.y) * outset
            )
        }
    }
}

/// Fair territory: the two foul lines from home plate out to the poles, closed
/// by an outfield fence that bows up to a deep centre. All contained in the
/// frame so the corners never clip.
struct FairTerritoryShape: Shape {
    func path(in rect: CGRect) -> Path {
        func p(_ unit: CGPoint) -> CGPoint { FieldGeometry.scaled(unit, in: rect.size) }

        var path = Path()
        path.move(to: p(DrawnField.plate))
        path.addLine(to: p(DrawnField.leftFoulPole))
        path.addQuadCurve(
            to: p(DrawnField.rightFoulPole),
            control: p(DrawnField.fenceControl)
        )
        path.closeSubpath()
        return path
    }
}

/// The infield dirt — the base diamond, outset a touch so the bags sit on it.
struct InfieldShape: Shape {
    func path(in rect: CGRect) -> Path {
        let corners = DrawnField.infieldCorners().map { FieldGeometry.scaled($0, in: rect.size) }

        var path = Path()
        path.move(to: corners[0])
        for corner in corners.dropFirst() { path.addLine(to: corner) }
        path.closeSubpath()
        return path
    }
}

/// The base paths, drawn as thin lines bag to bag inside the dirt.
struct BasePathsShape: Shape {
    func path(in rect: CGRect) -> Path {
        func p(_ unit: CGPoint) -> CGPoint { FieldGeometry.scaled(unit, in: rect.size) }

        var path = Path()
        path.move(to: p(DrawnField.plate))
        path.addLine(to: p(DrawnField.firstBag))
        path.addLine(to: p(DrawnField.secondBag))
        path.addLine(to: p(DrawnField.thirdBag))
        path.closeSubpath()
        return path
    }
}
