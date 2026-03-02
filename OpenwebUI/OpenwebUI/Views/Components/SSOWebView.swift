import SwiftUI
import WebKit

/// A WebView-based SSO login sheet.
/// Opens the server's OAuth login page and captures the JWT token
/// from cookies or the URL after authentication completes.
struct SSOWebView: View {
    let serverURL: String
    let onTokenCaptured: (String) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("SSO Login")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Button("Cancel") { onCancel() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
            .padding(16)

            Divider()

            // WebView
            SSOWebViewRepresentable(
                serverURL: serverURL,
                onTokenCaptured: onTokenCaptured
            )
        }
    }
}

// MARK: - NSViewRepresentable

struct SSOWebViewRepresentable: NSViewRepresentable {
    let serverURL: String
    let onTokenCaptured: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onTokenCaptured: onTokenCaptured, serverURL: serverURL)
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView

        // Load the server's auth page
        let cleanURL = serverURL.hasSuffix("/") ? String(serverURL.dropLast()) : serverURL
        if let url = URL(string: "\(cleanURL)/auth") {
            webView.load(URLRequest(url: url))
        }

        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    // MARK: - Coordinator

    class Coordinator: NSObject, WKNavigationDelegate {
        let onTokenCaptured: (String) -> Void
        let serverURL: String
        weak var webView: WKWebView?
        private var hasExtractedToken = false

        init(onTokenCaptured: @escaping (String) -> Void, serverURL: String) {
            self.onTokenCaptured = onTokenCaptured
            self.serverURL = serverURL
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // After each navigation, check for the JWT token in cookies
            checkForToken()
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            // Check if the URL contains a token parameter (some OAuth flows redirect with token)
            if let url = navigationAction.request.url {
                let urlString = url.absoluteString
                // Check for token in URL fragment or query
                if let fragment = url.fragment {
                    if let token = extractTokenFromParams(fragment) {
                        captureToken(token)
                    }
                }
                if let query = url.query {
                    if let token = extractTokenFromParams(query) {
                        captureToken(token)
                    }
                }
                // Check if redirected back to the main app page (auth complete)
                let cleanServer = serverURL.hasSuffix("/") ? String(serverURL.dropLast()) : serverURL
                if urlString.hasPrefix(cleanServer) && !urlString.contains("/auth") {
                    checkForToken()
                }
            }
            decisionHandler(.allow)
        }

        private func extractTokenFromParams(_ params: String) -> String? {
            let pairs = params.split(separator: "&")
            for pair in pairs {
                let kv = pair.split(separator: "=", maxSplits: 1)
                if kv.count == 2 {
                    let key = String(kv[0])
                    let value = String(kv[1])
                    if key == "token" || key == "access_token" || key == "jwt" {
                        return value.removingPercentEncoding ?? value
                    }
                }
            }
            return nil
        }

        private func checkForToken() {
            guard !hasExtractedToken else { return }

            // Try to extract token from cookies
            webView?.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
                guard let self, !self.hasExtractedToken else { return }
                for cookie in cookies {
                    if cookie.name == "token" || cookie.name == "jwt" {
                        self.captureToken(cookie.value)
                        return
                    }
                }

                // Also try extracting from localStorage via JS
                self.webView?.evaluateJavaScript("localStorage.getItem('token')") { result, _ in
                    if let token = result as? String, !token.isEmpty {
                        self.captureToken(token)
                    }
                }
            }
        }

        private func captureToken(_ token: String) {
            guard !hasExtractedToken else { return }
            hasExtractedToken = true
            DispatchQueue.main.async {
                self.onTokenCaptured(token)
            }
        }
    }
}
