#!/usr/bin/env swift
import AppKit
import Foundation

let arguments = CommandLine.arguments
guard arguments.count == 2 else {
    FileHandle.standardError.write(Data("Usage: generate-dmg-background.swift <output-png>\n".utf8))
    exit(64)
}

let outputURL = URL(fileURLWithPath: arguments[1])
let canvasSize = NSSize(width: 640, height: 420)

func drawText(_ text: String, rect: NSRect, font: NSFont, color: NSColor, alignment: NSTextAlignment = .center) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = alignment
    paragraph.lineBreakMode = .byWordWrapping
    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: color,
        .paragraphStyle: paragraph
    ]
    text.draw(in: rect, withAttributes: attributes)
}

func strokeArrow(from start: NSPoint, to end: NSPoint, color: NSColor) {
    let path = NSBezierPath()
    path.move(to: start)
    path.line(to: end)
    path.lineWidth = 5
    path.lineCapStyle = .round
    color.setStroke()
    path.stroke()

    let angle = atan2(end.y - start.y, end.x - start.x)
    let arrowLength: CGFloat = 17
    let arrowSpread: CGFloat = .pi / 7

    let head = NSBezierPath()
    head.move(to: end)
    head.line(to: NSPoint(
        x: end.x - arrowLength * cos(angle - arrowSpread),
        y: end.y - arrowLength * sin(angle - arrowSpread)
    ))
    head.move(to: end)
    head.line(to: NSPoint(
        x: end.x - arrowLength * cos(angle + arrowSpread),
        y: end.y - arrowLength * sin(angle + arrowSpread)
    ))
    head.lineWidth = 5
    head.lineCapStyle = .round
    head.stroke()
}

let image = NSImage(size: canvasSize)
image.lockFocus()

NSColor(calibratedRed: 0.965, green: 0.972, blue: 0.984, alpha: 1).setFill()
NSRect(origin: .zero, size: canvasSize).fill()

let panelRect = NSRect(x: 45, y: 49, width: 550, height: 305)
let panelPath = NSBezierPath(roundedRect: panelRect, xRadius: 18, yRadius: 18)
NSColor.white.setFill()
panelPath.fill()

NSColor(calibratedWhite: 0, alpha: 0.08).setStroke()
panelPath.lineWidth = 1
panelPath.stroke()

let accent = NSColor(calibratedRed: 0.11, green: 0.36, blue: 0.86, alpha: 1)
drawText(
    "Install Markdown Editor",
    rect: NSRect(x: 90, y: 325, width: 460, height: 28),
    font: .systemFont(ofSize: 21, weight: .semibold),
    color: NSColor(calibratedRed: 0.10, green: 0.12, blue: 0.16, alpha: 1)
)
drawText(
    "Drag the app to Applications",
    rect: NSRect(x: 120, y: 300, width: 400, height: 22),
    font: .systemFont(ofSize: 13, weight: .regular),
    color: NSColor(calibratedRed: 0.38, green: 0.42, blue: 0.49, alpha: 1)
)

strokeArrow(
    from: NSPoint(x: 215, y: 195),
    to: NSPoint(x: 420, y: 195),
    color: accent
)

drawText(
    "MarkdownEditor.app",
    rect: NSRect(x: 90, y: 82, width: 160, height: 22),
    font: .systemFont(ofSize: 11, weight: .medium),
    color: NSColor(calibratedRed: 0.22, green: 0.25, blue: 0.30, alpha: 1)
)
drawText(
    "Applications",
    rect: NSRect(x: 390, y: 82, width: 160, height: 22),
    font: .systemFont(ofSize: 11, weight: .medium),
    color: NSColor(calibratedRed: 0.22, green: 0.25, blue: 0.30, alpha: 1)
)

drawText(
    "Open the app from Applications after copying.",
    rect: NSRect(x: 130, y: 53, width: 380, height: 18),
    font: .systemFont(ofSize: 9, weight: .regular),
    color: NSColor(calibratedRed: 0.52, green: 0.56, blue: 0.63, alpha: 1)
)

image.unlockFocus()

guard
    let tiff = image.tiffRepresentation,
    let bitmap = NSBitmapImageRep(data: tiff),
    let png = bitmap.representation(
    using: NSBitmapImageRep.FileType.png,
    properties: [NSBitmapImageRep.PropertyKey.compressionFactor: 0.95]
    )
else {
    FileHandle.standardError.write(Data("Failed to render DMG background.\n".utf8))
    exit(1)
}

do {
    try FileManager.default.createDirectory(
        at: outputURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try png.write(to: outputURL, options: Data.WritingOptions.atomic)
} catch {
    FileHandle.standardError.write(Data("Failed to write \(outputURL.path): \(error.localizedDescription)\n".utf8))
    exit(1)
}
