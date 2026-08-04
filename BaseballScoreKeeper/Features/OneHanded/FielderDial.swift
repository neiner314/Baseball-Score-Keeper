import SwiftUI

/// The no-look fielder dial.
///
/// It puts all nine positions on a drawn field under your thumb. Sliding
/// between them ticks; the selected position is announced in type large enough
/// to read at a glance, and the whole thing is laid out the way the field
/// looks, so "the ball went to left" is a flick toward the upper left rather
/// than a menu item to find.
///
/// Two ways in. Drag out of the in-play pad and the dial tracks your finger,
/// releasing on whoever is lit — one gesture, no looking, the ball goes down as
/// a play by that fielder. Or tap, and the dial latches open so positions can
/// be tapped in sequence to build a real fielding chain: `3-1`, `6-4-3`, or
/// whatever the rundown actually was.
struct FielderDial: View {
    var fingerLocation: CGPoint?
    var coordinateSpace: String
    var hapticsEnabled: Bool
    /// When true the markers are tappable. Used by the latched (tapped-open)
    /// presentation; the drag presentation stays hit-testing-transparent so
    /// the in-play pad keeps receiving the gesture.
    var isInteractive: Bool = false
    /// The chain entered so far, drawn on the field in order.
    var chain: [Position] = []
    /// Reports the live drag selection, including nil when the finger moves
    /// clear of every position — that's how a drag is cancelled.
    var onSelectionChange: (Position?) -> Void
    var onTapPosition: ((Position) -> Void)?

    @State private var selection: Position?

    /// A touch further than this from every fielder selects nobody, so the
    /// scorer can bail out by dragging clear of the dial. Sized against the
    /// ~90pt gap between neighbouring positions: generous enough that a rough
    /// drag still lands, tight enough that leaving the dial cancels.
    private let selectionRadius: CGFloat = 108

    var body: some View {
        GeometryReader { geo in
            let frame = geo.frame(in: .named(coordinateSpace))

            ZStack {
                fieldBackdrop(size: frame.size)
                chainPath(size: frame.size)
                markers(size: frame.size)
            }
            .frame(width: frame.width, height: frame.height)
            .onChange(of: fingerLocation) { _, newValue in
                updateSelection(finger: newValue, frame: frame)
            }
            .onDisappear {
                selection = nil
            }
        }
    }

    private func updateSelection(finger: CGPoint?, frame: CGRect) {
        guard let finger else {
            if selection != nil {
                selection = nil
                onSelectionChange(nil)
            }
            return
        }

        let local = CGPoint(x: finger.x - frame.minX, y: finger.y - frame.minY)
        let hit = FieldGeometry.nearestPosition(
            to: local,
            in: frame.size,
            maximumDistance: selectionRadius
        )

        guard hit != selection else { return }
        selection = hit
        if hit != nil {
            Haptics.shared.zoneChanged(enabled: hapticsEnabled)
        }
        onSelectionChange(hit)
    }

    // MARK: - Field

    private func fieldBackdrop(size: CGSize) -> some View {
        ZStack {
            FairTerritoryShape()
                .fill(Theme.fieldGrass.opacity(0.9))
            FairTerritoryShape()
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
            InfieldShape()
                .fill(Theme.fieldDirt.opacity(0.9))
            BasePathsShape()
                .stroke(Color.white.opacity(0.22), lineWidth: 1.5)

            // The live drag draws a line from the plate so the ball's path is
            // visible while the thumb is still moving.
            if chain.isEmpty, let selection, size.width > 0 {
                Path { path in
                    path.move(to: FieldGeometry.homePlate(in: size))
                    path.addLine(to: FieldGeometry.point(for: selection, in: size))
                }
                .stroke(
                    Theme.accent,
                    style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [7, 6])
                )
            }
        }
        .allowsHitTesting(false)
    }

    /// The chain drawn as the ball actually travelled: plate to the first
    /// fielder, then fielder to fielder.
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
            style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
        )
        .allowsHitTesting(false)
    }

    // MARK: - Position markers

    private func markers(size: CGSize) -> some View {
        ZStack {
            ForEach(Position.fielders) { position in
                FielderMarker(
                    position: position,
                    isSelected: selection == position,
                    chainOrder: chainOrder(for: position)
                )
                .contentShape(Circle())
                .onTapGesture {
                    guard isInteractive else { return }
                    selection = position
                    Haptics.shared.commit(enabled: hapticsEnabled)
                    onTapPosition?(position)
                }
                .position(FieldGeometry.point(for: position, in: size))
            }
        }
    }

    /// Where this position sits in the chain, 1-based. A fielder who touched it
    /// twice — the pivot man in a rundown — shows the last time.
    private func chainOrder(for position: Position) -> Int? {
        guard let index = chain.lastIndex(of: position) else { return nil }
        return index + 1
    }
}

private struct FielderMarker: View {
    var position: Position
    var isSelected: Bool
    var chainOrder: Int?

    /// Fixed outer frame so the tap target stays a comfortable size whether or
    /// not the marker is currently enlarged.
    private let tapTarget: CGFloat = 66

    private var isInChain: Bool { chainOrder != nil }
    private var isHighlighted: Bool { isSelected || isInChain }

    var body: some View {
        ZStack {
            Circle()
                .fill(isHighlighted ? Theme.accent : Theme.surfaceHigh.opacity(0.95))
                .frame(width: isSelected ? 62 : 46, height: isSelected ? 62 : 46)
                .shadow(color: .black.opacity(0.35), radius: isSelected ? 10 : 4, y: 2)

            VStack(spacing: 0) {
                Text("\(position.rawValue)")
                    .font(Theme.Typeface.score(isSelected ? 25 : 18))
                    .foregroundStyle(isHighlighted ? .white : Theme.primaryText)
                if isSelected {
                    Text(position.abbreviation)
                        .font(Theme.Typeface.caption())
                        .foregroundStyle(.white.opacity(0.85))
                }
            }
        }
        // The order badge is what makes a long chain readable: tapping
        // 6-4-3-2-5-1-6 leaves numbered pips around the field.
        .overlay(alignment: .topTrailing) {
            if let chainOrder {
                Text("\(chainOrder)")
                    .font(Theme.Typeface.label(10, weight: .heavy))
                    .foregroundStyle(Theme.background)
                    .frame(width: 18, height: 18)
                    .background(Circle().fill(Theme.foul))
                    .offset(x: -6, y: 6)
            }
        }
        .frame(width: tapTarget, height: tapTarget)
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isSelected)
        .animation(.spring(response: 0.22, dampingFraction: 0.8), value: chainOrder)
        .accessibilityElement()
        .accessibilityLabel(Text("\(position.rawValue), \(position.fullName)"))
    }
}
