import Foundation

/// 城市坐标(领券接口的 wm_latitude / wm_longitude 参数)
struct CityInfo: Equatable {
    let name: String
    let latitude: Double
    let longitude: Double
}

enum Cities {
    /// 全国主要城市,随机定位时从中选取(不同城市红包池库存不同)
    static let all: [CityInfo] = [
        CityInfo(name: "北京",   latitude: 39.9097, longitude: 116.4134),
        CityInfo(name: "上海",   latitude: 31.2304, longitude: 121.4737),
        CityInfo(name: "广州",   latitude: 23.1291, longitude: 113.2644),
        CityInfo(name: "深圳",   latitude: 22.5431, longitude: 114.0579),
        CityInfo(name: "杭州",   latitude: 30.2741, longitude: 120.1551),
        CityInfo(name: "成都",   latitude: 30.5728, longitude: 104.0668),
        CityInfo(name: "重庆",   latitude: 29.5630, longitude: 106.5516),
        CityInfo(name: "武汉",   latitude: 30.5928, longitude: 114.3055),
        CityInfo(name: "西安",   latitude: 34.3416, longitude: 108.9398),
        CityInfo(name: "南京",   latitude: 32.0603, longitude: 118.7969),
        CityInfo(name: "天津",   latitude: 39.3434, longitude: 117.3616),
        CityInfo(name: "苏州",   latitude: 31.2989, longitude: 120.5853),
        CityInfo(name: "郑州",   latitude: 34.7466, longitude: 113.6254),
        CityInfo(name: "长沙",   latitude: 28.2282, longitude: 112.9388),
        CityInfo(name: "宁波",   latitude: 29.8683, longitude: 121.5440),
        CityInfo(name: "青岛",   latitude: 36.0671, longitude: 120.3826),
        CityInfo(name: "无锡",   latitude: 31.4912, longitude: 120.3119),
        CityInfo(name: "合肥",   latitude: 31.8206, longitude: 117.2272),
        CityInfo(name: "福州",   latitude: 26.0745, longitude: 119.2965),
        CityInfo(name: "厦门",   latitude: 24.4798, longitude: 118.0894),
        CityInfo(name: "济南",   latitude: 36.6512, longitude: 117.1201),
        CityInfo(name: "大连",   latitude: 38.9140, longitude: 121.6147),
        CityInfo(name: "沈阳",   latitude: 41.8057, longitude: 123.4315),
        CityInfo(name: "哈尔滨", latitude: 45.8038, longitude: 126.5349),
        CityInfo(name: "长春",   latitude: 43.8171, longitude: 125.3235),
        CityInfo(name: "石家庄", latitude: 38.0428, longitude: 114.5149),
        CityInfo(name: "太原",   latitude: 37.8706, longitude: 112.5489),
        CityInfo(name: "南昌",   latitude: 28.6829, longitude: 115.8582),
        CityInfo(name: "贵阳",   latitude: 26.6470, longitude: 106.6302),
        CityInfo(name: "南宁",   latitude: 22.8170, longitude: 108.3669),
        CityInfo(name: "昆明",   latitude: 24.8801, longitude: 102.8329),
        CityInfo(name: "海口",   latitude: 20.0311, longitude: 110.3312),
        CityInfo(name: "兰州",   latitude: 36.0611, longitude: 103.8343),
        CityInfo(name: "西宁",   latitude: 36.6171, longitude: 101.7782),
        CityInfo(name: "银川",   latitude: 38.4872, longitude: 106.2309),
        CityInfo(name: "呼和浩特", latitude: 40.8426, longitude: 111.7492),
        CityInfo(name: "乌鲁木齐", latitude: 43.8256, longitude: 87.6168),
        CityInfo(name: "拉萨",   latitude: 29.6456, longitude: 91.1409),
        CityInfo(name: "温州",   latitude: 27.9944, longitude: 120.6994),
        CityInfo(name: "嘉兴",   latitude: 30.7466, longitude: 120.7555),
        CityInfo(name: "金华",   latitude: 29.0794, longitude: 119.6474),
        CityInfo(name: "绍兴",   latitude: 30.0303, longitude: 120.5802),
        CityInfo(name: "台州",   latitude: 28.6566, longitude: 121.4208),
        CityInfo(name: "扬州",   latitude: 32.3943, longitude: 119.4127),
        CityInfo(name: "常州",   latitude: 31.8112, longitude: 119.9741),
        CityInfo(name: "南通",   latitude: 31.9802, longitude: 120.8943),
        CityInfo(name: "徐州",   latitude: 34.2618, longitude: 117.1848),
        CityInfo(name: "潍坊",   latitude: 36.7069, longitude: 119.1618),
        CityInfo(name: "烟台",   latitude: 37.4638, longitude: 121.4479),
        CityInfo(name: "洛阳",   latitude: 34.6197, longitude: 112.4539),
        CityInfo(name: "佛山",   latitude: 23.0288, longitude: 113.1220),
        CityInfo(name: "东莞",   latitude: 23.0207, longitude: 113.7518),
        CityInfo(name: "珠海",   latitude: 22.2707, longitude: 113.5767),
        CityInfo(name: "中山",   latitude: 22.5159, longitude: 113.3926),
        CityInfo(name: "惠州",   latitude: 23.1116, longitude: 114.4162),
        CityInfo(name: "汕头",   latitude: 23.3535, longitude: 116.6820)
    ]

    static let fallback = all[0]

    static func random() -> CityInfo { all.randomElement() ?? fallback }

    static func named(_ name: String) -> CityInfo? {
        all.first { $0.name == name }
    }
}
