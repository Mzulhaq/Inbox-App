import SwiftUI

struct RootView: View {
    @AppStorage("hasOnboarded") private var hasOnboarded = false

    var body: some View {
        if hasOnboarded {
            MainTabView()
        } else {
            OnboardingView { hasOnboarded = true }
        }
    }
}

struct MainTabView: View {
    var body: some View {
        TabView {
            InboxView()
                .tabItem { Label("Inbox", systemImage: "tray.fill") }
            SourcesView()
                .tabItem { Label("Sources", systemImage: "link") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
    }
}

#Preview {
    RootView()
        .modelContainer(PreviewData.container)
}
