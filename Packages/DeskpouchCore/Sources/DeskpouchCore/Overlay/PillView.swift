import SwiftUI

/// Root of the overlay canvas. Switches on `PillState` and animates between states.
struct PillRoot: View {
    let controller: OverlayController

    var body: some View {
        ZStack(alignment: .top) {
            Color.clear
            switch controller.state {
            case .hidden:
                EmptyView()
            case .listening:
                ListeningPill(meter: controller.meter, elapsed: controller.elapsed)
                    .transition(.opacity.combined(with: .offset(y: -8)))
            case .preparing(let message):
                PreparingPill(message: message)
                    .transition(.opacity.combined(with: .offset(y: -8)))
            case .transcribing(let detail):
                TranscribingPill(detail: detail)
                    .transition(.opacity.combined(with: .offset(y: -8)))
            case .pasted(let target):
                PastedPill(title: "Pasted into \(target)", hint: "⌘Z to undo")
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
            case .copied:
                PastedPill(title: "Copied", hint: "⌘V to paste")
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
            case .saved(let name, let copied):
                PastedPill(title: copied ? "Saved and copied" : "Saved", hint: name)
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
            case .recording(let detail):
                RecordingPill(elapsed: controller.elapsed, detail: detail, stop: { controller.stopRequested() })
                    .transition(.opacity.combined(with: .offset(y: -8)))
            case .failed(let message):
                FailedPill(message: message)
                    .transition(.opacity.combined(with: .offset(y: -8)))
            }
        }
        .padding(.top, OverlayController.topInset)
        .frame(width: controller.canvasSize.width, height: controller.canvasSize.height)
        .animation(.easeOut(duration: 0.2), value: controller.state)
    }
}

/// Listening: amber ring, pulsing dot, 25 bar meter, timer.
struct ListeningPill: View {
    let meter: LevelMeterModel
    let elapsed: TimeInterval

    var body: some View {
        HStack(spacing: 16) {
            PulsingDot(color: Theme.Colors.accent)
            MeterView(levels: meter.bars)
            Text(TimeFormat.minutesSeconds(elapsed))
                .font(.dp(12))
                .monospacedDigit()
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .padding(.leading, 18)
        .padding(.trailing, 22)
        .frame(height: 52)
        .modifier(PillChrome(ring: Theme.Colors.accent))
    }
}

/// Preparing: amber ring, pulsing dot, message, sweeping hairline.
struct PreparingPill: View {
    let message: String

    var body: some View {
        HStack(spacing: 14) {
            PulsingDot(color: Theme.Colors.accent)
            Text(message)
                .font(.dp(13, .medium))
                .foregroundStyle(Theme.Colors.text)
            ProgressHairline(indeterminate: true)
        }
        .padding(.leading, 18)
        .padding(.trailing, 22)
        .frame(height: 52)
        .modifier(PillChrome(ring: Theme.Colors.accent))
    }
}

/// Transcribing: amber ring, sweeping hairline, "Transcribing", engine name.
struct TranscribingPill: View {
    let detail: String

    var body: some View {
        HStack(spacing: 14) {
            ProgressHairline(indeterminate: true)
            Text("Transcribing")
                .font(.dp(13, .medium))
                .foregroundStyle(Theme.Colors.text)
            Rectangle().fill(Theme.Colors.tint(0.15)).frame(width: 1, height: 18)
            Text(detail)
                .font(.dp(12))
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .padding(.leading, 20)
        .padding(.trailing, 22)
        .frame(height: 52)
        .modifier(PillChrome(ring: Theme.Colors.accent))
    }
}

/// Pasted or copied: mint ring, check disc, title, hint.
struct PastedPill: View {
    let title: String
    let hint: String

