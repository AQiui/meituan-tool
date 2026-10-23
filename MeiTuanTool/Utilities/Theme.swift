import SwiftUI

/// 美团配色主题
enum Theme {
    /// 美团黄 #FFD100
    static let yellow = Color(red: 1.0, green: 209.0 / 255.0, blue: 0.0)
    /// 美团红 #E2231A
    static let red = Color(red: 226.0 / 255.0, green: 35.0 / 255.0, blue: 26.0 / 255.0)
    /// 成功绿
    static let green = Color(red: 52.0 / 255.0, green: 199.0 / 255.0, blue: 89.0 / 255.0)
    /// 卡片背景
    static let card = Color(.secondarySystemGroupedBackground)
}

/// 通用时间格式
enum TimeFormat {
    static let time: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "MM-dd HH:mm:ss"
        return f
    }()

    static func string(_ date: Date) -> String {
        time.string(from: date)
    }
}
