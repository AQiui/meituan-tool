import SwiftUI

struct LogsView: View {
    @EnvironmentObject var appState: AppState
    @State private var showClearConfirm = false

    private var grouped: [(key: String, value: [LogEntry])] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd"
        let dict = Dictionary(grouping: appState.logs) { formatter.string(from: $0.date) }
        return dict.sorted { $0.key > $1.key }
    }

    var body: some View {
        NavigationView {
            List {
                if appState.logs.isEmpty {
                    Section {
                        Text("还没有执行记录,去首页点「一键签到 + 领券」试试")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                ForEach(grouped, id: \.key) { group in
                    Section(header: Text(group.key)) {
                        ForEach(group.value) { entry in
                            NavigationLink(destination: LogDetailView(entry: entry)) {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(entry.date, format: .dateTime.hour().minute().second())
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                        Text(entry.trigger)
                                            .font(.caption2)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Theme.card)
                                            .cornerRadius(4)
                                        Spacer()
                                        Text(entry.scopeTitle)
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                    Text(entry.summary)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .padding(.vertical, 2)
                            }
                        }
                    }
                }
            }
            .navigationTitle("执行日志")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("清空") { showClearConfirm = true }
                        .disabled(appState.logs.isEmpty)
                        .font(.subheadline)
                }
            }
            .confirmationDialog("清空全部执行日志?", isPresented: $showClearConfirm, titleVisibility: .visible) {
                Button("清空", role: .destructive) { appState.clearLogs() }
                Button("取消", role: .cancel) {}
            }
        }
    }
}

/// 单条日志详情:展示每个账号每个步骤
struct LogDetailView: View {
    let entry: LogEntry

    var body: some View {
        List {
            Section {
                infoRow("触发方式", entry.trigger)
                infoRow("执行范围", entry.scopeTitle)
                infoRow("时间", TimeFormat.string(entry.date))
                infoRow("结果", entry.summary)
            }
            ForEach(entry.reports) { report in
                Section(header: Text(report.accountName)) {
                    ForEach(report.steps) { step in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: step.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundColor(step.success ? Theme.green : Theme.red)
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
        }
        .navigationTitle("日志详情")
        .navigationBarTitleDisplayMode(.inline)
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
    LogsView()
        .environmentObject(AppState.shared)
}
