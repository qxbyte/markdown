import Down
import Foundation

enum MarkdownProcessor {

    /// Convert Markdown to a full HTML page string.
    static func buildPage(markdown: String, css: String) -> String {
        let body = toHTML(markdown)
        return """
        <!DOCTYPE html>
        <html lang="zh-CN">
        <head>
          <meta charset="UTF-8">
          <meta name="viewport" content="width=device-width, initial-scale=1.0">
          <meta name="color-scheme" content="light dark">
          <style>\(css)</style>
        </head>
        <body class="markdown-body">
        \(body)
        </body>
        </html>
        """
    }

    // MARK: - Private

    private static func toHTML(_ markdown: String) -> String {
        let down = Down(markdownString: markdown)
        // .smartUnsafe: smart typography + allow raw HTML pass-through
        return (try? down.toHTML([.smartUnsafe])) ?? "<p><em>Render error</em></p>"
    }
}
