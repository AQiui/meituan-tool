import SwiftUI

@main
struct MeiTuanToolApp: App {
    /// 用于在 didFinishLaunching 中注册后台任务
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(AppState.shared)
                .onOpenURL { url in
                    // 快捷指令 / URL Scheme 入口:meituantool://run
                    if let request = URLSchemeRouter.handle(url) {
                        AppState.shared.runFromScheme(request)
                    }
                }
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // 后台任务必须在启动阶段注册
        BackgroundService.shared.registerTasks()
        return true
    }
}
