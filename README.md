# 美团助手(MeiTuanTool)

iOS 巨魔(TrollStore)可用的**美团优惠券一键领取 + 会员签到**工具。原生 SwiftUI 开发,无需越狱、无需账号密码,通过美团公开接口完成每日签到、抢天天神券、红包管理。

## 功能特性

| 模块 | 说明 |
| --- | --- |
| 一键领取 | 单个按钮完成「签到领红豆 → 签到领必中符 → 任务领豆 → 查询红包池 → 必中符抽奖 → 发放到账/小额转豆 → 查询红包库」全流程 |
| 会员签到 | 每日签到领红豆、连续签到领必中符、浏览任务领豆,支持仅签到模式 |
| 天天神券 | 自动获取抢券批次,有必中符自动使用,低于阈值的小额券自动转红豆 |
| 多账号 | 支持多 token 账号、备注名、批量导入、单独配置固定城市 |
| 免抓包登录 | App 内置美团网页登录页,登录成功自动提取 token |
| 定时自动化 | 支持快捷指令 URL Scheme(`meituantool://run`)+ iOS 后台刷新 |
| 本地通知 | 执行完成后推送各账号结果摘要 |
| 执行日志 | 每账号每步骤结果留痕,按日分组查看 |
| 接口可配置 | 全部接口路径在 `endpoints.json` 中,美团改接口只需换文件,不用改代码 |
| 黑金会员监控 | 自动查询会员等级/成长值/任务状态,今日未签到本地提醒,一键跳转美团 App 签到(签到接口有签名风控,无法第三方自动重放) |

## 环境要求

-  macOS + Xcode 15 及以上(用于编译)
-  部署目标 iOS 15.0+
-  安装方式:TrollStore(巨魔)安装导出的 IPA

## 目录结构

```
MeiTuanTool/
├── MeiTuanTool.xcodeproj/      # Xcode 工程
└── MeiTuanTool/
    ├── MeiTuanToolApp.swift    # App 入口(注册后台任务、URL Scheme)
    ├── ContentView.swift       # 主界面 Tab
    ├── Models/                 # 数据模型(账号/报告/设置/接口配置)
    ├── Services/               # 核心服务(网络客户端/任务编排/存储/通知/后台)
    ├── Utilities/              # 工具(城市库/表单编码/JSON 解析/主题/路由)
    ├── Views/                  # SwiftUI 界面(首页/账号/登录/日志/设置)
    └── Resources/
        ├── Info.plist          # URL Scheme、后台模式声明
        ├── endpoints.json      # 接口配置(可覆盖)
        └── Assets.xcassets/    # App 图标
docs/
├── 接口与抓包.md                # 接口清单、token 获取、接口更新方法
└── 快捷指令自动化.md             # 定时自动化配置教程
```

## 编译与安装(巨魔)

### 1. 打开工程

```bash
open MeiTuanTool/MeiTuanTool.xcodeproj
```

### 2. 配置签名

- 选中 Target `MeiTuanTool` → Signing & Capabilities
- 勾选 "Automatically manage signing"
- Team 选择你的 Apple ID(免费个人账号即可,巨魔安装不依赖证书有效期)

### 3. 打包 IPA

**方式 A(Xcode 直接构建):**

1. 顶部设备选择 "Any iOS Device (arm64)"
2. Product → Build(或 ⌘B)
3. 左侧 Products 分组右键 `MeiTuanTool.app` → Show in Finder
4. 将该 `.app` 放入名为 `Payload` 的文件夹,压缩为 `Payload.zip`,重命名为 `MeiTuanTool.ipa`

**方式 B(Archive 导出):**

1. Product → Archive
2. Organizer 中选择 Distribute App → Development → 导出
3. 对导出的 `.app` 按方式 A 第 4 步打包成 IPA

### 4. 安装到 iPhone

把 `MeiTuanTool.ipa` 通过 AirDrop / 文件 App / iCloud 传到 iPhone,用 TrollStore(巨魔)打开安装即可。

## 快速上手

1. **添加账号**:「账号」页 → 右上角 ➕
   - **网页登录(推荐)**:打开美团登录页,用美团 App 扫码或手机号验证码登录,自动抓取 token
   - **手动输入**:粘贴 token(青龙脚本用的 `meituanCookie` 同款值)
   - **批量导入**:每行一个,支持 `备注=token`
2. **一键执行**:「首页」→「一键签到 + 领券」,可展开查看每个步骤结果
3. **查看结果**:首页卡片 + 本地通知 + 「日志」页历史记录

## 定时自动化(重点)

iOS 不允许 App 常驻后台。要每天准时抢券(11:00 / 17:00 / 21:00 开放),请用系统「快捷指令」创建个人自动化,动作选「打开 URL」,填入:

```
meituantool://run
```

App 被唤起后会在后台争取约 30 秒把任务跑完并推送通知。完整教程见 [docs/快捷指令自动化.md](docs/快捷指令自动化.md)。

## 常见问题

**Q: token 失效怎么办?**
A: 账号卡片会显示异常标记。进入「账号」页点击该账号重新保存新 token,或用网页登录重新抓取。token 一般 7~30 天有效。

**Q: 接口失效/抢券提示"不在时段"?**
A: 天天神券每天 11:00 / 17:00 / 21:00 三个时段开放,其他时间查询红包池会提示当前不在抢券时段,属正常现象。若接口地址变更,按 [docs/接口与抓包.md](docs/接口与抓包.md) 更新 `endpoints.json` 即可。

**Q: 抢券一定要开必中符吗?**
A: 不必须。没有必中符时按拼手气抽取;开启"有必中符自动使用"后会优先消耗道具库中的必中符。

**Q: 为什么实际抢券时间比快捷指令晚几秒?**
A: 快捷指令唤起 App 到发出请求有启动开销。追求极限速度可在自动化时间上提前 10~20 秒,让 App 完成轮询等待(红包池未开放时会自动返回,到点后重试即可)。

**Q: 支持饿了么/其他平台吗?**
A: 当前版本专注美团。架构上接口全部配置化,可按同样模式扩展。

**Q: 黑金会员签到怎么用?**
A: 美团会员签到接口带 mtgsig 密码学校验(实测:无签名报系统异常、伪造签名 403),第三方 App 无法自动重放。本工具改用「监控 + 提醒」模式:「设置 → 黑金会员监控 → 导入抓包凭证」粘贴 HAR 全文(Stream 抓包后分享复制),之后 App 每天自动查等级/成长值/签到状态,未签到就发通知,点一下跳转美团 App 手动签到(3 秒)。查询接口本身全自动,无需任何手动操作。详见 [docs/接口与抓包.md](docs/接口与抓包.md) 第五节。

## 免责声明

本项目仅供个人学习交流使用,所有功能通过美团公开 H5 接口实现。请合理设置执行频率,过于频繁的请求可能导致账号被风控。使用本工具产生的任何后果由使用者自行承担。

## 致谢

接口流程参考开源项目 [meituan-shenquan](https://github.com/blacksun1993/meituan-shenquan)、[MeituanRedenvelope](https://github.com/jiazengp/MeituanRedenvelope) 等,感谢相关作者的逆向与分析工作。
