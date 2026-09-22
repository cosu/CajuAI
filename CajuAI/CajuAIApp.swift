//
//  CajuAIApp.swift
//  CajuAI
//
//  Created by Cosmin Dumitru on 26/03/2026.
//

import SwiftUI

@main
struct CajuAIApp: App {
    @State private var viewModel = ClaudeUsageViewModel()
    @State private var cursorViewModel = CursorUsageViewModel()
    @State private var deepSeekViewModel = DeepSeekUsageViewModel()
    @State private var openRouterViewModel = OpenRouterUsageViewModel()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environment(viewModel)
                .environment(cursorViewModel)
                .environment(deepSeekViewModel)
                .environment(openRouterViewModel)
        } label: {
            let status = MenuBarUsage.pick([
                viewModel.menuBarUsage,
                cursorViewModel.menuBarUsage,
                deepSeekViewModel.menuBarUsage,
                openRouterViewModel.menuBarUsage,
            ])
            if let status {
                Label(status.text, systemImage: status.systemImage)
                    .labelStyle(.titleAndIcon)
            } else {
                Image(systemName: "c.circle")
            }
        }
        .menuBarExtraStyle(.window)
    }
}
