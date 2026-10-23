import SwiftUI
import UIKit

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var showShare = false
    @State private var shareItems: [Any] = []
    @State private var showCopied = false
    @State private var showCredentialImport = false
    @State private var importText = ""
    @State private var importMessage = ""

    private var scopeBinding: Binding<String> {
        Binding(
            get: { appState.settings.defaultScope },
            set: { v in appState.updateSettings { $0.defaultScope = v } }
        )
    }

    var body: some View {
        NavigationView {
            Form {
                notificationSection
                automationSection
                strategySection
                memberSection
                configSection
                dataSection
                aboutSection
            }
            .navigationTitle("设置")
            .sheet(isPresented: $showShare) {
                ShareSheet(items: shareItems)
            }
            .sheet(isPresented: $showCredentialImport) {
                credentialImportSheet
            }
        }
    }

    // MARK: 黑金会员监控

    private var memberSection: some View {
        Section(header: Text("黑金会员监控"),
                footer: Text("实测结论:签到领成长值接口(receiveAndOpUserTask)带 mtgsig 密码学校验(无签名 code=4 / 伪造签名 403),第三方 App 无法自动重放;而查询接口(会员信息、任务列表)只需 Cookie+Token,可全自动。因此采用「自动监控 + 未签到提醒 + 一键跳转美团 APP」策略,签到点一下 3 秒完成。")) {
            Toggle("开启会员监控", isOn: Binding(
                get: { appState.settings.memberMonitorEnabled },
                set: { v in appState.updateSettings { $0.memberMonitorEnabled = v } }
            ))

            Button("导入抓包凭证(HAR / 请求链接 / Cookie)") { showCredentialImport = true }
                .disabled(appState.memberChecking)

            infoRow("Cookie", appState.settings.memberCookie.isEmpty ? "未导入" : "已导入 \(appState.settings.memberCookie.count) 字符")
            infoRow("Token", appState.settings.memberToken.isEmpty ? "未导入" : "\(appState.settings.memberToken.prefix(12))…")
            infoRow("userId", appState.settings.memberUserId.isEmpty ? "未导入" : appState.settings.memberUserId)

            if let status = appState.memberStatus {
                infoRow("会员等级", status.ok ? "\(status.levelName) \(status.levelShow)-\(status.subLevel)" : "—")
                infoRow("成长值", status.ok ? "\(status.growthValue) / \(status.levelEnd)" : "—")
                infoRow("今日签到", status.signSummary)
            }

            Button("立即检查会员状态") { appState.memberCheck() }
                .disabled(appState.memberChecking || !appState.memberCredentialReady)

            Button("打开美团 APP 签到") { openMeituan() }

            if !appState.settings.memberCookie.isEmpty || !appState.settings.memberToken.isEmpty {
                Button("清除会员凭证", role: .destructive) {
                    appState.updateSettings {
                        $0.memberCookie = ""
                        $0.memberToken = ""
                        $0.memberUserId = ""
                    }
                    appState.memberStatus = nil
                }
            }
        }
    }

    /// 凭证导入面板:粘贴抓包内容,自动解析三项凭证
    private var credentialImportSheet: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 12) {
                Text("在美团 APP 内打开会员中心并点一次签到,用 Stream/Thor/Charles 抓包,任选其一粘贴到此:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                VStack(alignment: .leading, spacing: 4) {
                    Text("1. HAR 全文(推荐):Stream 抓包 → 分享 → 全选复制")
                    Text("2. 请求链接:复制 member.meituan.com/…/queryMemberInfo?… 的完整 URL")
                    Text("3. Cookie 字符串(Token/userId 仍需另外提供)")
                }
                .font(.caption2)
                .foregroundColor(.secondary)

                TextEditor(text: $importText)
                    .font(.system(.caption, design: .monospaced))
                    .frame(minHeight: 160)
                    .padding(6)
                    .background(Color(.tertiarySystemGroupedBackground))
                    .cornerRadius(10)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)

                if !importMessage.isEmpty {
                    Text(importMessage)
                        .font(.caption)
                        .foregroundColor(importMessage.hasPrefix("解析失败") ? Theme.red : Theme.green)
                }

                Button("解析并保存") {
                    guard let result = MemberCredentialImporter.parse(importText) else {
                        importMessage = "解析失败:未识别到有效凭证,请粘贴 HAR 全文或完整请求链接"
                        return
                    }
                    appState.updateSettings {
                        if !result.cookie.isEmpty { $0.memberCookie = result.cookie }
                        if !result.token.isEmpty { $0.memberToken = result.token }
                        if !result.userId.isEmpty { $0.memberUserId = result.userId }
                    }
                    var missing: [String] = []
                    if appState.settings.memberCookie.isEmpty { missing.append("Cookie") }
                    if appState.settings.memberToken.isEmpty { missing.append("Token") }
                    if appState.settings.memberUserId.isEmpty { missing.append("userId") }
                    importMessage = missing.isEmpty
                        ? "已保存(来源:\(result.source)),点「立即检查」验证"
                        : "已部分保存(来源:\(result.source)),还缺:\(missing.joined(separator: "、"))"
                }
                .disabled(importText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Spacer()
            }
            .padding()
            .navigationTitle("导入会员凭证")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { showCredentialImport = false }
                }
            }
        }
    }

    private func openMeituan() {
        guard let url = URL(string: "imeituan://www.meituan.com/home") else { return }
        if UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        } else if let web = URL(string: "https://i.meituan.com/") {
            UIApplication.shared.open(web)
        }
    }

    // MARK: 通知

    private var notificationSection: some View {
        Section(header: Text("通知"), footer: Text("执行完成后通过本地通知推送各账号结果摘要。")) {
            Toggle("完成后发送通知", isOn: Binding(
                get: { appState.settings.notifyOnFinish },
                set: { v in appState.updateSettings { $0.notifyOnFinish = v } }
            ))
            Button("发送测试通知") {
                NotificationService.shared.post(title: "美团助手", body: "测试通知:签到 + 领券服务运行正常")
            }
        }
    }

    // MARK: 自动化

    private var automationSection: some View {
        Section(header: Text("定时自动化"), footer: Text("iOS 不允许 App 长期后台运行,系统调度时机不固定;每天 11:00 / 17:00 / 21:00 抢券建议使用快捷指令个人自动化。")) {
            Toggle("允许后台刷新", isOn: Binding(
                get: { appState.settings.backgroundRefresh },
                set: { v in
                    appState.updateSettings { $0.backgroundRefresh = v }
                    if v { BackgroundService.shared.scheduleNextRefresh() }
                }
            ))
            VStack(alignment: .leading, spacing: 8) {
                Text("快捷指令 URL Scheme(点击复制)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                ForEach(URLSchemeRouter.sampleURLs, id: \.0) { url, desc in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(url)
                                .font(.system(.caption, design: .monospaced))
                            Text(desc)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Image(systemName: "doc.on.doc")
                            .foregroundColor(Theme.red)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        UIPasteboard.general.string = url
                        showCopied = true
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: 执行策略

    private var strategySection: some View {
        Section(header: Text("执行策略")) {
            Picker("默认执行范围", selection: scopeBinding) {
                Text("签到 + 领券").tag("all")
                Text("仅签到").tag("sign")
                Text("仅抢券").tag("coupon")
                Text("黑金会员检查").tag("member")
            }
            Toggle("随机城市定位", isOn: Binding(
                get: { appState.settings.useRandomCity },
                set: { v in appState.updateSettings { $0.useRandomCity = v } }
            ))
            if !appState.settings.useRandomCity {
                Picker("默认城市", selection: Binding(
                    get: { appState.settings.defaultCityName },
                    set: { v in appState.updateSettings { $0.defaultCityName = v } }
                )) {
                    ForEach(Cities.all.map { $0.name }, id: \.self) { city in
                        Text(city).tag(city)
                    }
                }
            }
            Toggle("有必中符时自动使用", isOn: Binding(
                get: { appState.settings.usePropIfAvailable },
                set: { v in appState.updateSettings { $0.usePropIfAvailable = v } }
            ))
            Stepper("小额券转红豆阈值:\(appState.settings.smallRedToBeanThreshold / 100) 元",
                    value: Binding(
                        get: { appState.settings.smallRedToBeanThreshold },
                        set: { v in appState.updateSettings { $0.smallRedToBeanThreshold = v } }
                    ), in: 100...1000, step: 100)
            Stepper(value: Binding(
                get: { appState.settings.exchangeBeanThreshold },
                set: { v in appState.updateSettings { $0.exchangeBeanThreshold = v } }
            ), in: 0...5000, step: 100) {
                Text(appState.settings.exchangeBeanThreshold == 0
                     ? "自动兑换必中符:关闭"
                     : "满 \(appState.settings.exchangeBeanThreshold) 红豆自动兑换")
            }
            Toggle("执行自定义任务(extraTasks)", isOn: Binding(
                get: { appState.settings.includeExtraTasks },
                set: { v in appState.updateSettings { $0.includeExtraTasks = v } }
            ))
        }
    }

    // MARK: 接口配置

    private var configSection: some View {
        Section(header: Text("接口配置"), footer: Text("美团调整接口时:把改好的 endpoints.json 通过「文件」App 放到本 App 文件夹即可覆盖,无需重新编译。")) {
            infoRow("接口域名", appState.config.baseURL)
            infoRow("接口数量", "\(appState.config.paths.count) 个")
            infoRow("自定义任务", "\(appState.config.extraTasks.count) 个")
            Button("重新加载配置") { appState.reloadConfig() }
            Button("恢复默认接口配置", role: .destructive) { appState.resetConfigOverride() }
        }
    }

    // MARK: 数据

    private var dataSection: some View {
        Section(header: Text("数据")) {
            Button("导出账号备份(含 token,请妥善保管)") {
                if let data = appState.exportAccountsData() {
                    shareItems = [data]
                    showShare = true
                }
            }
        }
    }

    // MARK: 关于

    private var aboutSection: some View {
        Section(header: Text("关于")) {
            infoRow("版本", Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
            VStack(alignment: .leading, spacing: 8) {
                Text("免责声明")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text("本工具仅供个人学习交流使用,所有操作均通过美团公开接口完成,请勿用于商业用途或频繁请求以免账号受限。接口失效时请以 docs/接口与抓包.md 为准更新 endpoints.json。")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 4)
        }
    }

    /// iOS 15 兼容的信息行(LabeledContent 需 iOS 16)
    private func infoRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppState.shared)
}
