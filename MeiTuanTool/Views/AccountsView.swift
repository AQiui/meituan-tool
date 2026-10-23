import SwiftUI
import UIKit

struct AccountsView: View {
    @EnvironmentObject var appState: AppState
    @State private var showAddSheet = false
    @State private var editingAccount: Account?

    var body: some View {
        NavigationView {
            List {
                Section {
                    ForEach(appState.accounts) { account in
                        Button(action: { editingAccount = account }) {
                            AccountRow(account: account)
                        }
                        .foregroundColor(.primary)
                    }
                    .onDelete { offsets in
                        appState.deleteAccount(at: offsets)
                    }
                } header: {
                    Text("共 \(appState.accounts.count) 个账号")
                } footer: {
                    Text("token 失效后需重新获取:点击账号可查看/编辑,左滑可删除。")
                }
            }
            .navigationTitle("账号")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showAddSheet = true }) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                    }
                }
            }
            .sheet(isPresented: $showAddSheet) {
                AddAccountSheet()
                    .environmentObject(appState)
            }
            .sheet(item: $editingAccount) { account in
                EditAccountSheet(account: account)
                    .environmentObject(appState)
            }
        }
    }
}

/// 账号列表行
struct AccountRow: View {
    let account: Account

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(account.name)
                    .font(.headline)
                Text(account.maskedToken)
                    .font(.caption)
                    .foregroundColor(.secondary)
                if let last = account.lastRunAt {
                    Text("\(TimeFormat.string(last)) · \(account.lastRunSummary)")
                        .font(.caption2)
                        .foregroundColor(account.lastRunOK == true ? Theme.green : .orange)
                }
            }
            Spacer()
            if account.lastRunOK == false {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
            } else if account.lastRunOK == true {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundColor(Theme.green)
            }
        }
        .padding(.vertical, 4)
    }
}

/// 添加账号:网页登录(自动抓 token)/ 手动输入 / 批量导入
struct AddAccountSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var mode = 0
    @State private var manualName = ""
    @State private var manualToken = ""
    @State private var batchText = ""
    @State private var showWebLogin = false
    @State private var message = ""

    var body: some View {
        NavigationView {
            Form {
                Section {
                    Picker("添加方式", selection: $mode) {
                        Text("网页登录").tag(0)
                        Text("手动输入").tag(1)
                        Text("批量导入").tag(2)
                    }
                    .pickerStyle(.segmented)
                }

                switch mode {
                case 0:
                    webLoginSection
                case 1:
                    manualSection
                default:
                    batchSection
                }

                if !message.isEmpty {
                    Section {
                        Text(message)
                            .font(.caption)
                            .foregroundColor(Theme.red)
                    }
                }
            }
            .navigationTitle("添加账号")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("保存") { save() }
                        .disabled(mode == 0)
                }
            }
            .sheet(isPresented: $showWebLogin) {
                LoginWebView { token in
                    let name = manualName.trimmingCharacters(in: .whitespaces)
                    appState.addAccount(Account(
                        name: name.isEmpty ? "账号\(appState.accounts.count + 1)" : name,
                        token: token
                    ))
                    showWebLogin = false
                    dismiss()
                }
            }
        }
    }

    // MARK: 网页登录(推荐)

    private var webLoginSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Text("打开美团网页版并登录(支持美团 App 扫码或手机号验证码),登录成功后会自动抓取 token。")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Button(action: { showWebLogin = true }) {
                    Label("打开美团登录页", systemImage: "safari.fill")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Theme.yellow)
                        .foregroundColor(.black)
                        .cornerRadius(10)
                }
            }
            .padding(.vertical, 4)
        } header: {
            Text("网页登录(推荐,免抓包)")
        } footer: {
            Text("登录成功后自动识别并保存 token。若未自动识别,可在登录页内点「手动获取」。")
        }
    }

    // MARK: 手动输入

    private var manualSection: some View {
        Section {
            TextField("备注名(可选)", text: $manualName)
            VStack(alignment: .leading, spacing: 6) {
                Text("token")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextEditor(text: $manualToken)
                    .frame(minHeight: 80)
                    .font(.system(.body, design: .monospaced))
            }
            if let clip = UIPasteboard.general.string, !clip.isEmpty {
                Button("从剪贴板粘贴") { manualToken = clip.trimmingCharacters(in: .whitespacesAndNewlines) }
            }
        } header: {
            Text("手动输入 token")
        } footer: {
            Text("只要 token 值本身,不带 \"token=\" 前缀;青龙脚本用的 meituanCookie 也是这个值。")
        }
    }

    // MARK: 批量导入

    private var batchSection: some View {
        Section {
            TextEditor(text: $batchText)
                .frame(minHeight: 120)
                .font(.system(.body, design: .monospaced))
        } header: {
            Text("批量导入(每行一个)")
        } footer: {
            Text("支持格式:token、备注=token、备注:token。账号间可用换行分隔。")
        }
    }

    // MARK: 保存

    private func save() {
        switch mode {
        case 1:
            let token = manualToken.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !token.isEmpty else {
                message = "token 不能为空"
                return
            }
            let name = manualName.trimmingCharacters(in: .whitespaces)
            appState.addAccount(Account(name: name.isEmpty ? "账号\(appState.accounts.count + 1)" : name,
                                        token: token))
            dismiss()
        default:
            let parsed = Account.parseBatch(batchText)
            guard !parsed.isEmpty else {
                message = "没有解析到有效 token,请检查格式"
                return
            }
            appState.addAccounts(parsed)
            dismiss()
        }
    }
}

/// 编辑账号
struct EditAccountSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    let account: Account
    @State private var name: String
    @State private var token: String
    @State private var useFixedLocation: Bool
    @State private var fixedCityName: String
    @State private var showDeleteConfirm = false

    init(account: Account) {
        self.account = account
        _name = State(initialValue: account.name)
        _token = State(initialValue: account.token)
        _useFixedLocation = State(initialValue: account.useFixedLocation)
        _fixedCityName = State(initialValue: account.fixedCityName)
    }

    var body: some View {
        NavigationView {
            Form {
                Section("基本信息") {
                    TextField("备注名", text: $name)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("token")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextEditor(text: $token)
                            .frame(minHeight: 80)
                            .font(.system(.body, design: .monospaced))
                    }
                }

                Section("定位设置") {
                    Toggle("固定城市(关闭则每次随机)", isOn: $useFixedLocation)
                    if useFixedLocation {
                        Picker("城市", selection: $fixedCityName) {
                            ForEach(Cities.all.map { $0.name }, id: \.self) { city in
                                Text(city).tag(city)
                            }
                        }
                    }
                }

                Section {
                    Button("删除该账号", role: .destructive) {
                        showDeleteConfirm = true
                    }
                }
            }
            .navigationTitle("编辑账号")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("保存") { save() }
                        .disabled(token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .confirmationDialog("确认删除该账号?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                Button("删除", role: .destructive) {
                    appState.deleteAccount(id: account.id)
                    dismiss()
                }
                Button("取消", role: .cancel) {}
            }
        }
    }

    private func save() {
        var updated = account
        updated.name = name.trimmingCharacters(in: .whitespaces).isEmpty ? account.name : name.trimmingCharacters(in: .whitespaces)
        updated.token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.useFixedLocation = useFixedLocation
        updated.fixedCityName = fixedCityName
        if let city = Cities.named(fixedCityName) {
            updated.latitude = city.latitude
            updated.longitude = city.longitude
        }
        updated.updatedAt = Date()
        appState.updateAccount(updated)
        dismiss()
    }
}

#Preview {
    AccountsView()
        .environmentObject(AppState.shared)
}
