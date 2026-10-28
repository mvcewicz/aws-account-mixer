// Draws the 1024×1024 app icon: `swift scripts/make-icon.swift <output.png>`
import AppKit

let canvas = 1024.0
let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: Int(canvas), pixelsHigh: Int(canvas),
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// macOS icon grid: 824×824 body on a 1024 canvas, corner radius ~185.
let body = NSRect(x: 100, y: 100, width: 824, height: 824)
let shape = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)

let shadow = NSShadow()
shadow.shadowColor = .black.withAlphaComponent(0.35)
shadow.shadowBlurRadius = 24
shadow.shadowOffset = NSSize(width: 0, height: -12)
NSGraphicsContext.saveGraphicsState()
shadow.set()
NSColor(srgbRed: 0.09, green: 0.13, blue: 0.24, alpha: 1).setFill()
shape.fill()
NSGraphicsContext.restoreGraphicsState()

NSGradient(
    starting: NSColor(srgbRed: 0.20, green: 0.27, blue: 0.45, alpha: 1),
    ending: NSColor(srgbRed: 0.06, green: 0.09, blue: 0.18, alpha: 1)
)!.draw(in: shape, angle: -90)

let configuration = NSImage.SymbolConfiguration(pointSize: 430, weight: .medium)
    .applying(.init(paletteColors: [.white, NSColor(srgbRed: 1.0, green: 0.62, blue: 0.18, alpha: 1)]))
let symbol = NSImage(systemSymbolName: "key.icloud.fill", accessibilityDescription: nil)!
    .withSymbolConfiguration(configuration)!
let size = symbol.size
symbol.draw(in: NSRect(x: (canvas - size.width) / 2, y: (canvas - size.height) / 2 - 10, width: size.width, height: size.height))

NSGraphicsContext.restoreGraphicsState()
try rep.representation(using: .png, properties: [:])!.write(to: URL(filePath: CommandLine.arguments[1]))
