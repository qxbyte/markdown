import AppKit

/// 对 NSTextView 的 NSTextStorage 进行 Markdown 语法高亮。
/// 作为 NSTextStorageDelegate 挂载，每次字符变化后自动触发。
final class MarkdownSyntaxHighlighter: NSObject, NSTextStorageDelegate {

    private let baseFont: NSFont
    private let boldFont: NSFont
    private let italicFont: NSFont
    private let boldItalicFont: NSFont
    private let codeFont: NSFont

    // MARK: - Init

    init(baseFont: NSFont) {
        self.baseFont = baseFont
        let size = baseFont.pointSize
        let fm = NSFontManager.shared
        self.boldFont      = fm.font(withFamily: baseFont.familyName ?? "", traits: .boldFontMask,   weight: 9, size: size) ?? baseFont
        self.italicFont    = fm.font(withFamily: baseFont.familyName ?? "", traits: .italicFontMask, weight: 5, size: size) ?? baseFont
        self.boldItalicFont = fm.font(withFamily: baseFont.familyName ?? "", traits: [.boldFontMask, .italicFontMask], weight: 9, size: size) ?? baseFont
        self.codeFont      = NSFont(name: "JetBrains Mono", size: size)
                          ?? NSFont(name: "JetBrainsMono-Regular", size: size)
                          ?? NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
        super.init()
    }

    // MARK: - NSTextStorageDelegate

    func textStorage(_ textStorage: NSTextStorage,
                     didProcessEditing editedMask: NSTextStorageEditActions,
                     range editedRange: NSRange,
                     changeInLength delta: Int) {
        guard editedMask.contains(.editedCharacters) else { return }
        highlight(textStorage)
    }

    // MARK: - Core Highlight

