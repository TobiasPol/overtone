import SwiftUI

/// AutoEQ headphone correction: search thousands of measured headphones and apply a fix.
struct HeadphonesSection: View {
    @Environment(AppState.self) private var state
    @Environment(AutoEQCatalog.self) private var catalog
    @Environment(AppController.self) private var controller
    @State private var applying: AutoEQEntry.ID?
    @State private var error: String?

    var body: some View {
        @Bindable var catalog = catalog
        VStack(spacing: 10) {
            ActiveCorrectionCard()
            TextField("Search headphones (e.g. HD 650, AirPods Pro)", text: $catalog.query)
                .textFieldStyle(.roundedBorder)
            results
            footer
        }
        .task { await catalog.loadIfNeeded() }
    }

    @ViewBuilder
    private var results: some View {
        switch catalog.state {
        case .loading:
            ProgressView("Loading AutoEQ database…").controlSize(.small).frame(maxHeight: .infinity)
        case let .failed(message):
            VStack(spacing: 8) {
                EmptyStateView(systemImage: "wifi.exclamationmark", title: "Couldn't load AutoEQ", message: message)
                Button("Try Again") { Task { await catalog.refresh() } }.controlSize(.small)
            }
            .frame(maxHeight: .infinity)
        default:
            if catalog.query.isEmpty {
                EmptyStateView(
                    systemImage: "headphones",
                    title: "\(catalog.entries.count.formatted()) headphone profiles",
                    message: "Search for your model to flatten its frequency response using measurements from the AutoEQ project."
                )
                .frame(maxHeight: .infinity)
            } else {
                resultList
            }
        }
    }

    private var resultList: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(catalog.results) { entry in
                    Button { apply(entry) } label: { row(entry) }
                        .buttonStyle(.plain)
                }
                if catalog.results.isEmpty {
                    Text("No matches").captionStyle().padding(.top, 20)
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    private func row(_ entry: AutoEQEntry) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.name).font(.system(size: 12)).lineLimit(1)
                Text(entry.detail).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if applying == entry.id {
                ProgressView().controlSize(.mini)
            } else if state.correction.profileName == entry.name && state.correction.source == entry.detail {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.04)))
        .contentShape(Rectangle())
    }

    private var footer: some View {
        HStack {
            Button("Import File…") { controller.importCorrectionFile() }
            Spacer()
            if let error {
                Text(error).font(.system(size: 10)).foregroundStyle(.orange).lineLimit(1)
            } else {
                Link("Data: AutoEQ project", destination: URL(string: "https://github.com/jaakkopasanen/AutoEq")!)
                    .font(.system(size: 10))
            }
        }
        .controlSize(.small)
    }

    private func apply(_ entry: AutoEQEntry) {
        applying = entry.id
        error = nil
        Task {
            do {
                try await controller.applyAutoEQ(entry)
            } catch {
                self.error = "Couldn't download \(entry.name)"
            }
            applying = nil
        }
    }
}

private struct ActiveCorrectionCard: View {
    @Environment(AppState.self) private var state
    @Environment(AppController.self) private var controller

    var body: some View {
        @Bindable var state = state
        if let name = state.correction.profileName, !state.correction.filters.isEmpty {
            SectionCard(title: "Headphone Correction", systemImage: "headphones") {
                Toggle("Correction", isOn: $state.correction.isEnabled).toggleStyle(.switch).controlSize(.mini).labelsHidden()
            } content: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    Text(
                        "\(state.correction.source ?? "") · \(state.correction.filters.count) filters · preamp \(Format.gain(state.correction.preamp)) dB"
                    )
                    .captionStyle().lineLimit(1)
                }
                HStack {
                    Button("Edit in Expert EQ") { controller.editCorrectionInExpertEQ() }
                    Spacer()
                    Button("Remove", role: .destructive) { state.correction = HeadphoneCorrection() }
                }
                .controlSize(.small)
            }
        }
    }
}
