// BudsBar — main control panel
// SPDX-License-Identifier: MIT

import SwiftUI
import BudsCore

private struct FrozenAnimationDateKey: EnvironmentKey {
    static let defaultValue: Date? = nil
}

/// Freezes the connect animation at a given instant.
///
/// The animation normally follows the wall clock. The documentation renderer
/// sets this so a captured frame is deterministic instead of landing on a
/// random phase of the sweep.
public extension EnvironmentValues {
    var budsFrozenAnimationDate: Date? {
        get { self[FrozenAnimationDateKey.self] }
        set { self[FrozenAnimationDateKey.self] = newValue }
    }
}

/// The popover panel shown from the menu bar.
public struct ControlPanel<Model: BudsViewModel>: View {
    @ObservedObject var controller: Model
    @StateObject private var volume = VolumeModel()
    @Environment(\.budsFrozenAnimationDate) private var frozenAnimationDate
    private let scrollable: Bool

    public init(controller: Model, scrollable: Bool = true) {
        self.controller = controller
        self.scrollable = scrollable
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if scrollable {
                ScrollView {
                    PanelContent(controller: controller)
                        .padding(14)
                }
            } else {
                PanelContent(controller: controller)
                    .padding(14)
            }
        }
        .frame(width: 320)
        .background(.regularMaterial)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                if controller.linkState == .connecting {
                    // A rotating sweep plus expanding rings: the panel is
                    // negotiating with the earbuds.
                    TimelineView(.animation) { context in
                        let t = (frozenAnimationDate ?? context.date)
                            .timeIntervalSinceReferenceDate
                        SweepRing(progress: t.truncatingRemainder(dividingBy: 1.6) / 1.6)
                        ForEach(0..<3, id: \.self) { index in
                            ExpandingRing(progress: t.truncatingRemainder(dividingBy: 1.8) / 1.8, index: index)
                        }
                    }
                }
                EarbudGlyph(
                    phase: phase,
                    noiseMode: controller.state.noiseMode,
                    bloom: bloomAmount
                )
                if controller.linkState == .connecting {
                    NoiseWaves(mode: nil, phase: wavePhase)
                        .offset(x: 30)
                }
            }
            .frame(width: 56, height: 56)

            VStack(alignment: .leading, spacing: 2) {
                Text(deviceTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Text(statusSubtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if controller.linkState == .connected {
                Button {
                    Task { await controller.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.borderless)
                .help("Refresh from the earbuds")
            } else {
                Button("Connect") {
                    Task { await controller.connect() }
                }
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var deviceTitle: String {
        controller.state.identity.displayName
    }

    private var statusSubtitle: String {
        switch controller.linkState {
        case .idle: "Not connected"
        case .connecting: "Connecting…"
        case .connected:
            controller.state.identity.modelCode.map { "Model \($0)" } ?? "Connected"
        case .failed: "Disconnected"
        }
    }

    private var phase: LinkPhase {
        switch controller.linkState {
        case .connected: .online
        case .connecting: .connecting
        default: .offline
        }
    }

    @State private var connectProgress: Double = 0
    @State private var wavePhase: Double = 0

    /// The halo behind the glyph brightens when noise control is engaged.
    private var bloomAmount: Double {
        switch controller.state.noiseMode {
        case .cancellation: 1
        case .awareness: 0.7
        default: 0
        }
    }
}

/// A titled card that groups related controls.
struct SectionCard<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .kerning(0.4)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A key/value line in the device section.
struct InfoLine: View {
    let label: String
    let value: String?

    var body: some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 58, alignment: .leading)
            Text(value ?? "—")
                .font(.system(size: 11))
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}

/// A row of pickers, one per earbud.
struct GestureRow: View {
    let title: String
    let left: Int?
    let right: Int?
    let options: [Int]
    let titleFor: (Int) -> String
    let onChange: (EarbudSide, Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                picker(for: .left, value: left)
                picker(for: .right, value: right)
            }
        }
    }

    private func picker(for side: EarbudSide, value: Int?) -> some View {
        ValueMenu(
            options: optionValues.map { ChoiceOption(value: $0, title: titleFor($0)) },
            selection: Binding(
                get: { value ?? -1 },
                set: { onChange(side, $0) }
            ),
            label: "\(title), \(side == .left ? "left" : "right")"
        )
    }

    private var optionValues: [Int] {
        options.isEmpty ? [-1, 0, 1, 2, 7, 255] : options
    }
}
