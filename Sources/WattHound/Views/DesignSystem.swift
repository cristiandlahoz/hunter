import SwiftUI

enum WattColors {
    static let sidebar = Color(red: 16/255, green: 47/255, blue: 73/255)
    static let sidebarHover = Color(red: 24/255, green: 63/255, blue: 94/255)
    static let sidebarText = Color(red: 220/255, green: 234/255, blue: 243/255)
    static let sidebarMuted = Color(red: 134/255, green: 167/255, blue: 188/255)
    static let workspace = Color(red: 238/255, green: 242/255, blue: 245/255)
    static let ink = Color(red: 39/255, green: 38/255, blue: 48/255)
    static let secondary = Color(red: 96/255, green: 112/255, blue: 131/255)
    static let rule = Color(red: 216/255, green: 224/255, blue: 231/255)
    static let violet = Color(red: 139/255, green: 61/255, blue: 255/255)
    static let violetWash = Color(red: 238/255, green: 229/255, blue: 255/255)
    static let energy = Color(red: 120/255, green: 184/255, blue: 51/255)
    static let warning = Color(red: 196/255, green: 122/255, blue: 22/255)
    static let critical = Color(red: 199/255, green: 70/255, blue: 70/255)
}

struct Sheet<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .shadow(color: .black.opacity(0.09), radius: 9, y: 3)
    }
}

struct StatusDot: View {
    let color: Color

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 7, height: 7)
            .accessibilityHidden(true)
    }
}

extension View {
    func tabularMeasurement() -> some View {
        fontDesign(.rounded).monospacedDigit()
    }
}

enum Formatters {
    static func duration(_ interval: TimeInterval) -> String {
        let totalMinutes = max(0, Int(interval / 60))
        if totalMinutes < 60 { return "\(totalMinutes)m" }
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return minutes == 0 ? "\(hours)h" : "\(hours)h \(minutes)m"
    }

    static func memory(_ bytes: UInt64) -> String {
        let value = Double(bytes)
        if value >= 1_073_741_824 { return String(format: "%.1f GB", value / 1_073_741_824) }
        return "\(Int(value / 1_048_576)) MB"
    }

    static func time(_ minutes: Int?) -> String {
        guard let minutes else { return "Calculating" }
        return duration(TimeInterval(minutes * 60))
    }
}
