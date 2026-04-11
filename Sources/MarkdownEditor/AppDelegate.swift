import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {

    private final class WeakDocumentBox {
        weak var value: MarkdownDocument?
        init(_ value: MarkdownDocument?) { self.value = value }
    }

    private let documents = NSHashTable<AnyObject>.weakObjects()
    private var windowDocuments: [ObjectIdentifier: WeakDocumentBox] = [:]
    private var windowObservationTokens: [ObjectIdentifier: NSObjectProtocol] = [:]
    private var initializedWindows = Set<ObjectIdentifier>()
    private var cascadeSeedTopLeft: NSPoint?
    private weak var activeDocument: MarkdownDocument?
    private var pendingURL: URL?
    private var windowsPendingClose: Set<ObjectIdentifier> = []

    func registerDocument(_ doc: MarkdownDocument) {
        if !documents.allObjects.contains(where: { $0 === doc }) {
            documents.add(doc)
        }
        if let url = pendingURL {
            pendingURL = nil
            open(url: url, preferredDocument: doc)
        }
    }

    func setActiveDocument(_ doc: MarkdownDocument) {
        registerDocument(doc)
        activeDocument = doc
    }

    func currentDocument() -> MarkdownDocument? {
        if let window = NSApp.keyWindow ?? NSApp.mainWindow {
            let key = ObjectIdentifier(window)
            if let doc = windowDocuments[key]?.value {
                return doc
            }
        }
        if let activeDocument { return activeDocument }
        return documents.allObjects.compactMap { $0 as? MarkdownDocument }.last
    }

    func saveCurrentDocument(preferredDocument: MarkdownDocument? = nil) {
        (preferredDocument ?? currentDocument())?.save()
    }

    func saveAsCurrentDocument(preferredDocument: MarkdownDocument? = nil) {
        (preferredDocument ?? currentDocument())?.saveAs()
    }

    func open(url: URL, preferredDocument: MarkdownDocument? = nil) {
        let target = preferredDocument ?? activeDocument ?? currentDocument()
        if let target {
            DispatchQueue.main.async {
                target.open(url: url)
                self.activeDocument = target
                NSApp.activate(ignoringOtherApps: true)
                if let w = NSApp.windows.first(where: { $0.isVisible && !($0 is NSPanel) }) {
                    w.makeKeyAndOrderFront(nil)
                    w.orderFrontRegardless()
                }
            }
        } else {
            pendingURL = url
        }
    }

    func registerWindow(_ window: NSWindow, document: MarkdownDocument) {
        let id = ObjectIdentifier(window)
        windowDocuments[id] = WeakDocumentBox(document)
        setActiveDocument(document)

        if initializedWindows.insert(id).inserted {
            window.toolbarStyle = .unifiedCompact

            // Create a cascading effect for newly created windows.
            if cascadeSeedTopLeft == nil {
                let visible = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
                cascadeSeedTopLeft = NSPoint(x: visible.minX + 120, y: visible.maxY - 120)
            }
            if let seed = cascadeSeedTopLeft {
                cascadeSeedTopLeft = window.cascadeTopLeft(from: seed)
            }

            let token = NotificationCenter.default.addObserver(
                forName: NSWindow.didBecomeKeyNotification,
                object: window,
                queue: .main
            ) { [weak self, weak window] _ in
                guard
                    let self,
                    let window
                else { return }
                let key = ObjectIdentifier(window)
                if let doc = self.windowDocuments[key]?.value {
                    self.activeDocument = doc
                }
            }
            windowObservationTokens[id] = token
            window.delegate = self
        }

        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
        }
    }

    // MARK: - 现代 macOS (10.13+) Finder 右键 / 双击 / 拖拽到 Dock 图标
    // macOS 优先调用这个方法，而非旧版 openFile(filename:String)
    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.last else { return }
        open(url: url)
    }

    // MARK: - 兼容旧版 API（保留作为 fallback）
    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        open(url: URL(fileURLWithPath: filename))
        return true
    }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        if let last = filenames.last {
            open(url: URL(fileURLWithPath: last))
        }
        NSApp.reply(toOpenOrPrint: .success)
    }

    deinit {
        for (_, token) in windowObservationTokens {
            NotificationCenter.default.removeObserver(token)
        }
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        let key = ObjectIdentifier(window)
        windowsPendingClose.remove(key)
        windowDocuments.removeValue(forKey: key)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        let key = ObjectIdentifier(sender)

        guard let doc = windowDocuments[key]?.value else { return true }

        if !doc.isDirty {
            return true
        }

        if doc.fileURL == nil {
            showNewDocumentCloseSheet(for: sender, document: doc, windowKey: key)
        } else {
            showUnsavedChangesAlert(for: sender, document: doc, windowKey: key)
        }

        return false
    }

    private func showNewDocumentCloseSheet(
        for window: NSWindow,
        document: MarkdownDocument,
        windowKey: ObjectIdentifier
    ) {
        let defaultLocation = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory())
        let defaultFileName = document.displayName + ".md"

        var sheet: NSWindow?

        let view = SaveCloseSheetView(
            defaultFileName: defaultFileName,
            defaultLocation: defaultLocation,
            onDelete: { [weak window] in
                guard let window else { return }
                if let s = sheet { window.endSheet(s) }
                // 直接关闭当前窗口，不触发 windowShouldClose
                window.close()
            },
            onCancel: { [weak window] in
                guard let window, let s = sheet else { return }
                window.endSheet(s)
            },
            onSave: { [weak window] url, tags in
                guard let window else { return }
                document.save(to: url)
                // 将 Finder 标签写入文件扩展属性
                let tagNames = tags.map { $0.rawValue }
                if !tagNames.isEmpty {
                    try? (url as NSURL).setResourceValue(tagNames, forKey: .tagNamesKey)
                }
                if let s = sheet { window.endSheet(s) }
                window.close()
            }
        )

        let controller = NSHostingController(rootView: view)
        let sheetWindow = NSWindow(contentViewController: controller)
        sheet = sheetWindow
        window.beginSheet(sheetWindow)
    }

    private func showUnsavedChangesAlert(
        for window: NSWindow,
        document: MarkdownDocument,
        windowKey: ObjectIdentifier
    ) {
        let alert = NSAlert()
        alert.messageText = "保存更改"
        alert.informativeText = "你要保存对\u{201C}\(document.displayName)\u{201D}的更改吗？"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "保存")
        alert.addButton(withTitle: "不保存")
        alert.addButton(withTitle: "取消")

        alert.beginSheetModal(for: window) { response in
            switch response {
            case .alertFirstButtonReturn:
                document.save()
                window.close()
            case .alertSecondButtonReturn:
                window.close()
            default:
                break
            }
        }
    }
}
