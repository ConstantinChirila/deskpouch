import AVFoundation
import AppKit
import DeskpouchCore
import SwiftUI

/// The recording on a dark well, and under it the timeline: a filmstrip with the cut parts dimmed, amber in and
/// out handles, and the playhead. Click the picture to play or pause.
struct TrimView: View {
    let document: TrimDocument

    static let stripHeight: CGFloat = 56
    /// Timeline, its labels and the gaps, for the window's ideal size.
    static let timelineBlockHeight: CGFloat = 12 + stripHeight + 8 + 14

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .fill(Theme.Colors.well)
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                            .strokeBorder(Theme.Colors.tint(0.08), lineWidth: 1)
                    )
                PlayerSurface(player: document.player)
                    .padding(12)
            }
            .contentShape(Rectangle())
            .onTapGesture { document.togglePlayback() }
            .accessibilityElement()
            .accessibilityLabel("Recording, \(document.isPlaying ? "playing" : "paused")")
            .accessibilityAddTraits(.isButton)

            VStack(spacing: 8) {
                TrimTimeline(document: document)
                    .frame(height: Self.stripHeight)
                labels
            }
        }
    }

    private var labels: some View {
        HStack {
            Text("In \(TrimModel.label(document.model.start))")
            Spacer()
            Text("Keeping \(TrimModel.label(document.model.selectedDuration)) of \(TrimModel.label(document.model.duration))")
                .foregroundStyle(document.model.isTrimmed ? Theme.Colors.accentHigh : Theme.Colors.textTertiary)
            Spacer()
            Text("Out \(TrimModel.label(document.model.end))")
        }
        .font(.dp(11))
        .monospacedDigit()
        .foregroundStyle(Theme.Colors.textTertiary)
        .padding(.horizontal, TrimTimeline.handleWidth)
        .frame(height: 14)
    }
}

/// Where a press on the timeline lands.
enum TrimDragTarget: Equatable {
    case start, end, playhead

    /// The handles sit outside the kept part (`startX` and `endX` are its edges), `handleWidth` wide, with a few
    /// points of slop. When the kept part is so short that both match, the nearer handle wins.
    static func at(x: CGFloat, startX: CGFloat, endX: CGFloat, handleWidth: CGFloat, slop: CGFloat = 5) -> TrimDragTarget {
        let onStart = x >= startX - handleWidth - slop && x <= startX + slop
        let onEnd = x >= endX - slop && x <= endX + handleWidth + slop
        switch (onStart, onEnd) {
        case (true, true): return abs(x - startX) <= abs(x - endX) ? .start : .end
        case (true, false): return .start
        case (false, true): return .end
        case (false, false): return .playhead
        }
    }
}

struct TrimTimeline: View {
    let document: TrimDocument
    @State private var target: TrimDragTarget?

    static let handleWidth: CGFloat = 12

    var body: some View {
        GeometryReader { geometry in
            let strip = max(1, geometry.size.width - Self.handleWidth * 2)
            let model = document.model
            let x: (TimeInterval) -> CGFloat = { Self.handleWidth + CGFloat($0 / model.duration) * strip }
            let startX = x(model.start)
            let endX = x(model.end)
            ZStack(alignment: .topLeading) {
                filmstrip(width: strip)
                    .offset(x: Self.handleWidth)
                // What is cut away.
                Rectangle().fill(Color.black.opacity(0.62))
                    .frame(width: max(0, startX - Self.handleWidth))
                    .offset(x: Self.handleWidth)
                Rectangle().fill(Color.black.opacity(0.62))
                    .frame(width: max(0, Self.handleWidth + strip - endX))
                    .offset(x: endX)
                // The kept part: amber rails top and bottom between the two handles.
                Rectangle().fill(Theme.Colors.accent)
                    .frame(width: max(0, endX - startX), height: 2)
                    .offset(x: startX)
                Rectangle().fill(Theme.Colors.accent)
                    .frame(width: max(0, endX - startX), height: 2)
                    .offset(x: startX, y: geometry.size.height - 2)
                Handle(leading: true, active: target == .start)
                    .offset(x: startX - Self.handleWidth)
                Handle(leading: false, active: target == .end)
                    .offset(x: endX)
            }
            // An overlay, so its extra height does not stretch the strip's pieces.
            .overlay(alignment: .topLeading) {
                Playhead()
                    .frame(height: geometry.size.height + 8)
                    .offset(x: x(model.playhead) - Playhead.width / 2, y: -4)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { value in
                        if target == nil {
                            target = TrimDragTarget.at(
                                x: value.startLocation.x, startX: startX, endX: endX, handleWidth: Self.handleWidth
                            )
                        }
                        let time = TimeInterval((value.location.x - Self.handleWidth) / strip) * model.duration
                        switch target {
                        case .start: document.dragStart(to: time)
                        case .end: document.dragEnd(to: time)
                        default: document.scrub(to: time)
                        }
                    }
                    .onEnded { _ in
                        if target != .playhead { document.handleDragFinished() }
                        target = nil
                    }
            )
        }
        .accessibilityElement()
        .accessibilityLabel("Timeline")
        .accessibilityValue("In \(TrimModel.label(document.model.start)), out \(TrimModel.label(document.model.end))")
    }

    @ViewBuilder
    private func filmstrip(width: CGFloat) -> some View {
        let images = document.thumbnails
        ZStack {
            Rectangle().fill(Theme.Colors.well)
            if !images.isEmpty {
                HStack(spacing: 0) {
                    ForEach(images.indices, id: \.self) { index in
                        Image(decorative: images[index], scale: 2)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: width / CGFloat(images.count), height: TrimView.stripHeight)
                            .clipped()
                    }
                }
                .transition(.opacity)
            }
        }
        .frame(width: width, height: TrimView.stripHeight)
        .overlay(Rectangle().strokeBorder(Theme.Colors.tint(0.08), lineWidth: 1))
        .animation(.easeOut(duration: 0.2), value: images.count)
    }
}

/// An amber tab on the outside of the kept part, rounded on its outer side, with a dark grip line.
private struct Handle: View {
    let leading: Bool
    let active: Bool

    var body: some View {
        UnevenRoundedRectangle(
            topLeadingRadius: leading ? 6 : 0, bottomLeadingRadius: leading ? 6 : 0,
            bottomTrailingRadius: leading ? 0 : 6, topTrailingRadius: leading ? 0 : 6, style: .continuous
        )
        .fill(active ? Theme.Colors.accentHigh : Theme.Colors.accent)
        .overlay(Capsule().fill(Theme.Colors.accentInk.opacity(0.7)).frame(width: 2, height: 18))
        .frame(width: TrimTimeline.handleWidth)
        .shadow(color: Theme.Colors.accent(active ? 0.5 : 0.25), radius: 6)
        .pointerStyle(.columnResize)
    }
}

private struct Playhead: View {
    static let width: CGFloat = 9

    var body: some View {
        VStack(spacing: 0) {
            Capsule().fill(Theme.Colors.text).frame(width: Self.width, height: 5)
            Rectangle().fill(Theme.Colors.text).frame(width: 2)
        }
        .frame(width: Self.width)
        .shadow(color: .black.opacity(0.6), radius: 2)
        .allowsHitTesting(false)
    }
}

/// `AVPlayerLayer` in a view, instead of AVKit's player and its native controls.
private struct PlayerSurface: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> PlayerLayerView {
        PlayerLayerView(player: player)
    }

    func updateNSView(_ view: PlayerLayerView, context: Context) {}
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
