import AppKit
import SwiftUI

struct RootView: View {
    @ObservedObject var store: EnergyStore
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
        .onAppear { store.start() }
    }
}

struct MenuBarView: View {
    @ObservedObject var store: EnergyStore
    @ObservedObject var chatGPTUsage: ChatGPTUsageStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(store.snapshot.isOnAC ? "On power adapter" : "On battery")
                        .font(.headline)
                    Text("\(store.snapshot.percentage)% · \(Formatters.time(store.snapshot.timeRemainingMinutes))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(store.snapshot.watts.map { String(format: "%.1f W", $0) } ?? "—")
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
            }

            if let session = store.session, !store.snapshot.isOnAC {
                Divider()
                HStack {
                    MenuMetric(label: "Session", value: Formatters.duration(session.duration))
                    MenuMetric(label: "Used", value: "\(session.percentageDrop)%")
                    MenuMetric(label: "Rate", value: session.drainPerHour.map { String(format: "%.1f%%/h", $0) } ?? "—")
                }
            }

            Divider()
            ChatGPTMenuUsage(store: chatGPTUsage)

            Divider()
            Button("Open WattHound") {
                NSApplication.shared.activate(ignoringOtherApps: true)
                openWindow(id: "main")
            }
            Button("Refresh now") { Task { await store.refresh() } }
            Button("Settings…") {
                NSApplication.shared.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                NSApplication.shared.activate(ignoringOtherApps: true)
            }
            Divider()
            Button("Quit WattHound Completely") {
                WattHoundAppDelegate.shared?.quitCompletely()
            }
        }
        .padding(12)
        .frame(width: 280)
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
