import Foundation

/// 单个步骤的执行结果
struct StepResult: Identifiable, Codable, Equatable {
    var id: String = UUID().uuidString
    var title: String
    var success: Bool
    var detail: String = ""
    /// token 失效标记:失效时该账号后续步骤直接跳过
    var tokenExpired: Bool = false
    var at: Date = Date()
}

/// 单个账号一次完整执行的报告
struct AccountReport: Identifiable, Codable, Equatable {
    var id: String = UUID().uuidString
    var accountId: String
    var accountName: String
    var scope: String = "all"
    var steps: [StepResult] = []
    var startedAt: Date = Date()
    var finishedAt: Date = Date()

    var failedSteps: [StepResult] { steps.filter { !$0.success } }
    var ok: Bool { !steps.isEmpty && failedSteps.isEmpty }
    var tokenExpired: Bool { steps.contains { $0.tokenExpired } }

    var summary: String {
        let okCount = steps.count - failedSteps.count
        return "\(okCount)/\(steps.count) 步成功"
    }

    /// 通知/日志用的一行摘要
    var oneLineSummary: String {
        let icon = ok ? "✅" : (tokenExpired ? "⚠️" : "❌")
        return "\(icon) \(accountName): \(summary)\(tokenExpired ? " · token失效" : "")"
    }
}

/// 一条执行日志(一次批量执行,可包含多个账号的报告)
struct LogEntry: Identifiable, Codable, Equatable {
    var id: String = UUID().uuidString
    var date: Date = Date()
    /// 触发方式:手动 / 快捷指令 / 后台刷新 / 后台处理
    var trigger: String
    /// 执行范围:all / sign / coupon
    var scope: String
    var reports: [AccountReport] = []
    var summary: String = ""

    var scopeTitle: String { RunScope(rawValue: scope)?.title ?? scope }
}

/// 一次批量执行的总体结果
struct RunOutcome {
    var reports: [AccountReport] = []
    var trigger: String = "手动"
    var scope: String = "all"
    var startedAt: Date = Date()
    var finishedAt: Date = Date()

    var hadFailure: Bool { reports.contains { !$0.ok } }
    var okCount: Int { reports.filter { $0.ok }.count }

    var summary: String {
        guard !reports.isEmpty else { return "没有可执行的账号" }
        return "\(okCount)/\(reports.count) 个账号执行成功"
    }

    var notificationBody: String {
        reports.map { $0.oneLineSummary }.joined(separator: "\n")
    }
}
