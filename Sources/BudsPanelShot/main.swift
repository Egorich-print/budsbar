// BudsBar — panel preview renderer
// SPDX-License-Identifier: MIT
//
// Renders the real control panel to a PNG using SwiftUI's ImageRenderer,
// with a scripted device state. This gives a faithful picture of the UI
// without needing screen-recording permission or a device in range.
//
//   swift run BudsPanelShot <output.png> [state]

import SwiftUI
import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import BudsCore
import BudsUI

/// A controller stand-in that serves a fixed state to the panel.
@MainActor
final class PreviewController: ObservableObject, BudsViewModel {
    @Published var state = DeviceState()
    @Published var linkState: LinkState = .connected
    @Published var lastError: String?
    /// The stream the system negotiates with the earbuds.
    @Published var codecInfo = AudioCodecInfo(
        codec: "AAC-LC",
        bitrateKbps: 192,
        sampleRate: 44100,
        deviceName: "HUAWEI FreeBuds 6",
        isBluetooth: true
    )

    init(state: DeviceState) {
        self.state = state
    }

    func connect() async {}
    func refresh() async {}
    func refreshCodec() async {}
    func setNoiseMode(_ mode: NoiseMode, level: Int?) async -> Bool {
        state.noiseMode = mode
        if let level { state.cancellationLevel = level }
        return true
    }
    func setEqualizer(_ preset: Int) async -> Bool { state.equalizerPreset = preset; return true }
    func setLowLatency(_ enabled: Bool) async -> Bool { state.lowLatencyEnabled = enabled; return true }
    func setSoundQuality(_ quality: SoundQuality) async -> Bool { state.soundQuality = quality; return true }
    func setDoubleTap(side: EarbudSide, action: Int) async -> Bool {
        if side == .left { state.gestures.doubleTapLeft = action } else { state.gestures.doubleTapRight = action }
        return true
    }
    func setTripleTap(side: EarbudSide, action: Int) async -> Bool {
        if side == .left { state.gestures.tripleTapLeft = action } else { state.gestures.tripleTapRight = action }
        return true
    }
    func setLongTap(side: EarbudSide, action: Int) async -> Bool {
        if side == .left { state.gestures.holdLeft = action } else { state.gestures.holdRight = action }
        return true
    }
    func setAutoPause(_ enabled: Bool) async -> Bool { state.autoPauseEnabled = enabled; return true }
}

@MainActor
func makeState(_ variant: String) -> DeviceState {
    var state = DeviceState()
    state.identity.modelCode = "BTFT0020"
    state.identity.modelCode = "BTFT0020"
    state.identity.firmware = "HarmonyOS 6.1.0.358(F003H003C90)"
    state.identity.serialNumber = "3EDBB25621102105"
    state.battery = BatteryReading(left: 92, right: 88, caseLevel: 74)
    state.isChargingRight = true
    state.availableEqualizerPresets = [0, 2, 3, 9, 11, 12]

    switch variant {
    case "offline":
        state.identity = DeviceIdentity()
        state.battery = BatteryReading()
    case "cancelling":
        state.noiseMode = .cancellation
        // The deepest level is not implemented on this model, so the
        // preview uses one of the levels it really offers.
        state.cancellationLevel = 3
        state.equalizerPreset = 2
        state.lowLatencyEnabled = true
        state.soundQuality = .quality
        state.autoPauseEnabled = true
        state.gestures = GestureSettings(
            doubleTapLeft: 1, doubleTapRight: 2,
            tripleTapLeft: 1, tripleTapRight: 1,
            holdLeft: 10, holdRight: 18,
            noiseCycleLeft: 2, noiseCycleRight: 2,
            availableTapActions: [0, 1, 2, 7, 255],
            availableHoldActions: [0, 10, 18, 19, 255]
        )
    default:
        // The FreeBuds 6 has no transparency mode, so the preview shows the
        // model without it.
        state.noiseMode = .off
        state.cancellationLevel = 0
        state.equalizerPreset = 0
        state.lowLatencyEnabled = false
        state.soundQuality = .connectivity
        state.autoPauseEnabled = true
        state.gestures = GestureSettings(
            doubleTapLeft: 1, doubleTapRight: 1,
            tripleTapLeft: 1, tripleTapRight: 1,
            holdLeft: 10, holdRight: 10,
            noiseCycleLeft: 2, noiseCycleRight: 2,
            availableTapActions: [0, 1, 2, 7, 255],
            availableHoldActions: [0, 10, 18, 19, 255]
        )
    }
    return state
}

