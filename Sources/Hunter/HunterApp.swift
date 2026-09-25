import AppKit
import SwiftUI
import UserNotifications

@MainActor
final class HunterAppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    static weak var shared: HunterAppDelegate?
    private var shouldTerminateCompletely = false

    override init() {
        super.init()
        Self.shared = self
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.migrateFromWattHoundIfNeeded()
        UserDefaults.standard.register(defaults: [
            "serverMemoryAlertsEnabled": true,
            "serverMemoryThresholdGB": 2.0
        ])
        UNUserNotificationCenter.current().delegate = self
        if let iconURL = Bundle.main.url(forResource: "Hunter", withExtension: "icns"),
           let icon = NSImage(contentsOf: iconURL) {
            NSApplication.shared.applicationIconImage = icon
        }
        NSApplication.shared.setActivationPolicy(.accessory)
        DispatchQueue.main.async {
            NSApplication.shared.windows
                .filter(\.canBecomeMain)
                .forEach { $0.orderOut(nil) }
        }
    }

    private static func migrateFromWattHoundIfNeeded() {
        let defaults = UserDefaults.standard
        if !defaults.bool(forKey: "didMigrateFromWattHound"),
           let legacy = defaults.persistentDomain(forName: "com.cristiandlahoz.watthound") {
            for (key, value) in legacy where defaults.object(forKey: key) == nil {
                defaults.set(value, forKey: key)
            }
            defaults.set(true, forKey: "didMigrateFromWattHound")
        }

        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let legacyRoot = support.appendingPathComponent("WattHound", isDirectory: true)
        let hunterRoot = support.appendingPathComponent("Hunter", isDirectory: true)
        guard FileManager.default.fileExists(atPath: legacyRoot.path) else { return }
        if !FileManager.default.fileExists(atPath: hunterRoot.path) {
            try? FileManager.default.moveItem(at: legacyRoot, to: hunterRoot)
            return
        }
        for name in ["power-samples.json", "application-activity.json", "bin"] {
            let source = legacyRoot.appendingPathComponent(name)
            let destination = hunterRoot.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: source.path),
               !FileManager.default.fileExists(atPath: destination.path) {
                try? FileManager.default.moveItem(at: source, to: destination)
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
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
struct HunterApp: App {
    @NSApplicationDelegateAdaptor(HunterAppDelegate.self) private var appDelegate
    @StateObject private var store = EnergyStore()
    @StateObject private var serverStore = ServerStore()
    @StateObject private var chatGPTUsage = ChatGPTUsageStore()
    @AppStorage("showMenuBarPercentage") private var showMenuBarPercentage = true

    var body: some Scene {
        WindowGroup("Hunter", id: "main") {
            RootView(store: store, serverStore: serverStore)
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
            MenuBarView(store: store, serverStore: serverStore, chatGPTUsage: chatGPTUsage)
                .onAppear {
                    store.start()
                    serverStore.start()
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
