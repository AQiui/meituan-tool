import Foundation

enum FormBody {
    /// application/x-www-form-urlencoded 编码
    /// 与 Python requests 的默认行为对齐:参数按 key 排序、空格转 "+"
    static func encode(_ params: [String: String]) -> String {
        params
            .sorted { $0.key < $1.key }
            .map { key, value in
                "\(percentEncode(key))=\(percentEncode(value))"
            }
            .joined(separator: "&")
    }

    /// 百分号编码(保留 RFC3986 非保留字符,空格转为 "+",与 quote_plus 一致)
    static func percentEncode(_ string: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        let encoded = string.addingPercentEncoding(withAllowedCharacters: allowed) ?? string
        return encoded.replacingOccurrences(of: "%20", with: "+")
    }
}
