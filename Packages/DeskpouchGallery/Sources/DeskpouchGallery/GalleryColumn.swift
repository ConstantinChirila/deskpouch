import AppKit
import DeskpouchCore
import SwiftUI

/// The left side: search, kind chips, and every row grouped by day.
struct GalleryColumn: View {
    let controller: GalleryWindowController
    @FocusState private var searching: Bool

    static let width: CGFloat = 300
    /// Kinds with a chip, in order. Meetings and conversions join when those tools exist.
    static let kinds: [HistoryKind] = [.screenshot, .recording, .text, .color]

    private var model: GalleryModel { controller.model }

    var body: some View {
        VStack(spacing: 10) {
            search
            chips
            filters
                // Above the list, which is drawn after it: the dropdowns hang over the first rows.
                .zIndex(1)
            if !model.missing.isEmpty { missingLine }
            list
        }
        .frame(width: Self.width)
        .onChange(of: controller.ui.searchFocusRequests) { searching = true }
    }

    private var search: some View {
        HStack(spacing: 8) {
            SearchIcon()
                .stroke(style: .icon(1.6))
                .foregroundStyle(Theme.Colors.textTertiary)
                .frame(width: 13, height: 13)
            TextField("Search", text: Binding(get: { model.query.text }, set: { model.query.text = $0 }))
                .textFieldStyle(.plain)
                .font(.dp(13))
                .focused($searching)
            Text("⌘F")
                .font(.dp(11))
                .foregroundStyle(Theme.Colors.textFaint)
                .opacity(searching || !model.query.text.isEmpty ? 0 : 1)
        }
        .padding(.horizontal, 12)
        .frame(height: 34)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.well, style: .continuous).fill(Theme.Colors.well))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.well, style: .continuous)
                .strokeBorder(searching ? Theme.Colors.accent(0.45) : Theme.Colors.tint(0.08), lineWidth: 1)
        )
    }

    private var chips: some View {
        FlowLayout(spacing: 6) {
            KindChip(label: "All", count: model.counts.values.reduce(0, +), selected: model.query.kinds == nil) {
                model.query.kinds = nil
            }
            ForEach(Self.kinds, id: \.self) { kind in
                KindChip(label: GalleryText.kindLabel(kind), count: model.counts[kind] ?? 0, selected: model.query.kinds == [kind]) {
                    model.query.kinds = [kind]
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Starred, when, and where it was pasted. The last one only when something was pasted somewhere.
    private var filters: some View {
        HStack(spacing: 6) {
            Button { model.query.starredOnly.toggle() } label: {
                HStack(spacing: 5) {
                    StarShape().fill(model.query.starredOnly ? Theme.Colors.accentHigh : Theme.Colors.textSecondary).frame(width: 10, height: 10)
                    Text("Starred").font(.dp(12, model.query.starredOnly ? .medium : .regular))
                }
                .fixedSize()
                .foregroundStyle(model.query.starredOnly ? Theme.Colors.accentHigh : Theme.Colors.textSecondary)
                .padding(.horizontal, 10)
                .frame(height: 26)
                .background(Capsule().fill(model.query.starredOnly ? Theme.Colors.accent(0.16) : Theme.Colors.tint(0.04)))
                .overlay(Capsule().strokeBorder(model.query.starredOnly ? Theme.Colors.accent(0.40) : Theme.Colors.tint(0.12), lineWidth: 1))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Starred only")
            .accessibilityAddTraits(model.query.starredOnly ? .isSelected : [])

            MenuChip(
                label: model.datePreset.label, active: model.datePreset != .any, isOpen: controller.ui.openMenu == .date,
                options: GalleryDatePreset.allCases.map { (title: $0.label, selected: $0 == model.datePreset) },
                toggle: { controller.ui.openMenu = controller.ui.openMenu == .date ? nil : .date },
                pick: { index in
                    model.datePreset = GalleryDatePreset.allCases[index]
                    controller.ui.openMenu = nil
                }
            )
            if !model.pastedApps.isEmpty {
                let apps = model.pastedApps
                MenuChip(
                    label: model.query.pastedInto.map { "Into \($0)" } ?? "Pasted anywhere", active: model.query.pastedInto != nil,
                    isOpen: controller.ui.openMenu == .pastedInto,
                    options: [(title: "Pasted anywhere", selected: model.query.pastedInto == nil)]
                        + apps.map { (title: $0, selected: $0 == model.query.pastedInto) },
                    toggle: { controller.ui.openMenu = controller.ui.openMenu == .pastedInto ? nil : .pastedInto },
                    pick: { index in
                        model.query.pastedInto = index == 0 ? nil : apps[index - 1]
                        controller.ui.openMenu = nil
                    }
                )
            }
            Spacer(minLength: 0)
        }
    }

    private var missingLine: some View {
        HStack(spacing: 6) {
            Circle().fill(Theme.Colors.record).frame(width: 6, height: 6)
            Text(model.missing.count == 1 ? "1 file missing" : "\(model.missing.count) files missing")
                .foregroundStyle(Theme.Colors.textSecondary)
            Spacer(minLength: 8)
            Button("Clean up") { model.requestCleanUp() }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.Colors.accentHigh)
        }
        .font(.dp(12))
        .padding(.horizontal, 8)
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4, pinnedViews: [.sectionHeaders]) {
                    ForEach(DayGroup.sections(model.items, date: \.createdAt)) { section in
                        Section {
                            ForEach(section.items) { item in
                                GalleryTile(
                                    item: item, selected: model.selectedIDs.contains(item.id),
                                    focused: model.focused?.id == item.id, missing: model.missing.contains(item.id),
                                    swatch: item.kind == .color ? GalleryText.color(hex: controller.actions.swatchHex(item)) : nil,
                                    thumbnails: controller.thumbnails
                                )
                                .id(item.id)
                                .overlay {
                                    TileMouse(
                                        click: { count, flags in controller.tileClicked(item, count: count, flags: flags) },
                                        drag: { controller.dragPayloads(startingAt: item) }
                                    )
                                }
                                .onAppear { if item.id == model.items.last?.id { model.loadMore() } }
                            }
                        } header: {
                            Text(section.label.uppercased())
                                .font(.dp(10, .semibold))
                                .tracking(0.8)
                                .foregroundStyle(Theme.Colors.textTertiary)
                                .padding(.horizontal, 8)
                                .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)
                                .background(Theme.Colors.panelBottom.opacity(0.94))
                        }
                    }
                    if model.items.isEmpty {
                        EmptyColumn(filtered: model.isFiltered)
                    }
                }
                .padding(.trailing, 4)
            }
            .scrollIndicators(.never)
            .onChange(of: model.focused?.id) { _, id in
                guard let id else { return }
                withAnimation(.easeOut(duration: 0.12)) { proxy.scrollTo(id) }
            }
        }
    }
}

