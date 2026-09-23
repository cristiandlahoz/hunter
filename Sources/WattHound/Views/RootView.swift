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
            Button("Quit WattHound") { NSApplication.shared.terminate(nil) }
        }
        .padding(12)
        .frame(width: 280)
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
