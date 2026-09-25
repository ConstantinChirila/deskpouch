import Foundation
import Observation

/// Which tools are switched on in General. Stores the switched-off ids under `tools.disabled`, so a tool that
/// arrives in a new build is on from its first launch. Tools named in `offByDefault` (Calendar: it asks for a
/// permission and only works with an account in macOS Calendar) work the other way round: off until switched on,
/// stored under `tools.enabled`.
@MainActor
@Observable
public final class ToolSwitches {
    public private(set) var disabled: Set<String>
    public private(set) var optedIn: Set<String>
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let offByDefault: Set<String>

    static let defaultsKey = "tools.disabled"
    static let optInKey = "tools.enabled"

    public init(defaults: UserDefaults = .standard, offByDefault: Set<String> = []) {
        self.defaults = defaults
        self.offByDefault = offByDefault
        disabled = Set(defaults.stringArray(forKey: Self.defaultsKey) ?? [])
        optedIn = Set(defaults.stringArray(forKey: Self.optInKey) ?? [])
    }

    public func isEnabled(_ toolID: String) -> Bool {
        offByDefault.contains(toolID) ? optedIn.contains(toolID) : !disabled.contains(toolID)
    }

    public func set(_ toolID: String, enabled: Bool) {
        if offByDefault.contains(toolID) {
            if enabled { optedIn.insert(toolID) } else { optedIn.remove(toolID) }
            defaults.set(optedIn.sorted(), forKey: Self.optInKey)
            return
        }
        if enabled {
            disabled.remove(toolID)
        } else {
            disabled.insert(toolID)
        }
        defaults.set(disabled.sorted(), forKey: Self.defaultsKey)
    }
}
