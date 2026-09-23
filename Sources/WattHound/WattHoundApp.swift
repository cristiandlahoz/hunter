import AppKit
import SwiftUI

@MainActor
final class WattHoundAppDelegate: NSObject, NSApplicationDelegate {
    static weak var shared: WattHoundAppDelegate?
    private var shouldTerminateCompletely = false

    override init() {
        super.init()
        Self.shared = self
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        DispatchQueue.main.async {
            NSApplication.shared.windows
                .filter(\.canBecomeMain)
                .forEach { $0.orderOut(nil) }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard shouldTerminateCompletely else {
            sender.windows.filter(\.canBecomeMain).forEach { $0.orderOut(nil) }
            sender.hide(nil)
            return .terminateCancel
        }
        return .terminateNow
    }

    func quitCompletely() {
        shouldTerminateCompletely = true
        NSApplication.shared.terminate(nil)
    }
}

@main
struct WattHoundApp: App {
    @NSApplicationDelegateAdaptor(WattHoundAppDelegate.self) private var appDelegate
    @StateObject private var store = EnergyStore()
    @StateObject private var chatGPTUsage = ChatGPTUsageStore()
    @AppStorage("showMenuBarPercentage") private var showMenuBarPercentage = true

    var body: some Scene {
        WindowGroup("WattHound", id: "main") {
            RootView(store: store)
                .preferredColorScheme(.light)
                .onAppear { chatGPTUsage.start() }
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
            SettingsView(store: store, chatGPTUsage: chatGPTUsage)
        }

        MenuBarExtra {
            MenuBarView(store: store, chatGPTUsage: chatGPTUsage)
                .onAppear {
                    store.start()
                    chatGPTUsage.start()
                }
        } label: {
            MenuBarStatusLabel(
                batteryPercentage: store.snapshot.percentage,
                showBatteryPercentage: showMenuBarPercentage,
                chatGPTUsage: chatGPTUsage.usage
            )
        }
        .menuBarExtraStyle(.window)
    }
}
