import Foundation

/// 会员凭证导入解析
/// 支持三种粘贴来源(均来自美团 APP 抓包,Stream/Thor/Charles 均可):
/// 1. 完整 HAR 文件文本(推荐,一次提取 Cookie + Token + userId)
/// 2. 单条请求 URL(需含 mini_program_token 与 userId 参数,如 queryMemberInfo 链接)
/// 3. Cookie 字符串(Token/userId 需另行粘贴)
enum MemberCredentialImporter {

    struct Result {
        var cookie: String
        var token: String
        var userId: String
        var source: String   // 说明提取来源,用于 UI 反馈
    }

    /// 从任意粘贴文本中尽力提取凭证
    static func parse(_ text: String) -> Result? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // 1. HAR JSON
        if let data = trimmed.data(using: .utf8),
           let json = (try? JSONSerialization.jsonObject(with: data)) as? [String:Any],
           let log = json["log"] as? [String: Any],
           let entries = log["entries"] as? [[String: Any]] {
            return parseHAR(entries)
        }

        // 2. 裸 URL(可能带引号或前后缀杂质,先尝试定位 http(s) 链接)
        if let url = firstURL(in: trimmed) {
            return parseURL(url)
        }

        // 3. 纯 Cookie 字符串(含分号分隔的键值对)
        if trimmed.contains("=") && (trimmed.contains(";") || trimmed.split(separator: "=").count >= 2) {
            return Result(cookie: trimmed, token: "", userId: "", source: "Cookie 字符串")
        }
        return nil
    }

    // MARK: - HAR

    private static func parseHAR(_ entries: [[String: Any]]) -> Result? {
        for entry in entries {
            guard let req = entry["request"] as? [String: Any],
                  let urlString = req["url"] as? String,
                  let url = URL(string: urlString),
                  let host = url.host,
                  host.contains("meituan.com") else { continue }

            var cookie = ""
            var tokenHeader = ""
            if let headers = req["headers"] as? [[String: Any]] {
                for h in headers {
                    let name = (h["name"] as? String ?? "").lowercased()
                    let value = h["value"] as? String ?? ""
                    if name == "cookie" { cookie = value }
                    if name == "token" { tokenHeader = value }
                }
            }

            // token 优先取 URL 参数 mini_program_token,其次 token 头
            let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
            let items = comps?.queryItems ?? []
            let urlToken = items.first { $0.name == "mini_program_token" }?.value ?? ""
            let token = urlToken.isEmpty ? tokenHeader : urlToken
            let userId = items.first { $0.name == "userId" }?.value ?? ""

            if !cookie.isEmpty || !token.isEmpty {
                return Result(cookie: cookie, token: token, userId: userId,
                              source: "HAR 抓包(\(host))")
            }
        }
        return nil
    }

    // MARK: - URL

    private static func parseURL(_ url: URL) -> Result? {
        let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let items = comps?.queryItems ?? []
        let token = items.first { $0.name == "mini_program_token" }?.value ?? ""
        let userId = items.first { $0.name == "userId" }?.value ?? ""
        guard !token.isEmpty || !userId.isEmpty else { return nil }
        return Result(cookie: "", token: token, userId: userId, source: "请求链接")
    }

    /// 从含杂质文本中提取第一个 http(s) 链接
    private static func firstURL(in text: String) -> URL? {
        // URL 不能含空白,按空白切分逐段探测
        for part in text.split(whereSeparator: { $0.isWhitespace || $0 == "\"" || $0 == "'" || $0 == "<" || $0 == ">" }) {
            let s = String(part)
            if s.hasPrefix("http://") || s.hasPrefix("https://") {
                // 去掉可能的尾缀标点
                let cleaned = s.trimmingCharacters(in: CharacterSet(charactersIn: "),;\"'"))
                if let url = URL(string: cleaned), url.host != nil {
                    return url
                }
            }
        }
        return nil
    }
}
