import SwiftUI
import UIKit

struct HomeView: View {
    @EnvironmentObject var appState: AppState

    /// 最近一次执行后状态异常的账号数
    private var abnormalCount: Int {
        appState.accounts.filter { $0.lastRunOK == false }.count
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    statsCard
                    runButtons
                    quickOptions
                    if appState.memberChecking {
                        memberCheckingCard
                    } else if let member = appState.memberStatus {
                        memberStatusCard(member)
                    }
                    if appState.isRunning {
                        runningCard
                    }
                    if !appState.reports.isEmpty {
                        reportsSection
                    } else if !appState.isRunning {
                        emptyHint
                    }
                    tipsCard
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("美团助手")
        }
    }

    // MARK: 账号统计卡片

    private var statsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 0) {
                statItem(title: "账号", value: "\(appState.accounts.count)", color: .primary)
                cellDivider
                statItem(title: "异常", value: "\(abnormalCount)",
                         color: abnormalCount > 0 ? Theme.red : .secondary)
                cellDivider
                statItem(title: "今日执行", value: "\(appState.todayRunCount)", color: .primary)
            }
            if let last = appState.lastRunAt {
                Text("上次执行:\(TimeFormat.string(last))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card)
        .cornerRadius(16)
    }

    private func statItem(title: String, value: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(color)
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var cellDivider: some View {
        Rectangle()
            .fill(Color(.separator))
            .frame(width: 1, height: 32)
    }

    // MARK: 执行按钮

    private var runButtons: some View {
        VStack(spacing: 12) {
            Button(action: { appState.run() }) {
                HStack(spacing: 8) {
                    Image(systemName: "bolt.circle.fill")
                    Text("一键签到 + 领券")
                        .fontWeight(.bold)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(appState.isRunning ? Color.gray : Theme.yellow)
                .foregroundColor(.black)
                .cornerRadius(14)
            }
            .disabled(appState.isRunning || appState.accounts.isEmpty)

            HStack(spacing: 12) {
                Button(action: { appState.run(scope: .sign) }) {
                    Text("仅签到")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Theme.card)
                        .foregroundColor(.primary)
                        .cornerRadius(12)
                }
                .disabled(appState.isRunning || appState.accounts.isEmpty)

                Button(action: { appState.run(scope: .coupon) }) {
                    Text("仅抢券")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Theme.card)
                        .foregroundColor(.primary)
                        .cornerRadius(12)
                }
                .disabled(appState.isRunning || appState.accounts.isEmpty)

                Button(action: { appState.memberCheck(notify: true) }) {
                    Text("会员检查")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Theme.card)
                        .foregroundColor(.primary)
                        .cornerRadius(12)
                }
                .disabled(appState.memberChecking || !appState.memberCredentialReady)
            }

            if appState.isRunning {
                Button(action: { appState.cancelRun() }) {
                    Text("取消执行")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Theme.card)
                        .foregroundColor(Theme.red)
                        .cornerRadius(12)
                }
            }
        }
    }

    // MARK: 快捷选项

    private var quickOptions: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle("随机城市定位(扩大红包池覆盖)", isOn: Binding(
                get: { appState.settings.useRandomCity },
                set: { v in appState.updateSettings { $0.useRandomCity = v } }
            ))
            Toggle("有必中符时自动使用", isOn: Binding(
                get: { appState.settings.usePropIfAvailable },
                set: { v in appState.updateSettings { $0.usePropIfAvailable = v } }
            ))
            Toggle("黑金会员监控(未签到时提醒)", isOn: Binding(
                get: { appState.settings.memberMonitorEnabled },
                set: { v in appState.updateSettings { $0.memberMonitorEnabled = v } }
            ))
        }
        .font(.subheadline)
        .padding()
        .background(Theme.card)
        .cornerRadius(14)
    }

    // MARK: 会员状态

    private var memberCheckingCard: some View {
        HStack(spacing: 12) {
            ProgressView()
            Text("正在查询黑金会员状态…")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
        }
        .padding()
        .background(Theme.card)
        .cornerRadius(14)
    }

    private func memberStatusCard(_ status: MemberMonitor.Status) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "crown.fill")
                    .foregroundColor(Theme.yellow)
                Text(status.ok ? "黑金会员" : "会员查询失败")
                    .font(.headline)
                Spacer()
                if let at = appState.memberLastCheckAt {
                    Text(TimeFormat.string(at))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            if status.ok {
                HStack(spacing: 0) {
                    memberStat(title: "等级", value: "\(status.levelShow)-\(status.subLevel)")
                    cellDivider
                    memberStat(title: "成长值", value: "\(status.growthValue)")
                    cellDivider
                    memberStat(title: "本级上限", value: "\(status.levelEnd)")
                }
                HStack(spacing: 6) {
                    Image(systemName: status.signedToday ? "checkmark.seal.fill" : "clock.badge.exclamationmark")
                        .foregroundColor(status.signedToday ? Theme.green : Theme.red)
                    Text(status.signSummary)
                        .font(.subheadline)
                        .foregroundColor(status.signedToday ? .primary : Theme.red)
                }
                if !status.signedToday {
                    Button(action: { openMeituan() }) {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.up.forward.app")
                            Text("打开美团 APP 签到")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Theme.yellow)
                        .foregroundColor(.black)
                        .cornerRadius(10)
                    }
                }
                if !status.otherTasks.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(status.otherTasks, id: \.self) { task in
                            Text("· \(task)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            } else {
                Text(status.error ?? "未知错误")
                    .font(.caption)
                    .foregroundColor(Theme.red)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card)
        .cornerRadius(14)
    }

    private func memberStat(title: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.headline)
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    /// 跳转美团 APP(会员中心为原生页面,URL Scheme 打开首页后由用户进入)
    private func openMeituan() {
        guard let url = URL(string: "imeituan://www.meituan.com/home") else { return }
        if UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        } else if let web = URL(string: "https://i.meituan.com/") {
            UIApplication.shared.open(web)
        }
    }

    // MARK: 执行中

    private var runningCard: some View {
        HStack(spacing: 12) {
            ProgressView()
            Text(appState.progressText)
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
        }
        .padding()
        .background(Theme.card)
        .cornerRadius(14)
    }

    // MARK: 结果

    private var reportsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("本次执行结果")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
            ForEach(appState.reports) { report in
                AccountReportCard(report: report)
            }
        }
    }

    private var emptyHint: some View {
        VStack(spacing: 8) {
            Image(systemName: "ticket.fill")
                .font(.largeTitle)
                .foregroundColor(Theme.yellow)
            Text("点击「一键签到 + 领券」开始")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    // MARK: 提示

    private var tipsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("精确定时自动化", systemImage: "clock.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(Theme.red)
            Text("iOS 不允许 App 常驻后台。每天 11:00 / 17:00 / 21:00 抢券,建议用「快捷指令」创建个人自动化,添加「打开 URL」动作,内容填:")
                .font(.caption)
                .foregroundColor(.secondary)
            Text("meituantool://run")
                .font(.system(.caption, design: .monospaced))
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.tertiarySystemGroupedBackground))
                .cornerRadius(8)
                .onTapGesture {
                    UIPasteboard.general.string = "meituantool://run"
                }
            Text("详细配置见 docs/快捷指令自动化.md")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card)
        .cornerRadius(14)
    }
}

/// 单账号执行报告卡片(可展开查看每个步骤)
struct AccountReportCard: View {
    let report: AccountReport
    @State private var expanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: { withAnimation(.easeInOut) { expanded.toggle() } }) {
                HStack(spacing: 8) {
                    Image(systemName: report.ok
                          ? "checkmark.seal.fill"
                          : (report.tokenExpired ? "exclamationmark.triangle.fill" : "xmark.seal.fill"))
                        .foregroundColor(report.ok ? Theme.green : (report.tokenExpired ? .orange : Theme.red))
                    Text(report.accountName)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    Spacer()
                    Text(report.summary)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(.plain)

            if expanded {
                ForEach(report.steps) { step in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: step.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundColor(step.success ? Theme.green : Theme.red)
                            .font(.subheadline)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(step.title)
                                .font(.subheadline)
                            if !step.detail.isEmpty {
                                Text(step.detail)
                                    .font(.caption)
                                    .foregroundColor(step.tokenExpired ? Theme.red : .secondary)
                            }
                        }
                    }
                }
            }
        }
        .padding()
        .background(Theme.card)
        .cornerRadius(14)
    }
}

#Preview {
    HomeView()
        .environmentObject(AppState.shared)
}
