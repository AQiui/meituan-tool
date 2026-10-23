import SwiftUI
import WebKit

/// 黑金会员中心抓包学习页
///
/// 美团会员(成长值)体系的签到/任务接口未公开,本页面通过 WKWebView 加载会员中心 H5,
/// 注入 JS hook 捕获页面真实发出的 XHR/fetch 请求(方法 + 路径 + body),
/// 用户点一下「添加为任务」即可把接口配置进 endpoints.json,之后全自动执行。
///
/// 使用步骤:
/// 1. 在美团 App 里打开「我的 → 会员中心」,点右上角分享 → 复制链接,粘贴到顶部输入框打开
///    (默认地址打不开时再用分享链接;App 内打开本页面前的账号即登录态)
/// 2. 在页面里正常点一次「签到」/做一次任务
/// 3. 回到本 App,下方会列出捕获到的请求,点目标请求 → 添加为会员任务
struct MemberCenterView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var urlText = "https://member.meituan.com"
    @State private var loadedURL: URL?
    /// 每次「打开」递增,用于强制重建 WebView(同一 URL 重复打开也能刷新)
    @State private var loadToken = UUID()
    @State private var requests: [SniffedRequest] = []
    @State private var showList = false
    @State private var editing: SniffedRequest?

    private let mobileUA = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                urlBar
                webArea
                footerBar
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("黑金会员中心")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .sheet(isPresented: $showList) {
                snifferListSheet
            }
            .sheet(item: $editing) { req in
                AddMemberTaskSheet(request: req) { name, bodyExtra in
                    addTask(name: name, bodyExtra: bodyExtra)
                }
            }
        }
    }

    // MARK: 顶部 URL 栏

    private var urlBar: some View {
        HStack(spacing: 8) {
            TextField("会员中心链接", text: $urlText)
                .font(.caption)
                .keyboardType(.URL)
                .autocapitalization(.none)
                .disableAutocorrection(true)
                .padding(8)
                .background(Color(.tertiarySystemGroupedBackground))
                .cornerRadius(8)
            Button("打开") {
                var text = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.contains("://") { text = "https://" + text }
                if let url = URL(string: text) {
                    loadedURL = url
                    loadToken = UUID()
                    requests = []
                }
            }
            .font(.subheadline)
            .disabled(urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding()
    }

    // MARK: WebView 区域

    private var webArea: some View {
        Group {
            if let url = loadedURL {
                SnifferWebView(
                    url: url,
                    userAgent: mobileUA,
                    onCapture: { req in
                        // 去重:同 URL + 同 body 只保留一条(刷新时间)
                        if let idx = requests.firstIndex(where: { $0.url == req.url && $0.body == req.body }) {
                            requests[idx].date = Date()
                            requests[idx].count += 1
                        } else {
                            requests.insert(req, at: 0)
                            if requests.count > 200 { requests.removeLast() }
                        }
                    }
                )
                .id(loadToken)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "person.crop.circle.badge.questionmark")
                        .font(.largeTitle)
                        .foregroundColor(Theme.yellow)
                    Text("在美团 App 打开「我的 → 会员中心」,分享 → 复制链接,粘贴到上面打开")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    Text("然后在页面里点一次签到,本 App 会自动捕获接口")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
                .frame(maxHeight: .infinity)
            }
        }
    }

    // MARK: 底部状态栏

    private var footerBar: some View {
        HStack(spacing: 12) {
            Image(systemName: requests.isEmpty ? "dot.radiowaves.up" : "dot.radiowaves.up.fill")
                .foregroundColor(requests.isEmpty ? .secondary : Theme.green)
            Text(requests.isEmpty ? "正在监听页面请求…" : "已捕获 \(requests.count) 个请求")
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            if !requests.isEmpty {
                Button("查看并添加任务") { showList = true }
                    .font(.caption)
            }
        }
        .padding()
        .background(Theme.card)
    }

    // MARK: 捕获列表

    private var snifferListSheet: some View {
        NavigationView {
            List {
                Section(header: Text("捕获到的请求"), footer: Text("只保留 XHR/fetch。找到类似「签到 / sign / task / growth」的请求,点它添加为任务。token 字段会自动剔除,执行时自动补充。")) {
                    ForEach(requests) { req in
                        Button(action: { editing = req }) {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(req.method)
                                        .font(.system(.caption2, design: .monospaced))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color(.tertiarySystemGroupedBackground))
                                        .cornerRadius(4)
                                    Text(req.shortPath)
                                        .font(.system(.caption, design: .monospaced))
                                        .lineLimit(1)
                                    Spacer()
                                    if req.count > 1 {
                                        Text("×\(req.count)")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                    if req.added {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(Theme.green)
                                    }
                                }
                                if !req.body.isEmpty {
                                    Text(req.bodyPreview)
                                        .font(.system(.caption2, design: .monospaced))
                                        .foregroundColor(.secondary)
                                        .lineLimit(2)
                                }
                            }
                        }
                        .foregroundColor(.primary)
                    }
                }
            }
            .navigationTitle("请求捕获")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { showList = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("清空") { requests = [] }
                }
            }
        }
    }

    // MARK: 添加任务

    private func addTask(name: String, bodyExtra: [String: String]) {
        guard let req = editing else { return }
        var config = appState.config
        // path 取 URL 的 path+query(query 属于动态定位参数时一般也在 body,这里只取 path)
        let path = req.pathOnly
        config.addMemberTask(EndpointConfig.MemberTask(
            name: name.isEmpty ? req.shortPath : name,
            path: path,
            bodyExtra: bodyExtra
        ))
        appState.reloadConfig()
        if let idx = requests.firstIndex(where: { $0.id == req.id }) {
            requests[idx].added = true
        }
        editing = nil
    }
}

