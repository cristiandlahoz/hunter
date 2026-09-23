import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: EnergyStore
    @ObservedObject var chatGPTUsage: ChatGPTUsageStore
    @AppStorage("monitoringEnabled") private var monitoringEnabled = true
    @AppStorage("notificationsEnabled") private var notificationsEnabled = false
    @AppStorage("chatGPTUsageNotificationsEnabled") private var chatGPTUsageNotificationsEnabled = true
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
                        requestNotificationAccess(when: enabled) {
                            notificationsEnabled = false
                        }
                    }

                Toggle("ChatGPT pace alerts every 10% consumed", isOn: $chatGPTUsageNotificationsEnabled)
                    .onChange(of: chatGPTUsageNotificationsEnabled) { enabled in
                        requestNotificationAccess(when: enabled) {
                            chatGPTUsageNotificationsEnabled = false
                        }
                    }

                if let notificationError {
                    Text(notificationError)
                        .font(.caption)
                        .foregroundStyle(WattColors.critical)
                } else {
                    Text("Usage alerts include the percentage remaining, reset countdown, and comparison with an even pace.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("ChatGPT Usage") {
                if chatGPTUsage.isConnected {
                    HStack {
                        Label("Connected", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(WattColors.energy)
                        Spacer()
                        if chatGPTUsage.isRefreshing {
                            ProgressView().controlSize(.small)
                        }
                        Button("Refresh") { Task { await chatGPTUsage.refresh() } }
                        Button("Disconnect", role: .destructive) { chatGPTUsage.disconnect() }
                    }

                    if let usage = chatGPTUsage.usage {
                        HStack(spacing: 24) {
                            if let session = usage.session {
                                usageSummary("Session", window: session)
                            }
                            if let weekly = usage.weekly {
                                usageSummary("Weekly", window: weekly)
                            }
                        }
                    }
                } else if chatGPTUsage.isAuthenticating {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Finish signing in on the OpenAI page.")
                            .font(.caption)
                        if let code = chatGPTUsage.deviceCode {
                            HStack {
                                Text(code)
                                    .font(.system(.body, design: .monospaced).weight(.semibold))
                                    .textSelection(.enabled)
                                Button("Copy Code") {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(code, forType: .string)
                                }
                            }
                        } else {
                            ProgressView("Starting secure sign-in…")
                                .controlSize(.small)
                        }
                        Button("Cancel", role: .cancel) { chatGPTUsage.cancelAuthentication() }
                    }
                } else {
                    Button("Connect ChatGPT…") { chatGPTUsage.connect() }
                    Text("Uses the same OpenAI device-code OAuth flow as Pi. Your refresh token is stored in macOS Keychain.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let error = chatGPTUsage.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(WattColors.critical)
                }
            }

            Section("Privacy") {
                Text("Battery and process observations stay on this Mac. When connected, WattHound sends only your OAuth credential and account ID to OpenAI to fetch Codex usage limits.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .tint(WattColors.violet)
        .padding(8)
        .frame(width: 500, height: 600)
        .onAppear { chatGPTUsage.start() }
    }

    private func requestNotificationAccess(when enabled: Bool, onFailure: @escaping () -> Void) {
        guard enabled else { return }
        Task {
            if !(await store.enableNotifications()) {
                onFailure()
                notificationError = "Notifications are disabled in System Settings."
            } else {
                notificationError = nil
            }
        }
    }

    private func usageSummary(_ label: String, window: ChatGPTUsageWindow) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("\(Int(window.remainingPercent.rounded()))% left")
                .font(.body.weight(.semibold))
                .monospacedDigit()
            if let resetsAt = window.resetsAt {
                Text("Resets \(resetsAt, style: .relative)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