/// A chip that opens a short list under itself, in the app's own style instead of a system menu. Amber while it
/// holds anything but its default.
private struct MenuChip: View {
    let label: String
    let active: Bool
    let isOpen: Bool
    let options: [(title: String, selected: Bool)]
    let toggle: @MainActor () -> Void
    let pick: @MainActor (Int) -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 5) {
                Text(label)
                    .font(.dp(12, active ? .medium : .regular))
                    .lineLimit(1)
                ChevronIcon()
                    .stroke(style: .icon(1.4))
                    .frame(width: 8, height: 8)
                    .rotationEffect(.degrees(isOpen ? 180 : 0))
            }
            .foregroundStyle(active ? Theme.Colors.accentHigh : Theme.Colors.textSecondary)
            .padding(.horizontal, 10)
            .frame(height: 26)
            .frame(maxWidth: 130)
            .fixedSize(horizontal: true, vertical: false)
            .background(Capsule().fill(active ? Theme.Colors.accent(0.16) : Theme.Colors.tint(0.04)))
            .overlay(Capsule().strokeBorder(active || isOpen ? Theme.Colors.accent(0.40) : Theme.Colors.tint(0.12), lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .overlay(alignment: .topLeading) {
            if isOpen {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                        MenuRow(title: option.title, selected: option.selected) { pick(index) }
                    }
                }
                .padding(4)
                .frame(width: 180, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous).fill(Theme.Colors.card))
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous).strokeBorder(Theme.Colors.tint(0.14), lineWidth: 1))
                .shadow(color: .black.opacity(0.5), radius: 14, y: 8)
                .offset(y: 32)
                .transition(.opacity.combined(with: .offset(y: -4)))
            }
        }
        .animation(.easeOut(duration: 0.12), value: isOpen)
    }
}

