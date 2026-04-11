import SwiftUI
import AppKit

/// NSTextView wrapper — monospaced editor using JetBrains Mono.
struct MarkdownTextEditor: NSViewRepresentable {
    @Binding var text: String
    @AppStorage(EditorStyleSettings.fontFamilyKey) private var fontFamily: String = EditorStyleSettings.defaultFontFamily
    @AppStorage(EditorStyleSettings.fontSizeKey) private var fontSize: Double = EditorStyleSettings.defaultFontSize

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

        applyEditorStyle(to: textView, coordinator: context.coordinator)

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let textView = scrollView.documentView as! NSTextView
        applyEditorStyle(to: textView, coordinator: context.coordinator)
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
        var currentFontToken = ""

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

    private func applyEditorStyle(to textView: NSTextView, coordinator: Coordinator) {
        let font = editorFont()
        let styleTokens = MarkdownStyleTokens(baseFont: font)
        let fontToken = "\(font.fontName)-\(font.pointSize)"
        let needsRebuild = coordinator.currentFontToken != fontToken || coordinator.highlighter == nil

        textView.font = font
        textView.typingAttributes = [
            .font: font,
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: styleTokens.paragraphStyle
        ]

        if needsRebuild {
            let highlighter = MarkdownSyntaxHighlighter(baseFont: font)
            coordinator.highlighter = highlighter
            textView.textStorage?.delegate = highlighter
            coordinator.currentFontToken = fontToken
        }

        if let storage = textView.textStorage {
            coordinator.highlighter?.highlight(storage)
        }
    }

    private func editorFont() -> NSFont {
        let clampedSize = max(EditorStyleSettings.minFontSize, min(EditorStyleSettings.maxFontSize, fontSize))
        let size = CGFloat(clampedSize)

        return NSFont(name: fontFamily, size: size)
            ?? NSFont(name: "JetBrains Mono", size: size)
            ?? NSFont(name: "JetBrainsMono-Regular", size: size)
            ?? NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }
}
