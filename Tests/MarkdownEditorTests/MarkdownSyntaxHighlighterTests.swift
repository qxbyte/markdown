import XCTest
import AppKit
import SwiftCheck
import MarkdownEditorCore

// MARK: - Markdown 字符串生成器

extension Gen where A == String {
    /// 生成包含常见 Markdown 语法的随机字符串，最大长度为 maxLength。
    static func markdownString(maxLength: Int) -> Gen<String> {
        // 基础文本片段生成器
        let plainText = Gen<String>.fromElements(of: [
            "Hello world",
            "这是一段中文文本",
            "foo bar baz",
            "Swift programming",
            "1234567890",
            "test content here",
            "some text",
            ""
        ])

        // Markdown 语法片段生成器
        let markdownSnippets = Gen<String>.fromElements(of: [
            "# 标题一",
            "## 标题二",
            "### 标题三",
            "**加粗文本**",
            "*斜体文本*",
            "***加粗斜体***",
            "~~删除线~~",
            "`行内代码`",
            "```\ncode block\n```",
            "```swift\nlet x = 1\n```",
            "> 引用文本",
            "- 列表项一",
            "* 列表项二",
            "1. 有序列表",
            "[链接文本](https://example.com)",
            "![图片](image.png)",
            "---",
            "***",
            "| 列1 | 列2 |\n|-----|-----|\n| A   | B   |",
            "---\ntitle: test\n---",
            "<https://example.com>",
            "https://example.com/path",
            "[ref][label]\n[label]: https://example.com",
        ])

        // 随机选择 1~8 个片段拼接
        let count = Gen<Int>.choose((1, 8))
        return count.flatMap { n in
            sequence(Array(repeating: Gen.one(of: [plainText, markdownSnippets]), count: n))
                .map { parts in
                    let joined = parts.joined(separator: "\n")
                    // 截断到 maxLength（按 UTF-16 码元计，与 NSString 一致）
                    let nsStr = joined as NSString
                    if nsStr.length <= maxLength {
                        return joined
                    }
                    return nsStr.substring(to: maxLength)
                }
        }
    }
}

// MARK: - 属性测试：语法高亮不改变字符内容（属性 4）

/// **Validates: Requirements 6.2**
final class MarkdownSyntaxHighlighterTests: XCTestCase {

    // MARK: 属性测试

    /// 属性 4：语法高亮不改变字符内容
    ///
    /// 对任意 Markdown 文本，`highlight(_:)` 前后 `NSTextStorage.string` 应完全不变。
    ///
    /// **Validates: Requirements 6.2**
    func testHighlightDoesNotChangeStringContent() {
        // Feature: undo-redo-support, Property 4: 语法高亮不改变字符内容
        property("语法高亮不改变字符内容") <- forAll(
            Gen<String>.markdownString(maxLength: 500)
        ) { markdownText in
            let storage = NSTextStorage(string: markdownText)
            let highlighter = MarkdownSyntaxHighlighter(
                baseFont: .monospacedSystemFont(ofSize: 14, weight: .regular)
            )

            highlighter.highlight(storage)

            return storage.string == markdownText
        }
    }

    // MARK: 单元测试（具体示例验证）

    /// 空字符串：highlight 不崩溃，string 保持为空
    func testHighlightEmptyString() {
        let storage = NSTextStorage(string: "")
        let highlighter = MarkdownSyntaxHighlighter(
            baseFont: .monospacedSystemFont(ofSize: 14, weight: .regular)
        )
        highlighter.highlight(storage)
        XCTAssertEqual(storage.string, "")
    }

    /// 纯文本：highlight 不改变字符内容
    func testHighlightPlainText() {
        let text = "Hello, world! 这是普通文本。"
        let storage = NSTextStorage(string: text)
        let highlighter = MarkdownSyntaxHighlighter(
            baseFont: .monospacedSystemFont(ofSize: 14, weight: .regular)
        )
        highlighter.highlight(storage)
        XCTAssertEqual(storage.string, text)
    }