private struct MenuRow: View {
    let title: String
    let selected: Bool
    let action: @MainActor () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.dp(12, selected ? .medium : .regular))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 4)
                if selected {
                    CheckIcon().stroke(style: .icon(2)).frame(width: 9, height: 9)
                }
            }
            .foregroundStyle(selected ? Theme.Colors.accentHigh : Theme.Colors.text)
            .padding(.horizontal, 8)
            .frame(height: 28)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous).fill(Theme.Colors.tint(hovering ? 0.08 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Kind filter pill with its count. Selected: the chip's amber treatment.
private struct KindChip: View {
    let label: String
    let count: Int
    let selected: Bool
    let action: @MainActor () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(label).font(.dp(12, selected ? .medium : .regular))
                Text("\(count)")
                    .font(.dp(11))
                    .monospacedDigit()
                    .opacity(0.6)
            }
            .fixedSize()
            .foregroundStyle(selected ? Theme.Colors.accentHigh : Theme.Colors.textSecondary)
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(Capsule().fill(selected ? Theme.Colors.accent(0.16) : Theme.Colors.tint(0.04)))
            .overlay(Capsule().strokeBorder(selected ? Theme.Colors.accent(0.40) : Theme.Colors.tint(0.12), lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(label), \(count)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct EmptyColumn: View {
    let filtered: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(filtered ? "Nothing matches" : "Nothing captured yet")
                .font(.dp(13, .medium))
            Text(filtered ? "Try another word, or the All chip." : "⌘⇧2 takes a screenshot, ⌘⇧6 records the screen, hold Right Option to dictate.")
                .font(.dp(12))
                .foregroundStyle(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
    }
}

/// One row: a real thumbnail (or a glyph for text, a swatch for a colour), title and meta.
struct GalleryTile: View {
    let item: HistoryItem
    let selected: Bool
    /// The row in the preview; brighter than the rest of a multi-selection.
    let focused: Bool
    /// The file is gone: dimmed, and the meta line says so.
    let missing: Bool
    /// A colour row's colour.
    let swatch: Color?
    let thumbnails: ThumbnailCache
    @State private var hovering = false

    static let thumbSize = CGSize(width: 72, height: 48)

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
        HStack(spacing: 10) {
            thumb
                .opacity(missing ? 0.4 : 1)
            VStack(alignment: .leading, spacing: 3) {
                Text(GalleryText.title(item))
                    .font(.dp(13, .medium))
                    .lineLimit(item.text != nil && item.kind != .color ? 2 : 1)
                    .truncationMode(item.text == nil ? .middle : .tail)
                Text(missing ? GalleryText.meta(item) + " · file missing" : GalleryText.meta(item))
                    .font(.dp(11))
                    .foregroundStyle(missing ? Theme.Colors.record.opacity(0.85) : Theme.Colors.textTertiary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .opacity(missing ? 0.55 : 1)
            if item.starred {
                StarShape()
                    .fill(Theme.Colors.accentHigh)
                    .frame(width: 11, height: 11)
                    .accessibilityLabel("Starred")
            }
        }
        .padding(6)
        .padding(.trailing, 4)
        .background(shape.fill(selected ? Theme.Colors.accent(focused ? 0.16 : 0.10) : Theme.Colors.tint(hovering ? 0.05 : 0)))
        .overlay(shape.strokeBorder(selected ? Theme.Colors.accent(focused ? 0.45 : 0.25) : .clear, lineWidth: 1))
        .contentShape(shape)
        .onHover { hovering = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder
    private var thumb: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
        if item.kind == .color {
            shape.fill(swatch ?? Theme.Colors.well)
                .overlay(shape.strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
                .frame(width: Self.thumbSize.width, height: Self.thumbSize.height)
        } else if item.text != nil {
            MicIcon()
                .stroke(style: .icon(1.7))
                .foregroundStyle(Theme.Colors.accentHigh)
                .frame(width: 16, height: 16)
                .frame(width: Self.thumbSize.width, height: Self.thumbSize.height)
                .background(shape.fill(Theme.Colors.accent(0.12)))
                .overlay(shape.strokeBorder(Theme.Colors.accent(0.22), lineWidth: 1))
        } else {
            ZStack(alignment: .bottomTrailing) {
                shape.fill(LinearGradient(colors: [Color(hex: 0x3B42_52), Color(hex: 0x2226_2F)], startPoint: .topLeading, endPoint: .bottomTrailing))
                if let url = item.thumbURL ?? item.fileURL, let frame = thumbnails.image(for: url) {
                    Image(decorative: frame, scale: 2)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: Self.thumbSize.width, height: Self.thumbSize.height)
                        .clipShape(shape)
                        .transition(.opacity)
                }
                if let duration = item.duration {
                    Text(TimeFormat.minutesSeconds(duration))
                        .font(.dp(9))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .frame(height: 13)
                        .background(RoundedRectangle(cornerRadius: 3).fill(Color.black.opacity(0.6)))
                        .padding([.trailing, .bottom], 3)
                }
            }
            .frame(width: Self.thumbSize.width, height: Self.thumbSize.height)
            .overlay(shape.strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
        }
    }
}

/// Five-point star, filled.
struct StarShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let centre = CGPoint(x: rect.midX, y: rect.midY)
        let outer = min(rect.width, rect.height) / 2
        for index in 0..<10 {
            let radius = index.isMultiple(of: 2) ? outer : outer * 0.42
            let angle = Double(index) * .pi / 5 - .pi / 2
            let point = CGPoint(x: centre.x + cos(angle) * radius, y: centre.y + sin(angle) * radius)
            index == 0 ? path.move(to: point) : path.addLine(to: point)
        }
        path.closeSubpath()
        return path
    }
}