@MainActor
func render(variant: String, to path: String) {
    // "live" renders the panel the way the app shows it — with the scroll
    // area — so the real layout can be reviewed, not just the content.
    let scrollable = variant == "live"
    let stateVariant = scrollable ? "connected" : variant
    let controller = PreviewController(state: makeState(stateVariant))
    if variant == "connecting" {
        controller.linkState = .connecting
    }
    // Freeze the connect animation on a chosen phase, so the captured frame
    // is the same every time and shows the gesture in a readable state.
    // The value has to be set on a view *above* the panel, because the panel
    // reads the environment in its own body.
    let frozen = Date(timeIntervalSinceReferenceDate: 1.4)
    let content = Group {
        ControlPanel(controller: controller, scrollable: scrollable)
            .frame(width: 320)
    }
    .environment(\.budsFrozenAnimationDate, variant == "connecting" ? frozen : nil)

    // Render through a real hosting view in an offscreen window rather than
    // `ImageRenderer`: the latter does not resolve SF Symbols, and AppKit
    // backed controls only lay out once they are in a window.
    let hosting = NSHostingView(rootView: content)
    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 320, height: 800),
        styleMask: [.titled],
        backing: .buffered,
        defer: false
    )
    window.contentView = hosting
    // Match the appearance the live app shows on this machine.
    window.appearance = NSApp.effectiveAppearance
    window.orderBack(nil)
    hosting.layoutSubtreeIfNeeded()

    // "live" renders into a window of the size the popover actually gets,
    // so the scrolling layout can be reviewed the way the app shows it.
    if scrollable {
        let height: CGFloat = 601
        hosting.frame = NSRect(x: 0, y: 0, width: 320, height: height)
        window.setContentSize(NSSize(width: 320, height: height))
        hosting.layoutSubtreeIfNeeded()
        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.4))
        hosting.layoutSubtreeIfNeeded()

        guard let png = capture(hosting: hosting, size: hosting.frame.size) else {
            FileHandle.standardError.write(Data("render failed\n".utf8))
            exit(1)
        }
        try? png.write(to: URL(fileURLWithPath: path))
        print("wrote \(path) (\(png.count) bytes, 320x\(Int(height)))")
        return
    }

    // Let the hosting view size itself to the content.
    let fitting = hosting.fittingSize
    hosting.frame = NSRect(x: 0, y: 0, width: fitting.width, height: fitting.height)
    window.setContentSize(hosting.frame.size)
    hosting.layoutSubtreeIfNeeded()

    // A second pass lets controls that size on their first layout settle.
    RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.4))
    hosting.layoutSubtreeIfNeeded()

    guard let png = capture(hosting: hosting, size: fitting) else {
        FileHandle.standardError.write(Data("render failed\n".utf8))
        exit(1)
    }
    try? png.write(to: URL(fileURLWithPath: path))
    print("wrote \(path) (\(png.count) bytes, \(Int(fitting.width))x\(Int(fitting.height)))")
}

/// Capture the view hierarchy into a PNG.
///
/// The panel is drawn with SwiftUI primitives, so a layer-tree capture
/// (`cacheDisplay`) records everything: text, symbols, gradients and the
/// hand-drawn controls. The bitmap is created at twice the logical size so
/// the image stays crisp in a README.
///
/// A vector capture is kept as a fallback: it records AppKit-backed controls
/// that SwiftUI does not draw itself, but it leaves out SwiftUI content.
@MainActor
private func capture(hosting: NSView, size: NSSize) -> Data? {
    let scale: CGFloat = 2
    let pixelWidth = Int(size.width * scale)
    let pixelHeight = Int(size.height * scale)

    if let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: max(1, pixelWidth),
        pixelsHigh: max(1, pixelHeight),
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) {
        // Setting the size in points makes the pixel buffer the scaled size.
        rep.size = size
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        if let png = rep.representation(using: .png, properties: [:]), !png.isEmpty {
            return png
        }
    }

    let pdf = hosting.dataWithPDF(inside: hosting.bounds)
    if !pdf.isEmpty {
        let pixelSize = NSSize(width: size.width * scale, height: size.height * scale)
        if let png = rasterize(pdf: pdf, pixelSize: pixelSize) {
            return png
        }
    }
    return nil
}

/// Rasterize a single-page PDF at the given pixel size.
@MainActor
private func rasterize(pdf: Data, pixelSize: NSSize) -> Data? {
    guard let provider = CGDataProvider(data: pdf as CFData),
          let document = CGPDFDocument(provider),
          let page = document.page(at: 1)
    else { return nil }

    let box = page.getBoxRect(.mediaBox)
    let width = max(1, Int(pixelSize.width))
    let height = max(1, Int(pixelSize.height))
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }

    context.setFillColor(CGColor(gray: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    context.scaleBy(x: scaleFactor(width: width, box: box.width), y: scaleFactor(width: width, box: box.width))
    context.translateBy(x: -box.origin.x, y: -box.origin.y)
    context.drawPDFPage(page)

    guard let image = context.makeImage() else { return nil }
    let out = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(
        out as CFMutableData,
        UTType.png.identifier as CFString,
        1,
        nil
    ) else { return nil }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { return nil }
    return out as Data
}

private func scaleFactor(width: Int, box: CGFloat) -> CGFloat {
    box > 0 ? CGFloat(width) / box : 1
}

// Entry point
let arguments = CommandLine.arguments
let output = arguments.count > 1 ? arguments[1] : "panel.png"
let variant = arguments.count > 2 ? arguments[2] : "connected"

MainActor.assumeIsolated {
    // SF Symbols resolve through the system symbol font, which needs a real
    // application context and at least one turn of the run loop.
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    app.finishLaunching()

    let deadline = Date().addingTimeInterval(1.0)
    while Date() < deadline {
        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
    }

    render(variant: variant, to: output)
}
