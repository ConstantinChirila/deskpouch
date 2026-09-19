import DeskpouchCore
import SwiftUI

/// Bottom-bar controls: play / pause, the playhead's time, the format, and what the export will weigh.
struct TrimToolbar: View {
    let document: TrimDocument

    var body: some View {
        HStack(spacing: 12) {
            Button { document.togglePlayback() } label: {
                Group {
                    if document.isPlaying {
                        PauseGlyph().fill(Theme.Colors.text)
                    } else {
                        PlayGlyph().fill(Theme.Colors.text)
                    }
                }
                .frame(width: 11, height: 12)
                .frame(width: 34, height: 30)
                .background(Capsule().fill(Theme.Colors.tint(0.07)))
                .overlay(Capsule().strokeBorder(Theme.Colors.tint(0.14), lineWidth: 1))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .help(document.isPlaying ? "Pause (Space)" : "Play (Space)")
            .accessibilityLabel(document.isPlaying ? "Pause" : "Play")

            Text(TrimModel.label(document.model.playhead))
                .font(.dp(12, .medium))
                .monospacedDigit()
                .foregroundStyle(Theme.Colors.textSecondary)
                .frame(width: 52, alignment: .leading)

            Rectangle().fill(Theme.Colors.tint(0.12)).frame(width: 1, height: 18)

            Segmented(
                selection: Binding(get: { document.format }, set: { document.format = $0 }),
                options: TrimDocument.Format.allCases, title: \.label
            )

            if let progress = document.exportProgress {
                ProgressBar(fraction: progress)
            } else {
                estimate
            }
        }
    }

    @ViewBuilder
    private var estimate: some View {
        let size = document.estimatedBytes.map { "≈ " + ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file) }
        if document.gifIsLong {
            Text("GIF over 15 s" + (size.map { ": \($0)" } ?? ""))
                .font(.dp(12, .medium))
                .foregroundStyle(Theme.Colors.accentHigh)
        } else {
            Text(size ?? "Measuring")
                .font(.dp(12))
                .monospacedDigit()
                .foregroundStyle(Theme.Colors.textTertiary)
        }
    }
}

/// A flat bar, like the panel's meters.
private struct ProgressBar: View {
    let fraction: Double

    var body: some View {
        ZStack(alignment: .leading) {
            Capsule().fill(Theme.Colors.tint(0.10))
            Capsule().fill(Theme.Colors.accent)
                .frame(width: 96 * min(1, max(0, fraction)))
        }
        .frame(width: 96, height: 4)
        .animation(.linear(duration: 0.15), value: fraction)
        .accessibilityLabel("Writing GIF")
        .accessibilityValue("\(Int(fraction * 100)) percent")
    }
}

private struct PlayGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.1, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.1, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private struct PauseGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let bar = rect.width * 0.34
        var path = Path()
        path.addRoundedRect(in: CGRect(x: rect.minX, y: rect.minY, width: bar, height: rect.height), cornerSize: CGSize(width: 1, height: 1))
        path.addRoundedRect(in: CGRect(x: rect.maxX - bar, y: rect.minY, width: bar, height: rect.height), cornerSize: CGSize(width: 1, height: 1))
        return path
    }
}
