import XCTest
@testable import WattHound

final class SystemProbeTests: XCTestCase {
    func testParsesPowerHistoryAndPowerSource() throws {
        let text = """
        2025-03-09 10:15:00 -0400 Sleep Entering Sleep Using AC (Charge:100%) 60 secs
        2025-03-09 11:00:00 -0400 Wake DarkWake Using Batt (Charge: 98) 10 secs
        2025-03-09 12:30:00 -0400 Sleep Entering Sleep Using Batt (Charge:82%) 60 secs
        """

        let samples = SystemProbe.parsePowerHistory(text)

        XCTAssertEqual(samples.count, 3)
        XCTAssertTrue(samples[0].isOnAC)
        XCTAssertFalse(samples[1].isOnAC)
        XCTAssertEqual(samples[2].percentage, 82)
    }

    func testRejectsTruncatedPowerdPercentage() {
        let text = """
        2025-03-09 10:15:00 -0400 Wake Using Batt (Charge:100%)
        2025-03-09 10:15:01 -0400 Assertions Using Batt(Charge: 10
        2025-03-09 10:15:02 -0400 Sleep Using Batt (Charge:100%)
        """

        XCTAssertEqual(SystemProbe.parsePowerHistory(text).map(\.percentage), [100])
    }

    func testExtractsApplicationBundleIdentity() {
        let identity = SystemProbe.applicationIdentity(
            for: "/Applications/Safari.app/Contents/MacOS/Safari"
        )

        XCTAssertEqual(identity.name, "Safari")
        XCTAssertEqual(identity.path, "/Applications/Safari.app")
    }

    func testMergesDuplicateSamples() {
        let date = Date(timeIntervalSince1970: 100)
        let sample = PowerSample(capturedAt: date, percentage: 80, watts: nil, isOnAC: false)
        let duplicate = PowerSample(
            capturedAt: date.addingTimeInterval(10),
            percentage: 80,
            watts: 4.2,
            isOnAC: false
        )

        XCTAssertEqual(EnergyStore.merge(system: [sample], local: [duplicate]).count, 1)
    }
}
