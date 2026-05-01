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

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environment(viewModel)
                .environment(cursorViewModel)
        } label: {
            let label = viewModel.menuBarLabel
            if label.isEmpty {
                Image(systemName: "c.circle")
            } else {
                Label(label, systemImage: "c.circle.fill")
                    .labelStyle(.titleAndIcon)
            }
        }
        .menuBarExtraStyle(.window)
    }
}
