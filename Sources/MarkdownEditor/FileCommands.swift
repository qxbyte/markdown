import SwiftUI

struct FileCommands: Commands {
    @FocusedValue(\.markdownDocument) private var focusedDocument
    @AppStorage(EditorStyleSettings.fontFamilyKey) private var editorFontFamily: String = EditorStyleSettings.defaultFontFamily
    @AppStorage(EditorStyleSettings.fontSizeKey) private var editorFontSize: Double = EditorStyleSettings.defaultFontSize
    let appDelegate: AppDelegate

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("新建") {
                (focusedDocument ?? appDelegate.currentDocument())?.new()
            }
            .keyboardShortcut("n", modifiers: .command)

            Button("打开…") {
                let panel = NSOpenPanel()
                panel.allowsMultipleSelection = false
                panel.canChooseDirectories    = false
                panel.allowedContentTypes     = [.init(filenameExtension: "md")!, .plainText]
                guard panel.runModal() == .OK, let url = panel.url else { return }
                appDelegate.open(url: url, preferredDocument: focusedDocument)
            }
            .keyboardShortcut("o", modifiers: .command)
        }

        CommandGroup(replacing: .saveItem) {
            Button("保存") {
                focusedDocument?.save()
            }
            .keyboardShortcut("s", modifiers: .command)
            .disabled(!(focusedDocument?.isDirty ?? false))

            Button("另存为…") {
                focusedDocument?.saveAs()
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])
            .disabled(focusedDocument == nil)
        }

        CommandMenu("字体") {
            Menu("选择字体") {
                ForEach(EditorStyleSettings.fontCandidates, id: \.self) { family in
                    Button {
                        editorFontFamily = family
                    } label: {
                        if editorFontFamily == family {
                            Label(family, systemImage: "checkmark")
                        } else {
                            Text(family)
                        }
                    }
                }
            }

            Divider()

            Button("增大字号") {
                editorFontSize = min(EditorStyleSettings.maxFontSize, editorFontSize + 1)
            }
            .keyboardShortcut("=", modifiers: .command)

            Button("减小字号") {
                editorFontSize = max(EditorStyleSettings.minFontSize, editorFontSize - 1)
            }
            .keyboardShortcut("-", modifiers: .command)

            Button("重置字号") {
                editorFontSize = EditorStyleSettings.defaultFontSize
            }
            .keyboardShortcut("0", modifiers: .command)
        }
    }
}

private struct MarkdownDocumentFocusedKey: FocusedValueKey {
    typealias Value = MarkdownDocument
}

extension FocusedValues {
    var markdownDocument: MarkdownDocument? {
        get { self[MarkdownDocumentFocusedKey.self] }
        set { self[MarkdownDocumentFocusedKey.self] = newValue }
    }
}
