import XCTest
@testable import WattHound

final class AttributionCalculatorTests: XCTestCase {
    func testAllocatesObservedAndUnassignedShare() {
        let start = Date(timeIntervalSince1970: 1_000)
        let app = AppImpact(
            id: "browser",
            name: "Browser",
            executablePath: "/Applications/Browser.app",
            processCount: 2,
            cpuPercentage: 20,
            memoryBytes: 500_000_000,
            relativeImpact: 4
        )
        let frames = [
            AppActivityFrame(
                capturedAt: start,
                batteryPercentage: 100,
                systemWatts: 10,
                totalSystemImpact: 10,
                applications: [app]
            ),
            AppActivityFrame(
                capturedAt: start.addingTimeInterval(60),
                batteryPercentage: 98,
                systemWatts: 8,
                totalSystemImpact: 10,
                applications: [app]
            )
        ]
        let session = BatterySession(
            startedAt: start,
            startPercentage: 100,
            currentPercentage: 90,
            samples: []
        )

        let result = AttributionCalculator.calculate(
            session: session,
            frames: frames,
            now: start.addingTimeInterval(120)
        )

        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result.first { $0.id == "browser" }?.observedShare ?? 0, 0.4, accuracy: 0.001)
        XCTAssertEqual(result.first { $0.id == "browser" }?.equivalentCharge ?? 0, 4, accuracy: 0.001)
        XCTAssertEqual(result.first { $0.id == "system-unassigned" }?.observedShare ?? 0, 0.6, accuracy: 0.001)
    }

    func testCapsLongGapsToAvoidInventingCoverage() {
        let start = Date(timeIntervalSince1970: 2_000)
        let app = AppImpact(
            id: "editor",
            name: "Editor",
            executablePath: "/Applications/Editor.app",
            processCount: 1,
            cpuPercentage: 5,
            memoryBytes: 100,
            relativeImpact: 5
        )
        let frame = AppActivityFrame(
            capturedAt: start,
            batteryPercentage: 80,
            systemWatts: 5,
            totalSystemImpact: 5,
            applications: [app]
        )
        let session = BatterySession(
            startedAt: start,
            startPercentage: 80,
            currentPercentage: 79,
            samples: []
        )

        let result = AttributionCalculator.calculate(
            session: session,
            frames: [frame],
            now: start.addingTimeInterval(3_600)
        )

        XCTAssertEqual(result.first?.activeDuration ?? 0, 120, accuracy: 0.001)
    }
}
