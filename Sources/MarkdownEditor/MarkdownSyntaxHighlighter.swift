import AppKit

/// 对 NSTextView 的 NSTextStorage 进行 Markdown 语法高亮。
/// 作为 NSTextStorageDelegate 挂载，每次字符变化后自动触发。
final class MarkdownSyntaxHighlighter: NSObject, NSTextStorageDelegate {

    private let tokens: MarkdownStyleTokens

    init(baseFont: NSFont) {
        self.tokens = MarkdownStyleTokens(baseFont: baseFont)
        super.init()
    }

    func textStorage(_ textStorage: NSTextStorage,
                     didProcessEditing editedMask: NSTextStorageEditActions,
                     range editedRange: NSRange,
                     changeInLength delta: Int) {
        guard editedMask.contains(.editedCharacters) else { return }
        highlight(textStorage)
    }

    func highlight(_ storage: NSTextStorage) {
        let text = storage.string
        guard !text.isEmpty else { return }

        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)

        resetBaseStyle(in: storage, range: fullRange)

        // 记录代码范围，后续 inline 规则跳过
        var excluded = IndexSet()

        highlightFencedCode(in: storage, text: text, nsText: nsText, range: fullRange, excluded: &excluded)
        highlightHeaders(in: storage, text: text, nsText: nsText, range: fullRange)
        highlightBlockquotes(in: storage, text: text, range: fullRange)
        highlightListMarkers(in: storage, text: text, range: fullRange)
        highlightHorizontalRules(in: storage, text: text, range: fullRange)

