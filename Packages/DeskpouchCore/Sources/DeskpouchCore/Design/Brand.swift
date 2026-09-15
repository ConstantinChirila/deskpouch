import AppKit
import SwiftUI

/// Bitmap brand assets from the asset pack (`Resources/Brand`): the amber mark. The menubar glyph is drawn in
/// `MenubarGlyph`; the pack's outline template was too fine at 18 pt.
@MainActor
public enum Brand {
    /// The amber pouch mark on transparent, for the panel header. 64 and 128 px sources.
    public static let mark: NSImage? = {
        guard let image = load("Mark") else { return nil }
        image.size = NSSize(width: 32, height: 32)
        return image
    }()

    /// Loads `<name>.png` plus `<name>@2x.png` into one image with both representations.
    private static func load(_ name: String) -> NSImage? {
        let folder = Bundle.module.resourceURL?.appending(path: "Brand", directoryHint: .isDirectory)
        guard let folder, let base = NSImage(contentsOf: folder.appending(path: "\(name).png")) else { return nil }
        if let retina = NSImage(contentsOf: folder.appending(path: "\(name)@2x.png")) {
            for rep in retina.representations {
                rep.size = base.size
                base.addRepresentation(rep)
            }
        }
        return base
    }
}

/// SwiftUI view of the amber mark at a given point size.
public struct BrandMark: View {
    let size: CGFloat

    public init(size: CGFloat = 20) {
        self.size = size
    }

    public var body: some View {
        if let image = Brand.mark {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
        } else {
            PouchIcon()
                .stroke(style: .icon(1.6))
                .foregroundStyle(Theme.Colors.accent)
                .frame(width: size, height: size)
        }
    }
}
