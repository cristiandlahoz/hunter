import AppKit
import SwiftUI

struct RootView: View {
    @ObservedObject var store: EnergyStore
    @ObservedObject var serverStore: ServerStore
    @State private var selection: SidebarDestination = .session

    var body: some View {
        HStack(spacing: 0) {
            SidebarView(selection: $selection, store: store)
            Group {
                switch selection {
                case .session:
                    DashboardView(store: store)
                case .applications:
                    ApplicationsView(store: store)
                case .servers:
                    ServersView(store: serverStore)
                case .history:
                    HistoryView(store: store)
                case .battery:
                    BatteryView(store: store)
                }
            }
            .frame(minWidth: 760, maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 984, minHeight: 660)
        .background(WattColors.workspace)
        .onAppear {
            store.start()
            serverStore.start()
        }
    }
}

private enum MenuBarTab: String, CaseIterable, Identifiable {
    case battery = "Battery"
    case servers = "Servers"
    case ai = "AI"

    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .battery: "battery.75percent"
        case .servers: "network"
        case .ai: "sparkles"
        }
    }
}

struct MenuBarView: View {
    @ObservedObject var store: EnergyStore
    @ObservedObject var serverStore: ServerStore
    @ObservedObject var chatGPTUsage: ChatGPTUsageStore
    @Environment(\.openWindow) private var openWindow
    @State private var selectedTab: MenuBarTab = .battery

