// BudsBar — original motion design
// SPDX-License-Identifier: MIT
//
// All artwork and motion in this project is original to this project.
//
// The design language was informed by studying the general motion vocabulary
// of modern Bluetooth device interfaces — a rotating conic sweep while
// connecting, expanding rings that hand off to a steady state, waves that
// collapse inward when noise control engages. The specific geometry,
// palette, timing curve and rendering technique below are our own.

import SwiftUI
import BudsCore

/// Phase of the earbud indicator, used to drive the connect and disconnect
/// animations.
public enum LinkPhase: Equatable, Sendable {
    case offline
    case connecting
    case online
}

/// A rotating conic sweep — the "working" indicator shown while the app is
/// negotiating with the earbuds.
///
/// Rendered as a conic gradient masked into a ring and spun around its
/// centre. The sweep has a bright leading edge and a long fading tail, so the
/// direction of travel is legible at a glance.
struct SweepRing: View {
    /// 0...1 phase of the rotation.
    var progress: Double
    /// Ring thickness in points.
    var thickness: CGFloat = 3

    var body: some View {
        Circle()
            .trim(from: 0, to: 0.28)
            .stroke(
                AngularGradient(
                    colors: [
                        .accentColor.opacity(0),
                        .accentColor.opacity(0.25),
                        .accentColor.opacity(0.9),
                        .accentColor
                    ],
                    center: .center,
                    angle: .degrees(progress * 360)
                ),
                style: .init(lineWidth: thickness, lineCap: .round)
            )
            .rotationEffect(.degrees(progress * 360))
    }
}

/// A ring that expands and fades — one beat of the connect handshake.
///
/// Three of these are staggered to read as a single outward wave.
struct ExpandingRing: View {
    /// 0...1 progress of the whole gesture.
    var progress: Double
    /// Which ring this is (0 = innermost).
    var index: Int
    /// Delay before this ring starts, in seconds.
    var stagger: Double = 0.18
    /// How long a single ring takes to expand.
    var duration: Double = 0.72

    private var local: Double {
        let start = Double(index) * stagger
        return min(max((progress - start) / duration, 0), 1)
    }

    var body: some View {
        Circle()
            .strokeBorder(Color.accentColor.opacity(0.55), lineWidth: 1.5)
            .scaleEffect(0.5 + 1.6 * easeOut(local))
            .opacity((1 - local) * 0.75)
    }

    /// Cubic ease-out: fast departure, gentle arrival.
    private func easeOut(_ t: Double) -> Double {
        1 - pow(1 - t, 3)
    }
}

/// The central earbud glyph with a soft halo that blooms when noise
/// cancellation is engaged.
struct EarbudGlyph: View {
    var phase: LinkPhase
    var noiseMode: NoiseMode?
    /// 0...1 bloom of the halo.
    var bloom: Double

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [haloColor.opacity(0.5 * bloom), .clear],
                        center: .center,
                        startRadius: 2,
                        endRadius: 28
                    )
                )
                .frame(width: 56, height: 56)

            EarbudIcon(filled: isFilled, style: glyphColor)
                .frame(width: 24, height: 24)
                .accessibilityLabel(accessibilityLabel)
        }
        .frame(width: 56, height: 56)
    }

    /// The bud is solid while it is cancelling, and an outline otherwise.
    private var isFilled: Bool {
        switch phase {
        case .online: noiseMode == .cancellation
        default: false
        }
    }

    private var glyphColor: Color {
        switch phase {
        case .offline: .secondary
        case .connecting: .accentColor
        case .online:
            switch noiseMode {
            case .awareness: .orange
            case .cancellation: .accentColor
            default: .primary
            }
        }
    }

    /// What the glyph says out loud.
    private var accessibilityLabel: String {
        switch phase {
        case .offline: "Earbuds"
        case .connecting: "Connecting"
        case .online:
            switch noiseMode {
            case .cancellation: "Noise cancelling"
            case .awareness: "Transparency"
            default: "Noise off"
            }
        }
    }

    private var haloColor: Color {
        switch noiseMode {
        case .awareness: .orange
        default: .accentColor
        }
    }
}

/// Horizontal wave strokes that drift past the glyph, and collapse inward
/// when noise cancellation engages.
struct NoiseWaves: View {
    var mode: NoiseMode?
    /// 0...1 how far the waves have travelled.
    var phase: Double

