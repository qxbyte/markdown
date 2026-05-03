import SwiftUI
import WebKit

/// WKWebView wrapper — renders HTML produced by MarkdownProcessor.
struct MarkdownPreviewView: NSViewRepresentable {
    let markdownText: String
    let baseURL: URL?
    @Binding var scrollRatio: Double
    @Binding var scrollTarget: MarkdownScrollTarget?
    @Binding var currentHeadingLine: Int?

    func makeCoordinator() -> Coordinator { Coordinator(self) }

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
        context.coordinator.webView = webView
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self
        let renderToken = "\(markdownText.hashValue)|\(baseURL?.absoluteString ?? "")"
        guard context.coordinator.lastRenderToken != renderToken else {
            context.coordinator.applyScrollTargetIfNeeded(in: webView)
            return
        }
        context.coordinator.lastRenderToken = renderToken

        let anchoredMarkdown = MarkdownNavigation.markdownWithHeadingAnchors(markdownText)
        let html = MarkdownProcessor.buildPage(markdown: anchoredMarkdown, css: Self.css)
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
        var parent: MarkdownPreviewView
        let previewFileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("markdown_preview-\(UUID().uuidString).html")
        var lastRenderToken: String?
        weak var webView: WKWebView?
        private var lastAppliedScrollTargetID: UUID?
        private weak var observedScrollView: NSScrollView?
        private var headingDetectWorkItem: DispatchWorkItem?

        init(_ parent: MarkdownPreviewView) {
            self.parent = parent
        }

        deinit {
            if let scrollView = observedScrollView {
                NotificationCenter.default.removeObserver(self, name: NSView.boundsDidChangeNotification, object: scrollView.contentView)
            }
            try? FileManager.default.removeItem(at: previewFileURL)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            setupScrollObserverIfNeeded(for: webView)
            applyScrollTargetIfNeeded(in: webView)
            // Retry ratio-based scroll after layout settles (fonts/images may shift height)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self, weak webView] in
                guard let self, let wv = webView else { return }
                guard let target = self.parent.scrollTarget,
                      target.id == self.lastAppliedScrollTargetID,
                      case .ratio(let ratio) = target.kind else { return }
                self.scroll(toRatio: ratio, in: wv)
            }
        }

        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard navigationAction.navigationType == .linkActivated,
                  let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }

            MarkdownFileOpener.open(url, baseURL: parent.baseURL)
            decisionHandler(.cancel)
        }

        @objc private func scrollViewBoundsDidChange(_ notification: Notification) {
            guard let scrollView = observedScrollView else { return }
            updateRatio(currentScrollRatio(in: scrollView))
            scheduleHeadingDetection()
        }

        private func scheduleHeadingDetection() {
            headingDetectWorkItem?.cancel()
            let item = DispatchWorkItem { [weak self] in
                guard let self, let wv = self.webView else { return }
                let script = """
                (() => {
                    const anchors = document.querySelectorAll('div.md-source-anchor[id^="md-line-"]');
                    let line = null;
                    for (const el of anchors) {
                        if (el.getBoundingClientRect().top <= 64) {
                            const m = el.id.match(/md-line-(\\d+)/);
                            if (m) line = parseInt(m[1], 10);
                        }
                    }
                    return line;
                })();
                """
                wv.evaluateJavaScript(script) { [weak self] result, _ in
                    DispatchQueue.main.async {
                        self?.parent.currentHeadingLine = result as? Int
                    }
                }
            }
            headingDetectWorkItem = item
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: item)
        }

        private func updateRatio(_ ratio: Double) {
            let clamped = min(1, max(0, ratio))
            guard abs(parent.scrollRatio - clamped) > 0.002 else { return }
            DispatchQueue.main.async { [weak self] in
                self?.parent.scrollRatio = clamped
            }
        }

        private func setupScrollObserverIfNeeded(for webView: WKWebView) {
            guard observedScrollView == nil else { return }
            guard let scrollView = findScrollView(in: webView) else { return }
            observedScrollView = scrollView
            scrollView.contentView.postsBoundsChangedNotifications = true
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(scrollViewBoundsDidChange(_:)),
                name: NSView.boundsDidChangeNotification,
                object: scrollView.contentView
            )
            updateRatio(currentScrollRatio(in: scrollView))
        }

        private func findScrollView(in view: NSView) -> NSScrollView? {
            if let scrollView = view as? NSScrollView {
                return scrollView
            }
            for subview in view.subviews {
                if let match = findScrollView(in: subview) {
                    return match
                }
            }
            return nil
        }

        func applyScrollTargetIfNeeded(in webView: WKWebView) {
            guard let target = parent.scrollTarget else { return }
            guard lastAppliedScrollTargetID != target.id else { return }
            lastAppliedScrollTargetID = target.id

            switch target.kind {
            case .ratio(let ratio):
                scroll(toRatio: ratio, in: webView)
            case .line(let line):
                scroll(toLine: line, in: webView)
            }
        }

        private func scroll(toLine line: Int, in webView: WKWebView) {
            let script = """
            (() => {
              const anchor = document.getElementById('md-line-\(line)');
              if (!anchor) return false;
              anchor.scrollIntoView({ block: 'start', behavior: 'auto' });
              return true;
            })();
            """
            webView.evaluateJavaScript(script) { [weak self, weak webView] result, _ in
                guard let self, let webView else { return }
                if (result as? Bool) != true {
                    let totalLines = max(1, self.parent.markdownText.components(separatedBy: .newlines).count - 1)
                    self.scroll(toRatio: Double(line) / Double(totalLines), in: webView)
                }
            }
        }

        private func scroll(toRatio ratio: Double, in webView: WKWebView) {
            let clamped = min(1.0, max(0.0, ratio))
            // Use JavaScript so the browser engine resolves the real scroll height
            let script = """
            (function() {
                var maxY = document.documentElement.scrollHeight - window.innerHeight;
                if (maxY > 0) { window.scrollTo(0, maxY * \(clamped)); }
            })();
            """
            webView.evaluateJavaScript(script, completionHandler: nil)
        }

        private func currentScrollRatio(in scrollView: NSScrollView) -> Double {
            let visibleHeight = scrollView.contentView.bounds.height
            let contentHeight = scrollView.documentView?.bounds.height ?? visibleHeight
            let maxY = max(1, contentHeight - visibleHeight)
            return min(1, max(0, Double(scrollView.contentView.bounds.origin.y / maxY)))
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
