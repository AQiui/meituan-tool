import Foundation

enum RunScope: String, Codable {
    case all = "all"
    case sign = "sign"
    case coupon = "coupon"
    case member = "member"

    var title: String {
        switch self {
        case .all: return "签到 + 领券全流程"
        case .sign: return "仅签到"
        case .coupon: return "仅抢券"
        case .member: return "黑金会员任务"
        }
    }
}

/// 任务编排器:按开源脚本(meituan-shenquan)验证过的接口流程执行
/// ①签到领红豆 → ②签到领必中符 → ③每日任务红豆 → ④查询红包池
/// → ⑤必中符抽奖 → ⑥发放到账/小额转红豆 → ⑦查询红包库 → ⑧按需兑换 → ⑨自定义任务
/// → ⓾ 黑金会员签到/任务(路径由 App 内「会员中心」抓包学习配置)
final class TaskRunner {
    private let client: MeituanClient
    private let config: EndpointConfig

    init(client: MeituanClient = MeituanClient(), config: EndpointConfig = .load()) {
        self.client = client
        self.config = config
    }

    struct Options {
        var scope: RunScope = .all
        var useRandomCity: Bool = true
        var fixedCityName: String? = nil
        var usePropIfAvailable: Bool = true
        var smallRedToBeanThreshold: Int = 500
        var exchangeBeanThreshold: Int = 1800
        var includeExtraTasks: Bool = true
        /// 执行黑金会员任务(需先在「会员中心」抓包学习配置路径)
        var includeMemberTasks: Bool = true
    }

    typealias ProgressHandler = @MainActor (String) async -> Void

    // MARK: - 批量执行

    func run(accounts: [Account],
             options: Options,
             trigger: String,
             onProgress: ProgressHandler? = nil) async -> RunOutcome {
        var outcome = RunOutcome(trigger: trigger, scope: options.scope.rawValue)
        for (index, account) in accounts.enumerated() {
            if Task.isCancelled { break }
            await onProgress?("正在执行: \(account.name)(\(index + 1)/\(accounts.count))")
            let report = await runAccount(account, options: options)
            outcome.reports.append(report)
            // 账号间稍微间隔,降低被风控概率
            if index < accounts.count - 1 {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
            }
        }
        outcome.finishedAt = Date()
        return outcome
    }

    // MARK: - 单账号执行

