import SwiftUI

/// Hosts third-party Audio Unit effects in series after the equalizer and spatial stage.
struct PluginsSection: View {
    @Environment(PluginHost.self) private var host

    var body: some View {
        VStack(spacing: 8) {
            if host.plugins.isEmpty && host.unavailable.isEmpty {
                EmptyStateView(
                    systemImage: "puzzlepiece.extension",
                    title: "No effects loaded",
                    message: "Add any Audio Unit effect installed on this Mac. Effects run after the equalizer and spatial audio."
                )
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(Array(host.plugins.enumerated()), id: \.element.id) { index, plugin in
                            PluginRow(index: index, plugin: plugin, count: host.plugins.count)
                        }
                        ForEach(host.unavailable) { config in UnavailablePluginRow(config: config) }
                    }
                }
            }
            if let error = host.lastError {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text(error).font(.system(size: 10.5)).lineLimit(2)
                    Spacer()
                    Button { host.lastError = nil } label: { Image(systemName: "xmark") }.buttonStyle(.borderless)
                }
            }
            Spacer(minLength: 0)
            AddPluginMenu()
        }
        .onAppear { if host.available.isEmpty { host.scanComponents() } }
    }
}

private struct PluginRow: View {
    @Environment(PluginHost.self) private var host
    let index: Int
    let plugin: HostedPlugin
    let count: Int

    var body: some View {
        HStack(spacing: 8) {
            Text("\(index + 1)").font(.system(size: 11, weight: .bold).monospacedDigit()).foregroundStyle(.tertiary)
                .frame(width: 14)
            VStack(alignment: .leading, spacing: 1) {
                Text(plugin.config.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                Text(plugin.config.manufacturerName).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            Toggle("Active", isOn: Binding(
                get: { !plugin.config.isBypassed },
                set: { host.setBypassed(plugin, !$0) }
            ))
            .toggleStyle(.switch).controlSize(.mini).labelsHidden()
            .help(plugin.config.isBypassed ? "Bypassed" : "Active")
            Button { host.openEditor(plugin) } label: { Image(systemName: "slider.horizontal.3") }
                .help("Open plugin editor")
            Menu {
                Button("Move Up") { host.move(plugin, by: -1) }.disabled(index == 0)
                Button("Move Down") { host.move(plugin, by: 1) }.disabled(index == count - 1)
                Divider()
                Button("Remove", role: .destructive) { host.remove(plugin) }
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .buttonStyle(.borderless)
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.045)))
        .opacity(plugin.config.isBypassed ? 0.6 : 1)
    }
}

/// A saved plugin that failed to load; its settings are kept until the user removes it.
private struct UnavailablePluginRow: View {
    @Environment(PluginHost.self) private var host
    let config: PluginSlotConfig

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange).frame(width: 14)
            VStack(alignment: .leading, spacing: 1) {
                Text(config.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                Text("Unavailable · \(config.manufacturerName)").font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Retry") { Task { await host.retryUnavailable() } }
            Button("Remove", role: .destructive) { host.removeUnavailable(config) }
        }
        .controlSize(.small)
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.orange.opacity(0.08)))
    }
}

private struct AddPluginMenu: View {
    @Environment(PluginHost.self) private var host

    var body: some View {
        let groups = Dictionary(grouping: host.available, by: \.manufacturerName)
        Menu {
            if groups.isEmpty {
                Text("No Audio Unit effects found")
            }
            ForEach(groups.keys.sorted(), id: \.self) { manufacturer in
                Menu(manufacturer) {
                    ForEach(groups[manufacturer] ?? []) { component in
                        Button(component.name) { Task { await host.add(component) } }
                    }
                }
            }
            Divider()
            Button("Rescan Plugins") { host.scanComponents() }
        } label: {
            Label("Add Effect", systemImage: "plus")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
