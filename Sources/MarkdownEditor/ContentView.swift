import SwiftUI
import AppKit

struct ContentView: View {
    @ObservedObject var document: MarkdownDocument
    @State private var window: NSWindow?
    @AppStorage("editorViewMode") private var viewModeRawValue: String = EditorViewMode.editorAndPreview.rawValue

    private var viewMode: EditorViewMode {
        get { EditorViewMode(rawValue: viewModeRawValue) ?? .editorAndPreview }
        nonmutating set { viewModeRawValue = newValue.rawValue }
    }

    var body: some View {
        Group {
            switch viewMode {
            case .editor:
                MarkdownTextEditor(text: $document.text, documentURL: document.fileURL)
                    .frame(minWidth: 280, maxWidth: .infinity, maxHeight: .infinity)
            case .editorAndPreview:
                HSplitView {
                    MarkdownTextEditor(text: $document.text, documentURL: document.fileURL)
                        .frame(minWidth: 280, maxWidth: .infinity, maxHeight: .infinity)

                    MarkdownPreviewView(
                        markdownText: document.text,
                        baseURL: document.fileURL?.deletingLastPathComponent()
                    )
                        .frame(minWidth: 280, maxWidth: .infinity, maxHeight: .infinity)
                }
            case .preview:
                MarkdownPreviewView(
                    markdownText: document.text,
                    baseURL: document.fileURL?.deletingLastPathComponent()
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
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 3) {
                    modeButton(.editor, icon: "doc.plaintext")
                    modeButton(.editorAndPreview, icon: "rectangle.split.2x1")
                    modeButton(.preview, icon: "doc.richtext")
                }
                .padding(.horizontal, 2)
            }
        }
        .onAppear {
            NSApp.delegate.flatMap { $0 as? AppDelegate }?.setActiveDocument(document)
            window?.isDocumentEdited = document.isDirty
        }
        .onChange(of: document.isDirty) { isDirty in
            window?.isDocumentEdited = isDirty
        }
    }

    @ViewBuilder
    private func modeButton(_ mode: EditorViewMode, icon: String) -> some View {
        Button {
            viewMode = mode
        } label: {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .frame(width: 21, height: 17)
                .foregroundStyle(viewMode == mode ? .primary : .secondary)
                .background(viewMode == mode ? Color.gray.opacity(0.25) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
        .controlSize(.small)
        .help(mode.title)
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
    case editorAndPreview
    case preview

    var title: String {
        switch self {
        case .editor:
            return "Editor"
        case .editorAndPreview:
            return "Editor and Preview"
        case .preview:
            return "Preview"
        }
    }
}
