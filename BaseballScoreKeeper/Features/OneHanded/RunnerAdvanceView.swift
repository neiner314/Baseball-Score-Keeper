import SwiftUI

/// One runner in the advancement prompt: where they started, who they are, and
/// whether they're forced (which decides if "stay put" is even an option).
struct RunnerAdvancePrompt: Identifiable, Hashable {
    var base: Base
    var name: String
    var number: String
    var forced: Bool
    var defaultTarget: AdvanceTarget

    var id: Int { base.rawValue }
}

/// The runner-advancement prompt, one runner at a time on a little diamond.
///
/// Instead of a wall of buttons, it asks about the lead runner first — the one
/// the defense is usually playing — then the next. Tap the base the runner
/// reached (their own base means "held"), then Safe or Out. A forced runner
/// can't hold, so their own base isn't offered; a single with a man on first
/// becomes little more than a Safe/Out call at second.
struct RunnerAdvanceView: View {
    /// Lead runner first.
    var prompts: [RunnerAdvancePrompt]
    var hapticsEnabled: Bool = true
    var onComplete: ([ManualAdvance]) -> Void
    var onCancel: () -> Void

    @State private var index = 0
    @State private var results: [Base: AdvanceTarget] = [:]
    @State private var selected: AdvanceTarget = .held

    private var current: RunnerAdvancePrompt { prompts[min(index, prompts.count - 1)] }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.66)
                .ignoresSafeArea()
                .contentShape(Rectangle())

            VStack(spacing: 14) {
                header
                diamond
                controls
            }
            .frame(maxWidth: 360)
            .padding(.horizontal, 18)
            .padding(.bottom, 40)
        }
        .transition(.opacity)
        .onAppear { syncSelection() }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 4) {
            if prompts.count > 1 {
                Text("RUNNER \(index + 1) OF \(prompts.count)")
                    .font(Theme.Typeface.overline(9))
                    .tracking(1.4)
                    .foregroundStyle(.white.opacity(0.5))
            }
            Text("Where did \(runnerLabel) end up?")
                .font(Theme.Typeface.label(18, weight: .heavy))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(current.forced ? "Forced from \(current.base.label) — did they make it?" : "Tap the base, then Safe or Out")
                .font(Theme.Typeface.caption())
                .foregroundStyle(.white.opacity(0.55))
        }
    }

    private var runnerLabel: String {
        current.number.isEmpty ? current.name : "#\(current.number) \(current.name)"
    }

    // MARK: - Diamond

    private var diamond: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack {
                FairTerritoryShape().fill(Theme.fieldGrass)
                InfieldShape().fill(Theme.fieldDirt.opacity(0.85))
                BasePathsShape().stroke(Color.white.opacity(0.3), lineWidth: 1.5)

                advancePath(size: size)

                node(for: .held, unit: DrawnField.unit(for: current.base), size: size, label: "\(current.base.rawValue)")
                if current.base != .third {
                    node(for: targetForBase(.third), unit: DrawnField.thirdBag, size: size, label: "3")
                }
                if current.base == .first {
                    node(for: .second, unit: DrawnField.secondBag, size: size, label: "2")
                }
                node(for: .home, unit: DrawnField.plate, size: size, label: "H")
            }
        }
        .aspectRatio(1.15, contentMode: .fit)
        .frame(maxHeight: 220)
    }

    /// A dashed line from the runner's base to the base they're being sent to,
    /// so the chosen advance reads at a glance.
    private func advancePath(size: CGSize) -> some View {
        Path { path in
            path.move(to: FieldGeometry.scaled(DrawnField.unit(for: current.base), in: size))
            path.addLine(to: FieldGeometry.scaled(unit(for: selected), in: size))
        }
        .stroke(Theme.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [6, 5]))
        .allowsHitTesting(false)
        .opacity(selected == .held ? 0 : 1)
    }

    @ViewBuilder
    private func node(for target: AdvanceTarget, unit: CGPoint, size: CGSize, label: String) -> some View {
        let allowed = allowedTargets.contains(target)
        let isSelected = selected == target
        Button {
            guard allowed else { return }
            Haptics.shared.zoneChanged(enabled: hapticsEnabled)
            selected = target
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(isSelected ? Theme.accent : (allowed ? Theme.surfaceHigh : Color.clear))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .strokeBorder(
                                allowed ? Color.white.opacity(0.85) : Theme.secondaryText.opacity(0.35),
                                lineWidth: 1.5
                            )
                    )
                    .frame(width: 28, height: 28)
                    .rotationEffect(.degrees(45))

                Text(label)
                    .font(Theme.Typeface.score(12))
                    .foregroundStyle(isSelected ? .white : (allowed ? Theme.primaryText : Theme.tertiaryText))
            }
            .frame(width: 46, height: 46)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!allowed)
        .position(FieldGeometry.scaled(unit, in: size))
    }

    // MARK: - Controls

    private var controls: some View {
        HStack(spacing: 10) {
            Button {
                back()
            } label: {
                Image(systemName: index == 0 ? "xmark" : "chevron.left")
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(Circle().fill(.white.opacity(0.14)))
            }
            .buttonStyle(.plain)

            Button {
                choose(.out)
            } label: {
                Text("OUT")
                    .font(Theme.Typeface.label(16, weight: .heavy))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .luminousFill(Theme.miss, cornerRadius: 26, isProminent: true)
            }
            .buttonStyle(.plain)

            Button {
                choose(selected)
            } label: {
                Text("SAFE")
                    .font(Theme.Typeface.label(16, weight: .heavy))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .luminousFill(Theme.ball, cornerRadius: 26, isProminent: true)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Logic

    /// Forward stops only. A forced runner can't stay on their base.
    private var allowedTargets: [AdvanceTarget] {
        var targets: [AdvanceTarget] = []
        if !current.forced { targets.append(.held) }
        switch current.base {
        case .first: targets += [.second, .third, .home]
        case .second: targets += [.third, .home]
        case .third: targets += [.home]
        }
        return targets
    }

    private func targetForBase(_ base: Base) -> AdvanceTarget {
        switch base {
        case .first: .first
        case .second: .second
        case .third: .third
        }
    }

    private func unit(for target: AdvanceTarget) -> CGPoint {
        switch target {
        case .held: DrawnField.unit(for: current.base)
        case .first: DrawnField.firstBag
        case .second: DrawnField.secondBag
        case .third: DrawnField.thirdBag
        case .home, .out: DrawnField.plate
        }
    }

    private func syncSelection() {
        let allowed = allowedTargets
        if current.defaultTarget != .out, allowed.contains(current.defaultTarget) {
            selected = current.defaultTarget
        } else {
            selected = allowed.first ?? .held
        }
    }

    private func choose(_ target: AdvanceTarget) {
        results[current.base] = target
        Haptics.shared.commit(enabled: hapticsEnabled)
        if index >= prompts.count - 1 {
            let advances = prompts.map { ManualAdvance(from: $0.base, to: results[$0.base] ?? $0.defaultTarget) }
            onComplete(advances)
        } else {
            index += 1
            syncSelection()
        }
    }

    private func back() {
        if index == 0 {
            onCancel()
        } else {
            index -= 1
            selected = results[current.base] ?? current.defaultTarget
        }
    }
}
