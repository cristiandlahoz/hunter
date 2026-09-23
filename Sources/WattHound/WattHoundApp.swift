import AppKit
import SwiftUI

@main
struct WattHoundApp: App {
    @StateObject private var store = EnergyStore()
    @AppStorage("showMenuBarPercentage") private var showMenuBarPercentage = true

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
            HStack(spacing: 3) {
                AnimatedMenuBarHound()
                if showMenuBarPercentage {
                    Text("\(store.snapshot.percentage)%")
                        .monospacedDigit()
                }
            }
            .accessibilityLabel("WattHound, \(store.snapshot.percentage) percent")
        }
        .menuBarExtraStyle(.window)
    }
}
