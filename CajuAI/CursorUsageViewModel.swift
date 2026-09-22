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
    var lastUsageChange: Date?
    private var lastUsageSignature: String?

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
            recordUsageChange(usageSignature)
            lastUpdated = Date()
        } catch {
            self.error = error.localizedDescription
        }
    }

    var menuBarLabel: String {
        guard let usage else { return "" }
        if usage.isUnlimited { return "∞" }
        return String(format: "%.0f%%", usage.totalPercentUsed)
    }

    var menuBarUsage: MenuBarUsage {
        MenuBarUsage(text: menuBarLabel, systemImage: "chevron.left.forwardslash.chevron.right", changedAt: lastUsageChange)
    }

    private var usageSignature: String? {
        guard let usage else { return nil }
        return String(format: "%.3f", usage.totalPercentUsed)
    }

    private func recordUsageChange(_ signature: String?) {
        if let previous = lastUsageSignature, previous != signature {
            lastUsageChange = Date()
        }
        lastUsageSignature = signature
    }
}
