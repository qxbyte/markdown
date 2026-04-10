import SwiftUI

struct FileCommands: Commands {
    @FocusedValue(\.markdownDocument) private var focusedDocument
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
