import SwiftUI
import AppKit

struct ContentView: View {
    @ObservedObject var document: MarkdownDocument
    @State private var window: NSWindow?
    @State private var scrollRatio: Double = 0
    @State private var scrollTarget: MarkdownScrollTarget?
    @State private var isOutlinePresented = false
    @AppStorage("editorViewMode") private var viewModeRawValue: String = EditorViewMode.editor.rawValue

    private var viewMode: EditorViewMode {
        get { EditorViewMode(rawValue: viewModeRawValue) ?? .editor }
        nonmutating set { viewModeRawValue = newValue.rawValue }
    }

    private var headings: [MarkdownHeading] {
        MarkdownNavigation.headings(in: document.text)
    }

    private var currentHeading: MarkdownHeading? {
        guard !headings.isEmpty else { return nil }
        let totalLines = max(1, document.text.components(separatedBy: .newlines).count - 1)
        let currentLine = Int((min(1, max(0, scrollRatio)) * Double(totalLines)).rounded(.down))
        return headings.last { $0.line <= currentLine } ?? headings.first
    }

    private var outlineTitle: String {
        currentHeading?.title ?? document.displayName
    }

    var body: some View {
        Group {
            switch viewMode {
            case .editor:
                MarkdownTextEditor(
                    text: $document.text,
                    scrollRatio: $scrollRatio,
                    scrollTarget: $scrollTarget,
                    documentURL: document.fileURL
                )
                    .frame(minWidth: 280, maxWidth: .infinity, maxHeight: .infinity)
            case .preview:
                MarkdownPreviewView(
                    markdownText: document.text,
                    baseURL: document.fileURL?.deletingLastPathComponent(),
                    scrollRatio: $scrollRatio,
                    scrollTarget: $scrollTarget
                )
                    .frame(minWidth: 280, maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 650, minHeight: 450)
        .navigationTitle("")
        .background(
            DocumentEditedWindowAccessor { resolvedWindow in
                if window !== resolvedWindow {
                    window = resolvedWindow
                }
                resolvedWindow.toolbarStyle = .unifiedCompact
                resolvedWindow.toolbar?.sizeMode = .small
                resolvedWindow.toolbar?.displayMode = .iconOnly
                resolvedWindow.isDocumentEdited = document.isDirty
            }
        )
        .toolbar {
            ToolbarItem(placement: .navigation) {
                titleBarNavigation
            }
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 1) {
                    modeButton(.editor, icon: "doc.plaintext")
                    modeButton(.preview, icon: "doc.richtext")
                }
                .padding(.horizontal, 1)
            }
        }
        .onAppear {
            NSApp.delegate.flatMap { $0 as? AppDelegate }?.setActiveDocument(document)
            window?.isDocumentEdited = document.isDirty
            if EditorViewMode(rawValue: viewModeRawValue) == nil {
                viewModeRawValue = EditorViewMode.editor.rawValue
            }
            restoreScrollPosition()
        }
        .onChange(of: document.isDirty) { isDirty in
            window?.isDocumentEdited = isDirty
        }
        .onChange(of: document.fileURL) { _ in
            restoreScrollPosition()
        }
        .onChange(of: scrollRatio) { ratio in
            saveScrollPosition(ratio)
        }
    }

    private var titleBarNavigation: some View {
        HStack(spacing: 8) {
            Text(document.displayName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: 128, alignment: .leading)
            outlineButton
        }
        .frame(width: 310, alignment: .leading)
    }

