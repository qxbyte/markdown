import AppKit

enum AppModalPresenter {
    static func activeWindow(preferred view: NSView? = nil) -> NSWindow? {
        if let window = view?.window {
            return window
        }
        if let window = NSApp.keyWindow ?? NSApp.mainWindow, !(window is NSPanel) {
            return window
        }
        return NSApp.windows.first { $0.isVisible && !($0 is NSPanel) }
    }

    static func showAlert(_ alert: NSAlert, preferred view: NSView? = nil, completion: ((NSApplication.ModalResponse) -> Void)? = nil) {
        if let window = activeWindow(preferred: view) {
            alert.beginSheetModal(for: window) { response in
                completion?(response)
            }
            return
        }

        let response = alert.runModal()
        completion?(response)
    }

    static func showOpenPanel(_ panel: NSOpenPanel, preferred view: NSView? = nil, completion: @escaping (NSApplication.ModalResponse) -> Void) {
        if let window = activeWindow(preferred: view) {
            panel.beginSheetModal(for: window, completionHandler: completion)
        } else {
            completion(panel.runModal())
        }
    }

    static func showSavePanel(_ panel: NSSavePanel, preferred view: NSView? = nil, completion: @escaping (NSApplication.ModalResponse) -> Void) {
        if let window = activeWindow(preferred: view) {
            panel.beginSheetModal(for: window, completionHandler: completion)
        } else {
            completion(panel.runModal())
        }
    }
}
