import AppKit
import DeskpouchCore
import SwiftUI

/// Full-screen picker content for one screen: dim with a cutout, selection chrome, and on one screen the toolbar.
struct PickerScreenView: View {
    let model: PickerModel
    let screen: PickerScreen

    private static let dim = Color(red: 4 / 255, green: 8 / 255, blue: 6 / 255).opacity(0.62)

    var body: some View {
        let highlight = highlightRect
        ZStack(alignment: .topLeading) {
            Cutout(hole: highlight)
                .fill(Self.dim, style: FillStyle(eoFill: true))
                .ignoresSafeArea()
            if let highlight {
                SelectionChrome(rect: highlight, brackets: model.mode == .region, tint: model.style.tint)
                if let label = model.dimensionLabel {
                    DimensionChip(label: label, snapping: model.mode == .region && model.snapToAspect, tint: model.style.tint)
                        .offset(chipOffset(for: highlight))
                }
            }
            if screen.id == model.toolbarScreenID {
                VStack {
                    Spacer()
                    PickerToolbar(model: model)
                        .padding(.bottom, 28)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(width: screen.frame.width, height: screen.frame.height)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .onChanged { value in model.dragChanged(screenID: screen.id, location: value.location) }
                .onEnded { value in
                    model.dragEnded(screenID: screen.id, location: value.location, clickCount: NSApp.currentEvent?.clickCount ?? 1)
                }
        )
        .onContinuousHover(coordinateSpace: .local) { phase in
            switch phase {
            case .active(let point): model.hoverChanged(screenID: screen.id, location: point)
            case .ended: model.hoverChanged(screenID: screen.id, location: nil)
            }
        }
        .animation(.easeOut(duration: 0.12), value: model.hoveredWindow)
        .animation(.easeOut(duration: 0.12), value: model.mode)
        .foregroundStyle(Theme.Colors.text)
        .environment(\.colorScheme, .dark)
    }

    private var highlightRect: CGRect? {
        switch model.mode {
        case .region: model.regionRect(on: screen.id)
        case .window: model.hoveredWindowRect(on: screen.id)
        case .screen: model.hoveredScreenID == screen.id ? screen.localBounds.insetBy(dx: 1, dy: 1) : nil
        }
    }

    /// Chip's top-left: above the selection, flush with its left edge; inside it when there is no room above.
    private func chipOffset(for rect: CGRect) -> CGSize {
        let inside = rect.minY < 44
        return CGSize(width: rect.minX + (inside ? 10 : 0), height: inside ? rect.minY + 10 : rect.minY - 38)
    }
}

/// Full-rect fill with a hole, drawn even-odd.
private struct Cutout: Shape {
    let hole: CGRect?

    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.addRect(rect)
        if let hole { p.addRoundedRect(in: hole, cornerSize: CGSize(width: 6, height: 6)) }
        return p
    }
}

/// 2px border, 4px ring, glow, and cream corner brackets, tinted per `PickerStyle`.
private struct SelectionChrome: View {
    let rect: CGRect
    let brackets: Bool
    let tint: Color

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        let bleed: CGFloat = 48
        ZStack(alignment: .topLeading) {
            // Ring and glow are masked to the outside so the selection shows the screen untouched.
            shape
                .stroke(tint.opacity(0.18), lineWidth: 8)
                .padding(-2)
                .shadow(color: tint.opacity(0.25), radius: 20)
                .frame(width: rect.width, height: rect.height)
                .mask(
                    Cutout(hole: CGRect(x: bleed, y: bleed, width: rect.width, height: rect.height))
                        .fill(style: FillStyle(eoFill: true))
                        .padding(-bleed)
                )
                .offset(x: rect.minX, y: rect.minY)
            shape
                .strokeBorder(tint, lineWidth: 2)
                .frame(width: rect.width, height: rect.height)
                .offset(x: rect.minX, y: rect.minY)
            if brackets {
                ForEach(0..<4, id: \.self) { corner in
                    CornerBracket()
                        .stroke(Theme.Colors.text, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .frame(width: 18, height: 18)
                        .rotationEffect(.degrees(Double(corner) * 90))
                        .position(bracketCenter(corner))
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func bracketCenter(_ corner: Int) -> CGPoint {
        let inset: CGFloat = 8
        return switch corner {
        case 0: CGPoint(x: rect.minX - inset + 9, y: rect.minY - inset + 9)
        case 1: CGPoint(x: rect.maxX + inset - 9, y: rect.minY - inset + 9)
        case 2: CGPoint(x: rect.maxX + inset - 9, y: rect.maxY + inset - 9)
        default: CGPoint(x: rect.minX - inset + 9, y: rect.maxY + inset - 9)
        }
    }
}

/// Top-left bracket in an 18 box; rotate for the other corners.
private struct CornerBracket: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX + 1.5, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX + 1.5, y: rect.minY + 4.5))
        p.addArc(center: CGPoint(x: rect.minX + 4.5, y: rect.minY + 4.5), radius: 3, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + 1.5))
        return p
    }
}

/// Tinted capsule with the selection size and, while shift is held, the snap hint.
private struct DimensionChip: View {
    let label: String
    let snapping: Bool
    let tint: Color

    var body: some View {
        HStack(spacing: 8) {
            Text(label).font(.dp(12, .semibold)).monospacedDigit()
            if snapping {
                Rectangle().fill(Theme.Colors.bg.opacity(0.3)).frame(width: 1, height: 12)
                Text("16:9 snap").font(.dp(12))
            }
        }
        .foregroundStyle(Theme.Colors.bg)
        .padding(.horizontal, 10)
        .frame(height: 26)
        .background(Capsule().fill(tint))
        .shadow(color: tint.opacity(0.35), radius: 8, y: 6)
        .fixedSize()
        .allowsHitTesting(false)
    }
}

