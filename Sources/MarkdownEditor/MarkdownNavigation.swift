import Foundation

struct MarkdownScrollTarget: Equatable {
    enum Kind: Equatable {
        case ratio(Double)
        case line(Int)
    }

    let id = UUID()
    let kind: Kind

    static func == (lhs: MarkdownScrollTarget, rhs: MarkdownScrollTarget) -> Bool {
        lhs.id == rhs.id
    }
}

struct MarkdownHeading: Identifiable, Equatable {
    var id: Int { line }
    let level: Int
    let title: String
    let line: Int
}

enum MarkdownNavigation {
    static func headings(in markdown: String) -> [MarkdownHeading] {
        var result: [MarkdownHeading] = []
        var inFence = false

        for (index, rawLine) in markdown.components(separatedBy: .newlines).enumerated() {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                inFence.toggle()
                continue
            }

            guard !inFence else { continue }
            guard trimmed.hasPrefix("#") else { continue }

            let hashes = trimmed.prefix { $0 == "#" }.count
            guard (1...6).contains(hashes) else { continue }
            guard trimmed.count > hashes else { continue }

            let markerEnd = trimmed.index(trimmed.startIndex, offsetBy: hashes)
            guard trimmed[markerEnd] == " " else { continue }

            var title = String(trimmed[trimmed.index(after: markerEnd)...])
                .trimmingCharacters(in: .whitespaces)
            title = title.replacingOccurrences(
                of: #"#+\s*$"#,
                with: "",
                options: .regularExpression
            )
            title = title.trimmingCharacters(in: .whitespaces)

            guard !title.isEmpty else { continue }
            result.append(MarkdownHeading(level: hashes, title: title, line: index))
        }

        return result
    }

    static func markdownWithHeadingAnchors(_ markdown: String) -> String {
        var output: [String] = []
        var inFence = false

        for (index, rawLine) in markdown.components(separatedBy: .newlines).enumerated() {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                inFence.toggle()
                output.append(rawLine)
                continue
            }

            if !inFence, isHeadingLine(trimmed) {
                output.append(#"<a id="md-line-\#(index)" class="md-source-anchor"></a>"#)
            }

            output.append(rawLine)
        }

        return output.joined(separator: "\n")
    }

    private static func isHeadingLine(_ trimmed: String) -> Bool {
        guard trimmed.hasPrefix("#") else { return false }
        let hashes = trimmed.prefix { $0 == "#" }.count
        guard (1...6).contains(hashes), trimmed.count > hashes else { return false }
        let markerEnd = trimmed.index(trimmed.startIndex, offsetBy: hashes)
        return trimmed[markerEnd] == " "
    }
}