    func highlight(_ storage: NSTextStorage) {
        let str     = storage.string
        guard !str.isEmpty else { return }
        let nsStr   = str as NSString
        let full    = NSRange(location: 0, length: nsStr.length)

        // ── 1. 重置为基础样式 ──────────────────────────────────────────────────
        storage.addAttribute(.font,             value: baseFont,           range: full)
        storage.addAttribute(.foregroundColor,  value: NSColor.labelColor, range: full)
        storage.removeAttribute(.backgroundColor,  range: full)
        storage.removeAttribute(.strikethroughStyle, range: full)
        storage.removeAttribute(.underlineStyle,  range: full)

        // 记录代码区域，跳过 inline 规则
        var excluded = IndexSet()

        // ── 2. 围栏代码块 ``` ~~~ ────────────────────────────────────────────
        Patterns.fencedCode.enumerateMatches(in: str, range: full) { m, _, _ in
            guard let r = m?.range, r.length > 0 else { return }
            storage.addAttribute(.backgroundColor, value: Colors.codeBlockBg, range: r)
            storage.addAttribute(.font,            value: self.codeFont,      range: r)
            excluded.insert(integersIn: r.location ..< r.location + r.length)
        }

        // ── 3. 标题 ──────────────────────────────────────────────────────────
        Patterns.header.enumerateMatches(in: str, range: full) { m, _, _ in
            guard let match = m, match.numberOfRanges >= 3 else { return }
            let hashR = match.range(at: 1)
            let textR = match.range(at: 2)
            storage.addAttribute(.foregroundColor, value: Colors.headerMarker, range: hashR)
            if textR.location != NSNotFound, textR.length > 0 {
                let level = nsStr.substring(with: hashR).count
                storage.addAttribute(.foregroundColor, value: Colors.header(level: level), range: textR)
                storage.addAttribute(.font,            value: self.boldFont,               range: textR)
            }
        }

        // ── 4. 引用块 > ───────────────────────────────────────────────────────
        Patterns.blockquote.enumerateMatches(in: str, range: full) { m, _, _ in
            guard let r = m?.range else { return }
            storage.addAttribute(.foregroundColor, value: Colors.muted, range: r)
        }

        // ── 5. 水平分隔线 ─────────────────────────────────────────────────────
        Patterns.hr.enumerateMatches(in: str, range: full) { m, _, _ in
            guard let r = m?.range else { return }
            storage.addAttribute(.foregroundColor, value: Colors.muted, range: r)
        }

        // ── 6. Inline 规则（跳过代码块内部）─────────────────────────────────

        // 行内代码 `code`
        Patterns.inlineCode.enumerateMatches(in: str, range: full) { m, _, _ in
            guard let r = m?.range, r.length > 0,
                  !excluded.intersects(integersIn: r.location ..< r.location + r.length) else { return }
            storage.addAttribute(.backgroundColor, value: Colors.inlineCodeBg, range: r)
            storage.addAttribute(.font,            value: self.codeFont,       range: r)
            excluded.insert(integersIn: r.location ..< r.location + r.length)
        }

        // 粗斜体 ***
        Patterns.boldItalic.enumerateMatches(in: str, range: full) { m, _, _ in
            guard let r = m?.range, r.length > 0,
                  !excluded.intersects(integersIn: r.location ..< r.location + r.length) else { return }
            storage.addAttribute(.font, value: self.boldItalicFont, range: r)
        }

        // 粗体 **
        Patterns.bold.enumerateMatches(in: str, range: full) { m, _, _ in
            guard let r = m?.range, r.length > 0,
                  !excluded.intersects(integersIn: r.location ..< r.location + r.length) else { return }
            storage.addAttribute(.font, value: self.boldFont, range: r)
        }

        // 斜体 *
        Patterns.italic.enumerateMatches(in: str, range: full) { m, _, _ in
            guard let r = m?.range, r.length > 0,
                  !excluded.intersects(integersIn: r.location ..< r.location + r.length) else { return }
            storage.addAttribute(.font, value: self.italicFont, range: r)
        }

        // 链接 [text](url)
        Patterns.link.enumerateMatches(in: str, range: full) { m, _, _ in
            guard let r = m?.range, r.length > 0,
                  !excluded.intersects(integersIn: r.location ..< r.location + r.length) else { return }
            storage.addAttribute(.foregroundColor, value: Colors.link, range: r)
        }

        // 删除线 ~~text~~
        Patterns.strikethrough.enumerateMatches(in: str, range: full) { m, _, _ in
            guard let r = m?.range, r.length > 0,
                  !excluded.intersects(integersIn: r.location ..< r.location + r.length) else { return }
            storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: r)
            storage.addAttribute(.foregroundColor,    value: Colors.muted, range: r)
        }
    }

    // MARK: - Colors

    private enum Colors {
        static let headerMarker = dynamic(
            light: NSColor(red: 0.60, green: 0.60, blue: 0.60, alpha: 1),
            dark:  NSColor(red: 0.50, green: 0.50, blue: 0.50, alpha: 1)
        )
        static func header(level: Int) -> NSColor {
            switch level {
            case 1: return dynamic(
                light: NSColor(red: 0.00, green: 0.39, blue: 0.48, alpha: 1), // #00627A
                dark:  NSColor(red: 0.31, green: 0.79, blue: 0.69, alpha: 1)  // #4EC9B0
            )
            case 2: return dynamic(
                light: NSColor(red: 0.00, green: 0.39, blue: 0.48, alpha: 1),
                dark:  NSColor(red: 0.31, green: 0.79, blue: 0.69, alpha: 1)
            )
            case 3: return dynamic(
                light: NSColor(red: 0.10, green: 0.45, blue: 0.55, alpha: 1),
                dark:  NSColor(red: 0.40, green: 0.80, blue: 0.72, alpha: 1)
            )
            default: return dynamic(
                light: NSColor(red: 0.10, green: 0.45, blue: 0.55, alpha: 1),
                dark:  NSColor(red: 0.40, green: 0.80, blue: 0.72, alpha: 1)
            )
            }
        }
        static let codeBlockBg = dynamic(
            light: NSColor(red: 0.95, green: 0.98, blue: 0.95, alpha: 1), // 浅绿背景
            dark:  NSColor(red: 0.17, green: 0.20, blue: 0.17, alpha: 1)
        )
        static let inlineCodeBg = dynamic(
            light: NSColor(red: 0.93, green: 0.95, blue: 0.93, alpha: 1),
            dark:  NSColor(red: 0.20, green: 0.23, blue: 0.20, alpha: 1)
        )
        static let muted = dynamic(
            light: NSColor(red: 0.55, green: 0.55, blue: 0.55, alpha: 1),
            dark:  NSColor(red: 0.50, green: 0.50, blue: 0.50, alpha: 1)
        )
        static let link = dynamic(
            light: NSColor(red: 0.02, green: 0.40, blue: 0.84, alpha: 1), // #066AD7
            dark:  NSColor(red: 0.47, green: 0.62, blue: 0.86, alpha: 1)  // #789EDB
        )

        private static func dynamic(light: NSColor, dark: NSColor) -> NSColor {
            NSColor(name: nil) { appearance in
                let dark_names: [NSAppearance.Name] = [
                    .darkAqua, .vibrantDark,
                    .accessibilityHighContrastDarkAqua,
                    .accessibilityHighContrastVibrantDark
                ]
                return dark_names.contains(appearance.name) ? dark : light
            }
        }
    }

    // MARK: - Compiled Patterns (static — compiled once)

    private enum Patterns {
        // 围栏代码块：```lang\n...\n``` 或 ~~~\n...\n~~~
        static let fencedCode = regex(#"(?m)^(`{3,}|~{3,})[^\n]*\n[\s\S]*?^\1[ \t]*$"#)
        // 标题：# 到 ######
        static let header     = regex(#"(?m)^(#{1,6})([ \t].+?)[ \t]*$"#)
        // 引用块
        static let blockquote = regex(#"(?m)^>[ \t].*$"#)
        // 水平分隔线
        static let hr         = regex(#"(?m)^(---+|\*\*\*+|___+)[ \t]*$"#)
        // 行内代码
        static let inlineCode = regex(#"`[^`\n]+`"#)
        // 粗斜体 ***
        static let boldItalic = regex(#"\*{3}[^*\n]+\*{3}|_{3}[^_\n]+_{3}"#)
        // 粗体 **
        static let bold       = regex(#"\*{2}[^*\n]+\*{2}|_{2}[^_\n]+_{2}"#)
        // 斜体 *（不匹配 **）
        static let italic     = regex(#"(?<!\*)\*[^*\n]+\*(?!\*)|(?<!_)_[^_\n]+_(?!_)"#)
        // 链接
        static let link       = regex(#"\[[^\[\]]+\]\([^()]+\)"#)
        // 删除线
        static let strikethrough = regex(#"~~[^~\n]+~~"#)

        private static func regex(_ pattern: String) -> NSRegularExpression {
            // swiftlint:disable:next force_try
            try! NSRegularExpression(pattern: pattern)
        }
    }
}
