import CoreGraphics
import DeskpouchCore
import Foundation

extension PickerSelection {
    /// Where this selection sits, for the history row: the display and the rect in that display's points, top-left
    /// origin, which is what a region `StillCapture` takes back (Recapture, plan 04). A window is stored as the
    /// part of its frame on the display that holds most of it, so recapturing it is a region capture of where it
    /// was; nil when it is on none of `screens`.
    public func captureMeta(screens: [PickerScreen]) -> ResultMeta? {
        switch self {
        case .region(let screen, let rect):
            return Self.meta(display: screen.displayID, rect: rect)
        case .screen(let screen):
            return Self.meta(display: screen.displayID, rect: screen.localBounds)
        case .window(let window):
            func overlap(_ screen: PickerScreen) -> CGFloat {
                let shared = screen.cgFrame.intersection(window.frame)
                return shared.isNull ? 0 : shared.width * shared.height
            }
            guard let screen = screens.max(by: { overlap($0) < overlap($1) }), overlap(screen) > 0 else { return nil }
            return Self.meta(display: screen.displayID, rect: screen.localRect(fromCG: screen.cgFrame.intersection(window.frame)))
        }
    }

    private static func meta(display: CGDirectDisplayID, rect: CGRect) -> ResultMeta {
        ResultMeta(display: display, rect: [rect.minX, rect.minY, rect.width, rect.height].map(Double.init))
    }
}
