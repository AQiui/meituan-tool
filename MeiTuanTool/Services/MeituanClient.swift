import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

enum MeituanError: LocalizedError {
    case badURL
    case http(Int)
    case badResponse
    case tokenExpired(msg: String)
    case network(String)

    var errorDescription: String? {
        switch self {
        case .badURL: return "接口地址无效"
        case .http(let code): return "服务器返回 HTTP \(code)"
        case .badResponse: return "返回内容无法解析"
        case .tokenExpired(let msg): return msg.isEmpty ? "token 已失效,请重新获取" : msg
        case .network(let msg): return "网络错误: \(msg)"
        }
    }
}

/// 美团天天神券接口客户端(https://i.waimai.meituan.com)
/// 所有接口均为 form POST,token 放在 body 中,参数在 EndpointConfig 里配置
actor MeituanClient {
    private let config: EndpointConfig
    private let session: URLSession

    init(config: EndpointConfig = .load()) {
        self.config = config
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 15
        cfg.timeoutIntervalForResource = 30
        #if os(iOS) || os(macOS) || os(watchOS) || os(tvOS)
        cfg.waitsForConnectivity = true
        #endif
        self.session = URLSession(configuration: cfg)
    }

    struct APIResponse {
        let object: [String: Any]
        let raw: String

        /// 美团不同接口有的用 code、有的用 status 表示结果
        var code: Int? {
            if let v = object["code"] as? Int { return v }
            if let v = object["status"] as? Int { return v }
            if let s = object["code"] as? String, let v = Int(s) { return v }
            if let s = object["status"] as? String, let v = Int(s) { return v }
            return nil
        }
        var msg: String {
            object["msg"] as? String
                ?? object["message"] as? String
                ?? object["tip"] as? String
                ?? ""
        }
        var data: [String: Any]? { object["data"] as? [String: Any] }

        /// 生成步骤详情文案:接口返回非 0 时附带 code,方便定位问题(美团各接口错误码含义不同)
        func describe(_ fallback: String) -> String {
            let m = msg
            guard let c = code, c != 0 else { return m.isEmpty ? fallback : m }
            return m.isEmpty ? "(code=\(c))" : "\(m)(code=\(c))"
        }
    }

    /// 按配置 key 发起请求
    func post(_ key: String, params: [String: String], token: String) async throws -> APIResponse {
        guard let path = config.paths[key] else { throw MeituanError.badURL }
        return try await post(path: path, params: params, token: token)
    }

    /// 通用 form POST(带一次网络重试)
    func post(path: String, params: [String: String], token: String, retry: Int = 1) async throws -> APIResponse {
        guard let url = URL(string: config.baseURL + path) else { throw MeituanError.badURL }

        var body = params
        body["token"] = token

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(config.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("XMLHttpRequest", forHTTPHeaderField: "x-requested-with")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        if let host = url.host { request.setValue(host, forHTTPHeaderField: "Host") }
        request.httpBody = FormBody.encode(body).data(using: .utf8)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            if retry > 0, !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 800_000_000)
                return try await post(path: path, params: params, token: token, retry: retry - 1)
            }
            throw MeituanError.network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else { throw MeituanError.badResponse }
        if http.statusCode != 200 {
            if retry > 0, http.statusCode >= 500, !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 800_000_000)
                return try await post(path: path, params: params, token: token, retry: retry - 1)
            }
            throw MeituanError.http(http.statusCode)
        }

        let raw = String(data: data, encoding: .utf8) ?? ""
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw MeituanError.badResponse
        }

        let api = APIResponse(object: json, raw: raw)

        // token 失效识别:美团通常返回 code=401 或 msg 含"登录/失效/过期"
        let msg = api.msg
        if api.code == 401
            || msg.contains("登录")
            || msg.contains("失效")
            || msg.contains("过期")
            || msg.contains("请先登陆") {
            throw MeituanError.tokenExpired(msg: msg)
        }
        return api
    }
}
