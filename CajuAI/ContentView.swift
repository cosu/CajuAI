//
//  MenuBarView.swift
//  CajuAI
//

import SwiftUI

// MARK: - Root menu bar popover

enum AppTab: CaseIterable {
    case claude, cursor, deepseek, openrouter

    var title: String {
        switch self {
        case .claude: "Claude"
        case .cursor: "Cursor"
        case .deepseek: "DeepSeek"
        case .openrouter: "OpenRouter"
        }
    }
}

struct MenuBarView: View {
    @Environment(ClaudeUsageViewModel.self) var viewModel
    @Environment(CursorUsageViewModel.self) var cursorViewModel
    @Environment(DeepSeekUsageViewModel.self) var deepSeekViewModel
    @Environment(OpenRouterUsageViewModel.self) var openRouterViewModel
    @State private var selectedTab: AppTab = .claude

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 2) {
                ForEach(AppTab.allCases, id: \.self) { tab in
                    Button {
                        selectedTab = tab
                    } label: {
                        Text(tab.title)
                            .font(.system(size: 11))
                            .fontWeight(.medium)
                            .foregroundStyle(selectedTab == tab ? .primary : .secondary)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 5)
                            .background(
                                selectedTab == tab ? Color.primary.opacity(0.12) : Color.clear,
                                in: RoundedRectangle(cornerRadius: 5)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 10)
            .padding(.bottom, 6)

            Divider()

            switch selectedTab {
            case .claude:
                if viewModel.isAuthenticated {
                    UsageView()
                } else {
                    LoginView()
                }
            case .cursor:
                CursorView()
            case .deepseek:
                DeepSeekView()
            case .openrouter:
                OpenRouterView()
            }
        }
        .frame(width: 340)
        .onAppear {
            Task {
                await viewModel.userOpenedPopover()
                await cursorViewModel.userOpenedPopover()
                await deepSeekViewModel.userOpenedPopover()
                await openRouterViewModel.userOpenedPopover()
            }
        }
    }
}

// MARK: - Usage view (authenticated)

