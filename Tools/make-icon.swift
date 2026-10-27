// BudsBar — app icon generator
// SPDX-License-Identifier: MIT
//
// Draws the original BudsBar icon: a stylised earbud with a signal arc.
// Run with: swift Tools/make-icon.swift <output.icns>

import AppKit
import Foundation

let size = 1024

func makeImage() -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()

    guard let context = NSGraphicsContext.current?.cgContext else {
        fatalError("no graphics context")
    }

    // Background: rounded square with a vertical gradient.
    let inset = CGFloat(size) * 0.06
    let rect = NSRect(x: inset, y: inset, width: CGFloat(size) - inset * 2, height: CGFloat(size) - inset * 2)
    let background = NSBezierPath(roundedRect: rect, xRadius: CGFloat(size) * 0.22, yRadius: CGFloat(size) * 0.22)

    let gradient = NSGradient(colors: [
        NSColor(srgbRed: 0.13, green: 0.35, blue: 0.78, alpha: 1),
        NSColor(srgbRed: 0.24, green: 0.55, blue: 0.95, alpha: 1)
    ])!
    gradient.draw(in: background, angle: -90)

    context.saveGState()
    context.addPath(background.cgPath)
    context.clip()

    // Signal arcs: three concentric strokes opening to the upper right.
    let centre = CGPoint(x: CGFloat(size) * 0.40, y: CGFloat(size) * 0.44)
    NSColor.white.withAlphaComponent(0.28).setStroke()
    for (index, radius) in [CGFloat(0.30), CGFloat(0.40), CGFloat(0.50)].enumerated() {
        let lineWidth = CGFloat(size) * (index == 2 ? 0.030 : 0.036)
        let path = NSBezierPath()
        path.lineWidth = lineWidth
        path.lineCapStyle = .round
        let r = CGFloat(size) * radius
        path.appendArc(withCenter: centre, radius: r, startAngle: -40, endAngle: 40, clockwise: false)
        path.stroke()
    }

    // Earbud body: a rounded stem with a bulb.
    let bulbCentre = CGPoint(x: CGFloat(size) * 0.40, y: CGFloat(size) * 0.44)
    let bulbRadius = CGFloat(size) * 0.145
    let bulb = NSBezierPath(ovalIn: CGRect(
        x: bulbCentre.x - bulbRadius,
        y: bulbCentre.y - bulbRadius,
        width: bulbRadius * 2,
        height: bulbRadius * 2
    ))
    NSColor.white.setFill()
    bulb.fill()

    let stem = NSBezierPath(roundedRect: NSRect(
        x: bulbCentre.x - CGFloat(size) * 0.052,
        y: bulbCentre.y - CGFloat(size) * 0.30,
        width: CGFloat(size) * 0.104,
        height: CGFloat(size) * 0.22
    ), xRadius: CGFloat(size) * 0.052, yRadius: CGFloat(size) * 0.052)
    stem.fill()

    // Sound wave notch on the bulb.
    let notch = NSBezierPath()
    notch.lineWidth = CGFloat(size) * 0.028
    notch.lineCapStyle = .round
    let n = CGFloat(size) * 0.055
    notch.move(to: CGPoint(x: bulbCentre.x - n, y: bulbCentre.y))
    notch.curve(
        to: CGPoint(x: bulbCentre.x + n, y: bulbCentre.y),
        controlPoint1: CGPoint(x: bulbCentre.x - n * 0.4, y: bulbCentre.y + n * 0.8),
        controlPoint2: CGPoint(x: bulbCentre.x + n * 0.4, y: bulbCentre.y - n * 0.8)
    )
    NSColor(srgbRed: 0.18, green: 0.44, blue: 0.86, alpha: 1).setStroke()
    notch.stroke()

    context.restoreGState()
    image.unlockFocus()
    return image
}

let image = makeImage()

// Write PNG representations, then let iconutil build the .icns.
let work = NSTemporaryDirectory() + "BudsBarIcon-\(UUID().uuidString)"
try? FileManager.default.createDirectory(atPath: work, withIntermediateDirectories: true)
let iconset = work + "/BudsBar.iconset"
try! FileManager.default.createDirectory(atPath: iconset, withIntermediateDirectories: true)

func bitmap(_ size: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    rep.size = NSSize(width: size, height: size)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

for base in [16, 32, 128, 256, 512] {
    for suffix in ["", "@2x"] {
        let pixels = base * (suffix == "@2x" ? 2 : 1)
        let rep = bitmap(pixels)
        let data = rep.representation(using: .png, properties: [:])!
        try! data.write(to: URL(fileURLWithPath: "\(iconset)/icon_\(base)x\(base)\(suffix).png"))
    }
}

let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "BudsBar.icns"
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconset, "-o", output]
try process.run()
process.waitUntilExit()
print("wrote \(output)")
