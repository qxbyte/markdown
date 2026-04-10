import SwiftUI

struct ContentView: View {
    @ObservedObject var document: MarkdownDocument
    @AppStorage("editorViewMode") private var viewModeRawValue: String = EditorViewMode.editorAndPreview.rawValue

    private var viewMode: EditorViewMode {
        get { EditorViewMode(rawValue: viewModeRawValue) ?? .editorAndPreview }
        nonmutating set { viewModeRawValue = newValue.rawValue }
    }

    var body: some View {
        Group {
            switch viewMode {
            case .editor:
                MarkdownTextEditor(text: $document.text)
                    .frame(minWidth: 280, maxWidth: .infinity, maxHeight: .infinity)
            case .editorAndPreview:
                HSplitView {
                    MarkdownTextEditor(text: $document.text)
                        .frame(minWidth: 280, maxWidth: .infinity, maxHeight: .infinity)

                    MarkdownPreviewView(markdownText: document.text)
                        .frame(minWidth: 280, maxWidth: .infinity, maxHeight: .infinity)
                }
            case .preview:
                MarkdownPreviewView(markdownText: document.text)
                    .frame(minWidth: 280, maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 800, minHeight: 560)
        .navigationTitle(document.displayName)
        .navigationSubtitle(document.isDirty ? "已修改" : "")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 6) {
                    modeButton(.editor, icon: "doc.plaintext")
                    modeButton(.editorAndPreview, icon: "rectangle.split.2x1")
                    modeButton(.preview, icon: "doc.richtext")
                }
                .padding(.horizontal, 4)
            }
        }
        .onAppear {
            NSApp.delegate.flatMap { $0 as? AppDelegate }?.setActiveDocument(document)
        }
    }

    @ViewBuilder
    private func modeButton(_ mode: EditorViewMode, icon: String) -> some View {
        Button {
            viewMode = mode
        } label: {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 24, height: 20)
                .foregroundStyle(viewMode == mode ? .primary : .secondary)
                .background(viewMode == mode ? Color.gray.opacity(0.25) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .controlSize(.small)
        .help(mode.title)
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
