// BudsBar — the earbud, drawn
// SPDX-License-Identifier: MIT
//
// The system symbol for "ear" is an ear, and it does not belong next to a
// battery percentage in a menu bar. The bud itself is drawn here instead:
// a rounded body that tapers into a short stem. The same shape is used in
// the menu bar, in the panel header and in the section titles, so the app
// speaks with one voice.

import SwiftUI

/// The shape of an earbud, in a 24 by 24 box.
///
/// The silhouette is the one everybody recognises: a rounded head with a
/// straight stem that hangs off it. A round head on a thin stalk would
/// read as a mushroom, so the head is a little taller than it is wide and
/// the stem leans with the whole bud.
struct BudShape: Shape {
    /// How far the bud leans, in degrees.
    var tilt: Double = -12

    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / 24
        let mid = CGFloat(12.0)

        var bud = Path()
        // The head that sits in the ear.
        bud.move(to: CGPoint(x: mid, y: 2.2))
        bud.addCurve(
            to: CGPoint(x: 16.6, y: 8.4),
            control1: CGPoint(x: 14.8, y: 2.4),
            control2: CGPoint(x: 16.4, y: 5.0)
        )
        bud.addCurve(
            to: CGPoint(x: mid + 2.0, y: 13.6),
            control1: CGPoint(x: 16.9, y: 10.9),
            control2: CGPoint(x: 15.4, y: 12.9)
        )
        // The stem.
        bud.addLine(to: CGPoint(x: mid + 2.0, y: 19.2))
        bud.addQuadCurve(
            to: CGPoint(x: mid, y: 20.8),
            control: CGPoint(x: mid + 2.0, y: 20.4)
        )
        bud.addLine(to: CGPoint(x: mid - 2.0, y: 19.0))
        bud.addLine(to: CGPoint(x: mid - 2.0, y: 13.6))
        // Back up into the head.
        bud.addCurve(
            to: CGPoint(x: 7.4, y: 8.4),
            control1: CGPoint(x: 8.6, y: 12.9),
            control2: CGPoint(x: 7.6, y: 10.9)
        )
        bud.addCurve(
            to: CGPoint(x: mid, y: 2.2),
            control1: CGPoint(x: 7.6, y: 5.0),
            control2: CGPoint(x: 9.2, y: 2.4)
        )
        bud.closeSubpath()

        let center = CGPoint(x: 12, y: 12)
        let transform = CGAffineTransform(translationX: center.x, y: center.y)
            .rotated(by: tilt * .pi / 180)
            .translatedBy(x: -center.x, y: -center.y)
            .scaledBy(x: scale, y: scale)
        var path = Path()
        path.addPath(bud, transform: transform)
        return path
    }
}

/// The earbud of the app.
public struct EarbudIcon: View {
    /// Draw the bud solid rather than as an outline.
    public var filled: Bool
    /// The colour of the bud.
    public var style: Color

    public init(filled: Bool = true, style: Color = .primary) {
        self.filled = filled
        self.style = style
    }

    public var body: some View {
        Group {
            if filled {
                BudShape()
                    .fill(style)
            } else {
                BudShape()
                    .stroke(style, lineWidth: 1.6)
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
}
