import DeskpouchCore
import SwiftUI

/// Bottom-bar controls: tool segments, three colour swatches, two stroke sizes, undo and redo.
struct AnnotateToolbar: View {
    let document: AnnotateDocument

    var body: some View {
        HStack(spacing: 12) {
            tools
            divider
            HStack(spacing: 6) {
                ForEach(AnnotationColor.allCases, id: \.self) { color in
                    Swatch(color: color, selected: document.color == color) { document.setColor(color) }
                }
            }
            divider
            HStack(spacing: 2) {
                ForEach(StrokeSize.allCases, id: \.self) { size in
                    ToolbarIconButton(
                        label: size == .thin ? "Thin" : "Thick", selected: document.size == size,
                        action: { document.setSize(size) }
                    ) {
                        Capsule()
                            .frame(width: 14, height: size == .thin ? 2 : 4.5)
                    }
                }
            }
            .padding(2)
            .background(Capsule().fill(Theme.Colors.tint(0.04)))
            .overlay(Capsule().strokeBorder(Theme.Colors.tint(0.10), lineWidth: 1))
            divider
            HStack(spacing: 2) {
                ToolbarIconButton(label: "Undo (⌘Z)", selected: false, action: document.undo) {
                    UndoIcon().stroke(style: .icon(1.6)).frame(width: 14, height: 14)
                }
                .disabled(!document.model.canUndo)
                .opacity(document.model.canUndo ? 1 : 0.35)
                ToolbarIconButton(label: "Redo (⇧⌘Z)", selected: false, action: document.redo) {
                    RedoIcon().stroke(style: .icon(1.6)).frame(width: 14, height: 14)
                }
                .disabled(!document.model.canRedo)
                .opacity(document.model.canRedo ? 1 : 0.35)
            }
        }
    }

    private var tools: some View {
        HStack(spacing: 2) {
            ForEach(AnnotationTool.allCases, id: \.self) { tool in
                ToolbarIconButton(
                    label: "\(tool.label) (\(String(tool.key).uppercased()))", selected: document.tool == tool,
                    action: { document.select(tool) }
                ) {
                    icon(tool)
                }
            }
        }
        .padding(2)
        .background(Capsule().fill(Theme.Colors.tint(0.04)))
        .overlay(Capsule().strokeBorder(Theme.Colors.tint(0.10), lineWidth: 1))
    }

    @ViewBuilder
    private func icon(_ tool: AnnotationTool) -> some View {
        switch tool {
        case .arrow: ArrowIcon().stroke(style: .icon(1.7)).frame(width: 14, height: 14)
        case .box: BoxIcon().stroke(style: .icon(1.7)).frame(width: 14, height: 14)
        case .text: TextIcon().stroke(style: .icon(1.7)).frame(width: 14, height: 14)
        case .blur: BlurIcon().stroke(style: .icon(1.5)).frame(width: 14, height: 14)
        case .badge:
            ZStack {
                BadgeIcon().stroke(style: .icon(1.5))
                Text("1").font(.dp(8, .semibold))
            }
            .frame(width: 15, height: 15)
        }
    }

    private var divider: some View {
        Rectangle().fill(Theme.Colors.tint(0.12)).frame(width: 1, height: 18)
    }
}

/// 30 tall capsule segment. Selected: amber fill and text, like a chip that is on.
private struct ToolbarIconButton<Icon: View>: View {
    let label: String
    let selected: Bool
    let action: @MainActor () -> Void
    @ViewBuilder let icon: () -> Icon
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            icon()
                .foregroundStyle(selected ? Theme.Colors.accentHigh : Theme.Colors.text.opacity(hovering ? 0.9 : 0.62))
                .frame(width: 32, height: 28)
                .background(Capsule().fill(selected ? Theme.Colors.accent(0.18) : Theme.Colors.tint(hovering ? 0.06 : 0)))
                .overlay(Capsule().strokeBorder(selected ? Theme.Colors.accent(0.40) : .clear, lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(label)
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Colour dot; the selected one gets an amber ring.
private struct Swatch: View {
    let color: AnnotationColor
    let selected: Bool
    let action: @MainActor () -> Void

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(Color(cgColor: AnnotationRenderer.fill(color)))
                .overlay(Circle().strokeBorder(Color.white.opacity(color == .ink ? 0.28 : 0.12), lineWidth: 1))
                .frame(width: 16, height: 16)
                .padding(3)
                .overlay(Circle().strokeBorder(selected ? Theme.Colors.accentHigh : .clear, lineWidth: 1.5))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(name)
        .accessibilityLabel(name)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var name: String {
        switch color {
        case .accent: "Amber"
        case .white: "White"
        case .ink: "Ink"
        }
    }
}
