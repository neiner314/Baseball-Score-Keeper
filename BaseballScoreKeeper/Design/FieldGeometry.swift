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
        CGPoint(x: size.width * 0.5, y: size.height * 0.955)
    }
}

/// Fair territory: the wedge from home plate out to the wall.
struct FairTerritoryShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let home = CGPoint(x: rect.midX, y: rect.maxY * 0.97)
        let radius = rect.height * 0.92

        path.move(to: home)
        path.addLine(
            to: CGPoint(x: home.x - radius * 0.72, y: home.y - radius * 0.72)
        )
        path.addQuadCurve(
            to: CGPoint(x: home.x + radius * 0.72, y: home.y - radius * 0.72),
            control: CGPoint(x: home.x, y: home.y - radius * 1.34)
        )
        path.closeSubpath()
        return path
    }
}

/// The infield dirt — a diamond with the corners at the bases.
struct InfieldShape: Shape {
    func path(in rect: CGRect) -> Path {
        let size = rect.size
        let home = CGPoint(x: rect.midX, y: size.height * 0.93)
        let first = CGPoint(x: size.width * 0.795, y: size.height * 0.655)
        let second = CGPoint(x: rect.midX, y: size.height * 0.40)
        let third = CGPoint(x: size.width * 0.205, y: size.height * 0.655)

        var path = Path()
        path.move(to: home)
        path.addLine(to: first)
        path.addLine(to: second)
        path.addLine(to: third)
        path.closeSubpath()
        return path
    }
}

/// The base paths, drawn as thin lines over the dirt.
struct BasePathsShape: Shape {
    func path(in rect: CGRect) -> Path {
        let size = rect.size
        let home = CGPoint(x: rect.midX, y: size.height * 0.90)
        let first = CGPoint(x: size.width * 0.72, y: size.height * 0.655)
        let second = CGPoint(x: rect.midX, y: size.height * 0.455)
        let third = CGPoint(x: size.width * 0.28, y: size.height * 0.655)

        var path = Path()
        path.move(to: home)
        path.addLine(to: first)
        path.addLine(to: second)
        path.addLine(to: third)
        path.closeSubpath()
        return path
    }
}
