import Foundation

enum RunScope: String, Codable {
    case all = "all"
    case sign = "sign"
    case coupon = "coupon"

    var title: String {
        switch self {
        case .all: return "签到 + 领券全流程"
        case .sign: return "仅签到"
        case .coupon: return "仅抢券"
        }
    }
}

/// 任务编排器:按开源脚本(meituan-shenquan)验证过的接口流程执行
/// ①签到领红豆 → ②签到领必中符 → ③每日任务红豆 → ④查询红包池
/// → ⑤必中符抽奖 → ⑥发放到账/小额转红豆 → ⑦查询红包库 → ⑧按需兑换 → ⑨自定义任务
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

        // 通用定位参数
        func locParams() -> [String: String] {
            [
                "parActivityId": config.parActivityId,
                "wm_latitude": String(format: "%.6f", city.latitude),
                "wm_longitude": String(format: "%.6f", city.longitude),
                "wm_ctype": "mtandroid"
            ]
        }

        let wantSign = options.scope == .all || options.scope == .sign
        let wantCoupon = options.scope == .all || options.scope == .coupon

        // ---------- ① 签到领红豆(同时校验 token) ----------
        if wantSign {
            await step(&report, title: "① 签到领红豆") {
                let resp = try await client.post("drawPoints", params: [:], token: account.token)
                let beans = JSONSearch.intValue(resp.object, keys: ["sendBeanCount", "beanCount", "beans"])
                let detail = beans.map { "获得 \($0) 红豆" } ?? ""
                return detail.isEmpty ? (resp.msg.isEmpty ? "已完成" : resp.msg) : "\(detail) · \(resp.msg)"
            }
            if report.tokenExpired { return finish(report) }
        }

        // ---------- ② 签到领必中符 ----------
        if wantSign {
            var params = locParams()
            params["action"] = "SiginInGetProp"
            await step(&report, title: "② 签到领必中符") {
                let resp = try await client.post("signInProp", params: params, token: account.token)
                if let signDays = JSONSearch.intValue(resp.data, keys: ["signDays"]), signDays > 0 {
                    return "签到成功,本周已连续签到 \(signDays) 天"
                }
                return resp.msg.isEmpty ? "今日已签到" : resp.msg
            }
            if report.tokenExpired { return finish(report) }
        }

        // ---------- ③ 每日任务红豆(浏览任务) ----------
        if wantSign {
            var params = locParams()
            params["portraitId"] = "498"
            await step(&report, title: "③ 每日任务红豆") {
                let resp = try await client.post("sendTaskRedBean", params: params, token: account.token)
                let beans = JSONSearch.intValue(resp.data, keys: ["sendBeanCount", "beanCount", "beans"])
                return beans.map { "获得 \($0) 红豆" } ?? (resp.msg.isEmpty ? "已完成" : resp.msg)
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
                if let propsResp = try? await client.post("myProps", params: locParams(), token: account.token),
                   let props = JSONSearch.findArray(propsResp.object, key: "props") {
                    // status==1 表示可用
                    if let usable = props.first(where: { ($0["status"] as? Int) == 1 }) {
                        let pid = JSONSearch.intValue(usable, keys: ["propId"]) ?? 1
                        propId = String(pid)
                        let worth = JSONSearch.intValue(usable, keys: ["worth", "amount", "price"])
                        propDesc = worth.map { "使用 \($0) 元必中符" } ?? "使用必中符 #\(propId)"
                    }
                }
            }

            var params = locParams()
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
                return resp.msg.isEmpty ? "抽奖完成" : resp.msg
            }
            if report.tokenExpired { return finish(report) }

            // ---------- ⑥ 发放到账 / 小额转红豆 ----------
            if wonPrice != nil {
                var params = locParams()
                params["batchId"] = batchId
                let price = wonPrice!
                if price < options.smallRedToBeanThreshold {
                    await step(&report, title: "⑥ 小额券转红豆") {
                        let resp = try await client.post("redToBean", params: params, token: account.token)
                        return resp.msg.isEmpty ? "\(Double(price) / 100.0) 元神券已转为红豆" : resp.msg
                    }
                } else {
                    await step(&report, title: "⑥ 神券发放到账") {
                        let resp = try await client.post("acceptRed", params: params, token: account.token)
                        return resp.msg.isEmpty ? "\(Double(price) / 100.0) 元神券已放入账户" : resp.msg
                    }
                }
                if report.tokenExpired { return finish(report) }
            }
        }

        // ---------- ⑦ 查询红包库 ----------
        if options.scope == .all {
            await step(&report, title: "⑦ 查询红包库") {
                let resp = try await client.post("myReward", params: [:], token: account.token)
                if let rewards = JSONSearch.findArray(resp.object, key: "rewardList") ?? JSONSearch.findArray(resp.object, key: "list") {
                    return "红包库共 \(rewards.count) 个红包"
                }
                return resp.msg.isEmpty ? "查询完成" : resp.msg
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
                params["wm_actual_latitude"] = String(format: "%.6f", city.latitude)
                params["wm_actual_longitude"] = String(format: "%.6f", city.longitude)
                let resp = try await client.post("exchange", params: params, token: account.token)
                return resp.msg.isEmpty ? "已兑换" : resp.msg
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
