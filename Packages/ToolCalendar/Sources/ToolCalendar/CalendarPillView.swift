import AppKit
import DeskpouchCore
import SwiftUI

/// The stack of calendar pills (mock "Pill A": the dictation pill's anatomy), newest nearest the anchor at the
/// top right, plus the one-line message pill ⌃⌘J shows when there is no call.
struct CalendarPillStackView: View {
    let model: CalendarModel
    let actions: PillActions

    var body: some View {
        VStack(alignment: .trailing, spacing: 10) {
            if let message = model.message {
                MessagePill(text: message)
                    .gesture(drag)
            }
            ForEach(model.pills.pills) { pill in
                CalendarPillView(pill: pill, model: model, drag: drag, reset: actions.reset)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(CalendarPillController.margin)
        .fixedSize()
        .animation(.spring(duration: 0.28, bounce: 0.15), value: model.pills)
        .foregroundStyle(Theme.Colors.text)
    }

    /// Moves the whole stack. Reads the pointer in screen space: the window moves under the gesture, so
    /// SwiftUI's own translation would drift.
    private var drag: some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { _ in actions.dragChanged() }
            .onEnded { _ in actions.dragEnded() }
    }
}

private struct CalendarPillView<G: Gesture>: View {
    let pill: PillStack.Pill
    let model: CalendarModel
    let drag: G
    let reset: @MainActor () -> Void
    @State private var openTask: Task<Void, Never>?

    var body: some View {
        // The countdown text moves by the minute; the heads-up hairline animates on its own.
        TimelineView(.periodic(from: .now, by: 15)) { context in
            content(now: context.date)
        }
    }

    private func content(now: Date) -> some View {
        let started = pill.event.start <= now
        let ring: Color = pill.kind == .headsUp ? Theme.Colors.tint(1) : (started ? Theme.Colors.ok : Theme.Colors.accent)
        let ringAlpha = pill.kind == .headsUp ? 0.16 : 0.4
        let subtitle = PillStack.subtitle(pill, now: now, text: CalendarText())
        let parts = subtitle.components(separatedBy: " · ")
        return HStack(spacing: 12) {
            tile(ring: ring)
            VStack(alignment: .leading, spacing: 2) {
                Text(pill.event.title)
                    .font(.dp(13, .medium))
                    .lineLimit(1)
                (Text(parts.first ?? "").foregroundColor(pill.kind == .headsUp ? Theme.Colors.textTertiary : ring)
                    + Text(parts.count > 1 ? " · " + parts.dropFirst().joined(separator: " · ") : "").foregroundColor(Theme.Colors.textTertiary))
                    .font(.dp(11))
                    .monospacedDigit()
                    .lineLimit(1)
            }
            .frame(minWidth: 150, maxWidth: 240, alignment: .leading)
            HStack(spacing: 8) {
                if pill.event.joinable {
                    JoinButton { model.join(pill.event) }
                }
                CloseButton { model.pillHandler?(.dismiss(pill.id)) }
            }
            .fixedSize()
            .padding(.leading, 6)
        }
        .padding(.leading, 10)
        .padding(.trailing, 12)
        .frame(height: 52)
        .background(Capsule().fill(Theme.panelGradient))
        .overlay(Capsule().strokeBorder(ring.opacity(ringAlpha), lineWidth: 1))
        .overlay(alignment: .bottom) {
            if pill.kind == .headsUp {
                DrainLine(expiresAt: pill.expiresAt).padding(.horizontal, 22)
            }
        }
        .background(Capsule().stroke(ring.opacity(0.07), lineWidth: 12))
        .shadow(color: .black.opacity(0.6), radius: 25, y: 20)
        .contentShape(Capsule())
        .onHover { inside in model.pillHandler?(inside ? .hold(pill.id) : .release(pill.id)) }
        .onTapGesture { tapped() }
        .gesture(drag)
        .help("Drag to move · double-click to reset")
    }

    private func tile(ring: Color) -> some View {
        ZStack {
            Circle().fill(ring.opacity(0.12))
            Group {
                if pill.event.joinable {
                    CameraIcon().stroke(style: .icon(1.5))
                } else {
                    BellIcon().stroke(style: .icon(1.5))
                }
            }
            .foregroundStyle(pill.kind == .headsUp ? Theme.Colors.textSecondary : ring)
            .frame(width: 16, height: 16)
        }
        .frame(width: 32, height: 32)
    }

