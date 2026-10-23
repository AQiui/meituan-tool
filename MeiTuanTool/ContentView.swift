import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView {
            HomeView()
                .tabItem {
                    Label("首页", systemImage: "house.fill")
                }
            AccountsView()
                .tabItem {
                    Label("账号", systemImage: "person.2.fill")
                }
            LogsView()
                .tabItem {
                    Label("日志", systemImage: "list.bullet.rectangle.fill")
                }
            SettingsView()
                .tabItem {
                    Label("设置", systemImage: "gear")
                }
        }
        .tint(Theme.red)
        .onAppear {
            NotificationService.shared.requestAuthorizationIfNeeded()
        }
        .onChange(of: scenePhase) { phase in
            // 每次回到前台都尝试登记一次后台刷新
            if phase == .active {
                BackgroundService.shared.scheduleNextRefresh()
            }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState.shared)
}