    private var outlineButton: some View {
        Button {
            isOutlinePresented.toggle()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "list.bullet.rectangle.portrait.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.indigo.opacity(0.85))
                Text(outlineTitle)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .layoutPriority(1)
                    .frame(maxWidth: 170, alignment: .leading)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 3)
            .frame(height: 16)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isOutlinePresented, arrowEdge: .top) {
            HeadingOutlineView(headings: headings, currentHeading: currentHeading) { heading in
                viewMode = .editor
                scrollTarget = MarkdownScrollTarget(kind: .line(heading.line))
                isOutlinePresented = false
            }
        }
        .help("文档结构")
    }

    @ViewBuilder
    private func modeButton(_ mode: EditorViewMode, icon: String) -> some View {
        Button {
            scrollTarget = MarkdownScrollTarget(kind: .ratio(scrollRatio))
            viewMode = mode
        } label: {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .medium))
                .frame(width: 18, height: 13)
                .foregroundStyle(viewMode == mode ? .primary : .secondary)
                .background(viewMode == mode ? Color.gray.opacity(0.25) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 3))
        }
        .buttonStyle(.plain)
        .controlSize(.small)
        .help(mode.title)
    }

    private func scrollDefaultsKey() -> String? {
        guard let fileURL = document.fileURL else { return nil }
        return "documentScrollRatio.\(fileURL.standardizedFileURL.path)"
    }

    private func restoreScrollPosition() {
        guard let key = scrollDefaultsKey() else {
            scrollRatio = 0
            scrollTarget = MarkdownScrollTarget(kind: .ratio(0))
            return
        }
        let saved = UserDefaults.standard.double(forKey: key)
        scrollRatio = min(1, max(0, saved))
        scrollTarget = MarkdownScrollTarget(kind: .ratio(scrollRatio))
    }

    private func saveScrollPosition(_ ratio: Double) {
        guard let key = scrollDefaultsKey() else { return }
        UserDefaults.standard.set(min(1, max(0, ratio)), forKey: key)
    }
}

private struct HeadingOutlineView: View {
    let headings: [MarkdownHeading]
    let currentHeading: MarkdownHeading?
    let onSelect: (MarkdownHeading) -> Void

    private var outlineWidth: CGFloat {
        let longest = headings
            .map { estimatedRowWidth(for: $0) }
            .max() ?? 180
        return (min(520, max(260, longest)) * 3 / 5).rounded()
    }

    private func estimatedRowWidth(for heading: MarkdownHeading) -> CGFloat {
        let titleWidth = heading.title.reduce(CGFloat(0)) { width, character in
            width + (character.isASCII ? 6.5 : 11)
        }
        let indent = CGFloat(max(0, heading.level - 1)) * 14
        return titleWidth + indent + 82
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                if headings.isEmpty {
                    Text("暂无标题")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                } else {
                    ForEach(headings) { heading in
                        let isCurrent = heading.id == currentHeading?.id
                        Button {
                            onSelect(heading)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 11, weight: .semibold))
                                    .frame(width: 12)
                                    .foregroundStyle(.white)
                                    .opacity(isCurrent ? 1 : 0)
                                Image(systemName: "list.bullet.rectangle.portrait.fill")
                                    .font(.system(size: 10.5, weight: .medium))
                                    .foregroundStyle(isCurrent ? .white.opacity(0.85) : .indigo.opacity(0.75))
                                Text(heading.title)
                                    .font(.system(size: 11, weight: .regular))
                                    .foregroundStyle(isCurrent ? .white : .primary)
                                    .lineLimit(1)
                                Spacer(minLength: 6)
                            }
                            .padding(.leading, 7 + CGFloat(max(0, heading.level - 1)) * 14)
                            .padding(.trailing, 8)
                            .frame(height: 24)
                            .background(isCurrent ? Color.green.opacity(0.86) : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(6)
        }
        .background(.regularMaterial)
        .frame(width: outlineWidth, height: min(380, max(60, CGFloat(max(headings.count, 1)) * 27 + 12)))
    }
}

private struct DocumentEditedWindowAccessor: NSViewRepresentable {
    let onResolve: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                onResolve(window)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            if let window = nsView.window {
                onResolve(window)
            }
        }
    }
}

private enum EditorViewMode: String {
    case editor
    case preview

    var title: String {
        switch self {
        case .editor:
            return "Editor"
        case .preview:
            return "Preview"
        }
    }
}
