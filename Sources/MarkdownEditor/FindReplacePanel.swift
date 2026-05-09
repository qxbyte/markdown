import AppKit
import SwiftUI

// MARK: - State

final class FindReplaceState: ObservableObject {
    @Published var findText: String = ""
    @Published var replaceText: String = ""
    @Published var isRegex: Bool = false
    @Published var isCaseInsensitive: Bool = false
    @Published var isInSelection: Bool = false
    @Published var matchCount: Int = 0
    @Published var currentMatchIndex: Int = 0
    @Published var isRegexInvalid: Bool = false

    private var selectionAnchor: NSRange?

    // MARK: - Target text view

    private func targetTextView() -> NSTextView? {
        let windows = NSApp.windows.filter { !($0 is NSPanel) && $0.isVisible }
        for window in windows {
            if let tv = firstNSTextView(in: window.contentView) { return tv }
        }
        return nil
    }

    private func firstNSTextView(in view: NSView?) -> NSTextView? {
        guard let view else { return nil }
        if let tv = view as? NSTextView { return tv }
        for sub in view.subviews {
            if let tv = firstNSTextView(in: sub) { return tv }
        }
        return nil
    }

    // MARK: - Core search

    private func computeRanges(in text: String, anchor: NSRange?) -> [NSRange] {
        guard !findText.isEmpty else { return [] }
        let nsText = text as NSString
        let scope = anchor ?? NSRange(location: 0, length: nsText.length)

        if isRegex {
            var opts: NSRegularExpression.Options = []
            if isCaseInsensitive { opts.insert(.caseInsensitive) }
            guard let regex = try? NSRegularExpression(pattern: findText, options: opts) else {
                DispatchQueue.main.async { self.isRegexInvalid = true }
                return []
            }
            DispatchQueue.main.async { self.isRegexInvalid = false }
            return regex.matches(in: text, range: scope).map { $0.range }
        }

        DispatchQueue.main.async { self.isRegexInvalid = false }
        var cmpOpts: NSString.CompareOptions = []
        if isCaseInsensitive { cmpOpts.insert(.caseInsensitive) }
        var ranges: [NSRange] = []
        var search = scope
        while search.length > 0 {
            let found = nsText.range(of: findText, options: cmpOpts, range: search)
            guard found.location != NSNotFound else { break }
            ranges.append(found)
            let nextLoc = found.location + max(found.length, 1)
            let remaining = NSMaxRange(scope) - nextLoc
            guard remaining > 0 else { break }
            search = NSRange(location: nextLoc, length: remaining)
        }
        return ranges
    }

    // MARK: - Public helpers

    func refreshMatchCount() {
        guard let tv = targetTextView() else { matchCount = 0; return }
        let ranges = computeRanges(in: tv.string, anchor: isInSelection ? selectionAnchor : nil)
        matchCount = ranges.count
        applyHighlights(ranges, current: nil, in: tv)
    }

    func captureSelectionAnchor() {
        guard let tv = targetTextView() else { selectionAnchor = nil; return }
        let sel = tv.selectedRange()
        selectionAnchor = sel.length > 0 ? sel : nil
    }

    // MARK: - Navigation

    func findNext() {
        guard let tv = targetTextView(), !findText.isEmpty else { return }
        let ranges = computeRanges(in: tv.string, anchor: isInSelection ? selectionAnchor : nil)
        matchCount = ranges.count
        guard !ranges.isEmpty else { currentMatchIndex = 0; return }

        let curEnd = tv.selectedRange().location + tv.selectedRange().length
        let next = ranges.first(where: { $0.location >= curEnd }) ?? ranges[0]
        currentMatchIndex = (ranges.firstIndex { $0.location == next.location } ?? 0) + 1

        tv.setSelectedRange(next)
        tv.scrollRangeToVisible(next)
        applyHighlights(ranges, current: next, in: tv)
    }

    func findPrev() {
        guard let tv = targetTextView(), !findText.isEmpty else { return }
        let ranges = computeRanges(in: tv.string, anchor: isInSelection ? selectionAnchor : nil)
        matchCount = ranges.count
        guard !ranges.isEmpty else { currentMatchIndex = 0; return }

        let curStart = tv.selectedRange().location
        let prev = ranges.last(where: { $0.location < curStart }) ?? ranges[ranges.count - 1]
        currentMatchIndex = (ranges.firstIndex { $0.location == prev.location } ?? 0) + 1

        tv.setSelectedRange(prev)
        tv.scrollRangeToVisible(prev)
        applyHighlights(ranges, current: prev, in: tv)
    }

