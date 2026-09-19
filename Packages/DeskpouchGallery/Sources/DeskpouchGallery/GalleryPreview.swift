import AppKit
import DeskpouchCore
import ImageIO
import Observation
import SwiftUI
import os

private let previewLog = Logger(subsystem: "com.constantinchirila.deskpouch", category: "gallery")

/// The right side: the focused row at a useful size, a line about it, and what can be done with it.
struct GalleryPreview: View {
    let controller: GalleryWindowController
    @State private var images = PreviewImageLoader()

    private var model: GalleryModel { controller.model }

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .fill(Theme.Colors.well)
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                            .strokeBorder(Theme.Colors.tint(0.08), lineWidth: 1)
                    )
                content
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            bar
        }
        .onChange(of: model.focused?.id, initial: true) {
            let ahead = model.neighbours.filter { $0.kind == .screenshot }.compactMap(\.fileURL)
            images.prefetch(ahead, keeping: model.focused?.kind == .screenshot ? model.focused?.fileURL : nil)
        }
    }

    @ViewBuilder
    private var content: some View {
        let selected = model.selectedIDs.count
        if selected > 1 {
            Message(title: "\(selected) items selected", detail: "Drag them into another app, ⌘C copies their files, ⌘⌫ moves them to the Trash.")
        } else if let item = model.focused, model.missing.contains(item.id) {
            Message(title: "File moved or deleted", detail: "\(item.fileURL?.lastPathComponent ?? "It") is no longer where Deskpouch saved it. Delete removes the row.")
        } else if let item = model.focused {
            switch item.kind {
            case .screenshot:
                ImagePreview(item: item, loader: images, ui: controller.ui, thumbnails: controller.thumbnails)
            case .color:
                ColorPreview(
                    item: item, swatch: GalleryText.color(hex: controller.actions.swatchHex(item)),
                    formats: controller.actions.colorFormats(item), copy: controller.actions.copyText
                )
            default:
                if let text = item.text {
                    TextPreview(text: text)
                } else if let file = item.fileURL, FileManager.default.fileExists(atPath: file.path) {
                    if file.pathExtension.lowercased() == "gif" {
                        GIFPreview(url: file, gif: controller.gif)
                    } else {
                        VideoPreview(url: file, video: controller.video, thumbnails: controller.thumbnails)
                    }
                } else {
                    Message(title: "File moved or deleted", detail: "The recording is no longer where Deskpouch saved it.")
                }
            }
        } else {
            Message(title: "Nothing selected", detail: "Pick something on the left, or use ↑ and ↓.")
        }
    }

    // MARK: Bar

    private var bar: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(barTitle)
                    .font(.dp(13, .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(barDetail)
                    .font(.dp(11))
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 12)
            if model.selectedIDs.count == 1, let item = model.focused, !model.missing.contains(item.id) {
                GalleryButton(title: item.starred ? "Starred" : "Star", hint: "S", style: item.starred ? .on : .plain) {
                    model.toggleStar()
                }
                if item.fileURL != nil {
                    GalleryButton(title: "Show in Finder", hint: "", style: .plain) { controller.actions.reveal(item) }
                }
                if let label = controller.actions.editLabel(item) {
                    GalleryButton(title: label, hint: "↩", style: .plain) { controller.editFocused() }
                }
                GalleryButton(title: controller.ui.copied ? "Copied" : "Copy", hint: "⌘C", style: .primary) { controller.copyFocused() }
            }
            if model.selectedIDs.count > 1 {
                GalleryButton(title: controller.ui.copied ? "Copied" : "Copy all", hint: "⌘C", style: .primary) { controller.copyFocused() }
            }
            if !model.selectedIDs.isEmpty {
                GalleryButton(title: "Delete", hint: "⌘⌫", style: .destructive) { model.requestDelete() }
            }
        }
        .frame(height: 36)
    }

    private var barTitle: String {
        if model.selectedIDs.count > 1 { return "\(model.selectedIDs.count) items" }
        return model.focused.map(GalleryText.title) ?? ""
    }

    private var barDetail: String {
        guard model.selectedIDs.count == 1, let item = model.focused else { return "" }
        var parts = [DayGroup.label(for: item.createdAt) + " " + DayGroup.clock(item.createdAt)]
        if let text = item.text, item.kind != .color { parts.append(GalleryText.wordCount(text)) }
        if let target = item.pastedInto { parts.append("pasted into \(target)") }
        if item.kind == .screenshot, let size = images.pixelSize(for: item.fileURL) {
            parts.append("\(Int(size.width)) × \(Int(size.height)) px")
        }
        if let file = item.fileURL {
            if let bytes = (try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? NSNumber)?.int64Value {
                parts.append(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))
            }
            parts.append((file.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath)
        }
        return parts.joined(separator: " · ")
    }
}

