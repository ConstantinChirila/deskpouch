import Foundation
import Observation

/// Which tools are switched on in General. Stores the switched-off ids under `tools.disabled`, so a tool that
/// arrives in a new build is on from its first launch.
@MainActor
@Observable
public final class ToolSwitches {
    public private(set) var disabled: Set<String>
    @ObservationIgnored private let defaults: UserDefaults

    static let defaultsKey = "tools.disabled"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        disabled = Set(defaults.stringArray(forKey: Self.defaultsKey) ?? [])
    }

    public func isEnabled(_ toolID: String) -> Bool {
        !disabled.contains(toolID)
    }

    public func set(_ toolID: String, enabled: Bool) {
        if enabled {
            disabled.remove(toolID)
        } else {
            disabled.insert(toolID)
        }
        defaults.set(disabled.sorted(), forKey: Self.defaultsKey)
    }
}