    func findAll() {
        guard let tv = targetTextView() else { return }
        let ranges = computeRanges(in: tv.string, anchor: isInSelection ? selectionAnchor : nil)
        matchCount = ranges.count
        currentMatchIndex = ranges.isEmpty ? 0 : 1

        if let first = ranges.first {
            tv.setSelectedRange(first)
            tv.scrollRangeToVisible(first)
        }
        applyHighlights(ranges, current: ranges.first, in: tv)
    }

    // MARK: - Replace

    func replace() {
        guard let tv = targetTextView(), !findText.isEmpty else { return }
        let sel = tv.selectedRange()

        if sel.length > 0 {
            let selText = (tv.string as NSString).substring(with: sel)
            let check = computeRanges(in: selText, anchor: NSRange(location: 0, length: (selText as NSString).length))
            let isFullMatch = check.count == 1 && check[0].location == 0 && check[0].length == (selText as NSString).length
            if isFullMatch {
                let rep = resolvedReplacement(for: selText)
                if tv.shouldChangeText(in: sel, replacementString: rep) {
                    tv.textStorage?.replaceCharacters(in: sel, with: rep)
                    tv.didChangeText()
                }
            }
        }
        findNext()
    }

    func replaceAll() {
        guard let tv = targetTextView(), !findText.isEmpty else { return }
        let ranges = computeRanges(in: tv.string, anchor: isInSelection ? selectionAnchor : nil)
        guard !ranges.isEmpty else { return }

        tv.undoManager?.beginUndoGrouping()
        for range in ranges.reversed() {
            let original = (tv.string as NSString).substring(with: range)
            let rep = resolvedReplacement(for: original)
            if tv.shouldChangeText(in: range, replacementString: rep) {
                tv.textStorage?.replaceCharacters(in: range, with: rep)
                tv.didChangeText()
            }
        }
        tv.undoManager?.endUndoGrouping()

        matchCount = 0
        currentMatchIndex = 0
        clearHighlights(in: tv)
    }

    func clearAllHighlights() {
        if let tv = targetTextView() { clearHighlights(in: tv) }
    }

    // MARK: - Private helpers

    private func resolvedReplacement(for original: String) -> String {
        guard isRegex else { return replaceText }
        var opts: NSRegularExpression.Options = []
        if isCaseInsensitive { opts.insert(.caseInsensitive) }
        guard let regex = try? NSRegularExpression(pattern: findText, options: opts) else { return replaceText }
        let nsStr = original as NSString
        return regex.stringByReplacingMatches(
            in: original,
            range: NSRange(location: 0, length: nsStr.length),
            withTemplate: replaceText
        )
    }

    private func applyHighlights(_ ranges: [NSRange], current: NSRange?, in tv: NSTextView) {
        guard let lm = tv.layoutManager else { return }
        clearHighlights(in: tv)
        for range in ranges {
            let isCurrent = current.map { $0.location == range.location && $0.length == range.length } ?? false
            let color: NSColor = isCurrent
                ? .systemOrange.withAlphaComponent(0.55)
                : .systemYellow.withAlphaComponent(0.4)
            lm.addTemporaryAttribute(.backgroundColor, value: color, forCharacterRange: range)
        }
    }

    private func clearHighlights(in tv: NSTextView) {
        guard let lm = tv.layoutManager else { return }
        lm.removeTemporaryAttribute(.backgroundColor,
            forCharacterRange: NSRange(location: 0, length: (tv.string as NSString).length))
    }
}

// MARK: - FindReplaceView

struct FindReplaceView: View {
    @ObservedObject var state: FindReplaceState
    @FocusState private var focused: FocusedField?

    private enum FocusedField { case find, replace }

