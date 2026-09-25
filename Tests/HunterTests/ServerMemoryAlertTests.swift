import XCTest
@testable import Hunter

final class ServerMemoryAlertTests: XCTestCase {
    func testAlertsOnceUntilMemoryFallsBelowResetThreshold() {
        var tracker = ServerMemoryAlertTracker()
        let threshold: UInt64 = 2 * 1_073_741_824

        XCTAssertEqual(tracker.newAlerts(servers: [server(memory: threshold - 1)], thresholdBytes: threshold), [])
        XCTAssertEqual(tracker.newAlerts(servers: [server(memory: threshold)], thresholdBytes: threshold).map(\.port), [8080])
        XCTAssertEqual(tracker.newAlerts(servers: [server(memory: threshold + 500)], thresholdBytes: threshold), [])

        _ = tracker.newAlerts(servers: [server(memory: UInt64(Double(threshold) * 0.89))], thresholdBytes: threshold)
        XCTAssertEqual(tracker.newAlerts(servers: [server(memory: threshold)], thresholdBytes: threshold).map(\.port), [8080])
    }

    func testRemovesAlertsForExitedServers() {
        var tracker = ServerMemoryAlertTracker()
        let threshold: UInt64 = 100

        XCTAssertEqual(tracker.newAlerts(servers: [server(memory: 101)], thresholdBytes: threshold).count, 1)
        _ = tracker.newAlerts(servers: [], thresholdBytes: threshold)
        XCTAssertEqual(tracker.newAlerts(servers: [server(memory: 101)], thresholdBytes: threshold).count, 1)
    }

    private func server(memory: UInt64) -> DevServer {
        DevServer(
            port: 8080,
            pid: 42,
            processName: "java",
            command: "java -jar app.jar",
            workingDirectory: "/tmp/app",
            projectName: "app",
            framework: "Vaadin",
            gitBranch: "main",
            memoryBytes: memory,
            uptime: 60,
            tunnel: nil
        )
    }
}
