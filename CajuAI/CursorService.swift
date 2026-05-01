//
//  CursorService.swift
//  CajuAI
//

import Foundation
import SQLite3

struct CursorService {

    // MARK: - DB path

    static var dbPath: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Cursor/User/globalStorage/state.vscdb")
    }

    // MARK: - Token extraction

    static func readToken() throws -> CursorTokenInfo {
        let path = dbPath.path
        guard FileManager.default.fileExists(atPath: path) else {
            throw CursorServiceError.dbNotFound
        }
        let token = try readTokenFromSQLite(at: path)
        guard let userId = extractUserId(from: token) else {
            throw CursorServiceError.invalidToken
        }
        return CursorTokenInfo(token: token, userId: userId)
    }

    private static func readTokenFromSQLite(at path: String) throws -> String {
        var db: OpaquePointer?
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            let msg = db.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
            throw CursorServiceError.dbReadFailed(msg)
        }
        defer { sqlite3_close(db) }

        var stmt: OpaquePointer?
        let query = "SELECT value FROM ItemTable WHERE key = 'cursorAuth/accessToken'"
        guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else {
            let msg = db.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "prepare failed"
            throw CursorServiceError.dbReadFailed(msg)
        }
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_step(stmt) == SQLITE_ROW else {
            throw CursorServiceError.tokenNotFound
        }
        guard let bytes = sqlite3_column_text(stmt, 0) else {
            throw CursorServiceError.tokenNotFound
        }
        return String(cString: bytes)
    }

    static func extractUserId(from token: String) -> String? {
        let decoded = token.removingPercentEncoding ?? token

        if decoded.contains("::") {
            return decoded.components(separatedBy: "::").first
        }

        let parts = decoded.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }

        var base64 = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64 += "=" }

        guard let data = Data(base64Encoded: base64),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sub = json["sub"] as? String else { return nil }

        let pattern = #"user_[A-Za-z0-9]+"#
        if let range = sub.range(of: pattern, options: .regularExpression) {
            return String(sub[range])
        }
        return nil
    }

    // MARK: - API

    func fetchUsage(tokenInfo: CursorTokenInfo) async throws -> CursorUsageData {
        async let billing = fetchBilling(tokenInfo: tokenInfo)
        async let periodStart = fetchPeriodStart(tokenInfo: tokenInfo)

        let (billingResult, start) = try await (billing, periodStart)

        let events = try await fetchAllEvents(tokenInfo: tokenInfo, since: start)

        // Aggregate by model
        var byModel: [String: (requests: Double, cents: Double)] = [:]
        for e in events {
            let cur = byModel[e.model] ?? (0, 0)
            byModel[e.model] = (cur.requests + e.requestsCosts, cur.cents + e.totalCents)
        }
        let breakdown = byModel
            .map { (model: $0.key, requests: $0.value.requests, cents: $0.value.cents) }
            .sorted { $0.requests > $1.requests }

        let totalFast = events.reduce(0) { $0 + $1.requestsCosts }

        return CursorUsageData(
            billing: billingResult,
            fastRequestsUsed: totalFast,
            periodStart: start,
            modelBreakdown: breakdown,
            recentEvents: Array(events.prefix(20))
        )
    }

    // MARK: - Private fetches

    private func fetchBilling(tokenInfo: CursorTokenInfo) async throws -> CursorBillingInfo {
        let data = try await get("https://cursor.com/api/auth/stripe", tokenInfo: tokenInfo)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(CursorBillingInfo.self, from: data)
    }

    private func fetchPeriodStart(tokenInfo: CursorTokenInfo) async throws -> Date {
        let data = try await get(
            "https://cursor.com/api/usage?user=\(tokenInfo.userId)",
            tokenInfo: tokenInfo
        )
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let raw = json["startOfMonth"] as? String else {
            // Fall back to first of the current month
            return Calendar.current.date(from: Calendar.current.dateComponents(
                [.year, .month], from: Date()))!
        }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return iso.date(from: raw) ?? ISO8601DateFormatter().date(from: raw) ?? Date()
    }

    private func fetchAllEvents(tokenInfo: CursorTokenInfo, since periodStart: Date) async throws -> [CursorUsageEvent] {
        let startMs = Int64(periodStart.timeIntervalSince1970 * 1000)
        let endMs = Int64(Date().timeIntervalSince1970 * 1000)
        let pageSize = 100
        var page = 1
        var all: [CursorUsageEvent] = []

        while true {
            let body: [String: Any] = [
                "teamId": 0,
                "startDate": String(startMs),
                "endDate": String(endMs),
                "page": page,
                "pageSize": pageSize
            ]
            let data = try await post(
                "https://cursor.com/api/dashboard/get-filtered-usage-events",
                body: body,
                tokenInfo: tokenInfo
            )
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw CursorServiceError.apiError("Invalid JSON from events endpoint")
            }
            guard let raw = json["usageEventsDisplay"] as? [[String: Any]] else { break }
            let batch = raw.compactMap { parseEvent($0) }
            all.append(contentsOf: batch)

            let total = json["totalUsageEventsCount"] as? Int ?? 0
            if all.count >= total || batch.isEmpty { break }
            page += 1
        }
        return all
    }

    private func parseEvent(_ d: [String: Any]) -> CursorUsageEvent? {
        guard let tsStr = d["timestamp"] as? String,
              let tsMs = Double(tsStr) else { return nil }
        let ts = Date(timeIntervalSince1970: tsMs / 1000)
        let model = d["model"] as? String ?? "unknown"
        let kind = d["kind"] as? String ?? ""
        let requestsCosts = (d["requestsCosts"] as? Double) ?? 0
        let tokenUsage = d["tokenUsage"] as? [String: Any] ?? [:]
        let totalCents = (tokenUsage["totalCents"] as? Double) ?? 0
        let inputTokens = (tokenUsage["inputTokens"] as? Int) ?? 0
        let outputTokens = (tokenUsage["outputTokens"] as? Int) ?? 0
        let cacheRead = (tokenUsage["cacheReadTokens"] as? Int) ?? 0
        let cacheWrite = (tokenUsage["cacheWriteTokens"] as? Int) ?? 0
        return CursorUsageEvent(
            timestamp: ts,
            model: model,
            kind: kind,
            requestsCosts: requestsCosts,
            totalCents: totalCents,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            cacheReadTokens: cacheRead,
            cacheWriteTokens: cacheWrite
        )
    }

    // MARK: - HTTP helpers

    private func cookieValue(for tokenInfo: CursorTokenInfo) -> String {
        // Decode the raw token in case it is percent-encoded, then extract just the JWT portion.
        let rawToken = tokenInfo.token.removingPercentEncoding ?? tokenInfo.token
        let jwt = rawToken.contains("::")
            ? (rawToken.components(separatedBy: "::").last ?? rawToken)
            : rawToken
        return "WorkosCursorSessionToken=\(tokenInfo.userId)%3A%3A\(jwt)"
    }

    private func request(_ url: String, method: String, body: [String: Any]? = nil,
                         tokenInfo: CursorTokenInfo) async throws -> Data {
        guard let requestURL = URL(string: url) else {
            throw CursorServiceError.apiError("Invalid URL: \(url)")
        }
        var req = URLRequest(url: requestURL)
        req.httpMethod = method
        req.timeoutInterval = 15
        req.setValue(cookieValue(for: tokenInfo), forHTTPHeaderField: "Cookie")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36",
                     forHTTPHeaderField: "User-Agent")
        req.setValue("https://cursor.com", forHTTPHeaderField: "Origin")
        req.setValue("https://cursor.com/dashboard/spending", forHTTPHeaderField: "Referer")
        if let body {
            req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw CursorServiceError.apiError("Invalid response")
        }
        guard http.statusCode == 200 else {
            throw CursorServiceError.apiError("HTTP \(http.statusCode)")
        }
        return data
    }

    private func get(_ url: String, tokenInfo: CursorTokenInfo) async throws -> Data {
        try await request(url, method: "GET", tokenInfo: tokenInfo)
    }

    private func post(_ url: String, body: [String: Any], tokenInfo: CursorTokenInfo) async throws -> Data {
        try await request(url, method: "POST", body: body, tokenInfo: tokenInfo)
    }
}
