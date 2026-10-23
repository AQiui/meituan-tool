import Foundation

/// 账号持久化(Documents/accounts.json)
final class AccountStore {
    private let fileURL: URL
    private(set) var accounts: [Account] = []

    init(filename: String = "accounts.json") {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        fileURL = docs.appendingPathComponent(filename)
        load()
    }

    func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([Account].self, from: data) else {
            accounts = []
            return
        }
        accounts = decoded
    }

    func save() {
        guard let data = try? JSONEncoder.pretty.encode(accounts) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    func add(_ account: Account) {
        accounts.append(account)
        save()
    }

    func add(_ newAccounts: [Account]) {
        accounts.append(contentsOf: newAccounts)
        save()
    }

    func update(_ account: Account) {
        guard let index = accounts.firstIndex(where: { $0.id == account.id }) else { return }
        accounts[index] = account
        save()
    }

    func remove(atOffsets offsets: IndexSet) {
        accounts = accounts.enumerated()
            .filter { !offsets.contains($0.offset) }
            .map { $0.element }
        save()
    }

    func remove(id: String) {
        accounts.removeAll { $0.id == id }
        save()
    }

    func replaceAll(_ newAccounts: [Account]) {
        accounts = newAccounts
        save()
    }
}
