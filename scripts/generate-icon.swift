// scripts/generate-icon.swift — renders AppIcon.png (1024×1024) from an
// SF Symbol on a rounded gradient background. Run: swift generate-icon.swift
import AppKit

let side = 1024.0
let image = NSImage(size: NSSize(width: side, height: side))
image.lockFocus()

// Rounded background gradient.
let rect = NSRect(x: 0, y: 0, width: side, height: side)
let gradient = NSGradient(colors: [
    NSColor(calibratedRed: 0.10, green: 0.13, blue: 0.22, alpha: 1),
    NSColor(calibratedRed: 0.04, green: 0.06, blue: 0.12, alpha: 1),
])!
let path = NSBezierPath(roundedRect: rect, xRadius: 220, yRadius: 220)
gradient.draw(in: path, angle: -70)

// Fan symbol, centered.
let symbol = NSImage(systemSymbolName: "fan.fill", accessibilityDescription: nil)!
let symbolSize = side * 0.72
let symbolRect = NSRect(
    x: (side - symbolSize) / 2,
    y: (side - symbolSize) / 2,
    width: symbolSize,
    height: symbolSize
)
NSColor(calibratedRed: 0.33, green: 0.72, blue: 1.0, alpha: 1).set()
if let tuned = symbol.withSymbolConfiguration(.init(pointSize: symbolSize, weight: .light)) {
    tuned.draw(in: symbolRect, from: .zero, operation: .sourceOver, fraction: 1)
}

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write(Data("icon render failed\n".utf8))
    exit(1)
}
try! png.write(to: URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "appicon.png"))
print("wrote appicon.png")