/// Bottom pill: mode segments, audio toggles, Record with the return hint, esc.
struct PickerToolbar: View {
    let model: PickerModel

    var body: some View {
        HStack(spacing: 14) {
            segments
            if model.style.showsAudioToggles {
                HStack(spacing: 4) {
                    AudioToggle(isOn: model.systemAudio, help: "System audio") { model.systemAudio.toggle() } icon: {
                        SpeakerIcon().stroke(style: .icon(1.6))
                    }
                    AudioToggle(isOn: model.microphone, help: "Microphone") { model.microphone.toggle() } icon: {
                        MicIcon().stroke(style: .icon(1.6))
                    }
                }
                Rectangle().fill(Theme.Colors.tint(0.12)).frame(width: 1, height: 26)
            }
            Button(action: { model.confirm() }) {
                HStack(spacing: 10) {
                    Circle().fill(model.style.tint).frame(width: 12, height: 12)
                    Text(model.style.toolbarLabel).font(.dp(14, .semibold))
                    Text("↩")
                        .font(.dp(11, .medium))
                        .padding(.horizontal, 7)
                        .frame(height: 22)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Theme.Colors.bg.opacity(0.1)))
                }
                .foregroundStyle(Theme.Colors.bg)
                .padding(.leading, 14)
                .padding(.trailing, 18)
                .frame(height: 42)
                .background(Capsule().fill(Theme.Colors.text))
                .shadow(color: .black.opacity(0.4), radius: 10, y: 8)
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(!model.canRecord)
            .opacity(model.canRecord ? 1 : 0.45)
            .help(model.mode == .region ? "Drag a region, then \(model.style.toolbarLabel)" : "Click a target, or \(model.style.toolbarLabel)")
            Text("esc")
                .font(.dp(11))
                .foregroundStyle(Theme.Colors.textSecondary)
                .padding(.trailing, 8)
        }
        .padding(.leading, 8)
        .padding(.trailing, 10)
        .frame(height: 60)
        .background(Capsule().fill(Theme.panelGradient))
        .overlay(Capsule().strokeBorder(Theme.Colors.tint(0.16), lineWidth: 1))
        .overlay(alignment: .top) {
            Capsule().fill(Color.white.opacity(0.08)).frame(height: 1).padding(.horizontal, 24).padding(.top, 1)
        }
        .shadow(color: .black.opacity(0.6), radius: 30, y: 24)
        .contentShape(Capsule())
        .onTapGesture {} // Keeps clicks on the toolbar's own surface from reaching the picker's drag gesture.
        .animation(.easeOut(duration: 0.15), value: model.mode)
        .animation(.easeOut(duration: 0.15), value: model.canRecord)
    }

    private var segments: some View {
        HStack(spacing: 2) {
            ForEach(PickerMode.allCases, id: \.self) { mode in
                let on = model.mode == mode
                Button(action: { model.setMode(mode) }) {
                    HStack(spacing: 7) {
                        segmentIcon(mode)
                            .frame(width: 15, height: 15)
                        Text(mode.label).font(.dp(13, on ? .semibold : .regular))
                    }
                    .foregroundStyle(on ? Theme.Colors.bg : Theme.Colors.text.opacity(0.6))
                    .padding(.horizontal, 14)
                    .frame(height: 34)
                    .background {
                        if on {
                            Capsule()
                                .fill(LinearGradient(colors: model.style.tintGradient, startPoint: .top, endPoint: .bottom))
                                .overlay(alignment: .top) {
                                    Capsule().fill(Color.white.opacity(0.35)).frame(height: 1).padding(.horizontal, 12).padding(.top, 1)
                                }
                                .shadow(color: model.style.tint.opacity(0.35), radius: 6, y: 4)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .frame(height: 42)
        .background(Capsule().fill(Theme.Colors.well))
        .overlay(Capsule().strokeBorder(Theme.Colors.tint(0.08), lineWidth: 1))
    }

    @ViewBuilder
    private func segmentIcon(_ mode: PickerMode) -> some View {
        switch mode {
        case .region: RegionIcon().stroke(style: .icon(1.8))
        case .window: WindowIcon().stroke(style: .icon(1.6))
        case .screen: ScreenIcon().stroke(style: .icon(1.6))
        }
    }
}

private struct AudioToggle<Icon: View>: View {
    let isOn: Bool
    let help: String
    let action: @MainActor () -> Void
    @ViewBuilder let icon: () -> Icon

    init(isOn: Bool, help: String, action: @escaping @MainActor () -> Void, @ViewBuilder icon: @escaping () -> Icon) {
        self.isOn = isOn
        self.help = help
        self.action = action
        self.icon = icon
    }

    var body: some View {
        Button(action: action) {
            icon()
                .foregroundStyle(isOn ? Theme.Colors.accentHigh : Theme.Colors.textTertiary)
                .frame(width: 16, height: 16)
                .frame(width: 36, height: 36)
                .background(Circle().fill(isOn ? Theme.Colors.accent(0.16) : Theme.Colors.tint(0.04)))
                .overlay(Circle().strokeBorder(isOn ? Theme.Colors.accent(0.40) : Theme.Colors.tint(0.12), lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityAddTraits(isOn ? [.isToggle, .isSelected] : .isToggle)
        .animation(.easeOut(duration: 0.15), value: isOn)
    }
}