    /// 标题语法：highlight 不改变字符内容
    func testHighlightHeaders() {
        let text = "# 一级标题\n## 二级标题\n### 三级标题"
        let storage = NSTextStorage(string: text)
        let highlighter = MarkdownSyntaxHighlighter(
            baseFont: .monospacedSystemFont(ofSize: 14, weight: .regular)
        )
        highlighter.highlight(storage)
        XCTAssertEqual(storage.string, text)
    }

    /// 加粗/斜体语法：highlight 不改变字符内容
    func testHighlightEmphasis() {
        let text = "**加粗** *斜体* ***加粗斜体*** ~~删除线~~"
        let storage = NSTextStorage(string: text)
        let highlighter = MarkdownSyntaxHighlighter(
            baseFont: .monospacedSystemFont(ofSize: 14, weight: .regular)
        )
        highlighter.highlight(storage)
        XCTAssertEqual(storage.string, text)
    }

    /// 代码块语法：highlight 不改变字符内容
    func testHighlightFencedCode() {
        let text = "```swift\nlet x = 42\nprint(x)\n```"
        let storage = NSTextStorage(string: text)
        let highlighter = MarkdownSyntaxHighlighter(
            baseFont: .monospacedSystemFont(ofSize: 14, weight: .regular)
        )
        highlighter.highlight(storage)
        XCTAssertEqual(storage.string, text)
    }

    /// 链接语法：highlight 不改变字符内容
    func testHighlightLinks() {
        let text = "[链接](https://example.com) <https://auto.link> https://bare.url"
        let storage = NSTextStorage(string: text)
        let highlighter = MarkdownSyntaxHighlighter(
            baseFont: .monospacedSystemFont(ofSize: 14, weight: .regular)
        )
        highlighter.highlight(storage)
        XCTAssertEqual(storage.string, text)
    }

    /// 表格语法：highlight 不改变字符内容
    func testHighlightTable() {
        let text = "| 列1 | 列2 |\n|-----|-----|\n| A   | B   |"
        let storage = NSTextStorage(string: text)
        let highlighter = MarkdownSyntaxHighlighter(
            baseFont: .monospacedSystemFont(ofSize: 14, weight: .regular)
        )
        highlighter.highlight(storage)
        XCTAssertEqual(storage.string, text)
    }

    /// Front matter 语法：highlight 不改变字符内容
    func testHighlightFrontMatter() {
        let text = "---\ntitle: 测试文档\nauthor: 作者\n---\n\n正文内容"
        let storage = NSTextStorage(string: text)
        let highlighter = MarkdownSyntaxHighlighter(
            baseFont: .monospacedSystemFont(ofSize: 14, weight: .regular)
        )
        highlighter.highlight(storage)
        XCTAssertEqual(storage.string, text)
    }

    /// 混合复杂 Markdown：highlight 不改变字符内容
    func testHighlightComplexMarkdown() {
        let text = """
        # 文档标题

        这是一段包含 **加粗**、*斜体* 和 `行内代码` 的段落。

        ## 代码示例

        ```swift
        func hello() {
            print("Hello, World!")
        }
        ```

        > 这是一段引用文字

        - 列表项一
        - 列表项二
          - 嵌套列表

        [访问链接](https://example.com)

        | 名称 | 值 |
        |------|-----|
        | foo  | bar |

        ---
        """
        let storage = NSTextStorage(string: text)
        let highlighter = MarkdownSyntaxHighlighter(
            baseFont: .monospacedSystemFont(ofSize: 14, weight: .regular)
        )
        highlighter.highlight(storage)
        XCTAssertEqual(storage.string, text)
    }

    /// 多次调用 highlight：字符内容始终不变
    func testHighlightIdempotentOnStringContent() {
        let text = "# 标题\n\n**加粗** 和 *斜体*\n\n```\ncode\n```"
        let storage = NSTextStorage(string: text)
        let highlighter = MarkdownSyntaxHighlighter(
            baseFont: .monospacedSystemFont(ofSize: 14, weight: .regular)
        )
        // 连续调用三次
        highlighter.highlight(storage)
        highlighter.highlight(storage)
        highlighter.highlight(storage)
        XCTAssertEqual(storage.string, text)
    }
}
