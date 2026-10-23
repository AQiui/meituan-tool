import Foundation

/// 设置持久化(Documents/settings.json)
final class SettingsStore {
    private let fileURL: URL
    private(set) var settings: AppSettings = .default

    init(filename: String = "settings.json") {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        fileURL = docs.appendingPathComponent(filename)
        load()
    }

    func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) else {
            settings = .default
            return
        }
        settings = decoded
    }

    func save() {
        guard let data = try? JSONEncoder.pretty.encode(settings) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    func update(_ settings: AppSettings) {
        self.settings = settings
        save()
    }
}
