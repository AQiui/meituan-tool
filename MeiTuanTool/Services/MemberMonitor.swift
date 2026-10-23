import Foundation

/// 美团黑金会员(成长值体系)监控
///
/// 抓包实测结论(2025-10 用户真机抓包验证):
/// - 读接口(queryMemberInfo / getUserTaskByScene):只需 Cookie + token,无需 mtgsig 签名 → **可全自动查询**
/// - 写接口(receiveAndOpUserTask 签到领成长值):美团风控对 mtgsig 做密码学校验
///   (无签名 code=4,伪造签名 403,真实旧签名可复用约十几分钟) → **第三方无法自动重放**
///
/// 因此自动化策略为:定时查询会员状态,发现今日未签到 → 本地通知提醒 → 一键跳转美团 APP 手动签到
actor MemberMonitor {

    // MARK: - 凭证

    struct Credential {
        var cookie: String
        var token: String
        var userId: String
    }

    // MARK: - 状态模型

    struct Status {
        var ok = false
        var error: String?

        /// 会员等级:黑金会员 / V5 / 子级 1
        var levelName = ""
        var levelShow = ""
        var subLevel = 0
        /// 当前成长值 / 本级区间 / 下一等级名
        var growthValue = 0
        var levelBegin = 0
        var levelEnd = 0
        var nextLevelName = ""
        /// 今日签到是否完成
        var signedToday = false
        /// 签到任务标题与进度(如「连续循环签到 1/7」)
        var signTaskTitle = ""
        var signProgress = ""
        /// 其他可做任务标题
        var otherTasks: [String] = []
        var fetchedAt = Date()

        var growthSummary: String {
            guard ok else { return error ?? "未获取" }
            if levelName.isEmpty { return "成长值 \(growthValue)" }
            return "\(levelName) \(levelShow)-\(subLevel) · 成长值 \(growthValue)/\(levelEnd)"
        }

        var signSummary: String {
            guard ok else { return error ?? "未获取" }
            if signedToday {
                return signProgress.isEmpty ? "今日已签到 ✓" : "今日已签到 ✓(\(signProgress))"
            }
            return "今日未签到,去美团 APP 会员中心签到"
        }
    }

    // MARK: - 接口地址

    private let memberHost = "https://member.meituan.com"
    private let cubeHost = "https://cube.meituan.com"

    private let session: URLSession

    init() {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 15
        cfg.timeoutIntervalForResource = 30
        self.session = URLSession(configuration: cfg)
    }

    // MARK: - 查询

    /// 查询会员信息 + 任务列表,汇总为 Status
    func fetchStatus(_ cred: Credential) async -> Status {
        var status = Status()
        guard !cred.cookie.isEmpty, !cred.token.isEmpty else {
            status.error = "未配置会员凭证(Cookie/Token)"
            return status
        }
        guard !cred.userId.isEmpty else {
            status.error = "缺少 userId,请重新导入抓包链接"
            return status
        }

        // ① 会员信息(等级/成长值)
        do {
            let info = try await queryMemberInfo(cred)
            status.ok = true
            status.levelName = info.levelName
            status.levelShow = info.levelShow
            status.subLevel = info.subLevel
            status.growthValue = info.growthValue
            status.levelBegin = info.levelBegin
            status.levelEnd = info.levelEnd
            status.nextLevelName = info.nextLevelName
        } catch let error as MemberError {
            status.error = error.description
            return status
        } catch {
            status.error = "网络错误: \(error.localizedDescription)"
            return status
        }

        // ② 任务列表(签到状态)
        do {
            let tasks = try await queryTaskList(cred)
            status.signedToday = tasks.signedToday
            status.signTaskTitle = tasks.signTaskTitle
            status.signProgress = tasks.signProgress
            status.otherTasks = tasks.otherTasks
        } catch {
            // 任务列表失败不阻塞会员信息展示
            status.otherTasks = ["任务列表获取失败: \(error.localizedDescription)"]
        }
        status.fetchedAt = Date()
        return status
    }

    // MARK: - ① 会员信息

    private struct MemberInfo {
        var levelName = ""
        var levelShow = ""
        var subLevel = 0
        var growthValue = 0
        var levelBegin = 0
        var levelEnd = 0
        var nextLevelName = ""
    }

    /// GET /growthvalue/api/toc/queryMemberInfo(读接口,无需签名)
    private func queryMemberInfo(_ cred: Credential) async throws -> MemberInfo {
        var comps = URLComponents(string: memberHost + "/growthvalue/api/toc/queryMemberInfo")!
        comps.queryItems = [
            URLQueryItem(name: "appType", value: "1"),
            URLQueryItem(name: "appVersion", value: "12.67.403"),
            URLQueryItem(name: "cityId", value: "10"),
            URLQueryItem(name: "ctype", value: "mtiphone"),
            URLQueryItem(name: "lat", value: "31.2734663"),
            URLQueryItem(name: "lng", value: "121.669354"),
            URLQueryItem(name: "mini_program_token", value: cred.token),
            URLQueryItem(name: "sourceActivityId", value: "1"),
            URLQueryItem(name: "sourceActivityType", value: "3"),
            URLQueryItem(name: "userId", value: cred.userId),
            URLQueryItem(name: "userType", value: "MT"),
            URLQueryItem(name: "csecpkgname", value: "com.meituan.imeituan"),
            URLQueryItem(name: "csecplatform", value: "2"),
            URLQueryItem(name: "csecversion", value: "1.2.0"),
            URLQueryItem(name: "csecversionname", value: "12.67.403"),
        ]
        guard let url = comps.url else { throw MemberError.badResponse }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(cred.cookie, forHTTPHeaderField: "Cookie")
        request.setValue(cred.token, forHTTPHeaderField: "token")
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 16_6_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 MicroMessenger/6.5.7 miniprogram MMP/1.17.1.103.2 MSC/1.103.2 group/12.67.403", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw MemberError.badResponse }
        if http.statusCode == 403 { throw MemberError.rejected }
        if http.statusCode != 200 { throw MemberError.http(http.statusCode) }

        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw MemberError.notJSON
        }
        guard let code = json["code"] as? Int, code == 0 else {
            let msg = json["msg"] as? String ?? ""
            let failCode = json["code"] as? Int ?? -1
            if msg.contains("登录") || msg.contains("失效") || msg.contains("过期") {
                throw MemberError.tokenExpired
            }
            throw MemberError.api(failCode, msg.isEmpty ? "查询失败" : msg)
        }

        var info = MemberInfo()
        if let data = json["data"] as? [String: Any],
           let basic = data["currentMemberLevelBasicInfoBO"] as? [String: Any] {
            info.levelName = basic["memberName"] as? String ?? ""
            info.levelShow = basic["memberLevelShow"] as? String ?? ""
            info.subLevel = basic["memberSubLevel"] as? Int ?? 0
            info.growthValue = Self.intValue(basic, keys: ["growthValue", "currentGrowthValue"])
            info.levelBegin = basic["memberSubLevelBeginGrowthValue"] as? Int
                ?? basic["beginGrowthValue"] as? Int ?? 0
            info.levelEnd = basic["memberSubLevelEndGrowthValue"] as? Int
                ?? basic["endGrowthValue"] as? Int ?? 0
            if let next = data["nextMemberLevelBasicInfoBO"] as? [String: Any] {
                info.nextLevelName = next["memberName"] as? String ?? ""
            }
        }
        return info
    }

    // MARK: - ② 任务列表

    private struct TaskList {
        var signedToday = false
        var signTaskTitle = ""
        var signProgress = ""
        var otherTasks: [String] = []
    }

    /// POST /topcube/api/toc/taskCenter/getUserTaskByScene(读接口,无需签名)
    private func queryTaskList(_ cred: Credential) async throws -> TaskList {
        var comps = URLComponents(string: cubeHost + "/topcube/api/toc/taskCenter/getUserTaskByScene")!
        comps.queryItems = [
            URLQueryItem(name: "k", value: "member_1"),
            URLQueryItem(name: "csecpkgname", value: "com.meituan.imeituan"),
            URLQueryItem(name: "csecplatform", value: "2"),
            URLQueryItem(name: "csecversion", value: "1.2.0"),
            URLQueryItem(name: "csecversionname", value: "12.67.403"),
        ]
        guard let url = comps.url else { throw MemberError.badResponse }

        let body: [String: Any] = [
            "sourceActivityType": 3,
            "userId": cred.userId,
            "cityId": 10,
            "ctype": "mtiphone",
            "appVersion": "12.67.403",
            "lng": 121.669354,
            "sourceActivityId": 1,
            "lat": 31.2734663,
            "appType": 1,
            "userType": "MT",
            "mini_program_token": cred.token,
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(cred.cookie, forHTTPHeaderField: "Cookie")
        request.setValue(cred.token, forHTTPHeaderField: "token")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 16_6_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 MicroMessenger/6.5.7 miniprogram MMP/1.17.1.103.2 MSC/1.103.2 group/12.67.403", forHTTPHeaderField: "User-Agent")
        request.setValue("https://mmp.meituan.com/MSCSDK/0/service", forHTTPHeaderField: "Referer")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw MemberError.badResponse }
        if http.statusCode == 403 { throw MemberError.rejected }
        if http.statusCode != 200 { throw MemberError.http(http.statusCode) }

        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let data0 = json["data"] as? [String: Any],
              let tasks = data0["tasks"] as? [[String: Any]] else {
            throw MemberError.notJSON
        }

        var result = TaskList()
        for task in tasks {
            let title = task["title"] as? String ?? "任务"
            let status = task["status"] as? String ?? ""
            let desc = task["description"] as? String ?? ""
            let progress = task["taskProgress"] as? [String: Any]
            let reached = progress?["reachedCount"] as? Int ?? 0
            let all = progress?["allCount"] as? Int ?? 0

            let isSignTask = desc.contains("签到") || title.contains("签到")
            // RECEIVED=已领取并完成 / FORBID_RECEIVE=已领取不可再领 → 今日已签到
            let done = (status == "RECEIVED" || status == "FORBID_RECEIVE")

            if isSignTask {
                result.signedToday = done
                result.signTaskTitle = title
                result.signProgress = "\(reached)/\(all)"
            } else if status == "CAN_RECEIVE" || (done && all > reached) {
                result.otherTasks.append("\(title)(\(reached)/\(all))")
            }
        }
        return result
    }

    // MARK: - 错误

    enum MemberError: LocalizedError {
        case badResponse
        case notJSON
        case rejected
        case http(Int)
        case api(Int, String)
        case tokenExpired

        var description: String {
            switch self {
            case .badResponse: return "接口地址无效"
            case .notJSON: return "返回内容无法解析"
            case .rejected: return "请求被风控拒绝(HTTP 403),凭证可能已失效"
            case .http(let code): return "服务器返回 HTTP \(code)"
            case .api(let code, let msg): return msg.isEmpty ? "接口返回 code=\(code)" : "\(msg)(code=\(code))"
            case .tokenExpired: return "会员凭证已失效,请重新抓包导入"
            }
        }

        var errorDescription: String? { description }
    }

    // MARK: - 工具

    private static func intValue(_ dict: [String: Any], keys: [String]) -> Int {
        for key in keys {
            if let v = dict[key] as? Int { return v }
            if let s = dict[key] as? String, let v = Int(s) { return v }
        }
        return 0
    }
}
