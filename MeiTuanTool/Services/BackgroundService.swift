import Foundation
import UIKit
import BackgroundTasks

/// 后台能力:
/// 1. BGAppRefreshTask:系统调度的后台刷新(iOS 自行决定时机,精确定时请配合快捷指令)
/// 2. UIBackgroundTask:App 被 URL Scheme 唤起后在后台争取 ~30 秒把任务跑完
final class BackgroundService: NSObject {
    static let shared = BackgroundService()

    private let refreshTaskID = "com.meituantool.refresh"
    private let processingTaskID = "com.meituantool.processing"
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid

    // MARK: - 注册(必须在 didFinishLaunchingWithOptions 中调用)

    func registerTasks() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: refreshTaskID, using: nil) { task in
            BackgroundService.shared.handleAppRefresh(task as! BGAppRefreshTask)
        }
        BGTaskScheduler.shared.register(forTaskWithIdentifier: processingTaskID, using: nil) { task in
            BackgroundService.shared.handleProcessing(task as! BGProcessingTask)
        }
    }

    // MARK: - 调度后台刷新

    @MainActor
    func scheduleNextRefresh() {
        guard AppState.shared.settings.backgroundRefresh else { return }
        let request = BGAppRefreshTaskRequest(identifier: refreshTaskID)
        // 最快 30 分钟后;实际时机由系统决定
        request.earliestBeginDate = Date(timeIntervalSinceNow: 30 * 60)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            #if DEBUG
            print("BGTaskScheduler submit failed: \(error)")
            #endif
        }
    }

    private func handleAppRefresh(_ task: BGAppRefreshTask) {
        // 先登记下一次,避免重复提交失败
        Task { @MainActor in scheduleNextRefresh() }
        task.expirationHandler = {
            Task { @MainActor in AppState.shared.cancelRun() }
        }
        Task { @MainActor in
            AppState.shared.run(trigger: "后台刷新", notify: true) { success in
                task.setTaskCompleted(success: success)
            }
        }
    }

    private func handleProcessing(_ task: BGProcessingTask) {
        Task { @MainActor in scheduleNextRefresh() }
        task.expirationHandler = {
            Task { @MainActor in AppState.shared.cancelRun() }
        }
        Task { @MainActor in
            AppState.shared.run(trigger: "后台处理", notify: true) { success in
                task.setTaskCompleted(success: success)
            }
        }
    }

    // MARK: - 短时后台执行保活(URL Scheme 触发时)

    @MainActor
    func beginBackgroundTask() {
        guard backgroundTaskID == .invalid else { return }
        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "MeiTuanToolRun") { [weak self] in
            guard let self, self.backgroundTaskID != .invalid else { return }
            UIApplication.shared.endBackgroundTask(self.backgroundTaskID)
            self.backgroundTaskID = .invalid
        }
    }

    @MainActor
    func endBackgroundTask() {
        guard backgroundTaskID != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTaskID)
        backgroundTaskID = .invalid
    }
}
