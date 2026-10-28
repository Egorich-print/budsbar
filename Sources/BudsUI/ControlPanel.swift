// BudsBar — main control panel
// SPDX-License-Identifier: MIT

import SwiftUI
import Foundation
import AppKit
import BudsCore

private struct FrozenAnimationDateKey: EnvironmentKey {
    static let defaultValue: Date? = nil
}

/// Carries the measured height of the scrollable content.
private struct ContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat { 0 }
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// Carries the measured height of the header block.
private struct HeaderHeightKey: PreferenceKey {
    static var defaultValue: CGFloat { 0 }
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
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
    @Environment(\.budsFrozenAnimationDate) private var frozenAnimationDate
    private let scrollable: Bool

    /// Measured height of the scrollable content.
    @State private var contentHeight: CGFloat = 0

    /// Measured height of the header block.
    @State private var headerHeight: CGFloat = 0

    /// The error the user dismissed, so it does not come back on its own.
    @State private var dismissedError: String?

    public init(controller: Model, scrollable: Bool = true) {
        self.controller = controller
        self.scrollable = scrollable
    }

    public var body: some View {
        VStack(spacing: 0) {
            headerBlock
            if let message = activeError {
                errorBanner(message)
            }
            if scrollable {
                scrollArea
            } else {
                PanelContent(controller: controller)
                    .padding(14)
            }
        }
        .frame(width: 320)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(.regularMaterial)
        .onChange(of: controller.lastError) { _, newValue in
            if newValue == nil { dismissedError = nil }
        }
        .onChange(of: contentHeight) { _, newValue in
            resizePanelWindow(contentHeight: newValue)
        }
    }

    // MARK: - Panel sizing

    /// Resizes the popover window so that the panel fits its content.
    ///
    /// The menu bar extra sizes its window once, when the popover appears,
    /// and never touches it again. The window is therefore created with the
    /// height the panel guessed it would need, and a guess that is even a
    /// little too small cuts the last controls off. The content is measured
    /// instead, and the window is resized to match — the measurement happens
    /// while the popover is still being laid out, so the user never sees the
    /// wrong size.
    private func resizePanelWindow(contentHeight: CGFloat) {
        guard contentHeight > 0, let window = panelWindow else { return }
        let target = min(
            effectiveHeaderHeight + contentHeight,
            effectiveHeaderHeight + maxScrollHeight
        )
        guard abs(window.frame.height - target) > 0.5 else { return }
        var frame = window.frame
        frame.size.height = target
        window.setFrame(frame, display: true)
    }

    /// The window that shows the panel.
    ///
    /// The menu bar extra hosts the popover in a window of its own. It is
    /// found by the view it holds: the status bar windows of the app hold
    /// the menu bar item instead.
    private var panelWindow: NSWindow? {
        NSApp.windows.first { window in
            guard let content = window.contentView else { return false }
            return String(describing: type(of: content)).contains("MenuBarExtraHostingView")
        }
    }

    /// Height of the header block.
    ///
    /// The measured value is used once the header has been laid out; until
    /// then the estimate stands in for it.
    private var effectiveHeaderHeight: CGFloat {
        headerHeight > 0 ? headerHeight : 82
    }

    // MARK: - Header

    /// The header and the divider below it.
    ///
    /// The block is measured so that the popover window can be sized from
    /// real numbers instead of a constant that goes stale as soon as the
    /// header changes.
    private var headerBlock: some View {
        VStack(spacing: 0) {
            header
            Divider()
        }
        .background {
            GeometryReader { proxy in
                Color.clear.preference(key: HeaderHeightKey.self, value: proxy.size.height)
            }
        }
        .onPreferenceChange(HeaderHeightKey.self) { height in
            guard height > 0, abs(height - headerHeight) > 0.5 else { return }
            headerHeight = height
        }
    }

    // MARK: - Scroll area

    /// The scrollable body of the panel.
    ///
    /// The height follows the content instead of being a guess. A
    /// `ScrollView` reports an ideal height of roughly zero and the popover
    /// sizes itself to the ideal, so the height has to be given explicitly —
    /// but a fixed guess cuts the last line off as soon as the content grows.
    ///
    /// The content is therefore measured: it is pinned to its natural height
    /// and read back through a preference. Inside a scroll view a plain
    /// `GeometryReader` reports zero, because the scroll view proposes no
    /// height of its own; pinning the content with `fixedSize` gives it one.
    private var scrollArea: some View {
        ScrollView {
            PanelContent(controller: controller)
                .padding(14)
                .fixedSize(horizontal: false, vertical: true)
                .background {
                    GeometryReader { proxy in
                        Color.clear.preference(key: ContentHeightKey.self, value: proxy.size.height)
                    }
                }
        }
        .frame(height: scrollHeight)
        .onPreferenceChange(ContentHeightKey.self) { height in
            guard height > 0, abs(height - contentHeight) > 0.5 else { return }
            contentHeight = height
        }
    }

    /// Height of the scroll area: the content itself, or less when the
    /// screen cannot show it all.
    private var scrollHeight: CGFloat {
        guard contentHeight > 0 else { return maxScrollHeight }
        return min(contentHeight, maxScrollHeight)
    }

    /// The largest height the scroll area may take.
    ///
    /// The panel is a menu-bar popover, so it has to fit on the screen
    /// together with the menu bar. The smallest visible screen is used, so
    /// the panel also fits when it is opened on a smaller display.
    private var maxScrollHeight: CGFloat {
        let screenHeight = NSScreen.screens.map(\.visibleFrame.height).min() ?? 900
        return max(240, screenHeight - 60 - effectiveHeaderHeight)
    }

    // MARK: - Errors

    /// The error to show, unless the user dismissed exactly this one.
    private var activeError: String? {
        guard let error = controller.lastError else { return nil }
        return error == dismissedError ? nil : error
    }

    /// A compact notice that the earbuds refused or missed a change.
    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 10))
                .foregroundStyle(.orange)
            Text(message)
                .font(.system(size: 11))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Button {
                dismissedError = message
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Dismiss")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.14))
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
