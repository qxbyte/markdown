import SwiftUI

struct FileCommands: Commands {
    @FocusedValue(\.markdownDocument) private var focusedDocument
    @AppStorage(EditorStyleSettings.fontFamilyKey) private var editorFontFamily: String = EditorStyleSettings.defaultFontFamily
    @AppStorage(EditorStyleSettings.fontSizeKey) private var editorFontSize: Double = EditorStyleSettings.defaultFontSize
    @AppStorage(EditorStyleSettings.showLineNumbersKey) private var showLineNumbers: Bool = false
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
                AppModalPresenter.showOpenPanel(panel) { response in
                    guard response == .OK, let url = panel.url else { return }
                    appDelegate.open(url: url, preferredDocument: focusedDocument)
                }
            }
            .keyboardShortcut("o", modifiers: .command)
        }

        CommandGroup(replacing: .saveItem) {
            Button("保存") {
                appDelegate.saveCurrentDocument(preferredDocument: focusedDocument)
            }
            .keyboardShortcut("s", modifiers: .command)

            Button("另存为…") {
                appDelegate.saveAsCurrentDocument(preferredDocument: focusedDocument)
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])
        }

        CommandMenu("View") {
            Toggle("Show Line Numbers", isOn: $showLineNumbers)
                .keyboardShortcut("l", modifiers: [.command, .shift])
        }

        CommandMenu("Font") {
            Menu("Choose Font") {
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

            Button("Increase Size") {
                editorFontSize = min(EditorStyleSettings.maxFontSize, editorFontSize + 1)
            }
            .keyboardShortcut("=", modifiers: .command)

            Button("Decrease Size") {
                editorFontSize = max(EditorStyleSettings.minFontSize, editorFontSize - 1)
            }
            .keyboardShortcut("-", modifiers: .command)

            Button("Reset Size") {
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
