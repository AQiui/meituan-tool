import Foundation
import UserNotifications

/// 本地通知:执行完成后推送结果摘要
@MainActor
final class NotificationService {
    static let shared = NotificationService()

    private init() {}

    /// 请求通知权限(App 启动时调用一次)
    nonisolated func requestAuthorizationIfNeeded() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    func postRunResult(_ outcome: RunOutcome) {
        let content = UNMutableNotificationContent()
        if outcome.reports.isEmpty {
            content.title = "美团助手"
            content.body = "没有可执行的账号"
        } else {
            content.title = outcome.hadFailure
                ? "美团助手:\(outcome.okCount)/\(outcome.reports.count) 个账号成功"
                : "美团助手:全部 \(outcome.reports.count) 个账号执行成功"
            content.body = outcome.notificationBody
        }
        content.sound = .default
        post(content)
    }

    func post(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        post(content)
    }

    /// 黑金会员今日未签到提醒
    func postSignReminder(_ status: MemberMonitor.Status) {
        let content = UNMutableNotificationContent()
        content.title = "黑金会员今日还没签到"
        var lines: [String] = []
        if !status.levelName.isEmpty {
            lines.append("\(status.levelName) \(status.levelShow)-\(status.subLevel) · 成长值 \(status.growthValue)")
        }
        if !status.signTaskTitle.isEmpty {
            lines.append("「\(status.signTaskTitle)」\(status.signProgress) 今日奖励待领取")
        }
        content.body = lines.isEmpty
            ? "打开美团 APP 会员中心完成签到,成长值 +1"
            : lines.joined(separator: "\n") + "\n点开本 APP 一键跳转美团"
        content.sound = .default
        post(content)
    }

    private func post(_ content: UNMutableNotificationContent) {
        let request = UNNotificationRequest(identifier: UUID().uuidString,
                                            content: content,
                                            trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
