import SwiftUI

private enum RootTab: Hashable {
    case home
    case express
    case drill
    case review
}

/// Root tab navigation. Screen list: see docs/DESIGN.md.
struct RootView: View {
    @State private var selection: RootTab

    init() {
        #if DEBUG
        let initialSelection: RootTab = ProcessInfo.processInfo.arguments.contains("--design-express-fixture")
            ? .express
            : .home
        #else
        let initialSelection: RootTab = .home
        #endif
        _selection = State(initialValue: initialSelection)
    }

    var body: some View {
        TabView(selection: $selection) {
            HomeView()
                .tabItem { Label("今日", systemImage: "sun.max") }
                .tag(RootTab.home)
            ExpressView()
                .tabItem { Label("表达", systemImage: "text.bubble") }
                .tag(RootTab.express)
            DrillView()
                .tabItem { Label("操练", systemImage: "repeat") }
                .tag(RootTab.drill)
            ReviewView()
                .tabItem { Label("复习", systemImage: "checklist") }
                .tag(RootTab.review)
        }
        .tint(Theme.accent)
    }
}

#Preview {
    RootView()
}
