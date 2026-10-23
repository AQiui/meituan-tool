import Foundation

extension JSONEncoder {
    /// 统一的美观输出编码器(账号/设置/日志本地持久化用)
    static var pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
