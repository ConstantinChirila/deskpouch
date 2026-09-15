import Foundation

/// After-capture actions. v1 does copy + paste for text; per-tool configuration and history come next.
@MainActor
public final class OutputPipeline {
    public struct Delivery: Sendable, Equatable {
        public var copied = false
        public var pastedInto: String?
    }

    public init() {}

    public func deliver(_ result: ToolResult) async -> Delivery {
        var delivery = Delivery()
        if let text = result.text, !text.isEmpty {
            Paster.copy(text)
            delivery.copied = true
            // Give the pasteboard server a moment before the target app reads it.
            try? await Task.sleep(for: .milliseconds(40))
            delivery.pastedInto = Paster.pasteIntoFrontmostApp()
        }
        return delivery
    }
}
