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
        let normalized = linkifyBareURLs(in: markdown)
        let down = Down(markdownString: normalized)
        // .smartUnsafe: smart typography + allow raw HTML pass-through
        return (try? down.toHTML([.smartUnsafe])) ?? "<p><em>Render error</em></p>"
    }

    private static func linkifyBareURLs(in markdown: String) -> String {
        var output: [String] = []
        var inFence = false

        for line in markdown.split(separator: "\n", omittingEmptySubsequences: false) {
            let rawLine = String(line)
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                inFence.toggle()
                output.append(rawLine)
                continue
            }

            if inFence || rawLine.contains("](") || rawLine.contains("<http") || rawLine.contains("<https") {
                output.append(rawLine)
                continue
            }

            if let linked = linkifyBareURLLine(rawLine) {
                output.append(linked)
            } else {
                output.append(rawLine)
            }
        }

        return output.joined(separator: "\n")
    }

    private static func linkifyBareURLLine(_ line: String) -> String? {
        let pattern = #"(?i)\bhttps?://[^\s<>()\[\]{}"']+[^\s<>().,\[\]{}"']"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let nsLine = line as NSString
        let range = NSRange(location: 0, length: nsLine.length)
        let matches = regex.matches(in: line, range: range)
        guard !matches.isEmpty else { return nil }

        var result = line
        for match in matches.reversed() {
            let url = nsLine.substring(with: match.range)
            result = (result as NSString).replacingCharacters(in: match.range, with: "<\(url)>")
        }
        return result
    }
}
