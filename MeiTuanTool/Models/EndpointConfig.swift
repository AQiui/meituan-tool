import Foundation

/// 接口配置(与 Resources/endpoints.json 对应)
/// 美团调整接口时,只需更新 endpoints.json,不需要改代码:
///   1. 修改工程内 Resources/endpoints.json 重新编译;或
///   2. 通过分享面板把 endpoints.json 存到 App 的"文件"目录(iOS 文件 App 定位到本 App 文件夹)
struct EndpointConfig: Codable {
    var version: Int = 1
    var baseURL: String = "https://i.waimai.meituan.com"
    var parActivityId: String = "Gh1tkq-wvFU2xEP_ZPzHPQ"
    var userAgent: String = "MeituanGroup/11.9.208"
    /// 任务 key -> 接口路径
    var paths: [String: String] = EndpointConfig.builtinPaths
    /// 用户自定义附加任务(执行完主流程后逐个请求)
    var extraTasks: [ExtraTask] = []

    struct ExtraTask: Codable {
        var id: String = UUID().uuidString
        var name: String
        var path: String
        var method: String = "POST"
        /// 附加在 body 里的固定参数(token 和 parActivityId 会自动带上)
        var bodyExtra: [String: String] = [:]
    }

    /// 代码内置默认接口(与 endpoints.json 保持一致,作为最终兜底)
    static let builtinPaths: [String: String] = [
        "drawPoints":      "/cfeplay/playcenter/batchgrabred/drawPoints/v2",
        "signInProp":      "/cfeplay/playcenter/batchgrabred/doAction",
        "corePage":        "/cfeplay/playcenter/batchgrabred/corepage",
        "myProps":         "/cfeplay/playcenter/batchgrabred/myProps",
        "drawLottery":     "/cfeplay/playcenter/batchgrabred/drawlottery",
        "acceptRed":       "/cfeplay/playcenter/batchgrabred/acceptRed",
        "redToBean":       "/cfeplay/playcenter/batchgrabred/redToBean",
        "sendTaskRedBean": "/cfeplay/playcenter/batchgrabred/sendTaskRedBean",
        "myReward":        "/cfeplay/playcenter/batchgrabred/myreward",
        "exchange":        "/cfeplay/playcenter/batchgrabred/exchange"
    ]

    // MARK: 加载(优先级: Documents 用户覆盖 > App 内置 > 代码默认)

    static func load() -> EndpointConfig {
        if let override = loadFromDocuments() { return override }
        if let bundled = loadFromBundle() { return bundled }
        return EndpointConfig()
    }

    private static func documentsURL() -> URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent("endpoints.json")
    }

    private static func loadFromDocuments() -> EndpointConfig? {
        guard let url = documentsURL(), let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(EndpointConfig.self, from: data)
    }

    private static func loadFromBundle() -> EndpointConfig? {
        guard let url = Bundle.main.url(forResource: "endpoints", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(EndpointConfig.self, from: data)
    }

    /// 保存一份用户覆盖配置到 Documents
    func saveToDocuments() {
        guard let url = EndpointConfig.documentsURL(),
              let data = try? JSONEncoder.pretty.encode(self) else { return }
        try? data.write(to: url, options: .atomic)
    }

    /// 删除用户覆盖,恢复内置配置
    static func resetOverride() {
        guard let url = documentsURL() else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
