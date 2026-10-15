import SwiftUI

/// The popover: header, section tabs, the selected section, and output controls.
struct MenuBarView: View {
    @Environment(AppState.self) private var state

    private static let contentHeight: CGFloat = 372

    var body: some View {
        @Bindable var state = state
        VStack(spacing: 0) {
            HeaderView()
            StatusBanner()
            SectionTabs(selection: $state.general.selectedSection, hidden: state.general.hiddenSections)
                .padding(.horizontal, 14)
                .padding(.bottom, 10)
            sectionContent
                .padding(.horizontal, 14)
                .frame(height: Self.contentHeight, alignment: .top)
            Divider()
            OutputFooter()
        }
        .frame(width: 388)
    }

    @ViewBuilder
    private var sectionContent: some View {
        switch visibleSelection {
        case .equalizer: EqualizerSection()
        case .effects: ScrollView { EffectsSection() }.scrollIndicators(.never)
        case .headphones: HeadphonesSection()
        case .mixer: MixerSection()
        case .plugins: PluginsSection()
        }
    }

    /// Falls back to the first visible section if the selected one was hidden in Settings.
    private var visibleSelection: AppSection {
        let hidden = state.general.hiddenSections
        if !hidden.contains(state.general.selectedSection) { return state.general.selectedSection }
        return AppSection.allCases.first { !hidden.contains($0) } ?? .equalizer
    }
}

struct SectionTabs: View {
    @Binding var selection: AppSection
    let hidden: Set<AppSection>

    var body: some View {
        HStack(spacing: 2) {
            ForEach(AppSection.allCases.filter { !hidden.contains($0) }) { section in
                Button { selection = section } label: {
                    VStack(spacing: 3) {
                        Image(systemName: section.symbolName).font(.system(size: 13, weight: .medium))
                        Text(section.label).font(.system(size: 9.5, weight: .medium))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .foregroundStyle(selection == section ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(selection == section ? Color.primary.opacity(0.08) : .clear)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(section.label)
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.primary.opacity(0.04)))
    }
}
