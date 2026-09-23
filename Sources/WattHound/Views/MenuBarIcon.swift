import AppKit
import SwiftUI

enum MenuBarIcon {
    static let trackingHound: NSImage = {
        let image = Bundle.module.url(
            forResource: "BloodhoundMenuBar",
            withExtension: "svg",
            subdirectory: "Resources"
        ).flatMap(NSImage.init(contentsOf:))!
        image.accessibilityDescription = "WattHound"
        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = true
        return image
    }()

    static func status(
        batteryPercentage: Int,
        showBatteryPercentage: Bool,
        usageWindow: ChatGPTUsageWindow?,
        at date: Date
    ) -> NSImage {
        let labelAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 7.5, weight: .semibold),
            .foregroundColor: NSColor.black
        ]
        let valueAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 7.5, weight: .regular),
            .foregroundColor: NSColor.black
        ]
        let usageRows: [NSAttributedString] = usageWindow.map {
            let top = NSMutableAttributedString(string: "LEFT  ", attributes: labelAttributes)
            top.append(NSAttributedString(string: "\(Int($0.remainingPercent.rounded()))%", attributes: valueAttributes))
            let bottom = NSMutableAttributedString(string: "RESET ", attributes: labelAttributes)
            bottom.append(NSAttributedString(string: $0.compactResetCountdown(at: date), attributes: valueAttributes))
            return [top, bottom]
        } ?? []
        let batteryText = showBatteryPercentage ? "\(batteryPercentage)%" : nil
        let batteryAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 9, weight: .regular),
            .foregroundColor: NSColor.black
        ]

        let itemSpacing: CGFloat = 2
        let batteryWidth = batteryText.map {
            ceil(($0 as NSString).size(withAttributes: batteryAttributes).width)
                + (usageRows.isEmpty ? 0 : itemSpacing)
        } ?? 0
        let usageWidth = ceil(usageRows.map { $0.size().width }.max() ?? 0)
        let textWidth = batteryWidth + usageWidth
        let imageWidth = 18 + (textWidth > 0 ? itemSpacing + textWidth : 0)

        let image = NSImage(size: NSSize(width: imageWidth, height: 18), flipped: true) { _ in
            trackingHound.draw(
                in: NSRect(x: 0, y: 0, width: 18, height: 18),
                from: .zero,
                operation: .sourceOver,
                fraction: 1,
                respectFlipped: true,
                hints: nil
            )

            var x: CGFloat = 18 + itemSpacing
            if let batteryText {
                let size = (batteryText as NSString).size(withAttributes: batteryAttributes)
                (batteryText as NSString).draw(
                    at: NSPoint(x: x, y: (18 - size.height) / 2),
                    withAttributes: batteryAttributes
                )
                x += batteryWidth
            }
            if usageRows.count == 2 {
                usageRows[0].draw(at: NSPoint(x: x, y: 0))
                usageRows[1].draw(at: NSPoint(x: x, y: 8))
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}

struct MenuBarStatusLabel: View {
    let batteryPercentage: Int
    let showBatteryPercentage: Bool
    let chatGPTUsage: ChatGPTUsageSnapshot?

    private var usageWindows: [ChatGPTUsageWindow] {
        guard let chatGPTUsage else { return [] }
        return [chatGPTUsage.session, chatGPTUsage.weekly].compactMap { $0 }
    }

    private var nextResetWindow: ChatGPTUsageWindow? {
        usageWindows.min {
            ($0.resetsAt ?? .distantFuture) < ($1.resetsAt ?? .distantFuture)
        }
    }

    var body: some View {
        Image(
            nsImage: MenuBarIcon.status(
                batteryPercentage: batteryPercentage,
                showBatteryPercentage: showBatteryPercentage,
                usageWindow: nextResetWindow,
                at: .now
            )
        )
        .renderingMode(.template)
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private var accessibilitySummary: String {
        var parts = ["WattHound"]
        if showBatteryPercentage { parts.append("battery \(batteryPercentage) percent") }
        for window in usageWindows {
            parts.append("ChatGPT \(window.accessibilityLabel), \(Int(window.remainingPercent.rounded())) percent remaining")
        }
        return parts.joined(separator: ", ")
    }
}

struct AnimatedMenuBarHound: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isSniffing = false

    var body: some View {
        Image(nsImage: MenuBarIcon.trackingHound)
            .renderingMode(.template)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: 18, height: 18)
            .rotationEffect(.degrees(isSniffing ? -1.2 : 1.2), anchor: .bottomTrailing)
            .offset(y: isSniffing ? 0.4 : -0.2)
            .animation(
                reduceMotion ? nil : .easeInOut(duration: 1.15).repeatForever(autoreverses: true),
                value: isSniffing
            )
            .onAppear { isSniffing = !reduceMotion }
            .accessibilityHidden(true)
    }
}

private extension ChatGPTUsageWindow {
    func compactResetCountdown(at date: Date) -> String {
        guard let resetsAt else { return "—" }
        let totalMinutes = max(0, Int(resetsAt.timeIntervalSince(date) / 60))
        let days = totalMinutes / 1_440
        let hours = (totalMinutes % 1_440) / 60
        let minutes = totalMinutes % 60

        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }

    var accessibilityLabel: String {
        if windowSeconds <= 86_400 {
            let hours = max(1, Int((windowSeconds / 3_600).rounded()))
            return "\(hours) hour limit"
        }
        let days = max(1, Int((windowSeconds / 86_400).rounded()))
        return "\(days) day limit"
    }
}