private struct Message: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(spacing: 6) {
            Text(title).font(.dp(15, .semibold))
            Text(detail)
                .font(.dp(12))
                .foregroundStyle(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
    }
}

// MARK: Image

/// Full images for the preview, decoded off the main actor. Keeps the one on show and its neighbours, so
/// stepping through the list does not wait for a decode; screenshots are large, so nothing more than that.
@MainActor
@Observable
final class PreviewImageLoader {
    struct Loaded: Sendable {
        let url: URL
        let image: CGImage
        /// From the PNG's DPI; files without it count as 2x.
        let pixelsPerPoint: CGFloat
    }

    static let capacity = 3

    private var cache: [URL: Loaded] = [:]
    private(set) var failed: Set<URL> = []
    /// Least recently wanted first.
    @ObservationIgnored private var recency: [URL] = []
    @ObservationIgnored private var inflight: [URL: Task<Void, Never>] = [:]

    /// The image when it is ready; asking starts the decode.
    func image(for url: URL) -> Loaded? {
        touch(url)
        if let loaded = cache[url] { return loaded }
        start(url)
        return nil
    }

    /// Decodes `urls` ahead of time and drops loads nobody is waiting for any more.
    func prefetch(_ urls: [URL], keeping current: URL?) {
        let wanted = Set(urls + [current].compactMap { $0 })
        for (url, task) in inflight where !wanted.contains(url) {
            task.cancel()
            inflight[url] = nil
        }
        for url in urls where cache[url] == nil {
            touch(url)
            start(url)
        }
        if let current { touch(current) }
    }

    func pixelSize(for url: URL?) -> CGSize? {
        guard let url, let loaded = cache[url] else { return nil }
        return CGSize(width: loaded.image.width, height: loaded.image.height)
    }

    private func start(_ url: URL) {
        guard inflight[url] == nil, !failed.contains(url) else { return }
        inflight[url] = Task { [weak self] in
            let started = ContinuousClock.now
            let result = await Task.detached(priority: .userInitiated) { Self.decode(url) }.value
            guard let self, !Task.isCancelled else { return }
            inflight[url] = nil
            if let result {
                previewLog.info("decoded \(url.lastPathComponent, privacy: .public) \(result.image.width)x\(result.image.height) in \(String(describing: ContinuousClock.now - started), privacy: .public)")
                cache[url] = result
                trim()
            } else {
                failed.insert(url)
            }
        }
    }

    private func touch(_ url: URL) {
        recency.removeAll { $0 == url }
        recency.append(url)
    }

    private func trim() {
        while cache.count > Self.capacity, let oldest = recency.first(where: { cache[$0] != nil }) {
            cache[oldest] = nil
            recency.removeAll { $0 == oldest }
        }
    }

    nonisolated private static func decode(_ url: URL) -> Loaded? {
        let options = [kCGImageSourceShouldCacheImmediately: true] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, options) else { return nil }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let dpi = (properties?[kCGImagePropertyDPIWidth] as? Double) ?? 144
        return Loaded(url: url, image: image, pixelsPerPoint: max(1, CGFloat(dpi / 72)))
    }
}

/// Fitted to the pane, never past 1:1 points. Click or Space shows it at 100% in a scroller.
private struct ImagePreview: View {
    let item: HistoryItem
    let loader: PreviewImageLoader
    let ui: GalleryUI
    let thumbnails: ThumbnailCache

