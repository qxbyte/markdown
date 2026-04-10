import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {

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
        if let activeDocument { return activeDocument }
        return documents.allObjects.compactMap { $0 as? MarkdownDocument }.last
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
}
