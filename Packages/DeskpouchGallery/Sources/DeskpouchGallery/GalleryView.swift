import DeskpouchCore
import SwiftUI

/// The window's content: header, the column and the preview side by side, and the delete prompt over both.
struct GalleryView: View {
    let controller: GalleryWindowController

    private var model: GalleryModel { controller.model }

    var body: some View {
        VStack(spacing: 14) {
            header
            HStack(alignment: .top, spacing: 16) {
                if !controller.ui.filled {
                    GalleryColumn(controller: controller)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }
                GalleryPreview(controller: controller)
            }
            .animation(.easeOut(duration: 0.18), value: controller.ui.filled)
            .allowsHitTesting(model.pendingDelete == nil)
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.panelGradient)
        .overlay(alignment: .top) {
            Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)
        }
        .overlay {
            if let pending = model.pendingDelete {
                DeletePrompt(count: pending.count, model: model)
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
            }
        }
        .animation(.easeOut(duration: 0.15), value: model.pendingDelete != nil)
        .foregroundStyle(Theme.Colors.text)
        .ignoresSafeArea()
    }

    private var header: some View {
        HStack(spacing: 12) {
            PouchIcon()
                .stroke(style: .icon(1.6))
                .foregroundStyle(Theme.Colors.accentHigh)
                .frame(width: 16, height: 16)
                .frame(width: 32, height: 32)
                .background(RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous).fill(Theme.Colors.accent(0.14)))
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous).strokeBorder(Theme.Colors.accent(0.25), lineWidth: 1))
            VStack(alignment: .leading, spacing: 1) {
                Text("Gallery")
                    .font(.dp(15, .semibold))
                    .tracking(-0.15)
                Text(subtitle)
                    .font(.dp(11))
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
            Spacer(minLength: 12)
            Button { controller.close() } label: {
                CloseIcon()
                    .stroke(style: .icon(1.6))
                    .foregroundStyle(Theme.Colors.text.opacity(0.7))
                    .frame(width: 10, height: 10)
                    .frame(width: 28, height: 28)
                    .background(RoundedRectangle(cornerRadius: Theme.Radius.keycap, style: .continuous).fill(Theme.Colors.tint(0.06)))
                    .overlay(RoundedRectangle(cornerRadius: Theme.Radius.keycap, style: .continuous).strokeBorder(Theme.Colors.tint(0.12), lineWidth: 1))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Close (Esc)")
            .accessibilityLabel("Close")
        }
        .frame(height: 36)
        .contentShape(Rectangle())
        .gesture(WindowDragGesture())
    }

    private var subtitle: String {
        let items = model.total == 1 ? "1 item" : "\(model.total) items"
        return model.query == HistoryQuery() ? items : "\(items) match"
    }
}

/// Asked before a large delete. The files go to the Trash, so this is the only warning.
private struct DeletePrompt: View {
    let count: Int
    let model: GalleryModel

    var body: some View {
        ZStack {
            Color.black.opacity(0.55)
                .onTapGesture { model.cancelDelete() }
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 12) {
                    Circle()
                        .fill(Theme.Colors.record)
                        .frame(width: 10, height: 10)
                        .shadow(color: Theme.Colors.record(0.9), radius: 6)
                        .padding(.top, 5)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Move \(count) items to the Trash?")
                            .font(.dp(15, .semibold))
                        Text("They leave Deskpouch and their files go to the Trash, where they can still be put back.")
                            .font(.dp(13))
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                HStack(spacing: 8) {
                    Spacer(minLength: 8)
                    GalleryButton(title: "Keep them", hint: "Esc", style: .plain) { model.cancelDelete() }
                    GalleryButton(title: "Move to Trash", hint: "↩", style: .destructive) { model.confirmDelete() }
                }
            }
            .padding(20)
            .frame(width: 400)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).fill(Theme.panelGradient))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).strokeBorder(Theme.Colors.record(0.30), lineWidth: 1))
            .shadow(color: .black.opacity(0.6), radius: 25, y: 16)
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }
}
