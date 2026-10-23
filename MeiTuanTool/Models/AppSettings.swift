import Foundation

/// 全局设置(持久化在 Documents/settings.json)
struct AppSettings: Codable, Equatable {
    /// 执行完成后发送本地通知
    var notifyOnFinish: Bool = true
    /// 开启后台刷新(iOS 系统调度,时机由系统决定,精确定时请用快捷指令)
    var backgroundRefresh: Bool = true
    /// 默认执行范围:all / sign / coupon
    var defaultScope: String = "all"
    /// 随机城市定位(模拟不同地区红包池);关闭则用下面的默认城市
    var useRandomCity: Bool = true
    var defaultCityName: String = "北京"
    /// 有必中符时自动使用
    var usePropIfAvailable: Bool = true
    /// 小额神券自动转红豆的阈值(单位:分,默认 500 = 5 元以下转红豆)
    var smallRedToBeanThreshold: Int = 500
    /// 自动兑换必中符的红豆阈值(0 = 不自动兑换)
    var exchangeBeanThreshold: Int = 1800
    /// 执行 endpoints.json 中用户自定义的 extraTasks
    var includeExtraTasks: Bool = true
    /// 执行黑金会员签到/任务(路径需先在 App 内「会员中心」抓包学习)
    var includeMemberTasks: Bool = true
    /// 黑金会员监控:定时查询会员状态,今日未签到则本地通知提醒
    var memberMonitorEnabled: Bool = false
    /// 会员凭证(从美团 APP 抓包导入,读接口专用)
    var memberCookie: String = ""
    var memberToken: String = ""
    var memberUserId: String = ""

    static let `default` = AppSettings()

    var scope: RunScope { RunScope(rawValue: defaultScope) ?? .all }

    /// 兼容旧版 settings.json:新增字段缺失时用默认值,避免整份设置被重置
    enum CodingKeys: String, CodingKey {
        case notifyOnFinish, backgroundRefresh, defaultScope, useRandomCity, defaultCityName,
             usePropIfAvailable, smallRedToBeanThreshold, exchangeBeanThreshold,
             includeExtraTasks, includeMemberTasks, memberMonitorEnabled,
             memberCookie, memberToken, memberUserId
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        notifyOnFinish = try c.decodeIfPresent(Bool.self, forKey: .notifyOnFinish) ?? true
        backgroundRefresh = try c.decodeIfPresent(Bool.self, forKey: .backgroundRefresh) ?? true
        defaultScope = try c.decodeIfPresent(String.self, forKey: .defaultScope) ?? "all"
        useRandomCity = try c.decodeIfPresent(Bool.self, forKey: .useRandomCity) ?? true
        defaultCityName = try c.decodeIfPresent(String.self, forKey: .defaultCityName) ?? "北京"
        usePropIfAvailable = try c.decodeIfPresent(Bool.self, forKey: .usePropIfAvailable) ?? true
        smallRedToBeanThreshold = try c.decodeIfPresent(Int.self, forKey: .smallRedToBeanThreshold) ?? 500
        exchangeBeanThreshold = try c.decodeIfPresent(Int.self, forKey: .exchangeBeanThreshold) ?? 1800
        includeExtraTasks = try c.decodeIfPresent(Bool.self, forKey: .includeExtraTasks) ?? true
        includeMemberTasks = try c.decodeIfPresent(Bool.self, forKey: .includeMemberTasks) ?? true
        memberMonitorEnabled = try c.decodeIfPresent(Bool.self, forKey: .memberMonitorEnabled) ?? false
        memberCookie = try c.decodeIfPresent(String.self, forKey: .memberCookie) ?? ""
        memberToken = try c.decodeIfPresent(String.self, forKey: .memberToken) ?? ""
        memberUserId = try c.decodeIfPresent(String.self, forKey: .memberUserId) ?? ""
    }
}
