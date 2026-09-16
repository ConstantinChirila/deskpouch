import SwiftUI

/// The panel's side of a tool: its row on the main view, its tile, and its own view. One entry per tool, so the
/// Tools list, the tool views and General's switches all come from this table instead of naming tools.
@MainActor
struct PanelTool: Identifiable {
    let id: String
    let name: String
    let tile: (_ size: CGFloat) -> AnyView
    let row: (ShellState) -> AnyView
    let view: (ShellState, MenuPanelActions) -> AnyView
}

@MainActor
enum PanelTools {
    /// Every tool the panel knows, in list order. A new tool adds its entry here.
    static let all: [PanelTool] = [
        PanelTool(
            id: VoiceToolView.toolID, name: "Voice",
            tile: { AnyView(VoiceTile(size: $0)) },
            row: { AnyView(VoiceRow(state: $0)) },
            view: { AnyView(VoiceToolView(state: $0, actions: $1)) }
        ),
        PanelTool(
            id: ScreenToolView.toolID, name: "Record screen",
            tile: { AnyView(ScreenTile(size: $0)) },
            row: { AnyView(ScreenRow(state: $0)) },
            view: { AnyView(ScreenToolView(state: $0, actions: $1)) }
        ),
    ]

    static func tool(_ id: String) -> PanelTool? {
        all.first { $0.id == id }
    }

    static func enabled(in state: ShellState) -> [PanelTool] {
        all.filter { state.switches.isEnabled($0.id) }
    }
}
