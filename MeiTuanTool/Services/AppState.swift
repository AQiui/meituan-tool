import Foundation
import SwiftUI

/// 应用状态中心:统一管理账号、设置、日志和执行状态
@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    // MARK: - 可观察状态
    @Published var accounts: [Account] = []
    @Published var settings: AppSettings = .default
    @Published var logs: [LogEntry] = []
    @Published var config: EndpointConfig = .load()

    @Published var isRunning = false
    @Published var progressText = ""
    @Published var reports: [AccountReport] = []
    @Published var lastRunAt: Date?

    // MARK: - 存储
    private let accountStore = AccountStore()
    private let logStore = LogStore()
    private let settingsStore = SettingsStore()
    private var runTask: Task<Void, Never>?

    private init() {
        accounts = accountStore.accounts
        settings = settingsStore.settings
        logs = logStore.logs
    }

    // MARK: - 账号管理

    func addAccount(_ account: Account) {
        accountStore.add(account)
        accounts = accountStore.accounts
    }

    func addAccounts(_ newAccounts: [Account]) {
        accountStore.add(newAccounts)
        accounts = accountStore.accounts
    }

    func updateAccount(_ account: Account) {
        accountStore.update(account)
        accounts = accountStore.accounts
    }

    func deleteAccount(at offsets: IndexSet) {
        accountStore.remove(atOffsets: offsets)
        accounts = accountStore.accounts
    }

    func deleteAccount(id: String) {
        accountStore.remove(id: id)
        accounts = accountStore.accounts
    }

    /// 导出账号 JSON(备份用,含 token,注意保管)
    func exportAccountsData() -> Data? {
        try? JSONEncoder.pretty.encode(accounts)
    }

    // MARK: - 设置

    func updateSettings(_ mutate: (inout AppSettings) -> Void) {
        var s = settings
        mutate(&s)
        settingsStore.update(s)
        settings = s
    }

    func clearLogs() {
        logStore.clear()
        logs = logStore.logs
    }

    func reloadConfig() {
        config = EndpointConfig.load()
    }

    func resetConfigOverride() {
        EndpointConfig.resetOverride()
        config = EndpointConfig.load()
    }

    // MARK: - 执行

    func runOptions(scope: RunScope) -> TaskRunner.Options {
        TaskRunner.Options(
            scope: scope,
            useRandomCity: settings.useRandomCity,
            fixedCityName: settings.defaultCityName,
            usePropIfAvailable: settings.usePropIfAvailable,
            smallRedToBeanThreshold: settings.smallRedToBeanThreshold,
            exchangeBeanThreshold: settings.exchangeBeanThreshold,
            includeExtraTasks: settings.includeExtraTasks,
            includeMemberTasks: settings.includeMemberTasks
        )
    }

    /// 今日已执行次数(按日志统计)
    var todayRunCount: Int {
        logs.filter { Calendar.current.isDateInToday($0.date) }.count
    }

    /// 一键执行
    /// - Parameters:
    ///   - scope: 执行范围
    ///   - trigger: 触发来源(手动/快捷指令/后台刷新)
    ///   - notify: 完成后是否弹本地通知
    ///   - completion: 完成回调(参数: 是否全部成功),供后台任务标记完成
    func run(scope: RunScope? = nil,
             trigger: String = "手动",
             notify: Bool = true,
             completion: ((Bool) -> Void)? = nil) {
        guard !isRunning else { completion?(false); return }
        guard !accounts.isEmpty else {
            progressText = "请先在「账号」页添加美团账号"
            completion?(false)
            return
        }

        let finalScope = scope ?? settings.scope
        isRunning = true
        reports = []
        progressText = "开始执行(\(finalScope.title))"

        runTask = Task { [weak self] in
            guard let self else { return }
            let outcome = await TaskRunner().run(
                accounts: self.accounts,
                options: self.runOptions(scope: finalScope),
                trigger: trigger,
                onProgress: { text in
                    await MainActor.run { self.progressText = text }
                }
            )
            await MainActor.run {
                self.finish(outcome: outcome, notify: notify, completion: completion)
            }
        }
    }

    func cancelRun() {
        runTask?.cancel()
        runTask = nil
        isRunning = false
        progressText = "已取消"
    }

    private func finish(outcome: RunOutcome, notify: Bool, completion: ((Bool) -> Void)?) {
        isRunning = false
        reports = outcome.reports
        lastRunAt = Date()
        progressText = "执行完成 · \(outcome.summary)"

        // 更新账号最近执行状态
        for report in outcome.reports {
            if let index = accounts.firstIndex(where: { $0.id == report.accountId }) {
                accounts[index].lastRunAt = report.finishedAt
                accounts[index].lastRunOK = report.ok
                accounts[index].lastRunSummary = report.tokenExpired
                    ? "token 失效,需重新获取"
                    : report.summary
            }
        }
        accountStore.replaceAll(accounts)

        // 写日志
        let entry = LogEntry(date: Date(),
                             trigger: outcome.trigger,
                             scope: outcome.scope,
                             reports: outcome.reports,
                             summary: outcome.summary)
        logStore.add(entry)
        logs = logStore.logs

        if notify && settings.notifyOnFinish {
            NotificationService.shared.postRunResult(outcome)
        }
        completion?(!outcome.hadFailure)
    }

    // MARK: - URL Scheme 触发(快捷指令自动化)

    func runFromScheme(_ request: SchemeRequest) {
        BackgroundService.shared.beginBackgroundTask()
        run(scope: request.scope, trigger: "快捷指令", notify: request.notify) { _ in
            BackgroundService.shared.endBackgroundTask()
        }
    }
}
