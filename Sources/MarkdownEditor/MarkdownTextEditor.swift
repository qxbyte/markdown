import SwiftUI
import AppKit

/// NSTextView wrapper — monospaced editor using JetBrains Mono.
struct MarkdownTextEditor: NSViewRepresentable {
    @Binding var text: String

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        let textView   = scrollView.documentView as! NSTextView

        textView.delegate                            = context.coordinator
        textView.isRichText                          = false
        textView.allowsUndo                          = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled  = false
        textView.isAutomaticTextReplacementEnabled   = false
        textView.isGrammarCheckingEnabled            = false
        textView.isContinuousSpellCheckingEnabled    = false
        textView.textContainerInset                  = NSSize(width: 20, height: 20)
        textView.font    = editorFont()
        textView.textColor          = NSColor.labelColor
        textView.backgroundColor    = NSColor.textBackgroundColor
        textView.insertionPointColor = NSColor.controlAccentColor

        // Line wrapping
        textView.isHorizontallyResizable              = false
        textView.textContainer?.widthTracksTextView   = true
        textView.textContainer?.containerSize         = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)

        scrollView.hasVerticalScroller   = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers    = true
        scrollView.backgroundColor       = NSColor.textBackgroundColor

        let font = editorFont()
        textView.typingAttributes = [
            .font: font,
            .foregroundColor: NSColor.labelColor
        ]

        let highlighter = MarkdownSyntaxHighlighter(baseFont: font)
        context.coordinator.highlighter = highlighter
        textView.textStorage?.delegate = highlighter
        if let storage = textView.textStorage {
            highlighter.highlight(storage)
        }

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let textView = scrollView.documentView as! NSTextView
        guard textView.string != text else { return }
        // 设置 isUpdating 防止 textView.string = text 触发 textDidChange 反写 document
        context.coordinator.isUpdating = true
        let selected = textView.selectedRanges
        textView.string = text
        textView.selectedRanges = selected
        if let storage = textView.textStorage {
            context.coordinator.highlighter?.highlight(storage)
        }
        context.coordinator.isUpdating = false
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MarkdownTextEditor
        var isUpdating = false
        var highlighter: MarkdownSyntaxHighlighter?

        init(_ parent: MarkdownTextEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard !isUpdating, let tv = notification.object as? NSTextView else { return }
            if let storage = tv.textStorage {
                highlighter?.highlight(storage)
            }
            parent.text = tv.string
        }
    }

    // MARK: - Helpers

    private func editorFont() -> NSFont {
        let size: CGFloat = 14
        return NSFont(name: "JetBrains Mono", size: size)
            ?? NSFont(name: "JetBrainsMono-Regular", size: size)
            ?? NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }
}