    var body: some View {
        HStack(spacing: 14) {
            CheckIcon()
                .stroke(style: .icon(2.4))
                .foregroundStyle(Theme.Colors.bg)
                .frame(width: 14, height: 14)
                .frame(width: 24, height: 24)
                .background(Circle().fill(Theme.Colors.ok))
                .shadow(color: Theme.Colors.ok(0.5), radius: 7)
            Text(title)
                .font(.dp(14, .medium))
                .foregroundStyle(Theme.Colors.text)
            Rectangle().fill(Theme.Colors.tint(0.15)).frame(width: 1, height: 18)
            Text(hint)
                .font(.dp(12))
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .padding(.leading, 16)
        .padding(.trailing, 22)
        .frame(height: 52)
        .modifier(PillChrome(ring: Theme.Colors.ok))
    }
}

/// Recording: record ring, pulsing dot, timer, capture detail, Stop. Dims after a few seconds; hover restores it.
struct RecordingPill: View {
    let elapsed: TimeInterval
    let detail: String
    let stop: @MainActor () -> Void
    @State private var dimmed = false
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 14) {
            PulsingDot(color: Theme.Colors.record)
            Text(TimeFormat.minutesSeconds(elapsed))
                .font(.dp(15, .medium))
                .monospacedDigit()
                .foregroundStyle(Theme.Colors.text)
            if !detail.isEmpty {
                Text(detail)
                    .font(.dp(12))
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .lineLimit(1)
            }
            Rectangle().fill(Theme.Colors.tint(0.15)).frame(width: 1, height: 18)
            Button(action: stop) {
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 2).fill(Theme.Colors.bg).frame(width: 10, height: 10)
                    Text("Stop").font(.dp(13, .semibold))
                }
                .foregroundStyle(Theme.Colors.bg)
                .padding(.horizontal, 14)
                .frame(height: 34)
                .background(Capsule().fill(Theme.Colors.text))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .help("Stop recording")
        }
        .padding(.leading, 18)
        .padding(.trailing, 10)
        .frame(height: 52)
        .modifier(PillChrome(ring: Theme.Colors.record))
        .opacity(dimmed && !hovering ? 0.55 : 1)
        .animation(.easeOut(duration: 0.3), value: dimmed)
        .animation(.easeOut(duration: 0.15), value: hovering)
        .onHover { hovering = $0 }
        .task {
            try? await Task.sleep(for: .seconds(4))
            dimmed = true
        }
    }
}

/// Failed: record ring, message.
struct FailedPill: View {
    let message: String

    var body: some View {
        HStack(spacing: 14) {
            Circle()
                .fill(Theme.Colors.record)
                .frame(width: 12, height: 12)
                .shadow(color: Theme.Colors.record(0.9), radius: 7)
            Text(message)
                .font(.dp(13, .medium))
                .foregroundStyle(Theme.Colors.text)
        }
        .padding(.leading, 18)
        .padding(.trailing, 22)
        .frame(height: 52)
        .modifier(PillChrome(ring: Theme.Colors.record))
    }
}

/// Shared pill surface: panel gradient, 1px ring at 0.40, 6px outer ring at 0.07, inner top highlight, drop shadow.
struct PillChrome: ViewModifier {
    let ring: Color

    func body(content: Content) -> some View {
        content
            .background(Capsule().fill(Theme.panelGradient))
            .overlay(Capsule().strokeBorder(ring.opacity(0.40), lineWidth: 1))
            .overlay(alignment: .top) {
                Capsule()
                    .fill(Color.white.opacity(0.08))
                    .frame(height: 1)
                    .padding(.horizontal, 20)
                    .padding(.top, 1)
            }
            .background(Capsule().stroke(ring.opacity(0.07), lineWidth: 6).padding(-3))
            .shadow(color: .black.opacity(0.6), radius: 25, y: 20)
    }
}

/// 40x3 amber hairline. Full when determinate, a sweeping segment when indeterminate.
struct ProgressHairline: View {
    var indeterminate = false
    @State private var sweep = false

    var body: some View {
        ZStack(alignment: .leading) {
            Capsule().fill(Theme.Colors.accent(0.2))
            Capsule()
                .fill(Theme.Colors.accent)
                .frame(width: indeterminate ? 16 : 40)
                .offset(x: indeterminate && sweep ? 24 : 0)
        }
        .frame(width: 40, height: 3)
        .clipShape(Capsule())
        .task(id: indeterminate) {
            sweep = false
            guard indeterminate else { return }
            withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) { sweep = true }
        }
    }
}

struct PulsingDot: View {
    let color: Color
    @State private var on = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 12, height: 12)
            .shadow(color: color.opacity(0.9), radius: 7)
            .scaleEffect(on ? 0.85 : 1)
            .opacity(on ? 0.5 : 1)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                    on = true
                }
            }
    }
}

public enum TimeFormat {
    /// "0:04", "1:12", "12:05".
    public static func minutesSeconds(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval.rounded(.down)))
        return "\(total / 60):" + String(format: "%02d", total % 60)
    }

    /// "0.2s", "1.4s".
    public static func seconds(_ interval: TimeInterval) -> String {
        String(format: "%.1fs", max(0, interval))
    }
}
