import AppKit

final class LineNumberRulerView: NSRulerView {
    weak var textView: NSTextView?
    var lineNumberFont: NSFont = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)

    private let rightPadding: CGFloat = 8

    init(scrollView: NSScrollView, textView: NSTextView) {
        super.init(scrollView: scrollView, orientation: .verticalRuler)
        self.textView = textView
        clientView = textView
        ruleThickness = 36
    }

    required init(coder: NSCoder) { fatalError() }

    func update() {
        let needed = computeThickness()
        if abs(ruleThickness - needed) > 0.5 {
            ruleThickness = needed
        }
        needsDisplay = true
    }

    private func computeThickness() -> CGFloat {
        let digits = "\(lineCount)".count
        let sampleAttrs: [NSAttributedString.Key: Any] = [.font: lineNumberFont]
        let digitWidth = ("0" as NSString).size(withAttributes: sampleAttrs).width
        return max(36, CGFloat(digits) * digitWidth + rightPadding + 10)
    }

    private var lineCount: Int {
        guard let text = textView?.string else { return 1 }
        return max(1, text.components(separatedBy: "\n").count)
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let textView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer,
              let scrollView else { return }

        NSColor.textBackgroundColor.setFill()
        rect.fill()

        NSColor.separatorColor.withAlphaComponent(0.4).setFill()
        NSRect(x: bounds.maxX - 0.5, y: rect.minY, width: 0.5, height: rect.height).fill()

        let string = textView.string as NSString
        let visibleRect = scrollView.contentView.bounds
        let insetY = textView.textContainerInset.height
        let insetX = textView.textContainerInset.width
        let thickness = ruleThickness

        let attrs: [NSAttributedString.Key: Any] = [
            .font: lineNumberFont,
            .foregroundColor: NSColor.tertiaryLabelColor
        ]

        if string.length == 0 {
            let label = "1" as NSString
            let size = label.size(withAttributes: attrs)
            label.draw(
                at: NSPoint(x: thickness - size.width - rightPadding, y: insetY + (layoutManager.defaultLineHeight(for: lineNumberFont) - size.height) / 2),
                withAttributes: attrs
            )
            return
        }

        // scrollView.contentView.bounds is in textView coordinates; glyphRange(forBoundingRect:in:)
        // expects text container coordinates, which are offset by textContainerInset.
        let containerRect = NSRect(
            x: visibleRect.minX - insetX,
            y: visibleRect.minY - insetY,
            width: visibleRect.width,
            height: visibleRect.height
        )
        let glyphRange = layoutManager.glyphRange(forBoundingRect: containerRect, in: textContainer)
        guard glyphRange.length > 0 else { return }

        let firstCharIndex = layoutManager.characterIndexForGlyph(at: glyphRange.location)
        var lineNumber = 1
        if firstCharIndex > 0 {
            string.enumerateSubstrings(
                in: NSRange(location: 0, length: firstCharIndex),
                options: .byLines
            ) { _, _, _, _ in lineNumber += 1 }
        }

        layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) { fragRect, _, _, fragGlyphRange, _ in
            let charIndex = layoutManager.characterIndexForGlyph(at: fragGlyphRange.location)
            let isHardStart = charIndex == 0 || string.character(at: charIndex - 1) == 10

            if isHardStart {
                let label = "\(lineNumber)" as NSString
                let size = label.size(withAttributes: attrs)
                let x = thickness - size.width - self.rightPadding
                let y = fragRect.minY + insetY + (fragRect.height - size.height) / 2
                label.draw(at: NSPoint(x: x, y: y), withAttributes: attrs)
                lineNumber += 1
            }
        }
    }
}