    var body: some View {
        VStack(spacing: 0) {
            Picker("Section", selection: $selectedTab) {
                ForEach(MenuBarTab.allCases) { tab in
                    Label(tab.rawValue, systemImage: tab.symbol).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(12)

            Divider()

            Group {
                switch selectedTab {
                case .battery:
                    BatteryMenuTab(store: store)
                case .servers:
                    ServersMenuTab(store: serverStore)
                case .ai:
                    ChatGPTMenuUsage(store: chatGPTUsage)
                        .padding(14)
                        .frame(minHeight: 176, alignment: .topLeading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)

            Divider()

            HStack(spacing: 14) {
                Button("Open Hunter") {
                    NSApplication.shared.activate(ignoringOtherApps: true)
                    openWindow(id: "main")
                }
                .buttonStyle(.plain)
                Spacer()
                Button { refreshSelectedTab() } label: { Image(systemName: "arrow.clockwise") }
                    .help("Refresh")
                Button { showSettings() } label: { Image(systemName: "gearshape") }
                    .help("Settings")
                Button("Quit") { HunterAppDelegate.shared?.quitCompletely() }
            }
            .buttonStyle(.plain)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .frame(height: 42)
        }
        .frame(width: 400, height: desiredContentHeight, alignment: .top)
        .background(MenuBarWindowSizer(contentHeight: desiredContentHeight))
    }

    private var desiredContentHeight: CGFloat {
        guard selectedTab == .servers else { return 266 }
        let rowHeight = min(CGFloat(serverStore.servers.count) * 52, 292)
        let messageHeight: CGFloat = (serverStore.errorMessage != nil || serverStore.dependencyMessage != nil) ? 52 : 0
        return max(266, 154 + rowHeight + messageHeight)
    }

    private func refreshSelectedTab() {
        Task {
            switch selectedTab {
            case .battery: await store.refresh()
            case .servers: await serverStore.refresh()
            case .ai: await chatGPTUsage.refresh()
            }
        }
    }

    private func showSettings() {
        NSApplication.shared.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}

private struct MenuBarWindowSizer: NSViewRepresentable {
    let contentHeight: CGFloat

    func makeNSView(context: Context) -> NSView { NSView(frame: .zero) }

    func updateNSView(_ view: NSView, context: Context) {
        guard contentHeight > 0 else { return }
        DispatchQueue.main.async { [weak view] in
            guard let window = view?.window else { return }
            let currentContent = window.contentRect(forFrameRect: window.frame)
            guard abs(currentContent.height - contentHeight) > 1 else { return }
            let targetFrameHeight = window.frameRect(
                forContentRect: NSRect(x: 0, y: 0, width: currentContent.width, height: contentHeight)
            ).height
            var frame = window.frame
            frame.origin.y = frame.maxY - targetFrameHeight
            frame.size.height = targetFrameHeight
            window.setFrame(frame, display: true, animate: false)
        }
    }
}

private struct BatteryMenuTab: View {
    @ObservedObject var store: EnergyStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Label(store.snapshot.isOnAC ? "Power adapter" : "On battery", systemImage: store.snapshot.isOnAC ? "powerplug.fill" : "battery.75percent")
                        .font(.system(size: 13, weight: .semibold))
                    Text(Formatters.time(store.snapshot.timeRemainingMinutes) + (store.snapshot.isOnAC ? "" : " remaining"))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(store.snapshot.percentage)%")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(WattColors.violet)
                    .monospacedDigit()
            }

            HStack(spacing: 0) {
                MenuMetric(label: "POWER", value: store.snapshot.watts.map { String(format: "%.1f W", $0) } ?? "—")
                MenuMetric(label: "HEALTH", value: store.snapshot.healthPercentage.map { "\($0)%" } ?? "—")
                MenuMetric(label: "CYCLES", value: store.snapshot.cycleCount.map(String.init) ?? "—")
            }

            if let session = store.session, !store.snapshot.isOnAC {
                Divider()
                HStack(spacing: 0) {
                    MenuMetric(label: "SESSION", value: Formatters.duration(session.duration))
                    MenuMetric(label: "USED", value: "\(session.percentageDrop)%")
                    MenuMetric(label: "AVG. DRAIN", value: session.drainPerHour.map { String(format: "%.1f%%/h", $0) } ?? "—")
                }
            }
        }
        .padding(14)
        .frame(minHeight: 176, alignment: .top)
    }
}

private struct ServersMenuTab: View {
    @ObservedObject var store: ServerStore

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .lastTextBaseline) {
                Text(Formatters.memory(store.servers.reduce(0) { $0 + $1.memoryBytes }))
                    .font(.system(size: 25, weight: .semibold))
                    .monospacedDigit()
                Text("across \(store.servers.count) server\(store.servers.count == 1 ? "" : "s")")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                let tunnels = store.servers.filter { $0.tunnel != nil }.count
                if tunnels > 0 {
                    Text("\(tunnels) public")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(WattColors.violet)
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 56)

            Divider()

            if store.servers.isEmpty {
                VStack(spacing: 7) {
                    Image(systemName: "network.slash")
                        .font(.system(size: 21))
                        .foregroundStyle(WattColors.secondary)
                    Text(store.isRefreshing ? "Scanning local ports…" : "No development servers found")
                        .font(.system(size: 12, weight: .medium))
                    Text("Start a Vaadin app or another local server.")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 150)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(store.servers.enumerated()), id: \.element.id) { index, server in
                            MenuServerRow(server: server, store: store, isAlternate: !index.isMultiple(of: 2))
                        }
                    }
                }
                .frame(maxHeight: 292)
            }

            if let message = store.errorMessage ?? store.dependencyMessage {
                HStack(spacing: 8) {
                    Text(message)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if store.ngrokPath == nil {
                        Button(store.isInstallingNgrok ? "Installing…" : "Install ngrok") {
                            Task { await store.installNgrok() }
                        }
                        .disabled(store.isInstallingNgrok)
                    } else if message.contains("authentication") {
                        Button("Set up") { store.openNgrokSetup() }
                    }
                }
                .font(.system(size: 10))
                .foregroundStyle(store.errorMessage == nil ? Color.secondary : WattColors.critical)
                .padding(10)
                .background(Color.primary.opacity(0.035))
            }
        }
    }
}

