// BudsBar — template icon for the macOS menu bar
// SPDX-License-Identifier: MIT

import AppKit

@MainActor
enum MenuBarIcon {
    /// Two mirrored TWS earbuds, drawn as a resolution-independent template.
    static let image: NSImage = {
        let image = NSImage(size: NSSize(width: 22, height: 18), flipped: false) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.saveGState()
            defer { context.restoreGState() }
            let bud = CGMutablePath()
            bud.move(to: CGPoint(x: 5, y: 17))
            bud.addCurve(to: CGPoint(x: 10, y: 13),
                         control1: CGPoint(x: 9, y: 17), control2: CGPoint(x: 11, y: 15))
            bud.addLine(to: CGPoint(x: 9, y: 10.5))
            bud.addLine(to: CGPoint(x: 9, y: 3))
            bud.addCurve(to: CGPoint(x: 5.8, y: 3),
                         control1: CGPoint(x: 9, y: 0.6), control2: CGPoint(x: 5.8, y: 0.6))
            bud.addLine(to: CGPoint(x: 5.8, y: 9.5))
            bud.addLine(to: CGPoint(x: 4, y: 9.5))
            bud.addCurve(to: CGPoint(x: 0.8, y: 13),
                         control1: CGPoint(x: 1.8, y: 9.5), control2: CGPoint(x: 0.8, y: 11))
            bud.addCurve(to: CGPoint(x: 5, y: 17),
                         control1: CGPoint(x: 0.8, y: 15.4), control2: CGPoint(x: 2.5, y: 17))
            bud.closeSubpath()
            bud.addEllipse(in: CGRect(x: 3, y: 12.5, width: 2.5, height: 1.7))

            context.setFillColor(NSColor.black.cgColor)
            context.addPath(bud)
            context.fillPath(using: .evenOdd)
            context.translateBy(x: 22, y: 0)
            context.scaleBy(x: -1, y: 1)
            context.addPath(bud)
            context.fillPath(using: .evenOdd)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "BudsBar earbuds"
        return image
    }()
}
