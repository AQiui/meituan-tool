import Foundation

/// 快捷指令 / URL Scheme 入口
/// 用法示例(快捷指令"打开 URL"动作):
///   meituantool://run            全部流程
///   meituantool://run?tasks=sign 仅签到
///   meituantool://run?tasks=coupon 仅领券
///   meituantool://run?notify=0   完成后不弹通知
struct SchemeRequest {
    var scope: RunScope
    var notify: Bool
}

enum URLSchemeRouter {
    static let scheme = "meituantool"

    static func handle(_ url: URL) -> SchemeRequest? {
        guard url.scheme?.lowercased() == scheme else { return nil }
        let host = url.host?.lowercased() ?? ""
        guard host.isEmpty || host == "run" else { return nil }

        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let tasks = items.first(where: { $0.name == "tasks" })?.value ?? "all"
        let scope = RunScope(rawValue: tasks.lowercased()) ?? .all
        let notify = items.first(where: { $0.name == "notify" })?.value != "0"
        return SchemeRequest(scope: scope, notify: notify)
    }

    /// 帮助文案里展示的快捷指令链接
    static var sampleURLs: [(String, String)] {
        [
            ("meituantool://run", "签到 + 领券全流程"),
            ("meituantool://run?tasks=sign", "仅签到领红豆"),
            ("meituantool://run?tasks=coupon", "仅抢天天神券")
        ]
    }
}
