import XCTest
import MarkdownEditorCore

final class MarkdownImageAssetManagerTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MarkdownImageAssetManagerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
        root = nil
    }

    func testSavedDocumentCopiesImageIntoSiblingAssetsDirectory() throws {
        let documentURL = root.appendingPathComponent("Note.md")
        let sourceURL = root.appendingPathComponent("photo one.png")
        try Data("image".utf8).write(to: sourceURL)

        let references = try MarkdownImageAssetManager.references(
            for: [sourceURL],
            documentURL: documentURL
        )

        XCTAssertEqual(
            references,
            [MarkdownImageReference(altText: "photo one.png", markdownPath: "Note.assets/photo%20one.png")]
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("Note.assets/photo one.png").path))
    }

    func testSavedDocumentGeneratesUniqueNameWithoutOverwritingExistingAsset() throws {
        let documentURL = root.appendingPathComponent("Note.md")
        let assetsDirectory = root.appendingPathComponent("Note.assets", isDirectory: true)
        try FileManager.default.createDirectory(at: assetsDirectory, withIntermediateDirectories: true)
        let existingURL = assetsDirectory.appendingPathComponent("photo.png")
        try Data("existing".utf8).write(to: existingURL)

        let sourceDirectory = root.appendingPathComponent("source", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
        let sourceURL = sourceDirectory.appendingPathComponent("photo.png")
        try Data("new".utf8).write(to: sourceURL)

        let references = try MarkdownImageAssetManager.references(
            for: [sourceURL],
            documentURL: documentURL
        )

        XCTAssertEqual(
            references,
            [MarkdownImageReference(altText: "photo.png", markdownPath: "Note.assets/photo-1.png")]
        )
        XCTAssertEqual(try Data(contentsOf: existingURL), Data("existing".utf8))
        XCTAssertEqual(try Data(contentsOf: assetsDirectory.appendingPathComponent("photo-1.png")), Data("new".utf8))
    }

    func testUnsavedDocumentUsesEncodedAbsoluteSourcePath() throws {
        let sourceURL = root.appendingPathComponent("draft image.png")
        try Data("image".utf8).write(to: sourceURL)

        let references = try MarkdownImageAssetManager.references(
            for: [sourceURL],
            documentURL: nil
        )

        XCTAssertEqual(references.first?.altText, "draft image.png")
        XCTAssertTrue(references.first?.markdownPath.hasPrefix("/") == true)
        XCTAssertTrue(references.first?.markdownPath.contains("draft%20image.png") == true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("未命名.assets").path))
    }
}
