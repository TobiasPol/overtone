import SwiftUI

/// A titled group of controls with a subtle rounded background.
struct SectionCard<Accessory: View, Content: View>: View {
    let title: String
    var systemImage: String?
    @ViewBuilder var accessory: () -> Accessory
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage).font(.system(size: 11, weight: .semibold))
                }
                Text(title).font(.system(size: 11, weight: .semibold)).textCase(.uppercase)
                Spacer(minLength: 4)
                accessory()
            }
            .foregroundStyle(.secondary)
            content()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.045)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.primary.opacity(0.06)))
    }
}

extension SectionCard where Accessory == EmptyView {
    init(_ title: String, systemImage: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.init(title: title, systemImage: systemImage, accessory: { EmptyView() }, content: content)
    }
}

/// A labelled horizontal slider with a value readout; double-click the label to reset.
struct ParameterSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var defaultValue: Double?
    var format: (Double) -> String = { String(format: "%.0f", $0) }

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .frame(width: 74, alignment: .leading)
                .onTapGesture(count: 2) { if let defaultValue { value = defaultValue } }
                .help(defaultValue == nil ? "" : "Double-click to reset")
            Slider(value: $value, in: range).controlSize(.small)
            Text(format(value))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 54, alignment: .trailing)
        }
        .font(.system(size: 12))
    }
}

/// Compact numeric text field for parameter entry.
struct NumberField: View {
    @Binding var value: Double
    var width: CGFloat = 52
    var fractionDigits = 0...2

    var body: some View {
        TextField("", value: $value, format: .number.precision(.fractionLength(fractionDigits)).grouping(.never))
            .textFieldStyle(.roundedBorder)
            .controlSize(.small)
            .multilineTextAlignment(.trailing)
            .frame(width: width)
    }
}

/// Centered placeholder for empty lists.
struct EmptyStateView: View {
    let systemImage: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: systemImage).font(.system(size: 26, weight: .light)).foregroundStyle(.tertiary)
            Text(title).font(.system(size: 13, weight: .medium))
            Text(message).captionStyle().multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
}
