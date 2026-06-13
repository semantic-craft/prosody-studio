import SwiftUI
import ResponsayCore

/// Minimal macOS shell for the prosody studio (Phase 3 — gets the target
/// building and runnable). The real UI is the upcoming fluent-based redesign;
/// for now this hosts the two migrated screens so the app launches.
@main
struct ProsodyStudioApp: App {
    var body: some Scene {
        WindowGroup {
            StudioRootView()
                .frame(minWidth: 920, minHeight: 620)
        }
    }
}

private struct StudioRootView: View {
    private enum Tab: Hashable { case pronunciation, studio }
    @State private var tab: Tab = .pronunciation

    var body: some View {
        TabView(selection: $tab) {
            PronunciationScreen(seed: nil)
                .tabItem { Label("发音", systemImage: "waveform") }
                .tag(Tab.pronunciation)
            StudioScreen()
                .tabItem { Label("练习室", systemImage: "brain.head.profile") }
                .tag(Tab.studio)
        }
        // 303 — the follow-read card's「练错词」exit jumps to the studio tab.
        .onReceive(NotificationCenter.default.publisher(for: .init("OpenStudioScreen"))) { _ in
            tab = .studio
        }
    }
}