private struct MenuServerRow: View {
    let server: DevServer
    @ObservedObject var store: ServerStore
    let isAlternate: Bool
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 5) {
                VStack(spacing: 3) {
                    Circle().fill(portColor).frame(width: 4, height: 4)
                    Circle().fill(portColor).frame(width: 4, height: 4)
                }
                Text(String(server.port))
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(portColor)
            }
            .frame(width: 62, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(server.gitBranch ?? server.projectName)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                    if server.framework == "Vaadin" {
                        Text("VAADIN")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(WattColors.violet)
                    }
                }
                Text(server.gitBranch == nil ? (server.framework ?? server.processName) : server.projectName)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)

            if store.busyPorts.contains(server.port) {
                HStack(spacing: 5) {
                    Text("Stopping")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(WattColors.critical)
                    KillPulseIndicator()
                }
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
            } else if isHovered {
                HStack(spacing: 5) {
                    Button { NSWorkspace.shared.open(server.tunnel?.publicURL ?? server.localURL) } label: {
                        Image(systemName: "arrow.up.right")
                    }
                    .help(server.tunnel == nil ? "Open local server" : "Open public tunnel")

                    if let tunnel = server.tunnel {
                        Button { Task { await store.stopTunnel(tunnel) } } label: {
                            Image(systemName: "link.badge.minus")
                        }
                        .help("Stop ngrok tunnel")
                    } else {
                        Button { Task { await store.startTunnel(for: server) } } label: {
                            Image(systemName: "point.3.connected.trianglepath.dotted")
                        }
                        .help("Open ngrok tunnel")
                    }

                    Button(role: .destructive) { Task { await store.stopServer(server) } } label: {
                        Image(systemName: "stop.fill")
                            .foregroundStyle(WattColors.critical)
                    }
                    .help("Stop server")
                }
            } else {
                Text(Formatters.memory(server.memoryBytes))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(isOverMemoryLimit ? WattColors.warning : Color.secondary)
            }
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 10)
        .frame(height: 40)
        .background(isHovered ? Color.primary.opacity(0.055) : .clear, in: RoundedRectangle(cornerRadius: 8))
        .padding(6)
        .background(isAlternate ? Color.primary.opacity(0.045) : .clear)
        .animation(.easeOut(duration: 0.18), value: store.busyPorts.contains(server.port))
        .onHover { isHovered = $0 }
    }

    private var isOverMemoryLimit: Bool { server.memoryBytes >= store.memoryThresholdBytes }

    private var portColor: Color {
        server.tunnel == nil ? Color(red: 0.36, green: 0.63, blue: 0.84) : WattColors.violet
    }
}

private struct ChatGPTMenuUsage: View {
    @ObservedObject var store: ChatGPTUsageStore

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Label("ChatGPT Codex", systemImage: "sparkles")
                    .font(.caption.weight(.semibold))
                Spacer()
                if store.isRefreshing {
                    ProgressView().controlSize(.mini)
                } else if store.isConnected {
                    Button {
                        Task { await store.refresh() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.plain)
                    .help("Refresh ChatGPT usage")
                }
            }

            if let usage = store.usage {
                HStack {
                    if let session = usage.session {
                        ChatGPTUsageMetric(label: "Session", window: session)
                    }
                    if let weekly = usage.weekly {
                        ChatGPTUsageMetric(label: "Weekly", window: weekly)
                    }
                    if !usage.isAllowed {
                        MenuMetric(label: "Status", value: "Limit reached")
                    }
                }
            } else if store.isConnected {
                Text(store.errorMessage ?? "Loading usage…")
                    .font(.caption)
                    .foregroundStyle(store.errorMessage == nil ? .secondary : WattColors.critical)
            } else {
                Text("Connect ChatGPT in Settings to show usage limits.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct ChatGPTUsageMetric: View {
    let label: String
    let window: ChatGPTUsageWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text("\(Int(window.remainingPercent.rounded()))% left")
                .font(.caption.weight(.semibold))
                .monospacedDigit()
            if let resetsAt = window.resetsAt {
                Text("Resets \(resetsAt, style: .relative)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

private struct MenuMetric: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.caption.weight(.semibold)).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
