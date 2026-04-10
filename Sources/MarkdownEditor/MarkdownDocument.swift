import SwiftUI
import Combine

final class MarkdownDocument: ObservableObject {
    @Published var text: String
    @Published private(set) var isDirty: Bool = false

    private(set) var fileURL: URL?
    private var savedText: String
    private var cancellables = Set<AnyCancellable>()

    init() {
        text      = ""
        savedText = ""

        $text
            .dropFirst()
            .sink { [weak self] newText in
                guard let self else { return }
                self.isDirty = (newText != self.savedText)
            }
            .store(in: &cancellables)
    }

    var displayName: String {
        fileURL?.deletingPathExtension().lastPathComponent ?? "未命名"
    }

    // MARK: - Operations

    func new() {
        fileURL   = nil
        savedText = ""
        text      = ""
        isDirty   = false
    }

    func open(url: URL) {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return }
        fileURL   = url
        savedText = content
        text      = content
        isDirty   = false
    }

    func save() {
        if let url = fileURL {
            write(to: url)
        } else {
            saveAs()
        }
    }

    func saveAs() {
        let panel = NSSavePanel()
        panel.allowedContentTypes  = [.init(filenameExtension: "md")!]
        panel.nameFieldStringValue = displayName + ".md"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        fileURL = url
        write(to: url)
    }

    // MARK: - Private

    private func write(to url: URL) {
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            savedText = text
            isDirty   = false
        } catch {
            isDirty = true

            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "保存失败"
            alert.informativeText = "无法写入文件：\(url.path)\n\(error.localizedDescription)"
            alert.addButton(withTitle: "确定")
            alert.runModal()
        }
    }

}
