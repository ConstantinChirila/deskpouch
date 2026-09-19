import AVFoundation
import AppKit
import SwiftUI

/// `AVPlayerLayer` in a view, instead of AVKit's player and its native controls. Trim and the gallery draw their
/// own transport around it.
public struct PlayerSurface: NSViewRepresentable {
    let player: AVPlayer

    public init(player: AVPlayer) {
        self.player = player
    }

    public func makeNSView(context: Context) -> NSView {
        PlayerLayerView(player: player)
    }

    public func updateNSView(_ view: NSView, context: Context) {
        (view.layer as? AVPlayerLayer)?.player = player
    }
}

private final class PlayerLayerView: NSView {
    init(player: AVPlayer) {
        super.init(frame: .zero)
        wantsLayer = true
        guard let layer = layer as? AVPlayerLayer else { return }
        layer.player = player
        layer.videoGravity = .resizeAspect
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override func makeBackingLayer() -> CALayer { AVPlayerLayer() }
}
