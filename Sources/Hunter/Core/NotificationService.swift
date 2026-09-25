import Foundation
import UserNotifications

struct ServerMemoryAlertTracker {
    private(set) var alertedServerIDs: Set<String> = []

    mutating func newAlerts(servers: [DevServer], thresholdBytes: UInt64) -> [DevServer] {
        let resetBelow = UInt64(Double(thresholdBytes) * 0.9)
        let activeIDs = Set(servers.map { String($0.pid) })
        alertedServerIDs = alertedServerIDs.filter { id in
            activeIDs.contains(id) && servers.first(where: { String($0.pid) == id }).map { $0.memoryBytes >= resetBelow } == true
        }
        var newProcessIDs: Set<String> = []
        let alerts = servers.filter { server in
            let processID = String(server.pid)
            return server.memoryBytes >= thresholdBytes
                && !alertedServerIDs.contains(processID)
                && newProcessIDs.insert(processID).inserted
        }
        alertedServerIDs.formUnion(newProcessIDs)
        return alerts
    }
}

actor NotificationService {
    private var sentLowBattery = false
    private var sentFullCharge = false
    private var serverMemoryTracker = ServerMemoryAlertTracker()

    func evaluate(previous: BatterySnapshot, current: BatterySnapshot, enabled: Bool) async {
        guard enabled else { return }
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized else { return }

        if !current.isOnAC, current.percentage <= 20, previous.percentage > 20, !sentLowBattery {
            await send(
                title: "Battery is at \(current.percentage)%",
                body: "Hunter estimates \(Formatters.time(current.timeRemainingMinutes)) remaining.",
                identifier: "low-battery"
            )
            sentLowBattery = true
        } else if current.percentage > 25 || current.isOnAC {
            sentLowBattery = false
        }

        if current.isOnAC, current.percentage >= 100, previous.percentage < 100, !sentFullCharge {
            await send(
                title: "Battery is fully charged",
                body: "Your Mac is ready for a new unplugged session.",
                identifier: "full-charge"
            )
            sentFullCharge = true
        } else if current.percentage < 95 || !current.isOnAC {
            sentFullCharge = false
        }
    }

    func evaluateChatGPT(
        previous: ChatGPTUsageSnapshot?,
        current: ChatGPTUsageSnapshot,
        enabled: Bool
    ) async {
        guard enabled, let previous else { return }
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized else { return }

        let windows: [(name: String, previous: ChatGPTUsageWindow?, current: ChatGPTUsageWindow?)] = [
            ("Session", previous.session, current.session),
            ("Weekly", previous.weekly, current.weekly)
        ]

        for window in windows {
            guard let old = window.previous,
                  let new = window.current,
                  new.usedPercent > old.usedPercent
            else { continue }

            let previousThreshold = Int(old.usedPercent / 10) * 10
            let currentThreshold = Int(new.usedPercent / 10) * 10
            guard currentThreshold >= 10, currentThreshold > previousThreshold else { continue }

            await send(
                title: "\(window.name) usage reached \(currentThreshold)%",
                body: paceMessage(for: new),
                identifier: "chatgpt-\(window.name.lowercased())-\(currentThreshold)-\(Int(new.resetsAt?.timeIntervalSince1970 ?? 0))"
            )
        }
    }

    func evaluateServerMemory(servers: [DevServer], thresholdBytes: UInt64, enabled: Bool) async {
        guard enabled else { return }
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized else { return }
        let alerts = serverMemoryTracker.newAlerts(servers: servers, thresholdBytes: thresholdBytes)

        for server in alerts {
            await send(
                title: "\(server.projectName) passed the memory limit",
                body: "Port \(server.port) is using \(Formatters.memory(server.memoryBytes)); your limit is \(Formatters.memory(thresholdBytes)).",
                identifier: "server-memory-\(server.id)-\(thresholdBytes)"
            )
        }
    }

    func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }

    private func paceMessage(for window: ChatGPTUsageWindow, now: Date = .now) -> String {
        var parts = ["\(Int(window.remainingPercent.rounded()))% remains"]
        if let resetsAt = window.resetsAt {
            let minutes = max(0, Int(resetsAt.timeIntervalSince(now) / 60))
            let resetText = minutes >= 1_440
                ? "\(minutes / 1_440)d \((minutes % 1_440) / 60)h"
                : minutes >= 60
                    ? "\(minutes / 60)h \(minutes % 60)m"
                    : "\(minutes)m"
            parts.append("resets in \(resetText)")

            let startedAt = resetsAt.addingTimeInterval(-window.windowSeconds)
            let elapsed = max(0, min(window.windowSeconds, now.timeIntervalSince(startedAt)))
            let evenPace = elapsed / max(window.windowSeconds, 1) * 100
            let difference = Int(abs(window.usedPercent - evenPace).rounded())
            if difference > 0 {
                parts.append("\(difference) points \(window.usedPercent > evenPace ? "ahead of" : "behind") an even pace")
            } else {
                parts.append("on an even pace")
            }
        }
        return parts.joined(separator: " · ")
    }

    private func send(title: String, body: String, identifier: String) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        content.threadIdentifier = "com.cristiandlahoz.hunter"
        content.targetContentIdentifier = "Hunter"
        try? await UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        )
    }
}
