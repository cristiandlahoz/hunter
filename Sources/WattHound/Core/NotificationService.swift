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

    func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }

    private func send(title: String, body: String, identifier: String) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        try? await UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        )
    }
}