    var body: some View {
        if let url = item.fileURL, let loaded = loader.image(for: url) {
            let points = CGSize(width: CGFloat(loaded.image.width) / loaded.pixelsPerPoint, height: CGFloat(loaded.image.height) / loaded.pixelsPerPoint)
            GeometryReader { geometry in
                let inset: CGFloat = 16
                let area = CGSize(width: max(1, geometry.size.width - inset * 2), height: max(1, geometry.size.height - inset * 2))
                let fit = min(1, area.width / points.width, area.height / points.height)
                if ui.zoomed && fit < 1 {
                    ScrollView([.horizontal, .vertical]) {
                        picture(loaded.image, size: points)
                            .padding(inset)
                            .frame(minWidth: geometry.size.width, minHeight: geometry.size.height)
                    }
                } else {
                    picture(loaded.image, size: CGSize(width: points.width * fit, height: points.height * fit))
                        .frame(width: geometry.size.width, height: geometry.size.height)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { ui.zoomed.toggle() }
            // The picture itself drags out as its file.
            .onDrag { NSItemProvider(contentsOf: url) ?? NSItemProvider() }
            .accessibilityElement()
            .accessibilityLabel("Screenshot, \(ui.zoomed ? "actual size" : "fitted")")
        } else if let url = item.fileURL, loader.failed.contains(url) {
            Message(title: "File moved or deleted", detail: "The screenshot is no longer where Deskpouch saved it.")
        } else if let thumb = (item.thumbURL ?? item.fileURL).flatMap({ thumbnails.image(for: $0) }) {
            // The tile's thumbnail, stretched, for the moment the full image takes to decode.
            Image(decorative: thumb, scale: 1)
                .resizable()
                .interpolation(.medium)
                .aspectRatio(contentMode: .fit)
                .padding(16)
                .blur(radius: 6)
                .opacity(0.85)
        } else {
            Color.clear
        }
    }

    private func picture(_ image: CGImage, size: CGSize) -> some View {
        Image(decorative: image, scale: 1)
            .resizable()
            .interpolation(.high)
            .frame(width: size.width, height: size.height)
            .shadow(color: .black.opacity(0.45), radius: 14, y: 6)
    }
}

// MARK: Text, colour

private struct TextPreview: View {
    let text: String

    var body: some View {
        ScrollView {
            Text(text)
                .font(.dp(15))
                .lineSpacing(5)
                .textSelection(.enabled)
                .frame(maxWidth: 640, alignment: .leading)
                .padding(28)
                .frame(maxWidth: .infinity)
        }
    }
}

/// A big swatch and every format of the colour, one line each; a line copies on click.
private struct ColorPreview: View {
    let item: HistoryItem
    let swatch: Color?
    let formats: [(label: String, value: String)]
    let copy: @MainActor (String) -> Void
    @State private var copied: String?

    var body: some View {
        VStack(spacing: 20) {
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .fill(swatch ?? Theme.Colors.well)
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
                .frame(width: 260, height: 150)
            if formats.isEmpty {
                Text(item.text ?? "")
                    .font(.dp(17, .semibold))
                    .textSelection(.enabled)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(formats.enumerated()), id: \.offset) { index, format in
                        if index > 0 { Rectangle().fill(Theme.Colors.tint(0.07)).frame(height: 1) }
                        Button {
                            copy(format.value)
                            copied = format.label
                            Task {
                                try? await Task.sleep(for: .seconds(1.2))
                                if copied == format.label { copied = nil }
                            }
                        } label: {
                            HStack(spacing: 12) {
                                Text(format.label.uppercased())
                                    .font(.dp(10, .semibold))
                                    .tracking(0.6)
                                    .foregroundStyle(Theme.Colors.textTertiary)
                                    .frame(width: 70, alignment: .leading)
                                Text(format.value)
                                    .font(.dp(13, .medium))
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Text(copied == format.label ? "Copied" : "Copy")
                                    .font(.dp(11))
                                    .foregroundStyle(copied == format.label ? Theme.Colors.ok : Theme.Colors.textFaint)
                            }
                            .padding(.horizontal, 14)
                            .frame(minHeight: 38)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Copy \(format.label): \(format.value)")
                    }
                }
                .frame(width: 420)
                .background(RoundedRectangle(cornerRadius: Theme.Radius.well, style: .continuous).fill(Theme.Colors.tint(0.03)))
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.well, style: .continuous).strokeBorder(Theme.Colors.tint(0.08), lineWidth: 1))
            }
        }
        .padding(24)
    }
}

// MARK: Buttons

struct GalleryButton: View {
    enum Style { case primary, plain, destructive, on }

    let title: String
    let hint: String
    let style: Style
    let action: @MainActor () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Text(title).font(.dp(13, .semibold))
                if !hint.isEmpty { Text(hint).font(.dp(11)).opacity(0.6) }
            }
            .foregroundStyle(foreground)
            .padding(.horizontal, 13)
            .frame(height: 32)
            .background(Capsule().fill(fill))
            .overlay(Capsule().strokeBorder(border, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }

    private var foreground: Color {
        switch style {
        case .primary: Theme.Colors.accentInk
        case .plain: Theme.Colors.text
        case .destructive: Theme.Colors.record
        case .on: Theme.Colors.accentHigh
        }
    }

    private var fill: Color {
        switch style {
        case .primary: Theme.Colors.accent
        case .plain: Theme.Colors.tint(0.07)
        case .destructive: Theme.Colors.record(0.10)
        case .on: Theme.Colors.accent(0.16)
        }
    }

    private var border: Color {
        switch style {
        case .primary: Color.white.opacity(0.18)
        case .plain: Theme.Colors.tint(0.14)
        case .destructive: Theme.Colors.record(0.35)
        case .on: Theme.Colors.accent(0.40)
        }
    }
}
