import Foundation

/// 美团账号
/// 核心凭证是 token(通过 App 内置网页登录自动抓取,或抓包/青龙脚本同款 token)
struct Account: Identifiable, Codable, Equatable {
    var id: String = UUID().uuidString
    /// 备注名,方便多账号区分
    var name: String
    /// 美团 token(只要 token 值本身,不带 "token=" 前缀和分号)
    var token: String
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    // MARK: 最近一次执行状态
    var lastRunAt: Date?
    var lastRunOK: Bool?
    var lastRunSummary: String = ""

    // MARK: 定位(领券接口需要经纬度参数)
    /// 是否使用固定城市;关闭时每次随机选城市
    var useFixedLocation: Bool = false
    var fixedCityName: String = "北京"
    var latitude: Double = 39.9097
    var longitude: Double = 116.4134

    /// 脱敏显示,避免截图泄露
    var maskedToken: String {
        guard token.count > 10 else { return token }
        return "\(token.prefix(4))****\(token.suffix(4))"
    }

    /// 批量导入解析:
    /// 每行一个账号,支持 "token" / "备注=token" / "备注:token" / "备注,token"
    /// 账号之间可用换行、@、分号分隔
    static func parseBatch(_ text: String) -> [Account] {
        var result: [Account] = []
        let lines = text.components(separatedBy: CharacterSet(charactersIn: "\n@;"))
        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty { continue }
            var name = ""
            var token = line
            // 去掉可能误粘贴的 "token=" 前缀和首尾引号/分号
            if let range = line.range(of: #"(?i)^token\s*=\s*"#, options: .regularExpression) {
                token = String(line[range.upperBound...])
            }
            token = token.trimmingCharacters(in: CharacterSet(charactersIn: "\"'`;"))
            // 拆分备注(仅当左侧像备注名:短;右侧像 token:较长时才拆)
            for sep in ["=", ":", ",", "，", "："] {
                if let idx = token.range(of: sep), !line.lowercased().hasPrefix("token=") {
                    let left = String(token[token.startIndex..<idx.lowerBound])
                        .trimmingCharacters(in: .whitespaces)
                    let right = String(token[idx.upperBound...])
                        .trimmingCharacters(in: .whitespaces)
                    if !left.isEmpty && !right.isEmpty && left.count <= 12 && right.count >= 8 {
                        name = left
                        token = right
                        break
                    }
                }
            }
            guard !token.isEmpty else { continue }
            result.append(Account(name: name.isEmpty ? "账号\(result.count + 1)" : name, token: token))
        }
        return result
    }
}
