import AppKit
import SwiftUI

private enum DocumentCloseAction {
    case delete
    case save(URL)
    case cancel
}

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

    func applicationDidFinishLaunching(_ notification: Notification) {
        updateApplicationIcon()
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(interfaceThemeDidChange),
            name: NSNotification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil
        )
    }

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

            // 仅在窗口首次创建时激活并置前，避免后续每次 SwiftUI 更新都重复触发
            DispatchQueue.main.async {
                NSApp.activate(ignoringOtherApps: true)
                window.makeKeyAndOrderFront(nil)
                window.orderFrontRegardless()
            }
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

    @objc private func interfaceThemeDidChange() {
        DispatchQueue.main.async { [weak self] in
            self?.updateApplicationIcon()
        }
    }

    private func updateApplicationIcon() {
        let iconName = isUsingDarkAppearance ? "AppIconDark" : "AppIconLight"
        guard
            let url = Bundle.main.url(forResource: iconName, withExtension: "png")
                ?? Bundle.module.url(forResource: iconName, withExtension: "png"),
            let image = NSImage(contentsOf: url)
        else { return }

        NSApp.applicationIconImage = image
    }

    private var isUsingDarkAppearance: Bool {
        NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    deinit {
        DistributedNotificationCenter.default().removeObserver(
            self,
            name: NSNotification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil
        )
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

        // 用户已在弹窗中确认操作，直接放行
        if windowsPendingClose.contains(key) {
            return true
        }

        guard let doc = windowDocuments[key]?.value else { return true }
        if !doc.isDirty { return true }

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
        // 用枚举记录用户的选择，在 beginSheet completion handler 里统一处理
        // 这与 NSAlert.beginSheetModal 的模式完全一致，保证 sheet 动画结束后再关窗口
        var pendingAction: DocumentCloseAction = .cancel

        let view = SaveCloseSheetView(
            defaultFileName: defaultFileName,
            defaultLocation: defaultLocation,
            onDelete: { [weak window] in
                guard let window, let s = sheet else { return }
                pendingAction = .delete
                window.endSheet(s, returnCode: .abort)
            },
            onCancel: { [weak window] in
                guard let window, let s = sheet else { return }
                window.endSheet(s, returnCode: .cancel)
            },
            onSave: { [weak window] url in
                guard let window, let s = sheet else { return }
                pendingAction = .save(url)
                window.endSheet(s, returnCode: .OK)
            }
        )

        let controller = NSHostingController(rootView: view)
        let sheetWindow = NSWindow(contentViewController: controller)
        sheet = sheetWindow

        // completion handler 在 sheet 动画完全结束后才触发，统一走窗口关闭流程
        window.beginSheet(sheetWindow) { [weak self, weak window] _ in
            guard let self, let window else { return }
            switch pendingAction {
            case .delete:
                self.requestWindowClose(window, windowKey: windowKey)
            case .save(let url):
                document.save(to: url)
                self.requestWindowClose(window, windowKey: windowKey)
            case .cancel:
                break
            }
        }
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

        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self else { return }
            switch response {
            case .alertFirstButtonReturn:
                document.save()
                self.requestWindowClose(window, windowKey: windowKey)
            case .alertSecondButtonReturn:
                self.requestWindowClose(window, windowKey: windowKey)
            default:
                break
            }
        }
    }

    private func requestWindowClose(_ window: NSWindow, windowKey: ObjectIdentifier) {
        windowsPendingClose.insert(windowKey)
        window.performClose(nil)

        // 某些场景下，sheet 回调与关闭时序会导致 performClose 未生效，这里做一次兜底。
        DispatchQueue.main.async { [weak self, weak window] in
            guard let self, let window, window.isVisible else { return }
            self.windowsPendingClose.insert(windowKey)
            window.close()
        }
    }
}
