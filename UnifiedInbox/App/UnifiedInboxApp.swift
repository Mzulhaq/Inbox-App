import SwiftUI
import SwiftData

@main
struct UnifiedInboxApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(for: [InboxItem.self, ConnectedSource.self])
    }
}
