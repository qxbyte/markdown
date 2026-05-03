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
        .frame(minWidth: 800, minHeight: 560)
        .navigationTitle(document.displayName)
        .background(
            DocumentEditedWindowAccessor { resolvedWindow in
                if window !== resolvedWindow {
                    window = resolvedWindow
                }
                resolvedWindow.isDocumentEdited = document.isDirty
            }
        )
        .toolbar {
            ToolbarItem(placement: .principal) {
                outlineButton
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

    private var outlineButton: some View {
        Button {
            isOutlinePresented.toggle()
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "list.bullet.rectangle.portrait.fill")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.indigo.opacity(0.85))
                Text(document.displayName)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 420)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 3)
            .frame(height: 20)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isOutlinePresented, arrowEdge: .top) {
            HeadingOutlineView(headings: headings, documentTitle: document.displayName) { heading in
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
    let documentTitle: String
    let onSelect: (MarkdownHeading) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                if headings.isEmpty {
                    Text("暂无标题")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                } else {
                    ForEach(headings) { heading in
                        Button {
                            onSelect(heading)
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "list.bullet.rectangle.portrait.fill")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(.indigo.opacity(0.8))
                                Text(heading.title)
                                    .font(.system(size: heading.level == 1 ? 15 : 14, weight: heading.level <= 2 ? .semibold : .regular))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                Spacer(minLength: 8)
                            }
                            .padding(.leading, CGFloat(max(0, heading.level - 1)) * 24)
                            .padding(.trailing, 14)
                            .frame(height: 30)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.vertical, 10)
        }
        .frame(width: 520, height: min(460, max(80, CGFloat(max(headings.count, 1)) * 38 + 20)))
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
