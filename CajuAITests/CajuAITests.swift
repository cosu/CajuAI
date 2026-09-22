//
//  CajuAITests.swift
//  CajuAITests
//
//  Created by Cosmin Dumitru on 26/03/2026.
//

import Testing
import Foundation
@testable import CajuAI

// MARK: - Cursor token extraction tests

@Suite("Cursor Token Extraction")
@MainActor
struct CursorTokenExtractionTests {

    // Verifies the expected DB path is present on this machine.
    @Test func dbPathExists() {
        let url = CursorService.dbPath
        #expect(
            FileManager.default.fileExists(atPath: url.path),
            "Cursor state DB not found at \(url.path) — is Cursor installed and logged in?"
        )
    }

    // Reads the real token from the SQLite DB and checks it looks like a JWT.
    @Test func tokenExtractionFromDB() throws {
        let info = try CursorService.readToken()
        #expect(!info.token.isEmpty, "Token should not be empty")
        // A JWT has exactly two '.' separators
        let parts = info.token.split(separator: ".", omittingEmptySubsequences: false)
        #expect(parts.count == 3, "Token should be a three-part JWT, got \(parts.count) parts")
    }

    // Verifies the userId is extracted from the real token.
    @Test func userIdExtractionFromRealToken() throws {
        let info = try CursorService.readToken()
        #expect(info.userId.hasPrefix("user_"), "userId should start with 'user_', got: \(info.userId)")
    }

    // Unit-tests the JWT userId extraction with a synthetic payload.
    @Test func userIdExtractionFromSyntheticJWT() {
        let payload = Data(#"{"sub":"google-oauth2|user_TESTID123"}"#.utf8)
        let b64 = payload.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        let jwt = "eyJhbGciOiJIUzI1NiJ9.\(b64).fakesig"
        let userId = CursorService.extractUserId(from: jwt)
        #expect(userId == "user_TESTID123")
    }

    // Unit-tests the cookie-format "user_XXX::JWT" token.
    @Test func userIdExtractionFromCookieFormat() {
        let token = "user_ABC999::eyJhbGciOiJIUzI1NiJ9.payload.sig"
        let userId = CursorService.extractUserId(from: token)
        #expect(userId == "user_ABC999")
    }

    @Test func usageSummaryJSONMatchesPlansAndUsagePercent() throws {
        let json = """
        {
          "billingCycleStart": "2026-08-31T09:11:17.000Z",
          "billingCycleEnd": "2026-09-30T09:11:17.000Z",
          "membershipType": "pro",
          "limitType": "user",
          "isUnlimited": false,
          "autoModelSelectedDisplayMessage": "You've used 4% of your included total usage",
          "namedModelSelectedDisplayMessage": "You've used 0% of your included API usage",
          "individualUsage": {
            "plan": {
              "enabled": true,
              "used": 1866,
              "limit": 2000,
              "remaining": 134,
              "autoPercentUsed": 4.1466666666666665,
              "apiPercentUsed": 0,
              "totalPercentUsed": 3.7696969696969695
            },
            "onDemand": { "enabled": false, "used": 0, "limit": null, "remaining": null }
          },
          "teamUsage": {}
        }
        """.data(using: .utf8)!

        let summary = try CursorService.decodeUsageSummary(json)
        #expect(summary.membershipType == "pro")
        let percent = summary.individualUsage?.plan?.totalPercentUsed ?? -1
        #expect(abs(percent - 3.7696969696969695) < 0.0001)
        #expect(Int(percent.rounded()) == 4)
        // used/limit (1866/2000) is a different unit and must not drive the bar
        #expect(summary.individualUsage?.plan?.used == 1866)
        #expect(summary.individualUsage?.plan?.limit == 2000)
    }

    // Integration test: reads token from DB then hits the live API.
    // Requires network access and a valid Cursor session.
    @Test func usageFetchFromAPI() async throws {
        let info = try CursorService.readToken()
        let service = CursorService()
        let usage = try await service.fetchUsage(tokenInfo: info)
        #expect(usage.totalPercentUsed >= 0)
        #expect(usage.billing.subscriptionStatus == "active")
        let daysSinceStart = Date().timeIntervalSince(usage.billingCycleStart) / 86400
        #expect(daysSinceStart >= 0 && daysSinceStart <= 60,
                "billingCycleStart should be recent, got \(usage.billingCycleStart)")
    }
}
