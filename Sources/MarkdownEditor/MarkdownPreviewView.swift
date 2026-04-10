import SwiftUI
import WebKit

/// WKWebView wrapper — renders HTML produced by MarkdownProcessor.
struct MarkdownPreviewView: NSViewRepresentable {
    let markdownText: String

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
        webView.setValue(false, forKey: "drawsBackground") // transparent → follows system bg via CSS
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let html = MarkdownProcessor.buildPage(markdown: markdownText, css: Self.css)
        // Use a bundle base URL so relative resource paths resolve (future: local images)
        let baseURL = Bundle.module.resourceURL
        webView.loadHTMLString(html, baseURL: baseURL)
    }
}