    var body: some View {
        Canvas { context, size in
            let rows = 3
            let collapsed = mode == .cancellation
            for row in 0..<rows {
                let offset = CGFloat(row) * 7 - 7
                let travel = CGFloat((phase * 22).truncatingRemainder(dividingBy: 22))
                let y = size.height / 2 + offset
                let span: CGFloat = collapsed ? 6 : 13
                let shift: CGFloat = collapsed ? 0 : travel
                var path = Path()
                path.move(to: CGPoint(x: -span / 2 + shift, y: y))
                path.addCurve(
                    to: CGPoint(x: span / 2 + shift, y: y),
                    control1: CGPoint(x: -span / 4 + shift, y: y - 4),
                    control2: CGPoint(x: span / 4 + shift, y: y + 4)
                )
                context.stroke(
                    path,
                    with: .color(waveColor.opacity(collapsed ? 0.9 : 0.4)),
                    lineWidth: 1.5
                )
            }
        }
        .frame(width: 44, height: 30)
    }

    private var waveColor: Color {
        switch mode {
        case .awareness: .orange
        case .cancellation: .accentColor
        default: .secondary
        }
    }
}

/// A small equaliser bar graph that morphs between presets.
struct BandGraph: View {
    var preset: Int?

    /// Height profile for each supported preset, in points.
    private func profile(for preset: Int) -> [CGFloat] {
        switch preset {
        case 2: [4, 12, 18, 10, 5]   // bass
        case 3: [4, 8, 12, 17, 8]     // treble
        case 9: [6, 11, 16, 11, 6]    // voices
        default: [4, 10, 16, 10, 4]   // flat
        }
    }

    var body: some View {
        Canvas { context, size in
            let target = profile(for: preset ?? 0)
            let count = target.count
            let barWidth: CGFloat = 2
            let gap: CGFloat = 3
            let totalWidth = CGFloat(count) * barWidth + CGFloat(count - 1) * gap
            let originX = (size.width - totalWidth) / 2
            let baseY = size.height - 2

            for index in 0..<count {
                let height = target[index]
                let rect = CGRect(
                    x: originX + CGFloat(index) * (barWidth + gap),
                    y: baseY - height,
                    width: barWidth,
                    height: height
                )
                context.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(.accentColor.opacity(0.85)))
            }
        }
        .frame(width: 30, height: 18)
    }
}

/// A circular level arc that fills as the volume rises.
struct LevelArc: View {
    /// 0...1 level.
    var level: Double
    /// 0...1 growth progress of the arc.
    var progress: Double
    /// Outer size of the arc, in points.
    var size: CGFloat = 34
    /// Stroke width of the arc, in points.
    var lineWidth: CGFloat = 2.5

    private var filled: Double { min(max(level, 0), 1) * min(max(progress, 0), 1) }

    var body: some View {
        ZStack {
            Circle()
                .trim(from: 0, to: 0.667)
                .stroke(Color.secondary.opacity(0.18), style: .init(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(150))

            Circle()
                .trim(from: 0, to: 0.667 * filled)
                .stroke(
                    AngularGradient(
                        colors: filled > 0.85 ? [Color.accentColor, .red] : [Color.accentColor, Color.accentColor.opacity(0.7)],
                        center: .center
                    ),
                    style: .init(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(150))
        }
        .frame(width: size, height: size)
    }
}

/// A pill showing one battery reading.
struct BatteryPill: View {
    var label: String
    var level: Int?
    var isCharging: Bool

    var body: some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2.5)
                    .strokeBorder(Color.secondary.opacity(0.45), lineWidth: 1)
                    .frame(width: 22, height: 11)
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(fillColor)
                    .frame(width: max(0, 18 * fraction), height: 7)
                    .padding(.leading, 1.5)
                if isCharging {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 6))
                        .foregroundStyle(.white)
                        .offset(x: 7)
                }
            }
            .frame(width: 22, height: 11)
            Text(level.map { "\($0)%" } ?? "—")
                .font(.system(size: 10, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(levelTextColor)
        }
    }

    private var fraction: Double {
        guard let level else { return 0 }
        return Double(level) / 100
    }

    private var fillColor: Color {
        guard let level else { return .clear }
        if level <= 15 { return .red }
        if level <= 30 { return .orange }
        return .accentColor
    }

    private var levelTextColor: Color {
        guard let level else { return .secondary }
        if level <= 15 { return .red }
        return .primary
    }
}
