import Foundation

enum EditorStyleSettings {
    static let fontFamilyKey = "editorFontFamily"
    static let fontSizeKey = "editorFontSize"
    static let showLineNumbersKey = "editorShowLineNumbers"

    static let defaultFontFamily = "JetBrains Mono"
    static let defaultFontSize = 14.0
    static let minFontSize = 11.0
    static let maxFontSize = 28.0

    static let fontCandidates: [String] = [
        "JetBrains Mono",
        "SF Mono",
        "Menlo",
        "Monaco",
        "Courier New",
        "Fira Code"
    ]
}
