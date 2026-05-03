import AppKit

public struct MarkdownStyleTokens {
    let bodyFont: NSFont
    let boldFont: NSFont
    let italicFont: NSFont
    let boldItalicFont: NSFont
    let codeFont: NSFont
    public let paragraphStyle: NSParagraphStyle

    let textColor: NSColor
    let mutedTextColor: NSColor
    let keywordMarkerColor: NSColor
    let stringTextColor: NSColor
    let hyperlinkTextColor: NSColor
    let linkDestinationColor: NSColor
    let linkLabelColor: NSColor
    let linkTitleColor: NSColor
    let codeFenceLanguageColor: NSColor
    let tableSeparatorColor: NSColor
    let frontMatterDelimiterColor: NSColor

    public init(baseFont: NSFont) {
        self.bodyFont = baseFont
        let size = baseFont.pointSize
        let fontManager = NSFontManager.shared
        self.boldFont = fontManager.font(withFamily: baseFont.familyName ?? "", traits: .boldFontMask, weight: 9, size: size) ?? baseFont
        self.italicFont = fontManager.font(withFamily: baseFont.familyName ?? "", traits: .italicFontMask, weight: 5, size: size) ?? baseFont
        self.boldItalicFont = fontManager.font(withFamily: baseFont.familyName ?? "", traits: [.boldFontMask, .italicFontMask], weight: 9, size: size) ?? baseFont
        self.codeFont = NSFont(name: "JetBrains Mono", size: size)
            ?? NSFont(name: "JetBrainsMono-Regular", size: size)
            ?? NSFont.monospacedSystemFont(ofSize: size, weight: .regular)

        let paragraph = NSMutableParagraphStyle()
        let lineHeight = round(size * 1.34)
        paragraph.minimumLineHeight = lineHeight
        paragraph.maximumLineHeight = lineHeight
        paragraph.paragraphSpacing = round(size * 0.18)
        self.paragraphStyle = paragraph

        self.textColor = NSColor.labelColor
        self.mutedTextColor = NSColor.secondaryLabelColor
        self.keywordMarkerColor = Self.dynamic(
            light: NSColor(red: 0.00, green: 0.20, blue: 0.70, alpha: 1), // IntelliJ Light keyword blue
            dark: NSColor(red: 0.80, green: 0.47, blue: 0.20, alpha: 1)   // Darcula keyword orange
        )
        self.stringTextColor = Self.dynamic(
            light: NSColor(red: 0.02, green: 0.49, blue: 0.09, alpha: 1), // IntelliJ Light string green
            dark: NSColor(red: 0.42, green: 0.67, blue: 0.45, alpha: 1)   // Darcula string green
        )
        self.hyperlinkTextColor = Self.dynamic(
            light: NSColor(red: 0.00, green: 0.27, blue: 0.80, alpha: 1),
            dark: NSColor(red: 0.47, green: 0.62, blue: 0.96, alpha: 1)
        )
        self.linkDestinationColor = Self.dynamic(
            light: NSColor(red: 0.00, green: 0.39, blue: 0.48, alpha: 1),
            dark: NSColor(red: 0.45, green: 0.74, blue: 0.98, alpha: 1)
        )
        self.linkLabelColor = self.keywordMarkerColor
        self.linkTitleColor = self.stringTextColor
        self.codeFenceLanguageColor = Self.dynamic(
            light: NSColor(red: 0.53, green: 0.39, blue: 0.00, alpha: 1),
            dark: NSColor(red: 0.96, green: 0.78, blue: 0.35, alpha: 1)
        )
        self.tableSeparatorColor = Self.dynamic(
            light: NSColor(red: 0.43, green: 0.43, blue: 0.43, alpha: 1),
            dark: NSColor(red: 0.58, green: 0.58, blue: 0.58, alpha: 1)
        )
        self.frontMatterDelimiterColor = self.keywordMarkerColor
    }

    func headerColor(level: Int) -> NSColor {
        switch level {
        case 1, 2:
            return Self.dynamic(
                light: NSColor(red: 0.52, green: 0.16, blue: 0.78, alpha: 1),
                dark: NSColor(red: 0.60, green: 0.46, blue: 0.79, alpha: 1)
            )
        case 3, 4:
            return Self.dynamic(
                light: NSColor(red: 0.48, green: 0.20, blue: 0.74, alpha: 1),
                dark: NSColor(red: 0.62, green: 0.50, blue: 0.82, alpha: 1)
            )
        default:
            return Self.dynamic(
                light: NSColor(red: 0.45, green: 0.24, blue: 0.68, alpha: 1),
                dark: NSColor(red: 0.64, green: 0.53, blue: 0.84, alpha: 1)
            )
        }
    }

    private static func dynamic(light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            let darkNames: [NSAppearance.Name] = [
                .darkAqua, .vibrantDark,
                .accessibilityHighContrastDarkAqua,
                .accessibilityHighContrastVibrantDark
            ]
            return darkNames.contains(appearance.name) ? dark : light
        }
    }
}