    private func runAccount(_ account: Account, options: Options) async -> AccountReport {
        var report = AccountReport(accountId: account.id,
                                   accountName: account.name,
                                   scope: options.scope.rawValue)

        // 定位策略:账号固定城市 > 随机城市 > 默认城市
        let city: CityInfo
        if account.useFixedLocation {
            city = Cities.named(account.fixedCityName) ?? Cities.named(options.fixedCityName ?? "") ?? Cities.random()
        } else if options.useRandomCity {
            city = Cities.random()
        } else {
            city = Cities.named(options.fixedCityName ?? "") ?? Cities.fallback
        }

        // 通用定位参数(微度整型:美团接口要求去掉小数点的纬度/经度,如成都 30657401,104065827)
        func microLat() -> String { String(Int((city.latitude * 1_000_000).rounded())) }
        func microLng() -> String { String(Int((city.longitude * 1_000_000).rounded())) }

        // 带 wm_ctype 的定位参数(对齐原脚本:仅 corePage / exchange 携带)
        func locParams() -> [String: String] {
            [
                "parActivityId": config.parActivityId,
                "wm_latitude": microLat(),
                "wm_longitude": microLng(),
                "wm_ctype": "mtandroid"
            ]
        }

        // 不带 wm_ctype 的精简定位参数(对齐原脚本:doAction/sendTaskRedBean/drawlottery/acceptRed/redToBean/myProps)
        func baseParams() -> [String: String] {
            [
                "parActivityId": config.parActivityId,
                "wm_latitude": microLat(),
                "wm_longitude": microLng()
            ]
        }

        let wantSign = options.scope == .all || options.scope == .sign
        let wantCoupon = options.scope == .all || options.scope == .coupon
        let wantMember = options.scope == .all || options.scope == .member

        // ---------- ① 签到领红豆(同时校验 token) ----------
        if wantSign {
            await step(&report, title: "① 签到领红豆") {
                let resp = try await client.post("drawPoints", params: [:], token: account.token)
                var parts: [String] = []
                if let beans = JSONSearch.intValue(resp.object, keys: ["sendBeanCount", "beanCount", "beans"]) {
                    parts.append("获得 \(beans) 红豆")
                }
                let msg = resp.describe("")
                if !msg.isEmpty { parts.append(msg) }
                return parts.isEmpty ? "已完成" : parts.joined(separator: " · ")
            }
            if report.tokenExpired { return finish(report) }
        }

        // ---------- ② 签到领必中符 ----------
        if wantSign {
            var params = baseParams()
            params["action"] = "SiginInGetProp"
            await step(&report, title: "② 签到领必中符") {
                let resp = try await client.post("signInProp", params: params, token: account.token)
                if let signDays = JSONSearch.intValue(resp.data, keys: ["signDays"]), signDays > 0 {
                    return "签到成功,本周已连续签到 \(signDays) 天"
                }
                return resp.describe("今日已签到")
            }
            if report.tokenExpired { return finish(report) }
        }

        // ---------- ③ 每日任务红豆(浏览任务) ----------
        if wantSign {
            var params = baseParams()
            params["portraitId"] = "498"
            await step(&report, title: "③ 每日任务红豆") {
                let resp = try await client.post("sendTaskRedBean", params: params, token: account.token)
                if let beans = JSONSearch.intValue(resp.data, keys: ["sendBeanCount", "beanCount", "beans"]) {
                    return "获得 \(beans) 红豆"
                }
                return resp.describe("已完成")
            }
            if report.tokenExpired { return finish(report) }
        }

        // ---------- ④ 查询红包池 / 当前批次 ----------
        var batchId: String?
        var exchangeRuleId: String?
        if wantCoupon {
            await step(&report, title: "④ 查询红包池") {
                let resp = try await client.post("corePage", params: locParams(), token: account.token)
                batchId = JSONSearch.stringValue(resp.data, keys: ["batchId"])
                exchangeRuleId = JSONSearch.stringValue(resp.object, keys: ["exchangeRuleId"])
                if batchId == nil {
                    // code 非 0 说明是接口/参数错误,不能误报成"不在抢券时段"
                    if let c = resp.code, c != 0 {
                        return resp.msg.isEmpty ? "接口异常(code=\(c))" : "\(resp.msg)(code=\(c))"
                    }
                    return "当前不在抢券时段(每天 11:00 / 17:00 / 21:00 开放)"
                }
                // 尝试解析红包池库存描述
                if let rounds = JSONSearch.findArray(resp.object, key: "roundList") ?? JSONSearch.findArray(resp.object, key: "rounds") {
                    let stocks = rounds.compactMap { round -> String? in
                        guard let price = JSONSearch.intValue(round, keys: ["showPriceNumberYuan", "showPriceNumber"]) else { return nil }
                        let left = JSONSearch.intValue(round, keys: ["leftStock", "leftNum"]) ?? 0
                        return "\(price)元券剩\(left)"
                    }
                    if !stocks.isEmpty {
                        return "批次 \(batchId!) · \(stocks.joined(separator: ", "))"
                    }
                }
                return "已获取抢券批次 \(batchId!) · 定位\(city.name)"
            }
            if report.tokenExpired { return finish(report) }
        }

        // ---------- ⑤ 抽奖抢券 ----------
        var wonPrice: Int?
        if wantCoupon, let batchId {
            // 先查道具库,有必中符就带上
            var propId = "1"
            var propDesc = "未使用必中符"
            if options.usePropIfAvailable {
                if let propsResp = try? await client.post("myProps", params: baseParams(), token: account.token) {
                    // 原脚本:响应 data 本身就是道具数组
                    var props: [[String: Any]] = []
                    if let arr = propsResp.object["data"] as? [[String: Any]] {
                        props = arr
                    } else if let arr = JSONSearch.findArray(propsResp.object, key: "props") {
                        props = arr
                    }
                    // status==1 表示可用,取第一个有效道具
                    if let usable = props.first(where: { ($0["status"] as? Int) == 1 }) {
                        let pid = JSONSearch.intValue(usable, keys: ["propId"]) ?? 1
                        propId = String(pid)
                        let worth = JSONSearch.intValue(usable, keys: ["worth", "amount", "price"])
                        propDesc = worth.map { "使用 \($0) 元必中符" } ?? "使用必中符 #\(propId)"
                    }
                }
            }

            var params = baseParams()
            params["batchId"] = batchId
            params["isShareLink"] = "true"
            params["propType"] = "1"
            params["propId"] = propId

            await step(&report, title: "⑤ 抢神券(\(propDesc))") {
                let resp = try await client.post("drawLottery", params: params, token: account.token)
                wonPrice = JSONSearch.intValue(resp.data, keys: ["showPriceNumber", "price", "amount"])
                if let price = wonPrice {
                    let yuan = Double(price) / 100.0
                    return String(format: "抢到 %.2f 元神券", yuan)
                }
                return resp.describe("抽奖完成")
            }
            if report.tokenExpired { return finish(report) }

            // ---------- ⑥ 发放到账 / 小额转红豆 ----------
            if wonPrice != nil {
                var params = baseParams()
                params["batchId"] = batchId
                let price = wonPrice!
                if price < options.smallRedToBeanThreshold {
                    await step(&report, title: "⑥ 小额券转红豆") {
                        let resp = try await client.post("redToBean", params: params, token: account.token)
                        return resp.describe("\(Double(price) / 100.0) 元神券已转为红豆")
                    }
                } else {
                    await step(&report, title: "⑥ 神券发放到账") {
                        let resp = try await client.post("acceptRed", params: params, token: account.token)
                        return resp.describe("\(Double(price) / 100.0) 元神券已放入账户")
                    }
                }
                if report.tokenExpired { return finish(report) }
            }
        }

        // ---------- ⑦ 查询红包库 ----------
        if options.scope == .all {
            await step(&report, title: "⑦ 查询红包库") {
                let resp = try await client.post("myReward", params: ["parActivityId": config.parActivityId], token: account.token)
                if let rewards = JSONSearch.findArray(resp.object, key: "myawardInfos")
                    ?? JSONSearch.findArray(resp.object, key: "rewardList")
                    ?? JSONSearch.findArray(resp.object, key: "list") {
                    return "红包库共 \(rewards.count) 个红包"
                }
                return resp.describe("查询完成")
            }
            if report.tokenExpired { return finish(report) }
        }

        // ---------- ⑧ 按需兑换必中符(需要接口返回 exchangeRuleId,拿不到就跳过) ----------
        if options.scope == .all, options.exchangeBeanThreshold > 0, let ruleId = exchangeRuleId {
            await step(&report, title: "⑧ 兑换必中符") {
                var params = locParams()
                params["exchangeRuleId"] = ruleId
                params["propId"] = "5"
                params["exchangeCoinNumber"] = String(options.exchangeBeanThreshold)
                params["wm_actual_latitude"] = microLat()
                params["wm_actual_longitude"] = microLng()
                let resp = try await client.post("exchange", params: params, token: account.token)
                return resp.describe("已兑换")
            }
            if report.tokenExpired { return finish(report) }
        }

        // ---------- ⑨ 用户自定义任务 ----------
        if options.includeExtraTasks {
            for extra in config.extraTasks {
                var params = extra.bodyExtra
                params["token"] = account.token
                await step(&report, title: "⑨ \(extra.name)") {
                    let resp = try await client.post(path: extra.path, params: params, token: account.token)
                    return resp.msg.isEmpty ? "已完成" : resp.msg
                }
                if report.tokenExpired { return finish(report) }
            }
        }

        // ---------- ⓾ 黑金会员(监控模式) ----------
        // 实测:签到写接口 receiveAndOpUserTask 带 mtgsig 密码学校验(无签名 code=4/伪造 403),
        // 第三方无法自动重放;读接口(会员信息/任务列表)无需签名,已在「会员检查」中全自动查询。
        // 这里只输出说明,引导用户使用监控+提醒模式,不再尝试自动执行签到。
        if wantMember, options.includeMemberTasks {
            await step(&report, title: "⓾ 黑金会员监控") {
                "签到接口有 mtgsig 签名风控,无法自动重放。请用首页「会员检查」查询状态(全自动),未签到时会本地提醒并一键跳转美团 APP"
            }
        }

        return finish(report)
    }

    // MARK: - 步骤包装

    /// 执行单个步骤并记录结果;token 失效时直接返回,不再继续后续步骤
    private func step(_ report: inout AccountReport, title: String, _ body: () async throws -> String) async {
        do {
            let detail = try await body()
            report.steps.append(StepResult(title: title, success: true, detail: detail))
        } catch let error as MeituanError {
            let expired: Bool
            if case .tokenExpired = error { expired = true } else { expired = false }
            report.steps.append(StepResult(title: title, success: false,
                                           detail: error.errorDescription ?? "失败",
                                           tokenExpired: expired))
        } catch {
            report.steps.append(StepResult(title: title, success: false,
                                           detail: error.localizedDescription))
        }
    }

    private func finish(_ report: AccountReport) -> AccountReport {
        var r = report
        r.finishedAt = Date()
        return r
    }
}
