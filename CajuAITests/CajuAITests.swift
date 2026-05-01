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

    // Integration test: reads token from DB then hits the live API.
    // Requires network access and a valid Cursor session.
    @Test func usageFetchFromAPI() async throws {
        let info = try CursorService.readToken()
        let service = CursorService()
        let usage = try await service.fetchUsage(tokenInfo: info)
        #expect(usage.fastRequestsUsed >= 0)
        #expect(usage.billing.subscriptionStatus == "active")
        let daysSinceStart = Date().timeIntervalSince(usage.periodStart) / 86400
        #expect(daysSinceStart >= 0 && daysSinceStart <= 60,
                "periodStart should be recent, got \(usage.periodStart)")
    }
}
