import SwiftUI

/// Root of the overlay canvas. Switches on `PillState` and animates between states.
struct PillRoot: View {
    let controller: OverlayController

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.clear
            switch controller.state {
            case .hidden:
                EmptyView()
            case .listening:
                ListeningPill(meter: controller.meter, elapsed: controller.elapsed)
                    .transition(.opacity.combined(with: .offset(y: 8)))
            }
        }
        .padding(.bottom, OverlayController.bottomInset)
        .frame(width: OverlayController.canvasSize.width, height: OverlayController.canvasSize.height)
        .animation(.easeOut(duration: 0.16), value: controller.state)
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
}
