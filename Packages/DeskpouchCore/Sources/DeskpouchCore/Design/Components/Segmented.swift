import SwiftUI

/// Small segmented control: 32 tall well, 24 tall pills. Selected pill uses the chip's amber treatment.
public struct Segmented<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [Value]
    let title: (Value) -> String

    public init(selection: Binding<Value>, options: [Value], title: @escaping (Value) -> String) {
        _selection = selection
        self.options = options
        self.title = title
    }

    public var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.self) { option in
                let on = option == selection
                Button {
                    selection = option
                } label: {
                    Text(title(option))
                        .font(.dp(12, on ? .medium : .regular))
                        .foregroundStyle(on ? Theme.Colors.accentHigh : Theme.Colors.textSecondary)
                        .padding(.horizontal, 10)
                        .frame(height: 24)
                        .background(Capsule().fill(on ? Theme.Colors.accent(0.16) : .clear))
                        .overlay(Capsule().strokeBorder(on ? Theme.Colors.accent(0.40) : .clear, lineWidth: 1))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .frame(height: 32)
        .background(Capsule().fill(Theme.Colors.well))
        .overlay(Capsule().strokeBorder(Theme.Colors.tint(0.08), lineWidth: 1))
        .animation(.easeOut(duration: 0.15), value: selection)
    }
}

/// Search well: 32 tall, magnifier, plain text field.
public struct SearchField: View {
    @Binding var text: String
    let placeholder: String

    public init(text: Binding<String>, placeholder: String = "Search") {
        _text = text
        self.placeholder = placeholder
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.well, style: .continuous)
        HStack(spacing: 8) {
            SearchIcon()
                .stroke(style: .icon(1.6))
                .foregroundStyle(Theme.Colors.textTertiary)
                .frame(width: 14, height: 14)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.dp(12))
                .foregroundStyle(Theme.Colors.text)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Text("Clear").font(.dp(11)).foregroundStyle(Theme.Colors.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 32)
        .background(shape.fill(Theme.Colors.well))
        .overlay(shape.strokeBorder(Theme.Colors.tint(0.08), lineWidth: 1))
    }
}