    /// One click opens the Calendar view (sticky pills only), a double-click resets the position. The single
    /// click waits out the double-click interval so the two do not both fire (one gesture, clickCount read from
    /// the event: two tap gestures delay every click).
    private func tapped() {
        if NSApp.currentEvent?.clickCount ?? 1 >= 2 {
            openTask?.cancel()
            reset()
            return
        }
        guard pill.kind == .sticky else { return }
        openTask?.cancel()
        openTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(NSEvent.doubleClickInterval))
            guard !Task.isCancelled else { return }
            model.pillHandler?(.open)
        }
    }
}

/// A heads-up's remaining life as a hairline along the bottom: one linear animation to empty, refilled while
/// the pointer holds the pill (`expiresAt` nil) and restarted when it lets go. The animation is attached to the
/// fill alone: a `withAnimation` block would also catch the window's first layout and slide the whole pill.
private struct DrainLine: View {
    let expiresAt: Date?
    @State private var fraction: CGFloat = 1
    @State private var duration: Double = 0

    var body: some View {
        GeometryReader { geo in
            Capsule().fill(Theme.Colors.tint(0.08))
                .overlay(alignment: .leading) {
                    Capsule().fill(Theme.Colors.textFaint)
                        .frame(width: geo.size.width * fraction)
                        .animation(.linear(duration: duration), value: fraction)
                }
        }
        .frame(height: 2)
        .onAppear(perform: restart)
        .onChange(of: expiresAt) { restart() }
    }

    private func restart() {
        guard let expiresAt else {
            duration = 0.2
            fraction = 1
            return
        }
        let remaining = max(0, expiresAt.timeIntervalSinceNow)
        duration = 0
        fraction = CGFloat(remaining / PillStack.headsUpLife)
        DispatchQueue.main.async {
            duration = remaining
            fraction = 0
        }
    }
}

private struct MessagePill: View {
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            CameraIcon().stroke(style: .icon(1.5))
                .foregroundStyle(Theme.Colors.textSecondary)
                .frame(width: 16, height: 16)
                .overlay(Path { p in
                    p.move(to: CGPoint(x: 1, y: 1)); p.addLine(to: CGPoint(x: 15, y: 15))
                }.stroke(Theme.Colors.textSecondary, style: .icon(1.5)))
                .frame(width: 32, height: 32)
                .background(Circle().fill(Theme.Colors.tint(0.08)))
            Text(text).font(.dp(13, .medium))
        }
        .padding(.leading, 10)
        .padding(.trailing, 22)
        .frame(height: 52)
        .background(Capsule().fill(Theme.panelGradient))
        .overlay(Capsule().strokeBorder(Theme.Colors.tint(0.16), lineWidth: 1))
        .shadow(color: .black.opacity(0.6), radius: 25, y: 20)
    }
}

private struct JoinButton: View {
    let action: @MainActor () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                CameraIcon().stroke(style: .icon(1.5)).frame(width: 14, height: 14)
                Text("Join").font(.dp(12, .semibold))
            }
            .foregroundStyle(Theme.Colors.accentInk)
            .padding(.horizontal, 14)
            .frame(height: 30)
            .background(Capsule().fill(LinearGradient(colors: [Theme.Colors.accentHigh, Theme.Colors.accent], startPoint: .top, endPoint: .bottom)))
            .shadow(color: Theme.Colors.accent(0.35), radius: 7, y: 4)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help("Join the call (⌃⌘J)")
        .accessibilityLabel("Join")
    }
}

private struct CloseButton: View {
    let action: @MainActor () -> Void

    var body: some View {
        Button(action: action) {
            CloseIcon().stroke(style: .icon(1.6))
                .foregroundStyle(Theme.Colors.textSecondary)
                .frame(width: 10, height: 10)
                .frame(width: 28, height: 28)
                .background(Circle().fill(Theme.Colors.tint(0.06)))
                .overlay(Circle().strokeBorder(Theme.Colors.tint(0.14), lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help("Dismiss")
        .accessibilityLabel("Dismiss")
    }
}
