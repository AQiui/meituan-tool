import SwiftUI
import WebKit

/// 美团网页登录页:登录成功后自动从 Cookie 中提取 token
/// 免去抓包,适合巨魔安装后直接使用
struct LoginWebView: View {
    /// 提取到 token 后的回调(只回调一次)
    var onToken: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var status = "请在页面中登录美团(可用美团 App 扫码或手机号验证码)"
    @State private var isLoading = true
    @State private var added = false

    private let loginURL = URL(string: "https://i.meituan.com/")!
    /// 移动端 UA,保证打开的是手机版登录页
    private let mobileUA = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                WebViewContainer(
                    url: loginURL,
                    userAgent: mobileUA,
                    isLoading: $isLoading,
                    onCookieString: handleCookieString,
                    onRequestManualFetch: nil
                )
                statusBar
            }
            .navigationTitle("美团网页登录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }

    // MARK: 状态栏

    private var statusBar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.8)
                }
                Text(added ? "已获取 token,正在保存…" : status)
                    .font(.caption)
                    .foregroundColor(added ? Theme.green : .secondary)
                    .multilineTextAlignment(.leading)
                Spacer()
            }
            HStack(spacing: 12) {
                Button("刷新页面") {
                    // 通过重新加载 URL 触发 cookieStore 刷新
                    NotificationCenter.default.post(name: .webViewReload, object: nil)
                }
                .font(.caption)
                Button("手动获取") {
                    NotificationCenter.default.post(name: .webViewManualFetch, object: nil)
                }
                .font(.caption)
                Spacer()
            }
        }
        .padding()
        .background(Theme.card)
    }

    // MARK: Cookie 解析

    /// 从 "name=value; name=value" 字符串中提取 token
    private func handleCookieString(_ cookieString: String) {
        guard !added else { return }
        guard let token = extractToken(from: cookieString) else { return }
        added = true
        status = "已获取 token:\(token.prefix(6))…"
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            onToken(token)
        }
    }

    private func extractToken(from cookieString: String) -> String? {
        for pair in cookieString.components(separatedBy: ";") {
            let kv = pair.split(separator: "=", maxSplits: 1)
            guard kv.count == 2 else { continue }
            let key = kv[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard key == "token" else { continue }
            var value = String(kv[1]).trimmingCharacters(in: .whitespacesAndNewlines)
            // 去掉可能的引号
            if value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 {
                value = String(value.dropFirst().dropLast())
            }
            guard !value.isEmpty else { continue }
            return value
        }
        return nil
    }
}

extension Notification.Name {
    static let webViewReload = Notification.Name("webViewReload")
    static let webViewManualFetch = Notification.Name("webViewManualFetch")
}

/// WKWebView 容器:负责加载页面、读取 Cookie、响应工具栏按钮
struct WebViewContainer: UIViewRepresentable {
    let url: URL
    let userAgent: String
    @Binding var isLoading: Bool
    /// 统一以 "name=value; ..." 字符串回调 Cookie
    var onCookieString: (String) -> Void
    var onRequestManualFetch: (() -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.customUserAgent = userAgent
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        context.coordinator.webView = webView
        webView.load(URLRequest(url: url))

        NotificationCenter.default.addObserver(context.coordinator,
                                               selector: #selector(Coordinator.reloadPage),
                                               name: .webViewReload,
                                               object: nil)
        NotificationCenter.default.addObserver(context.coordinator,
                                               selector: #selector(Coordinator.manualFetch),
                                               name: .webViewManualFetch,
                                               object: nil)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        NotificationCenter.default.removeObserver(coordinator)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var parent: WebViewContainer
        weak var webView: WKWebView?

        init(parent: WebViewContainer) {
            self.parent = parent
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            parent.isLoading = true
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            parent.isLoading = false
            fetchCookiesFromStore()
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            parent.isLoading = false
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            parent.isLoading = false
        }

        // MARK: Cookie 读取

        /// 主路径:从 WKHTTPCookieStore 读取
        func fetchCookiesFromStore() {
            WKWebsiteDataStore.default().httpCookieStore.getAllCookies { [weak self] cookies in
                guard let self else { return }
                let meituanCookies = cookies.filter { $0.domain.contains("meituan") }
                guard !meituanCookies.isEmpty else { return }
                let string = meituanCookies
                    .map { "\($0.name)=\($0.value)" }
                    .joined(separator: "; ")
                DispatchQueue.main.async {
                    self.parent.onCookieString(string)
                }
            }
        }

        /// 兜底路径:document.cookie
        @objc func manualFetch() {
            fetchCookiesFromStore()
            webView?.evaluateJavaScript("document.cookie") { [weak self] result, _ in
                guard let self, let cookieString = result as? String, !cookieString.isEmpty else { return }
                DispatchQueue.main.async {
                    self.parent.onCookieString(cookieString)
                }
            }
        }

        @objc func reloadPage() {
            guard let webView else { return }
            webView.reload()
        }
    }
}

#Preview {
    LoginWebView { _ in }
}
