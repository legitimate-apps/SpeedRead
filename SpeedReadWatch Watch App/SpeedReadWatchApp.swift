import SwiftUI

@main
struct SpeedReadWatch_Watch_AppApp: App {
    @StateObject private var syncService = WatchSyncService.shared
    @State private var selectedTab = 0

    var body: some Scene {
        WindowGroup {
            TabView(selection: $selectedTab) {
                NowReadingView()
                    .tag(0)
                    .containerBackground(Color.walnut.gradient, for: .tabView)

                WatchLibraryView()
                    .tag(1)
                    .containerBackground(Color.inkBlack.gradient, for: .tabView)
            }
            .tabViewStyle(.verticalPage)
            .environmentObject(syncService)
            .environment(\.selectedTab, $selectedTab)
            .onAppear { syncService.activate() }
        }
    }
}

// Environment key for tab selection
private struct SelectedTabKey: EnvironmentKey {
    static let defaultValue: Binding<Int> = .constant(0)
}

extension EnvironmentValues {
    var selectedTab: Binding<Int> {
        get { self[SelectedTabKey.self] }
        set { self[SelectedTabKey.self] = newValue }
    }
}
