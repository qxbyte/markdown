import SwiftUI
import WebKit

/// WKWebView wrapper — renders HTML produced by MarkdownProcessor.
struct MarkdownPreviewView: NSViewRepresentable {
    let markdownText: String
    let baseURL: URL?
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
        let previewHTML = Self.htmlForPreview(html, baseURL: baseURL)
        let tmpURL = context.coordinator.previewFileURL

        do {
            try previewHTML.write(to: tmpURL, atomically: true, encoding: .utf8)
            webView.loadFileURL(tmpURL, allowingReadAccessTo: URL(fileURLWithPath: "/"))
        } catch {
            webView.loadHTMLString(previewHTML, baseURL: baseURL)
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        let previewFileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("markdown_preview-\(UUID().uuidString).html")

        deinit {
            try? FileManager.default.removeItem(at: previewFileURL)
        }

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

    private static func htmlForPreview(_ html: String, baseURL: URL?) -> String {
        guard let baseURL else { return html }

        let directoryBaseURL = URL(fileURLWithPath: baseURL.path, isDirectory: true)
        let baseTag = #"  <base href="\#(htmlAttributeEscaped(directoryBaseURL.absoluteString))">"#

        if let headRange = html.range(of: "<head>") {
            var result = html
            result.insert(contentsOf: "\n\(baseTag)", at: headRange.upperBound)
            return result
        }

        return baseTag + "\n" + html
    }

    private static func htmlAttributeEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