// MARK: - 捕获记录模型

struct SniffedRequest: Identifiable {
    let id = UUID().uuidString
    var method: String
    var url: String
    var body: String
    var date = Date()
    var count = 1
    var added = false

    /// 去掉协议和域名的路径部分
    var shortPath: String {
        if let range = url.range(of: "://"), let slash = url.range(of: "/", range: range.upperBound..<url.endIndex) {
            return String(url[slash.lowerBound...])
        }
        return url
    }

    /// 纯 path(不含 query),用于接口配置
    var pathOnly: String {
        let p = shortPath
        if let q = p.range(of: "?") { return String(p[p.startIndex..<q.lowerBound]) }
        return p
    }

    var bodyPreview: String {
        String(body.prefix(120))
    }
}

// MARK: - 添加任务 Sheet

struct AddMemberTaskSheet: View {
    let request: SniffedRequest
    var onSave: (String, [String: String]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    /// body 的 key=value 编辑行(token 自动剔除)
    @State private var pairs: [(key: String, value: String)]

    init(request: SniffedRequest, onSave: @escaping (String, [String: String]) -> Void) {
        self.request = request
        self.onSave = onSave
        _name = State(initialValue: Self.guessName(request))
        _pairs = State(initialValue: Self.parsePairs(request.body))
    }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("任务名称")) {
                    TextField("如:会员签到领成长值", text: $name)
                }
                Section(header: Text("接口路径"), footer: Text("如需带 query 参数(如城市 id),可手动补到路径末尾。")) {
                    Text(request.pathOnly)
                        .font(.system(.caption, design: .monospaced))
                }
                Section(header: Text("请求参数(body)"), footer: Text("已自动剔除 token,执行时自动补充。执行结果里成长值字段会自动解析。")) {
                    if pairs.isEmpty {
                        Text("该请求没有 body 参数")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    ForEach(pairs.indices, id: \.self) { i in
                        HStack {
                            Text(pairs[i].key)
                                .font(.system(.caption, design: .monospaced))
                                .frame(minWidth: 90, alignment: .leading)
                            TextField("值", text: Binding(
                                get: { pairs[i].value },
                                set: { pairs[i].value = $0 }
                            ))
                            .font(.system(.caption, design: .monospaced))
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                        }
                    }
                }
            }
            .navigationTitle("添加会员任务")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        var extra: [String: String] = [:]
                        for pair in pairs where !pair.value.isEmpty {
                            extra[pair.key] = pair.value
                        }
                        onSave(name.trimmingCharacters(in: .whitespaces), extra)
                        dismiss()
                    }
                }
            }
        }
    }

    /// 从路径猜一个任务名
    static func guessName(_ req: SniffedRequest) -> String {
        let p = req.pathOnly.lowercased()
        if p.contains("sign") { return "会员签到" }
        if p.contains("task") { return "会员任务" }
        if p.contains("growth") { return "成长值任务" }
        return "会员任务"
    }

    /// 解析 urlencoded body;剔除 token / sign 等易变字段
    static func parsePairs(_ body: String) -> [(key: String, value: String)] {
        var result: [(String, String)] = []
        for seg in body.split(separator: "&") {
            let kv = seg.split(separator: "=", maxSplits: 1)
            guard kv.count == 2 else { continue }
            let key = String(kv[0])
            let value = String(kv[1])
            // token/登录态/签名类字段执行时自动生成,不入配置
            if key == "token" || key == "sign" || key == "timestamp" || key == "uuid" { continue }
            result.append((key: key, value: value.removingPercentEncoding ?? value))
        }
        return result
    }
}

