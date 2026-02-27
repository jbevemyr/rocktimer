import SwiftUI

@main
struct SplitStoneWatchApp: App {
    @StateObject private var state = SplitStoneState()
    @StateObject private var client: SplitStoneClient

    init() {
        let s = SplitStoneState()
        _state = StateObject(wrappedValue: s)
        // watchOS uses polling since WebSocket support is limited
        _client = StateObject(wrappedValue: SplitStoneClient(state: s, usePolling: true))
    }

    var body: some Scene {
        WindowGroup {
            WatchContentView()
                .environmentObject(state)
                .environmentObject(client)
        }
    }
}
