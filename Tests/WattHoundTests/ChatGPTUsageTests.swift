import Foundation
import XCTest
@testable import WattHound

final class ChatGPTUsageTests: XCTestCase {
    func testParsesSessionAndWeeklyWindowsByDuration() throws {
        let data = Data("""
        {
          "plan_type": "plus",
          "rate_limit": {
            "allowed": true,
            "primary_window": {
              "used_percent": 25,
              "limit_window_seconds": 18000,
              "reset_at": 2000
            },
            "secondary_window": {
              "used_percent": 60,
              "limit_window_seconds": 604800,
              "reset_at": 3000
            }
          }
        }
        """.utf8)

        let usage = try XCTUnwrap(ChatGPTUsageStore.parseUsage(data, now: Date(timeIntervalSince1970: 1000)))

        XCTAssertEqual(usage.plan, "plus")
        XCTAssertEqual(usage.session?.remainingPercent, 75)
        XCTAssertEqual(usage.weekly?.remainingPercent, 40)
        XCTAssertEqual(usage.session?.resetsAt, Date(timeIntervalSince1970: 2000))
        XCTAssertTrue(usage.isAllowed)
    }

    func testParsesPlanWithOnlyWeeklyWindowAndClampsPercent() throws {
        let data = Data("""
        {
          "plan_type": "prolite",
          "rate_limit": {
            "allowed": false,
            "primary_window": {
              "used_percent": 108,
              "limit_window_seconds": 604800,
              "reset_at": 3000
            },
            "secondary_window": null
          }
        }
        """.utf8)

        let usage = try XCTUnwrap(ChatGPTUsageStore.parseUsage(data))

        XCTAssertNil(usage.session)
        XCTAssertEqual(usage.weekly?.remainingPercent, 0)
        XCTAssertFalse(usage.isAllowed)
    }

    func testExtractsAccountIDFromJWT() throws {
        let payload = try JSONSerialization.data(withJSONObject: [
            "https://api.openai.com/auth": ["chatgpt_account_id": "account-123"]
        ])
        let encoded = payload.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        let token = "header.\(encoded).signature"

        XCTAssertEqual(ChatGPTUsageStore.accountID(fromJWT: token), "account-123")
    }
}