// MARK: - 带请求嗅探的 WebView 容器

struct SnifferWebView: UIViewRepresentable {
    let url: URL
    let userAgent: String
    var onCapture: (SniffedRequest) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let controller = WKUserContentController()
        controller.add(context.coordinator, name: "memberSniffer")
        config.userContentController = controller

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.customUserAgent = userAgent
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView

        // 注意:项目开启了 ENABLE_USER_SCRIPT_SANDBOXING,沙箱化的 WKUserScript
        // 无法访问 window.webkit.messageHandlers,因此改为页面加载完成后
        // 用 evaluateJavaScript 在主 world 注入 hook(didFinish 中每次重新注入)
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        // URL 变化由父视图重建本视图处理,这里不重复加载
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "memberSniffer")
    }

    /// 注入 JS:hook fetch 与 XMLHttpRequest,把请求方法与 body 回传 Swift
    static let snifferJS = """
    (function(){
      if (window.__mtSniffer) { return; }
      window.__mtSniffer = true;
      function post(d){
        try { window.webkit.messageHandlers.memberSniffer.postMessage(d); } catch(e) {}
      }
      function normBody(b){
        try {
          if (!b) { return ''; }
          if (typeof b === 'string') { return b; }
          if (b instanceof URLSearchParams) { return b.toString(); }
          if (typeof FormData !== 'undefined' && b instanceof FormData) {
            var p = []; b.forEach(function(v, k){ p.push(k + '=' + v); }); return p.join('&');
          }
          return JSON.stringify(b);
        } catch(e) { return ''; }
      }
      var of = window.fetch;
      if (of) {
        window.fetch = function(){
          try {
            var a = arguments;
            var u = (typeof a[0] === 'string') ? a[0] : (a[0] && a[0].url) || '';
            var o = a[1] || {};
            post({ method: (o.method || 'GET'), url: String(u), body: normBody(o.body) });
          } catch(e) {}
          return of.apply(this, arguments);
        };
      }
      var OX = window.XMLHttpRequest;
      if (OX) {
        var oOpen = OX.prototype.open;
        var oSend = OX.prototype.send;
        OX.prototype.open = function(m, u){
          this.__sM = m; this.__sU = u;
          return oOpen.apply(this, arguments);
        };
        OX.prototype.send = function(b){
          try {
            post({ method: String(this.__sM || 'GET'), url: String(this.__sU || ''), body: normBody(b) });
          } catch(e) {}
          return oSend.apply(this, arguments);
        };
      }
    })();
    """

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: SnifferWebView
        weak var webView: WKWebView?

        init(parent: SnifferWebView) {
            self.parent = parent
        }

        /// 页面加载完成后注入 hook;SPA 路由切换也会再次触发 didFinish,重新注入保证存活
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.evaluateJavaScript(SnifferWebView.snifferJS, completionHandler: nil)
        }

        func userContentController(_ userContentController: WKUserContentController,
                                               didReceive message: WKScriptMessage) {
            guard let dict = message.body as? [String: Any],
                  let url = dict["url"] as? String, !url.isEmpty,
                  let method = dict["method"] as? String else { return }
            let body = dict["body"] as? String ?? ""
            // 静态资源噪声过滤:只留接口请求(有 body 或路径含 api/xhr 特征)
            let lower = url.lowercased()
            let isStatic = lower.hasSuffix(".js") || lower.hasSuffix(".css") || lower.hasSuffix(".png")
                || lower.hasSuffix(".jpg") || lower.hasSuffix(".svg") || lower.hasSuffix(".woff")
                || lower.hasSuffix(".gif") || lower.hasSuffix(".ico") || lower.hasSuffix(".webp")
            if isStatic { return }

            let req = SniffedRequest(method: method.uppercased(), url: url, body: body)
            Task { @MainActor in
                parent.onCapture(req)
            }
        }
    }
}

#Preview {
    MemberCenterView()
        .environmentObject(AppState.shared)
}
