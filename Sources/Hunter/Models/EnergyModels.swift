import Foundation

struct BatterySnapshot: Codable, Sendable, Equatable {
    var capturedAt: Date
    var percentage: Int
    var isOnAC: Bool
    var isCharging: Bool
    var timeRemainingMinutes: Int?
    var watts: Double?
    var healthPercentage: Int?
    var cycleCount: Int?
    var temperatureCelsius: Double?

    static let empty = BatterySnapshot(
        capturedAt: .now,
        percentage: 0,
        isOnAC: false,
        isCharging: false,
        timeRemainingMinutes: nil,
        watts: nil,
        healthPercentage: nil,
        cycleCount: nil,
        temperatureCelsius: nil
    )
}

struct PowerSample: Codable, Sendable, Identifiable, Equatable {
    var id: Date { capturedAt }
    let capturedAt: Date
    let percentage: Int
    let watts: Double?
    let isOnAC: Bool
}

struct AppImpact: Codable, Sendable, Identifiable, Equatable {
    let id: String
    let name: String
    let executablePath: String
    let processCount: Int
    let cpuPercentage: Double
    let memoryBytes: UInt64
    let relativeImpact: Double
}

struct ProcessActivitySnapshot: Sendable {
    let capturedAt: Date
    let applications: [AppImpact]
    let totalSystemImpact: Double
}

struct AppActivityFrame: Codable, Sendable, Identifiable, Equatable {
    var id: Date { capturedAt }
    let capturedAt: Date
    let batteryPercentage: Int
    let systemWatts: Double?
    let totalSystemImpact: Double
    let applications: [AppImpact]
}

struct AppAttribution: Sendable, Identifiable, Equatable {
    let id: String
    let name: String
    let executablePath: String
    let observedShare: Double
    let equivalentCharge: Double
    let activeDuration: TimeInterval
    let averageImpact: Double
    let peakImpact: Double
}

struct BatterySession: Sendable, Equatable {
    let startedAt: Date
    let startPercentage: Int
    let currentPercentage: Int
    let samples: [PowerSample]

    var duration: TimeInterval { max(0, Date().timeIntervalSince(startedAt)) }
    var percentageDrop: Int { max(0, startPercentage - currentPercentage) }
    var drainPerHour: Double? {
        let hours = duration / 3_600
        guard hours >= 0.1, percentageDrop > 0 else { return nil }
        return Double(percentageDrop) / hours
    }

    var projectedRuntime: TimeInterval? {
        guard let drainPerHour, drainPerHour > 0 else { return nil }
        return Double(currentPercentage) / drainPerHour * 3_600
    }
}

enum SidebarDestination: String, CaseIterable, Identifiable {
    case session = "Session"
    case applications = "Applications"
    case servers = "Servers"
    case history = "History"
    case battery = "Battery"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .session: "bolt.horizontal.fill"
        case .applications: "list.bullet.rectangle"
        case .servers: "network"
        case .history: "chart.xyaxis.line"
        case .battery: "battery.75percent"
        }
    }

    var shortcut: Character {
        switch self {
        case .session: "1"
        case .applications: "2"
        case .servers: "3"
        case .history: "4"
        case .battery: "5"
        }
    }
}
