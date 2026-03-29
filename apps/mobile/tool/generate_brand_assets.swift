import AppKit
import Foundation

let fileManager = FileManager.default
let root = URL(fileURLWithPath: fileManager.currentDirectoryPath)
let brandingDir = root.appendingPathComponent("assets/branding", isDirectory: true)

try fileManager.createDirectory(at: brandingDir, withIntermediateDirectories: true)

let wordmarkURL = brandingDir.appendingPathComponent("wishiz_wordmark.png")
let iconURL = brandingDir.appendingPathComponent("wishiz_icon_1024.png")

let background = NSColor.white
let textColor = NSColor(calibratedRed: 108 / 255, green: 111 / 255, blue: 247 / 255, alpha: 1)
let shadowColor = NSColor(calibratedWhite: 0.12, alpha: 0.85)
let fontName = "HelveticaNeue-Bold"

func makeBitmap(size: NSSize) -> NSBitmapImageRep {
    NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(size.width),
        pixelsHigh: Int(size.height),
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
}

func savePNG(rep: NSBitmapImageRep, to url: URL) throws {
    let data = rep.representation(using: .png, properties: [:])!
    try data.write(to: url)
}

func drawWordmark(
    text: String,
    canvasSize: NSSize,
    backgroundColor: NSColor?,
    fontSize: CGFloat,
    destination: URL
) throws {
    let rep = makeBitmap(size: canvasSize)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    if let backgroundColor {
        backgroundColor.setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: canvasSize)).fill()
    } else {
        NSColor.clear.setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: canvasSize)).fill()
    }

    let font = NSFont(name: fontName, size: fontSize) ?? .boldSystemFont(ofSize: fontSize)
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center

    let textSize = (text as NSString).size(withAttributes: [.font: font])
    let textRect = NSRect(
        x: (canvasSize.width - textSize.width) / 2,
        y: (canvasSize.height - textSize.height) / 2 - fontSize * 0.08,
        width: textSize.width,
        height: textSize.height
    )

    let shadow = NSShadow()
    shadow.shadowColor = shadowColor
    shadow.shadowOffset = NSSize(width: 7, height: -5)
    shadow.shadowBlurRadius = 0

    let shadowAttributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: NSColor.black.withAlphaComponent(0.01),
        .paragraphStyle: paragraph,
        .shadow: shadow,
    ]
    (text as NSString).draw(in: textRect, withAttributes: shadowAttributes)

    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: textColor,
        .paragraphStyle: paragraph,
    ]
    (text as NSString).draw(in: textRect, withAttributes: attributes)

    NSGraphicsContext.restoreGraphicsState()
    try savePNG(rep: rep, to: destination)
}

try drawWordmark(
    text: "Wishiz",
    canvasSize: NSSize(width: 2048, height: 512),
    backgroundColor: nil,
    fontSize: 340,
    destination: wordmarkURL
)

try drawWordmark(
    text: "Wishiz",
    canvasSize: NSSize(width: 1024, height: 1024),
    backgroundColor: background,
    fontSize: 220,
    destination: iconURL
)

print("Generated \(wordmarkURL.path)")
print("Generated \(iconURL.path)")
