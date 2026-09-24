import Foundation
import UserNotifications

actor NotificationService {
    private var sentLowBattery = false
    private var sentFullCharge = false

    func evaluate(previous: BatterySnapshot, current: BatterySnapshot, enabled: Bool) async {
        guard enabled else { return }
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized else { return }

        if !current.isOnAC, current.percentage <= 20, previous.percentage > 20, !sentLowBattery {
            await send(
                title: "Battery is at \(current.percentage)%",
                body: "WattHound estimates \(Formatters.time(current.timeRemainingMinutes)) remaining.",
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
        try? await UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        )
    }
}