        highlightInlineCode(in: storage, text: text, nsText: nsText, range: fullRange, excluded: &excluded)
        highlightLinks(in: storage, text: text, range: fullRange, excluded: excluded)
        highlightTextEmphasis(in: storage, text: text, range: fullRange, excluded: excluded)
        highlightStrikethrough(in: storage, text: text, range: fullRange, excluded: excluded)
    }

    private func resetBaseStyle(in storage: NSTextStorage, range: NSRange) {
        storage.addAttribute(.font, value: tokens.bodyFont, range: range)
        storage.addAttribute(.foregroundColor, value: tokens.textColor, range: range)
        storage.addAttribute(.paragraphStyle, value: tokens.paragraphStyle, range: range)
        storage.removeAttribute(.backgroundColor, range: range)
        storage.removeAttribute(.strikethroughStyle, range: range)
        storage.removeAttribute(.underlineStyle, range: range)
    }

    private func highlightFencedCode(in storage: NSTextStorage,
                                     text: String,
                                     nsText: NSString,
                                     range: NSRange,
                                     excluded: inout IndexSet) {
        Patterns.fencedCode.enumerateMatches(in: text, range: range) { match, _, _ in
            guard let match = match else { return }
            let blockRange = match.range(at: 0)
            guard blockRange.length > 0 else { return }

            storage.addAttribute(.font, value: self.tokens.codeFont, range: blockRange)
            storage.addAttribute(.foregroundColor, value: self.tokens.stringTextColor, range: blockRange)

            let openMarkerRange = match.range(at: 1)
            if openMarkerRange.location != NSNotFound {
                storage.addAttribute(.foregroundColor, value: self.tokens.keywordMarkerColor, range: openMarkerRange)
            }

            let languageRange = match.range(at: 2)
            if languageRange.location != NSNotFound, languageRange.length > 0 {
                let languageText = nsText.substring(with: languageRange)
                let trimmed = languageText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty,
                   let tokenRange = languageTokenRange(in: nsText, original: languageRange, token: trimmed) {
                    storage.addAttribute(.foregroundColor, value: self.tokens.codeFenceLanguageColor, range: tokenRange)
                }
            }

            if let closeMarkerRange = closingFenceMarkerRange(in: nsText, blockRange: blockRange) {
                storage.addAttribute(.foregroundColor, value: self.tokens.keywordMarkerColor, range: closeMarkerRange)
            }

            excluded.insert(integersIn: blockRange.location ..< blockRange.location + blockRange.length)
        }
    }

    private func highlightHeaders(in storage: NSTextStorage, text: String, nsText: NSString, range: NSRange) {
        Patterns.header.enumerateMatches(in: text, range: range) { match, _, _ in
            guard let match = match, match.numberOfRanges >= 3 else { return }
            let markerRange = match.range(at: 1)
            let textRange = match.range(at: 2)

            storage.addAttribute(.foregroundColor, value: self.tokens.keywordMarkerColor, range: markerRange)
            if textRange.location != NSNotFound, textRange.length > 0 {
                let level = nsText.substring(with: markerRange).count
                storage.addAttribute(.foregroundColor, value: self.tokens.headerColor(level: level), range: textRange)
                storage.addAttribute(.font, value: self.tokens.boldFont, range: textRange)
            }
        }
    }

    private func highlightBlockquotes(in storage: NSTextStorage, text: String, range: NSRange) {
        Patterns.blockquote.enumerateMatches(in: text, range: range) { match, _, _ in
            guard let match = match else { return }
            let markerRange = match.range(at: 1)
            let textRange = match.range(at: 2)
            if markerRange.location != NSNotFound, markerRange.length > 0 {
                storage.addAttribute(.foregroundColor, value: self.tokens.keywordMarkerColor, range: markerRange)
            }
            if textRange.location != NSNotFound, textRange.length > 0 {
                storage.addAttribute(.foregroundColor, value: self.tokens.stringTextColor, range: textRange)
            }
        }
    }

    private func highlightListMarkers(in storage: NSTextStorage, text: String, range: NSRange) {
        Patterns.listMarker.enumerateMatches(in: text, range: range) { match, _, _ in
            guard let markerRange = match?.range(at: 1), markerRange.location != NSNotFound else { return }
            storage.addAttribute(.foregroundColor, value: self.tokens.keywordMarkerColor, range: markerRange)
        }
    }

    private func highlightHorizontalRules(in storage: NSTextStorage, text: String, range: NSRange) {
        Patterns.hrule.enumerateMatches(in: text, range: range) { match, _, _ in
            guard let markerRange = match?.range(at: 1), markerRange.location != NSNotFound else { return }
            storage.addAttribute(.foregroundColor, value: self.tokens.keywordMarkerColor, range: markerRange)
        }
    }

    private func highlightInlineCode(in storage: NSTextStorage,
                                     text: String,
                                     nsText: NSString,
                                     range: NSRange,
                                     excluded: inout IndexSet) {
        Patterns.inlineCode.enumerateMatches(in: text, range: range) { match, _, _ in
            guard let match = match else { return }
            let codeRange = match.range(at: 0)
            guard codeRange.length > 0, !excluded.intersects(integersIn: codeRange.location ..< codeRange.location + codeRange.length) else {
                return
            }

            storage.addAttribute(.font, value: self.tokens.codeFont, range: codeRange)
            storage.addAttribute(.foregroundColor, value: self.tokens.stringTextColor, range: codeRange)

            let markerLength = leadingBacktickCount(in: nsText, range: codeRange)
            if markerLength > 0, codeRange.length >= markerLength * 2 {
                let openMarkerRange = NSRange(location: codeRange.location, length: markerLength)
                let closeMarkerRange = NSRange(location: codeRange.location + codeRange.length - markerLength, length: markerLength)
                storage.addAttribute(.foregroundColor, value: self.tokens.keywordMarkerColor, range: openMarkerRange)
                storage.addAttribute(.foregroundColor, value: self.tokens.keywordMarkerColor, range: closeMarkerRange)
            }

            excluded.insert(integersIn: codeRange.location ..< codeRange.location + codeRange.length)
        }
    }

    private func highlightLinks(in storage: NSTextStorage, text: String, range: NSRange, excluded: IndexSet) {
        Patterns.autoLink.enumerateMatches(in: text, range: range) { match, _, _ in
            guard let match = match else { return }
            let linkRange = match.range(at: 0)
            guard !excluded.intersects(integersIn: linkRange.location ..< linkRange.location + linkRange.length) else { return }
            storage.addAttribute(.foregroundColor, value: self.tokens.hyperlinkTextColor, range: linkRange)
        }

        Patterns.inlineLink.enumerateMatches(in: text, range: range) { match, _, _ in
            guard let match = match else { return }
            let linkRange = match.range(at: 0)
            guard !excluded.intersects(integersIn: linkRange.location ..< linkRange.location + linkRange.length) else { return }

            let linkTextRange = match.range(at: 1)
            let destinationRange = match.range(at: 2)
            let titleRange = match.range(at: 3)

            if linkTextRange.location != NSNotFound {
                storage.addAttribute(.foregroundColor, value: self.tokens.hyperlinkTextColor, range: linkTextRange)
            }
            if destinationRange.location != NSNotFound {
                storage.addAttribute(.foregroundColor, value: self.tokens.linkDestinationColor, range: destinationRange)
            }
            if titleRange.location != NSNotFound {
                storage.addAttribute(.foregroundColor, value: self.tokens.linkTitleColor, range: titleRange)
            }
        }

        Patterns.referenceLink.enumerateMatches(in: text, range: range) { match, _, _ in
            guard let match = match else { return }
            let linkRange = match.range(at: 0)
            guard !excluded.intersects(integersIn: linkRange.location ..< linkRange.location + linkRange.length) else { return }

            let textRange = match.range(at: 1)
            let labelRange = match.range(at: 2)
            if textRange.location != NSNotFound {
                storage.addAttribute(.foregroundColor, value: self.tokens.hyperlinkTextColor, range: textRange)
            }
            if labelRange.location != NSNotFound {
                storage.addAttribute(.foregroundColor, value: self.tokens.linkLabelColor, range: labelRange)
            }
        }

        Patterns.linkDefinition.enumerateMatches(in: text, range: range) { match, _, _ in
            guard let match = match else { return }
            let definitionRange = match.range(at: 0)
            guard !excluded.intersects(integersIn: definitionRange.location ..< definitionRange.location + definitionRange.length) else { return }

            let labelRange = match.range(at: 1)
            let separatorRange = match.range(at: 2)
            let destinationRange = match.range(at: 3)
            let titleRange = match.range(at: 4)

            if labelRange.location != NSNotFound {
                storage.addAttribute(.foregroundColor, value: self.tokens.linkLabelColor, range: labelRange)
            }
            if separatorRange.location != NSNotFound {
                storage.addAttribute(.foregroundColor, value: self.tokens.keywordMarkerColor, range: separatorRange)
            }
            if destinationRange.location != NSNotFound {
                storage.addAttribute(.foregroundColor, value: self.tokens.linkDestinationColor, range: destinationRange)
            }
            if titleRange.location != NSNotFound {
                storage.addAttribute(.foregroundColor, value: self.tokens.linkTitleColor, range: titleRange)
            }
        }
    }

    private func highlightTextEmphasis(in storage: NSTextStorage, text: String, range: NSRange, excluded: IndexSet) {
        Patterns.boldItalic.enumerateMatches(in: text, range: range) { match, _, _ in
            guard let highlightRange = match?.range, highlightRange.length > 0 else { return }
            guard !excluded.intersects(integersIn: highlightRange.location ..< highlightRange.location + highlightRange.length) else { return }
            storage.addAttribute(.font, value: self.tokens.boldItalicFont, range: highlightRange)
        }

        Patterns.bold.enumerateMatches(in: text, range: range) { match, _, _ in
            guard let highlightRange = match?.range, highlightRange.length > 0 else { return }
            guard !excluded.intersects(integersIn: highlightRange.location ..< highlightRange.location + highlightRange.length) else { return }
            storage.addAttribute(.font, value: self.tokens.boldFont, range: highlightRange)
        }

        Patterns.italic.enumerateMatches(in: text, range: range) { match, _, _ in
            guard let highlightRange = match?.range, highlightRange.length > 0 else { return }
            guard !excluded.intersects(integersIn: highlightRange.location ..< highlightRange.location + highlightRange.length) else { return }
            storage.addAttribute(.font, value: self.tokens.italicFont, range: highlightRange)
        }
    }

    private func highlightStrikethrough(in storage: NSTextStorage, text: String, range: NSRange, excluded: IndexSet) {
        Patterns.strikethrough.enumerateMatches(in: text, range: range) { match, _, _ in
            guard let highlightRange = match?.range, highlightRange.length > 0 else { return }
            guard !excluded.intersects(integersIn: highlightRange.location ..< highlightRange.location + highlightRange.length) else { return }
            storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: highlightRange)
            storage.addAttribute(.foregroundColor, value: self.tokens.mutedTextColor, range: highlightRange)
        }
    }

    private func languageTokenRange(in nsText: NSString, original: NSRange, token: String) -> NSRange? {
        let source = nsText.substring(with: original) as NSString
        let tokenRange = source.range(of: token)
        guard tokenRange.location != NSNotFound else { return nil }
        return NSRange(location: original.location + tokenRange.location, length: tokenRange.length)
    }

    private func closingFenceMarkerRange(in nsText: NSString, blockRange: NSRange) -> NSRange? {
        let blockText = nsText.substring(with: blockRange) as NSString
        let searchRange = NSRange(location: 0, length: blockText.length)
        let lastNewline = blockText.range(of: "\n", options: .backwards, range: searchRange)
        guard lastNewline.location != NSNotFound else { return nil }
        let closingLineLocation = lastNewline.location + 1
        guard closingLineLocation < blockText.length else { return nil }
        let closingLineLength = blockText.length - closingLineLocation
        let closingLineRange = NSRange(location: closingLineLocation, length: closingLineLength)
        let closingLine = blockText.substring(with: closingLineRange)
        let markerRangeInLine = (closingLine as NSString).range(of: #"`{3,}|~{3,}"#, options: .regularExpression)
        guard markerRangeInLine.location != NSNotFound else { return nil }
        return NSRange(
            location: blockRange.location + closingLineLocation + markerRangeInLine.location,
            length: markerRangeInLine.length
        )
    }

    private func leadingBacktickCount(in nsText: NSString, range: NSRange) -> Int {
        guard range.length > 0 else { return 0 }
        var count = 0
        while count < range.length, nsText.character(at: range.location + count) == 96 {
            count += 1
        }
        return count
    }

    private enum Patterns {
        static let fencedCode = regex(#"(?m)^(`{3,}|~{3,})([^\n]*)\n([\s\S]*?)^\1[ \t]*$"#)
        static let header = regex(#"(?m)^(#{1,6})([ \t].+?)[ \t]*$"#)
        static let blockquote = regex(#"(?m)^([ \t]*>+)([ \t]?.*)$"#)
        static let listMarker = regex(#"(?m)^([ \t]{0,3}(?:[-+*]|\d+[.)]))(?=[ \t]+)"#)
        static let hrule = regex(#"(?m)^([ \t]*(?:---+|\*\*\*+|___+)[ \t]*)$"#)
        static let inlineCode = regex(#"(`+)([^`\n]+?)\1"#)
        static let boldItalic = regex(#"\*{3}[^*\n]+\*{3}|_{3}[^_\n]+_{3}"#)
        static let bold = regex(#"\*{2}[^*\n]+\*{2}|_{2}[^_\n]+_{2}"#)
        static let italic = regex(#"(?<!\*)\*[^*\n]+\*(?!\*)|(?<!_)_[^_\n]+_(?!_)"#)
        static let strikethrough = regex(#"~~[^~\n]+~~"#)

        static let autoLink = regex(#"<(?:https?|ftp)://[^>\n]+>"#)
        static let inlineLink = regex(#"\[([^\[\]\n]+)\]\(([^)\s\n]+)(?:\s+(\"[^\"]*\"|'[^']*'|\([^)]+\)))?\)"#)
        static let referenceLink = regex(#"\[([^\[\]\n]+)\]\[([^\[\]\n]*)\]"#)
        static let linkDefinition = regex(#"(?m)^(\[[^\[\]\n]+\])(:)([ \t]*<?[^>\s\n]+>?)(?:[ \t]+(\"[^\"]*\"|'[^']*'|\([^)]+\)))?[ \t]*$"#)

        private static func regex(_ pattern: String) -> NSRegularExpression {
            // swiftlint:disable:next force_try
            try! NSRegularExpression(pattern: pattern)
        }
    }
}
