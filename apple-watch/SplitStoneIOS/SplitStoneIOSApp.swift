import SwiftUI

@main
struct SplitStoneIOSApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

struct RootView: View {
    @StateObject private var state = SplitStoneState()
    @StateObject private var client: SplitStoneClient

    init() {
        let s = SplitStoneState()
        _state = StateObject(wrappedValue: s)
        _client = StateObject(wrappedValue: SplitStoneClient(state: s))
    }

    var body: some View {
        ContentView()
            .environmentObject(state)
            .environmentObject(client)
    }
}