    var body: some View {
        VStack(spacing: 10) {
            searchFieldRow
            replaceFieldRow
            optionsRow
            actionsRow
        }
        .padding(12)
        .frame(width: 380)
        .onAppear {
            DispatchQueue.main.async { focused = .find }
        }
        .onChange(of: state.findText) { _ in state.refreshMatchCount() }
        .onChange(of: state.isRegex) { _ in state.refreshMatchCount() }
        .onChange(of: state.isCaseInsensitive) { _ in state.refreshMatchCount() }
        .onChange(of: state.isInSelection) { isOn in
            if isOn { state.captureSelectionAnchor() }
            state.refreshMatchCount()
        }
    }

    // MARK: Search field

    private var searchFieldRow: some View {
        let borderColor: Color = state.isRegexInvalid ? .red : .accentColor
        return HStack(spacing: 6) {
            fieldIcon(name: "magnifyingglass", active: true)

            TextField("", text: $state.findText)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .focused($focused, equals: .find)
                .onSubmit { state.findNext() }

            // Match counter
            if state.matchCount > 0 {
                Text(state.currentMatchIndex > 0
                     ? "\(state.currentMatchIndex)/\(state.matchCount)"
                     : "\(state.matchCount)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .layoutPriority(1)
            } else if !state.findText.isEmpty && state.matchCount == 0 && !state.isRegexInvalid {
                Text("无匹配")
                    .font(.system(size: 11))
                    .foregroundStyle(.red.opacity(0.8))
                    .layoutPriority(1)
            }

            if !state.findText.isEmpty {
                Button {
                    state.findText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .background(fieldBackground(borderColor: borderColor, lineWidth: 2))
    }

    // MARK: Replace field

    private var replaceFieldRow: some View {
        HStack(spacing: 6) {
            fieldIcon(name: "pencil", active: false)

            TextField("替换", text: $state.replaceText)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .focused($focused, equals: .replace)
                .onSubmit { state.replace() }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(fieldBackground(borderColor: Color(nsColor: .separatorColor), lineWidth: 1))
    }

    // MARK: Options row

    private var optionsRow: some View {
        HStack(spacing: 10) {
            // Regex toggle + help badge
            HStack(spacing: 4) {
                Toggle(isOn: $state.isRegex) {
                    Text("正则表达式")
                }
                .toggleStyle(.checkbox)
                .font(.system(size: 12))

                Text("?")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 14, height: 14)
                    .background(Color.secondary.opacity(0.5))
                    .clipShape(Circle())
                    .help("使用正则表达式进行搜索，替换时支持 $1、$2 等反向引用")
            }

            Toggle("忽略大小写", isOn: $state.isCaseInsensitive)
                .toggleStyle(.checkbox)
                .font(.system(size: 12))

            Toggle("所选内容", isOn: $state.isInSelection)
                .toggleStyle(.checkbox)
                .font(.system(size: 12))

            Spacer()

            Button {
                // Reserved for future extended options
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("更多选项")
        }
    }

    // MARK: Actions row

    private var actionsRow: some View {
        HStack(spacing: 6) {
            // Find All (with dropdown chevron decoration)
            Button {
                state.findAll()
            } label: {
                HStack(spacing: 3) {
                    Text("全部查找")
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                }
            }

            Button("全部替换") { state.replaceAll() }

            Button("替换") { state.replace() }

            Spacer()

            // Prev / Next navigation
            HStack(spacing: 2) {
                Button {
                    state.findPrev()
                } label: {
                    Image(systemName: "chevron.left")
                        .frame(width: 16)
                }

                Button {
                    state.findNext()
                } label: {
                    Image(systemName: "chevron.right")
                        .frame(width: 16)
                }
            }
        }
        .controlSize(.regular)
    }

    // MARK: Helpers

    private func fieldIcon(name: String, active: Bool) -> some View {
        HStack(spacing: 2) {
            Image(systemName: name)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(active ? Color.accentColor : Color.secondary)
            Image(systemName: "chevron.down")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .frame(width: 32)
    }

    private func fieldBackground(borderColor: Color, lineWidth: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 7)
            .fill(Color(nsColor: .textBackgroundColor))
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(borderColor, lineWidth: lineWidth)
            )
    }
}

// MARK: - NSPanel

final class FindReplaceWindowPanel: NSPanel {
    private let state: FindReplaceState

    init(state: FindReplaceState) {
        self.state = state
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 10),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        title = "查找和替换"
        level = .floating
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        contentViewController = NSHostingController(rootView: FindReplaceView(state: state))
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func close() {
        state.clearAllHighlights()
        super.close()
    }
}
