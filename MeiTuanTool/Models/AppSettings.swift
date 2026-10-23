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

    static let `default` = AppSettings()

    var scope: RunScope { RunScope(rawValue: defaultScope) ?? .all }
}
