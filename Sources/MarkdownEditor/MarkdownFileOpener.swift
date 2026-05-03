import AppKit
import Foundation

enum MarkdownFileOpener {
    static func open(_ url: URL, baseURL: URL? = nil) {
        let resolved = resolve(url, baseURL: baseURL)

        if resolved.isFileURL, isMarkdownFile(resolved) {
            if let delegate = NSApp.delegate as? AppDelegate {
                delegate.open(url: resolved)
            } else {
                NSWorkspace.shared.open(resolved)
            }
            return
        }

        NSWorkspace.shared.open(resolved)
    }

    static func resolve(_ url: URL, baseURL: URL?) -> URL {
        guard !url.isFileURL else { return url.standardizedFileURL }

        if let baseURL,
           url.scheme == nil || url.scheme?.isEmpty == true {
            return baseURL.appendingPathComponent(url.relativeString).standardizedFileURL
        }

        return url
    }

    private static func isMarkdownFile(_ url: URL) -> Bool {
        ["md", "markdown", "mdown", "mkd"].contains(url.pathExtension.lowercased())
    }
}
