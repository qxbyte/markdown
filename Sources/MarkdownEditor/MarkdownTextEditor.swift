import SwiftUI
import AppKit
import MarkdownEditorCore
import UniformTypeIdentifiers

/// NSTextView wrapper — monospaced editor using JetBrains Mono.
struct MarkdownTextEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var scrollRatio: Double
    @Binding var scrollTarget: MarkdownScrollTarget?
    let documentURL: URL?
    @AppStorage(EditorStyleSettings.fontFamilyKey) private var fontFamily: String = EditorStyleSettings.defaultFontFamily
    @AppStorage(EditorStyleSettings.fontSizeKey) private var fontSize: Double = EditorStyleSettings.defaultFontSize
    @AppStorage(EditorStyleSettings.showLineNumbersKey) private var showLineNumbers: Bool = false

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = FileDropTextView(frame: .zero)

        textView.delegate                            = context.coordinator
        textView.isRichText                          = false
        textView.allowsUndo                          = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled  = false
        textView.isAutomaticTextReplacementEnabled   = false
        textView.isGrammarCheckingEnabled            = false
        textView.isContinuousSpellCheckingEnabled    = false
        textView.isAutomaticLinkDetectionEnabled     = false
        textView.linkTextAttributes = [
            .underlineStyle: NSUnderlineStyle.single.rawValue
        ]
        textView.textContainerInset                  = NSSize(width: 20, height: 20)
        textView.textColor           = NSColor.labelColor
        textView.backgroundColor     = NSColor.textBackgroundColor
        textView.insertionPointColor = NSColor.controlAccentColor

        // Line wrapping
        textView.isVerticallyResizable                = true
        textView.isHorizontallyResizable              = false
        textView.autoresizingMask                     = [.width]
        textView.textContainer?.widthTracksTextView   = true
        textView.textContainer?.containerSize         = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)

        // Wire up image drop / paste callbacks
        textView.onImagesDrop = { [weak coordinator = context.coordinator] urls in
            coordinator?.insertImageMarkdown(urls: urls)
        }
        textView.onFilesDrop = { [weak coordinator = context.coordinator] urls in
            coordinator?.insertFileLinks(urls: urls)
        }
        textView.onImagePaste = { [weak coordinator = context.coordinator] in
            guard let c = coordinator, let tv = c.textView else { return false }
            return c.handleImagePaste(in: tv)
        }

        let scrollView = NSScrollView()
        scrollView.documentView          = textView
        scrollView.hasVerticalScroller   = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers    = true
        scrollView.backgroundColor       = NSColor.textBackgroundColor

        let rulerView = LineNumberRulerView(scrollView: scrollView, textView: textView)
        scrollView.hasVerticalRuler = true
        scrollView.hasHorizontalRuler = false
        scrollView.verticalRulerView = rulerView
        scrollView.rulersVisible = showLineNumbers

        applyEditorStyle(to: textView, coordinator: context.coordinator)

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let textView = scrollView.documentView as! NSTextView
        context.coordinator.parent = self
        applyEditorStyle(to: textView, coordinator: context.coordinator)

        if let rulerView = scrollView.verticalRulerView as? LineNumberRulerView {
            rulerView.lineNumberFont = lineNumberFont()
            let wasVisible = scrollView.rulersVisible
            scrollView.rulersVisible = showLineNumbers
            rulerView.update()
            if wasVisible != showLineNumbers {
                // When rulersVisible changes, the scroll view re-tiles and the
                // clip view shrinks/grows. The text view (documentView) follows
                // via autoresizingMask = .width, and widthTracksTextView keeps
                // the text container in sync — but NSLayoutManager is not
                // automatically told that the container's effective width
                // changed, so cached glyph layout from the old width is reused
                // and the editor goes blank (no glyphs in the new visible area).
                //
                // The documented fix is textContainerChangedGeometry(_:): it
                // invalidates the cached layout and re-flows against the
                // current container geometry. Run it on the next runloop tick
                // so AppKit's tile + autoresizing has fully settled first;
                // running it inline would re-flow against the still-stale
                // container width.
                DispatchQueue.main.async { [weak scrollView, weak rulerView] in
                    guard let scrollView,
                          let tv = scrollView.documentView as? NSTextView,
                          let lm = tv.layoutManager,
                          let tc = tv.textContainer else { return }
                    lm.textContainerChangedGeometry(tc)
                    tv.needsDisplay = true
                    rulerView?.update()
                }
            }
        }

        guard !textView.hasMarkedText() else { return }
        guard textView.string != text else {
            context.coordinator.applyScrollTargetIfNeeded(scrollView)
            return
        }
        // 设置 isUpdating 防止 textView.string = text 触发 textDidChange 反写 document
        context.coordinator.isUpdating = true
        let selected = textView.selectedRanges
        textView.string = text
        textView.selectedRanges = selected
        if let storage = textView.textStorage {
            context.coordinator.highlighter?.highlight(storage)
        }
        // Flush any pending frame propagation (e.g. on first render with line numbers
        // enabled, the ruler reserves 36pt of width that hasn't reached the text view
        // yet) so widthTracksTextView resolves the real container width before layout.
        // Without this, ensureLayout below would lay glyphs into a zero-width container
        // and the editor would appear blank until the user interacts with it.
        scrollView.layoutSubtreeIfNeeded()
        if let lm = textView.layoutManager, let tc = textView.textContainer {
            lm.ensureLayout(for: tc)
            textView.setNeedsDisplay(textView.visibleRect)
        }
        context.coordinator.isUpdating = false
        context.coordinator.applyScrollTargetIfNeeded(scrollView)
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MarkdownTextEditor
        var isUpdating = false
        var highlighter: MarkdownSyntaxHighlighter?
        var currentFontToken = ""
        weak var textView: NSTextView?
        private var lastAppliedScrollTargetID: UUID?
        private var highlightedLineRange: NSRange?

        private var selectionPopover: NSPopover?
        private var selectionPopoverController: SelectionToolbarViewController?
        private var pendingPopoverWorkItem: DispatchWorkItem?
        private var keyMonitor: Any?
        private weak var observedClipView: NSClipView?

        init(_ parent: MarkdownTextEditor) { self.parent = parent }

        private var lineNumberRulerView: LineNumberRulerView? {
            textView?.enclosingScrollView?.verticalRulerView as? LineNumberRulerView
        }

        deinit {
            if let monitor = keyMonitor {
                NSEvent.removeMonitor(monitor)
            }
            if let clipView = observedClipView {
                NotificationCenter.default.removeObserver(self, name: NSView.boundsDidChangeNotification, object: clipView)
            }
            NotificationCenter.default.removeObserver(self)
        }

        func bind(textView: NSTextView) {
            self.textView = textView
            setupSelectionObserversIfNeeded(for: textView)
            setupKeyMonitorIfNeeded()
        }

        func textDidChange(_ notification: Notification) {
            guard !isUpdating, let tv = notification.object as? NSTextView else { return }
            guard !tv.hasMarkedText() else { return }
            if let storage = tv.textStorage {
                highlighter?.highlight(storage)
            }
            parent.text = tv.string
            lineNumberRulerView?.update()
            scheduleSelectionToolbar(for: tv)
        }

        func textDidEndEditing(_ notification: Notification) {
            guard !isUpdating, let tv = notification.object as? NSTextView else { return }
            if let storage = tv.textStorage {
                highlighter?.highlight(storage)
            }
            parent.text = tv.string
            hideSelectionToolbar()
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            scheduleSelectionToolbar(for: tv)
        }

        func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            guard NSApp.currentEvent?.modifierFlags.contains(.command) == true else { return true }
            if let url = link as? URL {
                MarkdownFileOpener.open(url, baseURL: parent.documentURL?.deletingLastPathComponent())
            } else if let value = link as? String, let url = URL(string: value) {
                MarkdownFileOpener.open(url, baseURL: parent.documentURL?.deletingLastPathComponent())
            }
            return true
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                hideSelectionToolbar()
                return false
            }
            return false
        }

        @objc private func clipViewBoundsDidChange(_ notification: Notification) {
            hideSelectionToolbar()
            updateScrollRatio()
            lineNumberRulerView?.needsDisplay = true
        }

        private func setupSelectionObserversIfNeeded(for textView: NSTextView) {
            guard observedClipView == nil, let clipView = textView.enclosingScrollView?.contentView else { return }
            observedClipView = clipView
            clipView.postsBoundsChangedNotifications = true
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(clipViewBoundsDidChange(_:)),
                name: NSView.boundsDidChangeNotification,
                object: clipView
            )
        }

        func applyScrollTargetIfNeeded(_ scrollView: NSScrollView) {
            guard let target = parent.scrollTarget else { return }
            guard lastAppliedScrollTargetID != target.id else { return }
            lastAppliedScrollTargetID = target.id

            DispatchQueue.main.async { [weak self, weak scrollView] in
                guard let self, let scrollView else { return }
                switch target.kind {
                case .ratio(let ratio):
                    self.scroll(toRatio: ratio, in: scrollView)
                case .line(let line):
                    self.scroll(toLine: line, in: scrollView)
                }
                self.updateScrollRatio()
            }
        }

        private func updateScrollRatio() {
            guard let textView, let scrollView = textView.enclosingScrollView else { return }
            let ratio = currentScrollRatio(in: scrollView)
            guard abs(parent.scrollRatio - ratio) > 0.002 else { return }
            DispatchQueue.main.async { [weak self] in
                self?.parent.scrollRatio = ratio
            }
        }

        private func currentScrollRatio(in scrollView: NSScrollView) -> Double {
            let visibleHeight = scrollView.contentView.bounds.height
            let contentHeight = scrollView.documentView?.bounds.height ?? visibleHeight
            let maxY = max(1, contentHeight - visibleHeight)
            return min(1, max(0, Double(scrollView.contentView.bounds.origin.y / maxY)))
        }

        private func scroll(toRatio ratio: Double, in scrollView: NSScrollView) {
            let visibleHeight = scrollView.contentView.bounds.height
            let contentHeight = scrollView.documentView?.bounds.height ?? visibleHeight
            let maxY = max(0, contentHeight - visibleHeight)
            let y = CGFloat(min(1, max(0, ratio))) * maxY
            scrollView.contentView.scroll(to: NSPoint(x: 0, y: y))
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }

        private func scroll(toLine line: Int, in scrollView: NSScrollView) {
            guard let textView else { return }
            let lineStartRange = characterRangeForLine(line, in: textView.string)
            highlightLine(containing: lineStartRange.location, in: textView)
            textView.scrollRangeToVisible(lineStartRange)
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }

        private func highlightLine(containing location: Int, in textView: NSTextView) {
            guard let layoutManager = textView.layoutManager else { return }
            if let highlightedLineRange {
                layoutManager.removeTemporaryAttribute(.backgroundColor, forCharacterRange: highlightedLineRange)
            }

            let nsText = textView.string as NSString
            let safeLocation = min(max(0, location), nsText.length)
            var lineRange = nsText.lineRange(for: NSRange(location: safeLocation, length: 0))
            if lineRange.length == 0 {
                lineRange.length = min(1, max(0, nsText.length - lineRange.location))
            }

            highlightedLineRange = lineRange
            layoutManager.addTemporaryAttribute(
                .backgroundColor,
                value: NSColor.controlAccentColor.withAlphaComponent(0.18),
                forCharacterRange: lineRange
            )
        }

        private func characterRangeForLine(_ line: Int, in text: String) -> NSRange {
            let nsText = text as NSString
            let lines = text.components(separatedBy: .newlines)
            let clampedLine = min(max(0, line), max(0, lines.count - 1))
            var location = 0

            if clampedLine > 0 {
                for index in 0..<clampedLine {
                    location += (lines[index] as NSString).length
                    location += 1
                }
            }

            return NSRange(location: min(location, nsText.length), length: 0)
        }

        private func setupKeyMonitorIfNeeded() {
            guard keyMonitor == nil else { return }
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self else { return event }
                guard let tv = self.textView, tv.window?.firstResponder === tv else { return event }
                guard !tv.hasMarkedText(), tv.selectedRange().length > 0 else { return event }
                guard self.handleShortcut(event: event, textView: tv) else { return event }
                return nil
            }
        }

        private func handleShortcut(event: NSEvent, textView: NSTextView) -> Bool {
            let flags = event.modifierFlags.intersection([.command, .shift])
            guard let chars = event.charactersIgnoringModifiers?.lowercased() else { return false }

            switch (chars, flags) {
            case ("b", [.command]):
                apply(.bold, on: textView)
                return true
            case ("i", [.command]):
                apply(.italic, on: textView)
                return true
            case ("s", [.command, .shift]):
                apply(.strikethrough, on: textView)
                return true
            case ("c", [.command, .shift]):
                apply(.code, on: textView)
                return true
            case ("u", [.command, .shift]):
                apply(.link, on: textView)
                return true
            default:
                return false
            }
        }

        private func scheduleSelectionToolbar(for textView: NSTextView) {
            pendingPopoverWorkItem?.cancel()
            guard textView.selectedRange().length > 0 else {
                hideSelectionToolbar()
                return
            }

            let item = DispatchWorkItem { [weak self, weak textView] in
                guard let self, let tv = textView else { return }
                guard tv.selectedRange().length > 0 else {
                    self.hideSelectionToolbar()
                    return
                }
                self.showSelectionToolbar(for: tv)
            }
            pendingPopoverWorkItem = item
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: item)
        }

        private func showSelectionToolbar(for textView: NSTextView) {
            let popover = selectionPopover ?? NSPopover()
            popover.behavior = .transient
            popover.animates = true

            if selectionPopoverController == nil {
                let controller = SelectionToolbarViewController { [weak self] action in
                    guard let self, let tv = self.textView else { return }
                    self.apply(action, on: tv)
                }
                selectionPopoverController = controller
                popover.contentViewController = controller
            }

            guard let rect = selectedRectInTextView(textView) else {
                hideSelectionToolbar()
                return
            }

            if !popover.isShown {
                popover.show(relativeTo: rect, of: textView, preferredEdge: .maxY)
            } else {
                popover.performClose(nil)
                popover.show(relativeTo: rect, of: textView, preferredEdge: .maxY)
            }
            selectionPopover = popover
        }

        private func hideSelectionToolbar() {
            pendingPopoverWorkItem?.cancel()
            pendingPopoverWorkItem = nil
            selectionPopover?.performClose(nil)
        }

        private func selectedRectInTextView(_ textView: NSTextView) -> NSRect? {
            let selected = textView.selectedRange()
            guard selected.location != NSNotFound, selected.length > 0 else { return nil }
            guard let layoutManager = textView.layoutManager, let textContainer = textView.textContainer else { return nil }
            let glyphRange = layoutManager.glyphRange(forCharacterRange: selected, actualCharacterRange: nil)
            var rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
            rect.origin.x += textView.textContainerInset.width
            rect.origin.y += textView.textContainerInset.height
            if rect.isEmpty { return nil }
            return rect
        }

        private func apply(_ action: SelectionAction, on textView: NSTextView) {
            switch action {
            case .bold:
                toggleWrappedText(prefix: "**", suffix: "**", in: textView)
            case .italic:
                toggleWrappedText(prefix: "*", suffix: "*", in: textView)
            case .strikethrough:
                toggleWrappedText(prefix: "~~", suffix: "~~", in: textView)
            case .code:
                toggleWrappedText(prefix: "`", suffix: "`", in: textView)
            case .link:
                createOrToggleLink(in: textView)
            }
            scheduleSelectionToolbar(for: textView)
        }

        private func toggleWrappedText(prefix: String, suffix: String, in textView: NSTextView) {
            let selected = textView.selectedRange()
            guard selected.location != NSNotFound, selected.length > 0 else { return }
            let source = textView.string as NSString
            let selectedText = source.substring(with: selected)
            let replacement: String
            let newSelectionRange: NSRange

            if selectedText.hasPrefix(prefix), selectedText.hasSuffix(suffix), selectedText.count >= prefix.count + suffix.count {
                let start = selectedText.index(selectedText.startIndex, offsetBy: prefix.count)
                let end = selectedText.index(selectedText.endIndex, offsetBy: -suffix.count)
                replacement = String(selectedText[start..<end])
                newSelectionRange = NSRange(location: selected.location, length: replacement.count)
            } else {
                replacement = "\(prefix)\(selectedText)\(suffix)"
                newSelectionRange = NSRange(location: selected.location + prefix.count, length: selected.length)
            }

            guard textView.shouldChangeText(in: selected, replacementString: replacement) else { return }
            textView.textStorage?.replaceCharacters(in: selected, with: replacement)
            textView.didChangeText()
            textView.setSelectedRange(newSelectionRange)
        }

        private func createOrToggleLink(in textView: NSTextView) {
            let selected = textView.selectedRange()
            guard selected.location != NSNotFound, selected.length > 0 else { return }
            let source = textView.string as NSString
            let selectedText = source.substring(with: selected)

            if isURLText(selectedText) {
                replaceSelection(in: textView, range: selected, with: "[\(selectedText)](\(selectedText))", selectInner: selectedText)
                return
            }

            let alert = NSAlert()
            alert.alertStyle = .informational
            alert.messageText = "创建链接"
            alert.informativeText = "请输入链接地址："
            let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
            input.placeholderString = "https://example.com"
            input.stringValue = "https://"
            alert.accessoryView = input
            alert.addButton(withTitle: "确定")
            alert.addButton(withTitle: "取消")

            AppModalPresenter.showAlert(alert, preferred: textView) { [weak self, weak textView] response in
                guard response == .alertFirstButtonReturn else { return }
                guard let self, let textView else { return }

                let destination = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !destination.isEmpty else { return }

                let normalized = self.normalizeURLString(destination)
                self.replaceSelection(in: textView, range: selected, with: "[\(selectedText)](\(normalized))", selectInner: selectedText)
            }
        }

        private func replaceSelection(in textView: NSTextView, range: NSRange, with replacement: String, selectInner: String) {
            guard textView.shouldChangeText(in: range, replacementString: replacement) else { return }
            textView.textStorage?.replaceCharacters(in: range, with: replacement)
            textView.didChangeText()
            if let open = replacement.range(of: selectInner) {
                let prefixLength = replacement.distance(from: replacement.startIndex, to: open.lowerBound)
                textView.setSelectedRange(NSRange(location: range.location + prefixLength, length: selectInner.count))
            }
        }

        private func isURLText(_ text: String) -> Bool {
            let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { return false }
            return value.lowercased().hasPrefix("http://") || value.lowercased().hasPrefix("https://")
        }

        private func normalizeURLString(_ value: String) -> String {
            if value.lowercased().hasPrefix("http://") || value.lowercased().hasPrefix("https://") {
                return value
            }
            return "https://\(value)"
        }

        // MARK: - Image Insert

        func insertImageMarkdown(urls: [URL]) {
            guard let tv = textView else { return }
            var references: [MarkdownImageReference] = []
            var failures: [(URL, Error)] = []

            for url in urls {
                do {
                    references += try MarkdownImageAssetManager.references(
                        for: [url],
                        documentURL: parent.documentURL
                    )
                } catch {
                    failures.append((url, error))
                }
            }

            if !references.isEmpty {
                let markdown = references
                    .map { "![\($0.altText)](\($0.markdownPath))" }
                    .joined(separator: "\n")
                insertMarkdownText(markdown, in: tv)
            }

            if !failures.isEmpty {
                showImageInsertFailure(failures)
            }
        }

        func insertFileLinks(urls: [URL]) {
            guard let tv = textView else { return }
            let markdown = urls
                .map { "[\($0.lastPathComponent)](\(markdownLinkDestination(for: $0)))" }
                .joined(separator: "\n")
            guard !markdown.isEmpty else { return }
            insertMarkdownText(markdown, in: tv)
        }

        func insertImageMarkdown(name: String, path: String) {
            guard let tv = textView else { return }
            insertMarkdownText("![\(name)](\(path))", in: tv)
        }

        private func insertMarkdownText(_ string: String, in tv: NSTextView) {
            let range = tv.selectedRange()
            let insertRange = NSRange(location: range.location, length: 0)
            guard tv.shouldChangeText(in: insertRange, replacementString: string) else { return }
            tv.textStorage?.replaceCharacters(in: insertRange, with: string)
            tv.didChangeText()
            tv.setSelectedRange(NSRange(location: insertRange.location + (string as NSString).length, length: 0))
        }

        func handleImagePaste(in tv: NSTextView) -> Bool {
            let pb = NSPasteboard.general
            guard let pngData = pasteboardImageAsPNG(pb) else { return false }
            let tmpDir = imageTmpDirectory()
            do {
                try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
                let name = UUID().uuidString + ".png"
                let fileURL = tmpDir.appendingPathComponent(name)
                try pngData.write(to: fileURL)
                insertImageMarkdown(name: name, path: fileURL.path)
            } catch {
                let alert = NSAlert()
                alert.alertStyle = .warning
                alert.messageText = "图片保存失败"
                alert.informativeText = error.localizedDescription
                alert.addButton(withTitle: "确定")
                AppModalPresenter.showAlert(alert, preferred: tv)
            }
            return true
        }

        private func pasteboardImageAsPNG(_ pb: NSPasteboard) -> Data? {
            // 1. 直接取 PNG 原始数据（部分截图/应用会直接放 public.png）
            if let data = pb.data(forType: NSPasteboard.PasteboardType("public.png")) {
                return data
            }
            // 2. 取 TIFF 原始数据并转 PNG（macOS 截图默认类型）
            if let data = pb.data(forType: .tiff),
               let rep = NSBitmapImageRep(data: data) {
                return rep.representation(using: .png, properties: [:])
            }
            // 3. 兜底：通过 CGImage 路径转 PNG
            if let image = NSImage(pasteboard: pb),
               let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                let rep = NSBitmapImageRep(cgImage: cgImage)
                return rep.representation(using: .png, properties: [:])
            }
            return nil
        }

        private func imageTmpDirectory() -> URL {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            return appSupport.appendingPathComponent("MarkdownEditor/.tmp", isDirectory: true)
        }

        private func showImageInsertFailure(_ failures: [(URL, Error)]) {
            let details = failures
                .map { url, error in "\(url.lastPathComponent): \(error.localizedDescription)" }
                .joined(separator: "\n")
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "图片插入失败"
            alert.informativeText = details
            alert.addButton(withTitle: "确定")
            AppModalPresenter.showAlert(alert, preferred: textView)
        }

        private func markdownLinkDestination(for url: URL) -> String {
            let rawPath: String

            if let documentURL = parent.documentURL {
                let basePath = documentURL.deletingLastPathComponent().standardizedFileURL.path
                let filePath = url.standardizedFileURL.path
                if filePath.hasPrefix(basePath + "/") {
                    rawPath = String(filePath.dropFirst(basePath.count + 1))
                } else {
                    rawPath = url.path
                }
            } else {
                rawPath = url.path
            }

            return rawPath
                .replacingOccurrences(of: " ", with: "%20")
                .replacingOccurrences(of: ")", with: "%29")
                .replacingOccurrences(of: "(", with: "%28")
        }

    }

    private enum SelectionAction {
        case bold
        case italic
        case strikethrough
        case code
        case link
    }

    private final class SelectionToolbarViewController: NSViewController {
        private let onAction: (SelectionAction) -> Void

        init(onAction: @escaping (SelectionAction) -> Void) {
            self.onAction = onAction
            super.init(nibName: nil, bundle: nil)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { nil }

        override func loadView() {
            let container = NSView()
            let blur = NSVisualEffectView()
            blur.material = .popover
            blur.blendingMode = .behindWindow
            blur.state = .active
            blur.wantsLayer = true
            blur.layer?.cornerRadius = 14
            blur.layer?.masksToBounds = true
            blur.translatesAutoresizingMaskIntoConstraints = false

            let row = NSStackView()
            row.orientation = .horizontal
            row.alignment = .centerY
            row.spacing = 6
            row.edgeInsets = NSEdgeInsets(top: 6, left: 8, bottom: 6, right: 8)
            row.translatesAutoresizingMaskIntoConstraints = false

            row.addArrangedSubview(makeIconButton(symbol: "bold", action: #selector(tapBold)))
            row.addArrangedSubview(makeIconButton(symbol: "italic", action: #selector(tapItalic)))
            row.addArrangedSubview(makeIconButton(symbol: "strikethrough", action: #selector(tapStrikethrough)))
            row.addArrangedSubview(makeIconButton(symbol: "chevron.left.forwardslash.chevron.right", action: #selector(tapCode)))
            row.addArrangedSubview(makeIconButton(symbol: "link", action: #selector(tapLink)))

            blur.addSubview(row)
            container.addSubview(blur)
            self.view = container

            NSLayoutConstraint.activate([
                blur.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                blur.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                blur.topAnchor.constraint(equalTo: container.topAnchor),
                blur.bottomAnchor.constraint(equalTo: container.bottomAnchor),

                row.leadingAnchor.constraint(equalTo: blur.leadingAnchor),
                row.trailingAnchor.constraint(equalTo: blur.trailingAnchor),
                row.topAnchor.constraint(equalTo: blur.topAnchor),
                row.bottomAnchor.constraint(equalTo: blur.bottomAnchor)
            ])
        }

        private func makeIconButton(symbol: String, action: Selector) -> NSButton {
            let config = NSImage.SymbolConfiguration(pointSize: 17, weight: .medium)
            let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?.withSymbolConfiguration(config)
            let button = NSButton(image: image ?? NSImage(), target: self, action: action)
            button.bezelStyle = .rounded
            button.imagePosition = .imageOnly
            button.contentTintColor = .secondaryLabelColor
            button.controlSize = .regular
            button.focusRingType = .none
            button.translatesAutoresizingMaskIntoConstraints = false
            button.widthAnchor.constraint(equalToConstant: 34).isActive = true
            button.heightAnchor.constraint(equalToConstant: 28).isActive = true
            return button
        }

        @objc private func tapBold() { onAction(.bold) }
        @objc private func tapItalic() { onAction(.italic) }
        @objc private func tapStrikethrough() { onAction(.strikethrough) }
        @objc private func tapCode() { onAction(.code) }
        @objc private func tapLink() { onAction(.link) }
    }

    // MARK: - Helpers

    private func applyEditorStyle(to textView: NSTextView, coordinator: Coordinator) {
        coordinator.bind(textView: textView)
        let font = editorFont()
        let fontToken = "\(font.fontName)-\(font.pointSize)"
        // Only rebuild when font actually changes — prevents re-highlighting on every scroll event
        guard coordinator.currentFontToken != fontToken || coordinator.highlighter == nil else { return }

        let styleTokens = MarkdownStyleTokens(baseFont: font)
        textView.font = font
        textView.typingAttributes = [
            .font: font,
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: styleTokens.paragraphStyle
        ]
        coordinator.highlighter = MarkdownSyntaxHighlighter(baseFont: font)
        coordinator.currentFontToken = fontToken
        if let storage = textView.textStorage {
            coordinator.highlighter?.highlight(storage)
        }
        if let rulerView = textView.enclosingScrollView?.verticalRulerView as? LineNumberRulerView {
            rulerView.lineNumberFont = lineNumberFont()
            rulerView.update()
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

    private func lineNumberFont() -> NSFont {
        let clampedSize = max(EditorStyleSettings.minFontSize, min(EditorStyleSettings.maxFontSize, fontSize))
        let size = max(10, CGFloat(clampedSize) * 0.82)
        return NSFont(name: fontFamily, size: size)
            ?? NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }
}

// MARK: - FileDropTextView

private final class FileDropTextView: NSTextView {
    var onImagesDrop: (([URL]) -> Void)?
    var onFilesDrop: (([URL]) -> Void)?
    var onImagePaste: (() -> Bool)?

    override init(frame: NSRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func paste(_ sender: Any?) {
        if onImagePaste?() == true { return }
        super.paste(sender)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        fileURLs(from: sender.draggingPasteboard).isEmpty ? super.draggingEntered(sender) : .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        fileURLs(from: sender.draggingPasteboard).isEmpty ? super.draggingUpdated(sender) : .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = fileURLs(from: sender.draggingPasteboard)
        guard !urls.isEmpty else { return super.performDragOperation(sender) }
        let viewPt = convert(sender.draggingLocation, from: nil)
        setSelectedRange(NSRange(location: characterIndexForInsertion(at: viewPt), length: 0))
        let imageURLs = urls.filter(\.isImageFileURL)
        let fileURLs = urls.filter { !$0.isImageFileURL }
        if !imageURLs.isEmpty {
            onImagesDrop?(imageURLs)
        }
        if !fileURLs.isEmpty {
            onFilesDrop?(fileURLs)
        }
        return true
    }

    private func fileURLs(from pasteboard: NSPasteboard) -> [URL] {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true
        ]
        return (pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL]) ?? []
    }
}

private extension URL {
    var isImageFileURL: Bool {
        guard isFileURL else { return false }
        guard let type = UTType(filenameExtension: pathExtension) else { return false }
        return type.conforms(to: .image)
    }
}
