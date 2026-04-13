import SwiftUI
import WebKit

/// WKWebView wrapper — renders HTML produced by MarkdownProcessor.
struct MarkdownPreviewView: NSViewRepresentable {
    let markdownText: String
    func makeCoordinator() -> Coordinator { Coordinator() }

    // CSS is loaded once and cached.
    // Bundle.main  → packaged .app (Contents/Resources/default.css)
    // Bundle.module → SPM development workflow
    private static let css: String = {
        let url = Bundle.main.url(forResource: "default", withExtension: "css")
               ?? Bundle.module.url(forResource: "default", withExtension: "css")
        guard let url, let content = try? String(contentsOf: url, encoding: .utf8)
        else { return "" }
        return content
    }()

    func makeNSView(context: Context) -> WKWebView {
        let prefs = WKWebpagePreferences()
        prefs.allowsContentJavaScript = false

        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences = prefs

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground") // transparent → follows system bg via CSS
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let html = MarkdownProcessor.buildPage(markdown: markdownText, css: Self.css)
        // Write to a temp file and use loadFileURL so WKWebView can load
        // local images at arbitrary absolute paths (drag: original path, paste: .tmp dir)
        let tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("markdown_preview.html")
        try? html.write(to: tmpURL, atomically: true, encoding: .utf8)
        webView.loadFileURL(tmpURL, allowingReadAccessTo: URL(fileURLWithPath: "/"))
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard navigationAction.navigationType == .linkActivated,
                  let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }

            NSWorkspace.shared.open(url)
            decisionHandler(.cancel)
        }
    }
}
