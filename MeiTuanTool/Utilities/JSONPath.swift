import Foundation

enum JSONSearch {
    /// 在 JSON 对象中递归查找指定 key(美团返回层级不固定,做容错解析)
    static func findValue(_ object: Any?, key: String) -> Any? {
        guard let object else { return nil }
        if let dict = object as? [String: Any] {
            if let v = dict[key] { return v }
            for (_, v) in dict {
                if let found = findValue(v, key: key) { return found }
            }
        } else if let array = object as? [Any] {
            for v in array {
                if let found = findValue(v, key: key) { return found }
            }
        }
        return nil
    }

    /// 递归查找数组字段(如 props / roundList)
    static func findArray(_ object: Any?, key: String) -> [[String: Any]]? {
        if let arr = findValue(object, key: key) as? [[String: Any]] { return arr }
        if let arr = findValue(object, key: key) as? [Any] {
            return arr.compactMap { $0 as? [String: Any] }
        }
        return nil
    }

    static func intValue(_ object: Any?, keys: [String]) -> Int? {
        for key in keys {
            if let v = findValue(object, key: key) as? Int { return v }
            if let v = findValue(object, key: key) as? String, let i = Int(v) { return i }
            if let v = findValue(object, key: key) as? Double { return Int(v) }
        }
        return nil
    }

    static func stringValue(_ object: Any?, keys: [String]) -> String? {
        for key in keys {
            if let v = findValue(object, key: key) as? String, !v.isEmpty { return v }
            if let v = findValue(object, key: key) as? Int { return String(v) }
        }
        return nil
    }
}
