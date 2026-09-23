import AppKit
import SwiftUI

@main
struct WattHoundApp: App {
    @StateObject private var store = EnergyStore()

    var body: some Scene {
        WindowGroup("WattHound", id: "main") {
            RootView(store: store)
                .preferredColorScheme(.light)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1_140, height: 760)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Refresh") { Task { await store.refresh() } }
                    .keyboardShortcut("r", modifiers: .command)
            }
        }

        Settings {
            SettingsView(store: store)
        }

        MenuBarExtra {
            MenuBarView(store: store)
                .onAppear { store.start() }
        } label: {
            Label("WattHound \(store.snapshot.percentage)%", systemImage: menuSymbol)
        }
        .menuBarExtraStyle(.window)
    }

    private var menuSymbol: String {
        if store.snapshot.isCharging { return "battery.100percent.bolt" }
        switch store.snapshot.percentage {
        case 76...: return "battery.100percent"
        case 51...: return "battery.75percent"
        case 26...: return "battery.50percent"
        case 11...: return "battery.25percent"
        default: return "battery.0percent"
        }
    }
}
