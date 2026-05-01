import Foundation

public struct MarkdownImageReference: Equatable {
    public let altText: String
    public let markdownPath: String

    public init(altText: String, markdownPath: String) {
        self.altText = altText
        self.markdownPath = markdownPath
    }
}

public enum MarkdownImageAssetManager {
    public static func references(
        for sourceURLs: [URL],
        documentURL: URL?,
        fileManager: FileManager = .default
    ) throws -> [MarkdownImageReference] {
        guard let documentURL else {
            return sourceURLs.map { sourceURL in
                MarkdownImageReference(
                    altText: altText(for: sourceURL),
                    markdownPath: encodedPath(sourceURL.path)
                )
            }
        }

        let documentDirectory = documentURL.deletingLastPathComponent()
        let assetsDirectoryName = documentURL.deletingPathExtension().lastPathComponent + ".assets"
        let assetsDirectory = documentDirectory.appendingPathComponent(assetsDirectoryName, isDirectory: true)

        try fileManager.createDirectory(at: assetsDirectory, withIntermediateDirectories: true)

        return try sourceURLs.map { sourceURL in
            let destinationURL = uniqueDestinationURL(
                for: sourceURL,
                in: assetsDirectory,
                fileManager: fileManager
            )

            if !sameFile(sourceURL, destinationURL) {
                try fileManager.copyItem(at: sourceURL, to: destinationURL)
            }

            let relativePath = encodedPath("\(assetsDirectoryName)/\(destinationURL.lastPathComponent)")
            return MarkdownImageReference(
                altText: altText(for: sourceURL),
                markdownPath: relativePath
            )
        }
    }

    private static func uniqueDestinationURL(
        for sourceURL: URL,
        in directory: URL,
        fileManager: FileManager
    ) -> URL {
        let fileName = sourceURL.deletingPathExtension().lastPathComponent
        let fileExtension = sourceURL.pathExtension
        var candidate = directory.appendingPathComponent(sourceURL.lastPathComponent, isDirectory: false)

        if !fileManager.fileExists(atPath: candidate.path) || sameFile(sourceURL, candidate) {
            return candidate
        }

        var suffix = 1
        repeat {
            let uniqueName = fileExtension.isEmpty
                ? "\(fileName)-\(suffix)"
                : "\(fileName)-\(suffix).\(fileExtension)"
            candidate = directory.appendingPathComponent(uniqueName, isDirectory: false)
            suffix += 1
        } while fileManager.fileExists(atPath: candidate.path)

        return candidate
    }

    private static func sameFile(_ lhs: URL, _ rhs: URL) -> Bool {
        lhs.standardizedFileURL.path == rhs.standardizedFileURL.path
    }

    private static func altText(for url: URL) -> String {
        url.lastPathComponent
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "]", with: "\\]")
    }

    private static func encodedPath(_ path: String) -> String {
        path.split(separator: "/", omittingEmptySubsequences: false)
            .map { encodePathComponent(String($0)) }
            .joined(separator: "/")
    }

    private static func encodePathComponent(_ component: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return component.addingPercentEncoding(withAllowedCharacters: allowed) ?? component
    }
}