struct UsageView: View {
    @Environment(ClaudeUsageViewModel.self) var viewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {

            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Claude Usage")
                        .font(.headline)
                    if let profile = viewModel.profile {
                        Text(profile.account.displayTitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button {
                    Task { await viewModel.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .rotationEffect(viewModel.isLoading ? .degrees(360) : .degrees(0))
                        .animation(viewModel.isLoading ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: viewModel.isLoading)
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isLoading)
            }

            Divider()

            if let error = viewModel.error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let usage = viewModel.usage {
                if let session = usage.fiveHour {
                    UsageRow(
                        label: "Session (5 hrs)",
                        value: session.utilization,
                        resetsAt: session.resetsAt
                    )
                }

                if let weekly = usage.sevenDay {
                    UsageRow(
                        label: "Weekly (all models)",
                        value: weekly.utilization,
                        resetsAt: weekly.resetsAt
                    )
                }

                if let sonnet = usage.sevenDaySonnet {
                    UsageRow(
                        label: "Weekly Sonnet",
                        value: sonnet.utilization,
                        resetsAt: sonnet.resetsAt
                    )
                }

                if let extra = usage.extraUsage, extra.isEnabled {
                    Divider()
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Extra Usage (pay-as-you-go)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            if let util = extra.utilization {
                                Text(String(format: "%.1f%%", util))
                                    .font(.caption)
                                    .fontWeight(.medium)
                            }
                        }
                        if let util = extra.utilization {
                            UsageProgressBar(fraction: util / 100)
                        }
                        Text(String(format: "$%.2f / $%.2f", extra.usedCreditsDisplay, extra.monthlyLimitDisplay))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            } else if !viewModel.isLoading {
                Text("No usage data available.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if viewModel.isLoading && viewModel.usage == nil {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
            }

            if let lastUpdated = viewModel.lastUpdated {
                Text("Updated \(lastUpdated, style: .relative) ago")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Divider()

            if viewModel.debugMode {
                DebugStatsView()
            }

            HStack {
                Button("Sign Out") { viewModel.signOut() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.red)
                    .font(.caption)
                Spacer()
                Toggle("Launch at Login", isOn: Binding(
                    get: { viewModel.launchAtLogin },
                    set: { _ in viewModel.toggleLaunchAtLogin() }
                ))
                .toggleStyle(.checkbox)
                .font(.caption)
                .foregroundStyle(.secondary)
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Text("Refresh every")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                let vm = viewModel
                @Bindable var bvm = vm
                Stepper(value: $bvm.refreshIntervalMinutes, in: 1...60, step: 0.5) {
                    Text(viewModel.refreshIntervalMinutes.truncatingRemainder(dividingBy: 1) == 0
                         ? "\(Int(viewModel.refreshIntervalMinutes)) min"
                         : String(format: "%.1f min", viewModel.refreshIntervalMinutes))
                        .font(.caption)
                        .monospacedDigit()
                }
                .onChange(of: viewModel.refreshIntervalMinutes) {
                    viewModel.refreshIntervalDidChange()
                }
                Spacer()
                Toggle("Debug", isOn: $bvm.debugMode)
                    .toggleStyle(.checkbox)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .onChange(of: viewModel.debugMode) {
                        viewModel.debugModeDidChange()
                    }
            }
        }
        .padding(12)
    }
}

// MARK: - Usage row

struct UsageRow: View {
    let label: String
    let value: Double
    let resetsAt: Date

    private var barColor: Color {
        value >= 70 ? .red : value >= 40 ? .yellow : .white
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(String(format: "%.1f%%", value))
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(barColor)
            }
            UsageProgressBar(fraction: value / 100)
            Text("Resets \(resetsAt, style: .relative)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }
}

// MARK: - Progress bar

struct UsageProgressBar: View {
    let fraction: Double

    private var barColor: Color {
        fraction >= 0.7 ? .red : fraction >= 0.4 ? .yellow : .white
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(.quaternary)
                    .frame(height: 6)
                RoundedRectangle(cornerRadius: 3)
                    .fill(barColor)
                    .frame(width: geo.size.width * min(max(fraction, 0), 1), height: 6)
            }
        }
        .frame(height: 6)
    }
}

// MARK: - Login view (unauthenticated)

struct LoginView: View {
    @Environment(ClaudeUsageViewModel.self) var viewModel
    @State private var pastedInput = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Claude Usage")
                .font(.headline)

            if !viewModel.authURLOpened {
                Text("Sign in with your Anthropic account to monitor your Claude usage limits.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button("Sign In with Claude") {
                    viewModel.openAuthPage()
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
            } else {
                Text("After approving in the browser, copy the full URL from the address bar and paste it here:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                TextField("https://console.anthropic.com/oauth/code/callback?code=…", text: $pastedInput, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
                    .lineLimit(6...12)

                HStack(spacing: 8) {
                    Button("Back") {
                        viewModel.authURLOpened = false
                        pastedInput = ""
                        viewModel.error = nil
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)

                    Spacer()

                    if viewModel.isLoading {
                        ProgressView()
                    }

                    Button("Continue") {
                        Task { await viewModel.submitCode(pastedInput) }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(pastedInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isLoading)
                }
            }

            if let error = viewModel.error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }

            Divider()

            Button("Quit") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
    }
}

// MARK: - Debug Stats

struct DebugStatsView: View {
    @Environment(ClaudeUsageViewModel.self) var viewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("API Stats")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Reset") { viewModel.resetDebugStats() }
                    .buttonStyle(.plain)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            HStack(spacing: 12) {
                Label("\(viewModel.apiCallCount)", systemImage: "arrow.up.arrow.down")
                    .help("Total calls")
                Label("\(viewModel.apiSuccessCount)", systemImage: "checkmark.circle")
                    .foregroundStyle(.green)
                    .help("Successes")
                Label("\(viewModel.apiErrorCount)", systemImage: "xmark.circle")
                    .foregroundStyle(viewModel.apiErrorCount > 0 ? .red : .secondary)
                    .help("Errors")
            }
            .font(.caption)
            .monospacedDigit()
        }
        .padding(8)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
    }
}

// MARK: - Cursor view

struct CursorView: View {
    @Environment(CursorUsageViewModel.self) var viewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {

            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Cursor Usage")
                        .font(.headline)
                    if let billing = viewModel.usage?.billing {
                        Text(billing.membershipType.capitalized + (billing.isYearlyPlan ? " (yearly)" : ""))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if let userId = viewModel.tokenInfo?.userId {
                        Text(userId)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button {
                    Task { await viewModel.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .rotationEffect(viewModel.isLoading ? .degrees(360) : .degrees(0))
                        .animation(
                            viewModel.isLoading
                                ? .linear(duration: 1).repeatForever(autoreverses: false)
                                : .default,
                            value: viewModel.isLoading
                        )
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isLoading)
            }

            Divider()

            if let error = viewModel.error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let usage = viewModel.usage {
                // Fast requests bar (included in plan)
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Included usage")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        if usage.isUnlimited {
                            Text("Unlimited")
                                .font(.caption)
                                .fontWeight(.medium)
                        } else {
                            Text(String(format: "%.0f%%", usage.totalPercentUsed))
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundStyle(usage.usageFraction >= 0.7 ? .red : usage.usageFraction >= 0.4 ? .yellow : .white)
                                .monospacedDigit()
                        }
                    }
                    UsageProgressBar(fraction: usage.usageFraction)
                    if let message = usage.displayMessage, !message.isEmpty {
                        Text(message)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    HStack {
                        Text("Cursor models \(String(format: "%.0f%%", usage.autoPercentUsed))")
                        Spacer()
                        Text("Other models \(String(format: "%.0f%%", usage.apiPercentUsed))")
                    }
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    HStack {
                        Text("Resets \(usage.billingCycleEnd, style: .date)")
                        if usage.onDemandEnabled {
                            Spacer()
                            Text(String(format: "On-demand $%.2f", usage.onDemandUsed / 100))
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                }

                // Model breakdown
                if !usage.modelBreakdown.isEmpty {
                    Divider()
                    VStack(alignment: .leading, spacing: 3) {
                        Text("By model")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ForEach(usage.modelBreakdown.prefix(6), id: \.model) { entry in
                            HStack {
                                Text(entry.model)
                                    .font(.caption2)
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                Spacer()
                                Text(String(format: "%.1f req", entry.requests))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                        }
                    }
                }

            } else if viewModel.isLoading {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
            }

            if let lastUpdated = viewModel.lastUpdated {
                Text("Updated \(lastUpdated, style: .relative) ago")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Divider()

            Button("Quit") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
    }
}

// MARK: - DeepSeek view

struct DeepSeekView: View {
    @Environment(DeepSeekUsageViewModel.self) var viewModel
    @State private var apiKeyInput = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {

            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("DeepSeek Usage")
                        .font(.headline)
                }
                Spacer()
                Button {
                    Task { await viewModel.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .rotationEffect(viewModel.isLoading ? .degrees(360) : .degrees(0))
                        .animation(
                            viewModel.isLoading
                                ? .linear(duration: 1).repeatForever(autoreverses: false)
                                : .default,
                            value: viewModel.isLoading
                        )
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isLoading)
            }

            Divider()

            if let error = viewModel.error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if viewModel.isAuthenticated {
                if let balance = viewModel.balance {
                    ForEach(balance.balanceInfos, id: \.currency) { info in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Total Balance")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(String(format: "%@ %.2f", info.currency, info.totalBalanceDouble))
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .monospacedDigit()
                            }
                            HStack {
                                Text("Topped Up")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                Spacer()
                                Text(String(format: "%@ %.2f", info.currency, info.toppedUpBalanceDouble))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                            HStack {
                                Text("Granted")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                Spacer()
                                Text(String(format: "%@ %.2f", info.currency, info.grantedBalanceDouble))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                        }
                    }

                    if !balance.isAvailable {
                        Label("Balance too low for API calls", systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.yellow)
                    }
                } else if !viewModel.isLoading {
                    Text("No balance data available.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if viewModel.isLoading && viewModel.balance == nil {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                }

                if let lastUpdated = viewModel.lastUpdated {
                    Text("Updated \(lastUpdated, style: .relative) ago")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                Divider()

                HStack {
                    Button("Remove Key") { viewModel.signOut() }
                        .buttonStyle(.plain)
                        .foregroundStyle(.red)
                        .font(.caption)
                    Spacer()
                    Button("Quit") { NSApplication.shared.terminate(nil) }
                        .buttonStyle(.plain)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Enter your DeepSeek API key to monitor your account balance.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 6) {
                    TextField("sk-...", text: $apiKeyInput)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption)

                    Button("Save") {
                        viewModel.saveKey(apiKeyInput)
                        apiKeyInput = ""
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                HStack {
                    Text("Get your API key at platform.deepseek.com/api_keys")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                Divider()

                Button("Quit") { NSApplication.shared.terminate(nil) }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
    }
}

// MARK: - OpenRouter view

struct OpenRouterView: View {
    @Environment(OpenRouterUsageViewModel.self) var viewModel
    @State private var apiKeyInput = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {

            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("OpenRouter Usage")
                        .font(.headline)
                    if let remaining = viewModel.usage?.credits.remaining {
                        Text(String(format: "$%.2f remaining", remaining))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button {
                    Task { await viewModel.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .rotationEffect(viewModel.isLoading ? .degrees(360) : .degrees(0))
                        .animation(
                            viewModel.isLoading
                                ? .linear(duration: 1).repeatForever(autoreverses: false)
                                : .default,
                            value: viewModel.isLoading
                        )
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isLoading)
            }

            Divider()

            if let error = viewModel.error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if viewModel.isAuthenticated {
                if let usage = viewModel.usage {
                    let credits = usage.credits
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Account credits")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(String(format: "$%.2f / $%.2f", credits.totalUsage, credits.totalCredits))
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundStyle(
                                    credits.fraction >= 0.7 ? .red
                                        : credits.fraction >= 0.4 ? .yellow
                                        : .white
                                )
                                .monospacedDigit()
                        }
                        UsageProgressBar(fraction: credits.fraction)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        creditRow("Today", usage.usageDaily)
                        creditRow("This week", usage.usageWeekly)
                        creditRow("This month", usage.usageMonthly)
                        if usage.byokUsage > 0 {
                            creditRow("BYOK", usage.byokUsage)
                        }
                    }

                    if !usage.rankedKeys.isEmpty {
                        Divider()
                        VStack(alignment: .leading, spacing: 3) {
                            Text("By key")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            ForEach(usage.rankedKeys.prefix(6)) { key in
                                HStack {
                                    Text(key.displayName)
                                        .font(.caption2)
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                    Spacer()
                                    Text(String(format: "$%.2f", key.usageMonthly ?? 0))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .monospacedDigit()
                                }
                            }
                        }
                    }
                } else if !viewModel.isLoading {
                    Text("No usage data available.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if viewModel.isLoading && viewModel.usage == nil {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                }

                if let lastUpdated = viewModel.lastUpdated {
                    Text("Updated \(lastUpdated, style: .relative) ago")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                Divider()

                HStack {
                    Button("Remove Key") { viewModel.signOut() }
                        .buttonStyle(.plain)
                        .foregroundStyle(.red)
                        .font(.caption)
                    Spacer()
                    Button("Quit") { NSApplication.shared.terminate(nil) }
                        .buttonStyle(.plain)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Enter an OpenRouter management key to monitor account credits and per-key usage. Regular inference keys will not work.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 6) {
                    TextField("sk-or-v1-...", text: $apiKeyInput)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption)

                    Button("Save") {
                        viewModel.saveKey(apiKeyInput)
                        apiKeyInput = ""
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                HStack {
                    Text("Create one at openrouter.ai/settings/keys")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                Divider()

                Button("Quit") { NSApplication.shared.terminate(nil) }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
    }

    private func creditRow(_ label: String, _ amount: Double) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(String(format: "$%.2f", amount))
                .font(.caption)
                .fontWeight(.medium)
                .monospacedDigit()
        }
    }
}

#Preview {
    MenuBarView()
        .environment(ClaudeUsageViewModel())
        .environment(CursorUsageViewModel())
        .environment(DeepSeekUsageViewModel())
        .environment(OpenRouterUsageViewModel())
}
