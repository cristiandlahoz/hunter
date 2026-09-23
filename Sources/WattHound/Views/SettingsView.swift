import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: EnergyStore
    @AppStorage("monitoringEnabled") private var monitoringEnabled = true
    @AppStorage("notificationsEnabled") private var notificationsEnabled = false
    @AppStorage("showMenuBarPercentage") private var showMenuBarPercentage = true
    @State private var notificationError: String?

    var body: some View {
        Form {
            Section("Monitoring") {
                Toggle("Sample battery activity in the background", isOn: $monitoringEnabled)
                Text("Battery state is sampled every 15 seconds. Application activity is sampled every 30 seconds.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Menu Bar") {
                Toggle("Show battery percentage beside the hound", isOn: $showMenuBarPercentage)
                Text("The bloodhound icon remains visible when the percentage is hidden.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Notifications") {
                Toggle("Low-battery and full-charge alerts", isOn: $notificationsEnabled)
                    .onChange(of: notificationsEnabled) { enabled in
                        guard enabled else { return }
                        Task {
                            if !(await store.enableNotifications()) {
                                notificationsEnabled = false
                                notificationError = "Notifications are disabled in System Settings."
                            }
                        }
                    }
                if let notificationError {
                    Text(notificationError)
                        .font(.caption)
                        .foregroundStyle(WattColors.critical)
                } else {
                    Text("WattHound alerts at 20% and when charging reaches 100%.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Privacy") {
                Text("All battery and process observations stay on this Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .tint(WattColors.violet)
        .padding(8)
        .frame(width: 480, height: 480)
    }
}
