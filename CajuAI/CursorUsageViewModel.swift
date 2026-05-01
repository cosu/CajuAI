//
//  CursorUsageViewModel.swift
//  CajuAI
//

import Foundation

@Observable
@MainActor
final class CursorUsageViewModel {
    var tokenInfo: CursorTokenInfo?
    var usage: CursorUsageData?
    var isLoading = false
    var error: String?
    var lastUpdated: Date?

    private let service = CursorService()

    init() {
        Task { await refresh() }
    }

    func userOpenedPopover() async {
        let eligible = lastUpdated.map { Date().timeIntervalSince($0) >= 60 } ?? true
        if eligible { await refresh() }
    }

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            let info = try CursorService.readToken()
            tokenInfo = info
            usage = try await service.fetchUsage(tokenInfo: info)
            lastUpdated = Date()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
