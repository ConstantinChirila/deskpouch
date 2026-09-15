import Foundation
import Observation

/// After-capture actions a tool can turn on. The pipeline runs the chosen ones in `executionOrder`.
public enum OutputAction: String, CaseIterable, Codable, Sendable, Hashable {
    case copy
    case paste
    case saveToFolder
    case revealInFinder
    case runShellCommand
    case notify
    /// Log the result so it shows under Recent and can be re-copied.
    case history

    /// Fixed order regardless of how a tool lists them: the pasteboard is set before ⌘V is posted, the file is
    /// saved before it is revealed or announced, history goes last so it can record where things ended up.
    public static let executionOrder: [OutputAction] = [
        .copy, .paste, .saveToFolder, .revealInFinder, .runShellCommand, .notify, .history,
    ]

    /// Panel chip label.
    public var label: String {
        switch self {
        case .copy: "Copy"
        case .paste: "Paste"
        case .saveToFolder: "Save"
        case .revealInFinder: "Reveal"
        case .runShellCommand: "Shell"
        case .notify: "Notify"
        case .history: "History"
        }
    }
}

/// One tool's after-capture settings.
public struct ToolOutputConfig: Codable, Sendable, Equatable {
    public var actions: Set<OutputAction>
    /// Where `saveToFolder` writes. nil means the tool's default folder.
    public var folder: URL?
    /// Run by `runShellCommand` through `/bin/zsh -c`. Gets DESKPOUCH_TEXT, DESKPOUCH_FILE, DESKPOUCH_TOOL in its env.
    public var shellCommand: String?

    public init(actions: Set<OutputAction>, folder: URL? = nil, shellCommand: String? = nil) {
        self.actions = actions
        self.folder = folder
        self.shellCommand = shellCommand
    }
}

/// Per-tool output configs, persisted in UserDefaults as JSON under `output.<toolID>`.
@MainActor
@Observable
public final class OutputSettings {
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var fallbacks: [String: ToolOutputConfig] = [:]
    private var configs: [String: ToolOutputConfig] = [:]

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Registers what a tool wants when nothing is stored yet.
    public func registerDefault(_ config: ToolOutputConfig, for toolID: String) {
        fallbacks[toolID] = config
        if configs[toolID] == nil, let stored = load(toolID) {
            configs[toolID] = stored
        }
    }

    public func config(for toolID: String) -> ToolOutputConfig {
        if let config = configs[toolID] { return config }
        if let stored = load(toolID) {
            configs[toolID] = stored
            return stored
        }
        return fallbacks[toolID] ?? ToolOutputConfig(actions: [])
    }

    public func update(_ toolID: String, _ change: (inout ToolOutputConfig) -> Void) {
        var config = config(for: toolID)
        change(&config)
        configs[toolID] = config
        if let data = try? JSONEncoder().encode(config) {
            defaults.set(data, forKey: Self.key(toolID))
        }
    }

    public func toggle(_ action: OutputAction, for toolID: String) {
        update(toolID) { config in
            if config.actions.contains(action) {
                config.actions.remove(action)
            } else {
                config.actions.insert(action)
            }
        }
    }

    private func load(_ toolID: String) -> ToolOutputConfig? {
        guard let data = defaults.data(forKey: Self.key(toolID)) else { return nil }
        return try? JSONDecoder().decode(ToolOutputConfig.self, from: data)
    }

    private static func key(_ toolID: String) -> String { "output.\(toolID)" }
}
