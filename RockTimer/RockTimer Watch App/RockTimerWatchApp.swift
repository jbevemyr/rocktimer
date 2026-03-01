//
//  RockTimerApp.swift
//  RockTimer Watch App
//
//  Created by Katrin Boberg Bevemyr on 24/2/2026.
//

import SwiftUI

@main
struct RockTimerWatchApp: App {
    @StateObject private var state = RockTimerState()
    @StateObject private var client: RockTimerClient

    init() {
        let s = RockTimerState()
        _state = StateObject(wrappedValue: s)
        // watchOS uses polling since WebSocket support is limited
        _client = StateObject(wrappedValue: RockTimerClient(state: s, usePolling: true))
    }

    var body: some Scene {
        WindowGroup {
            WatchContentView()
                .environmentObject(state)
                .environmentObject(client)
        }
    }
}


