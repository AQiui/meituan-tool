import Foundation

/// 执行日志持久化(Documents/logs.json),最多保留 500 条
final class LogStore {
    private let fileURL: URL
    private(set) var logs: [LogEntry] = []
    private let capacity = 500

    init(filename: String = "logs.json") {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        fileURL = docs.appendingPathComponent(filename)
        load()
    }

    func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([LogEntry].self, from: data) else {
            logs = []
            return
        }
        logs = decoded
    }

    func save() {
        guard let data = try? JSONEncoder.pretty.encode(logs) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    func add(_ entry: LogEntry) {
        logs.insert(entry, at: 0)
        if logs.count > capacity {
            logs.removeLast(logs.count - capacity)
        }
        save()
    }

    func clear() {
        logs = []
        save()
    }

    /// 按日期分组(日期字符串 -> 当天日志,时间倒序)
    func groupedByDay() -> [(key: String, value: [LogEntry])] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd"
        let dict = Dictionary(grouping: logs) { formatter.string(from: $0.date) }
        return dict.sorted { $0.key > $1.key }
    }
}
