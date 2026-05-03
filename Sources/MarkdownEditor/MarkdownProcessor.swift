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
        let withTables = processGFMTables(in: normalized)
        let down = Down(markdownString: withTables)
        // .smartUnsafe: smart typography + allow raw HTML pass-through
        return (try? down.toHTML([.smartUnsafe])) ?? "<p><em>Render error</em></p>"
    }

    // MARK: - GFM Table pre-processor

    private static func processGFMTables(in text: String) -> String {
        let lines = text.components(separatedBy: "\n")
        var output: [String] = []
        var i = 0
        var inFence = false

        while i < lines.count {
            let raw = lines[i]
            let trimmed = raw.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                inFence.toggle()
                output.append(raw)
                i += 1
                continue
            }
            if inFence {
                output.append(raw)
                i += 1
                continue
            }

            if i + 1 < lines.count,
               let headers = splitTableRow(lines[i]),
               headers.count >= 2,
               let aligns = parseSeparatorRow(lines[i + 1]),
               aligns.count == headers.count {

                var html = "<table>\n<thead>\n<tr>\n"
                for (j, h) in headers.enumerated() {
                    let attr = aligns[j].isEmpty ? "" : " align=\"\(aligns[j])\""
                    html += "<th\(attr)>\(renderInlineMarkdown(h))</th>\n"
                }
                html += "</tr>\n</thead>\n<tbody>\n"
                i += 2

                while i < lines.count,
                      !lines[i].trimmingCharacters(in: .whitespaces).isEmpty,
                      let cells = splitTableRow(lines[i]) {
                    html += "<tr>\n"
                    for j in 0..<headers.count {
                        let cell = j < cells.count ? cells[j] : ""
                        let attr = aligns[j].isEmpty ? "" : " align=\"\(aligns[j])\""
                        html += "<td\(attr)>\(renderInlineMarkdown(cell))</td>\n"
                    }
                    html += "</tr>\n"
                    i += 1
                }

                html += "</tbody>\n</table>"
                output.append(html)
            } else {
                output.append(raw)
                i += 1
            }
        }

        return output.joined(separator: "\n")
    }

    private static func splitTableRow(_ line: String) -> [String]? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.contains("|") else { return nil }
        var parts = trimmed.components(separatedBy: "|")
        if parts.first?.trimmingCharacters(in: .whitespaces).isEmpty == true { parts.removeFirst() }
        if parts.last?.trimmingCharacters(in: .whitespaces).isEmpty == true { parts.removeLast() }
        guard !parts.isEmpty else { return nil }
        return parts.map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private static func parseSeparatorRow(_ line: String) -> [String]? {
        guard let cells = splitTableRow(line) else { return nil }
        var aligns: [String] = []
        for cell in cells {
            let c = cell.trimmingCharacters(in: .whitespaces)
            guard !c.isEmpty,
                  c.unicodeScalars.allSatisfy({ $0 == "-" || $0 == ":" || $0 == " " }),
                  c.contains("-") else { return nil }
            let left = c.hasPrefix(":")
            let right = c.hasSuffix(":")
            aligns.append(left && right ? "center" : right ? "right" : left ? "left" : "")
        }
        return aligns
    }

    private static func renderInlineMarkdown(_ text: String) -> String {
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return "" }
        let down = Down(markdownString: text)
        guard var html = try? down.toHTML([.smartUnsafe]) else { return text }
        html = html.trimmingCharacters(in: .whitespacesAndNewlines)
        if html.hasPrefix("<p>") { html = String(html.dropFirst(3)) }
        if html.hasSuffix("</p>") { html = String(html.dropLast(4)) }
        return html.trimmingCharacters(in: .whitespacesAndNewlines)
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
