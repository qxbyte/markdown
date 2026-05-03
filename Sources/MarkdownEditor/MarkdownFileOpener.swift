import AppKit
import Foundation

enum MarkdownFileOpener {
    static func open(_ url: URL, baseURL: URL? = nil) {
        let resolved = resolve(url, baseURL: baseURL)
        // Drop URLs that couldn't be fully resolved (no scheme, no baseURL)
        guard let scheme = resolved.scheme, !scheme.isEmpty else { return }

        if resolved.isFileURL {
            if isMarkdownFile(resolved) {
                if let delegate = NSApp.delegate as? AppDelegate {
                    delegate.open(url: resolved)
                } else {
                    NSWorkspace.shared.open(resolved)
                }
            } else {
                NSWorkspace.shared.open(resolved)
            }
            return
        }

        NSWorkspace.shared.open(resolved)
    }

    static func resolve(_ url: URL, baseURL: URL?) -> URL {
        if url.isFileURL { return url.standardizedFileURL }

        if let baseURL, url.scheme == nil || url.scheme?.isEmpty == true {
            // Use url.path (percent-decoded) so appendingPathComponent handles spaces correctly
            let component = url.path.isEmpty ? url.relativeString : url.path
            return baseURL.appendingPathComponent(component).standardizedFileURL
        }

        return url
    }

    private static func isMarkdownFile(_ url: URL) -> Bool {
        ["md", "markdown", "mdown", "mkd"].contains(url.pathExtension.lowercased())
    }
}
