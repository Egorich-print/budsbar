// BudsBar — headless diagnostic
// SPDX-License-Identifier: MIT
//
// Runs the same protocol code as the app and prints what the earbuds
// report. Useful for verifying a device without opening the UI.
//
//   swift run BudsProbe
//   swift run BudsProbe --write      also exercises one write per feature

import Foundation
import BudsCore

@main
struct BudsProbe {
    static func main() {
        // `IOBluetoothRFCOMMChannel` delivers its delegate callbacks on the
        // main thread's NSRunLoop. An `async main` does not pump that run
        // loop, so the callbacks would never arrive and the probe would hang
        // waiting for the channel to open. Run the work as a main-actor task
        // and keep the run loop turning underneath it.
        Task { @MainActor in
            await run()
        }
        RunLoop.current.run()
    }

    @MainActor
    static func run() async {
        let wantsWrite = CommandLine.arguments.contains("--write")
        let controller = DeviceController()

        print("BudsBar probe — connecting…")
        await controller.connect()

        switch controller.linkState {
        case .failed(let message):
            print("FAILED: \(message)")
            exit(1)
        case .idle:
            print("FAILED: link never started")
            exit(1)
        default:
            break
        }

        let state = controller.state
        print("")
        print("identity")
        print("  model code : \(state.identity.modelCode ?? "—")")
        print("  name       : \(state.identity.displayName)")
        print("  build id   : \(state.identity.buildId ?? "—")")
        print("  firmware   : \(state.identity.firmware ?? "—")")
        print("  serial     : \(state.identity.serialNumber ?? "—")")
        print("  left sn    : \(state.identity.leftSerial ?? "—")")
        print("  right sn   : \(state.identity.rightSerial ?? "—")")
        print("")
        print("battery")
        print("  left       : \(state.battery.left.map { "\($0)%" } ?? "—")  charging=\(state.isChargingLeft)")
        print("  right      : \(state.battery.right.map { "\($0)%" } ?? "—")  charging=\(state.isChargingRight)")
        print("  case       : \(state.battery.caseLevel.map { "\($0)%" } ?? "—")  charging=\(state.isChargingCase)")
        print("")
        print("features")
        print("  noise mode : \(state.noiseMode?.title ?? "—")  level=\(state.cancellationLevel.map(String.init) ?? "—")")
        print("  equalizer  : \(state.equalizerPreset.map { EqualizerPreset.title(for: $0) } ?? "—")  available=\(state.availableEqualizerPresets)")
        print("  low latency: \(state.lowLatencyEnabled.map(String.init) ?? "—")")
        print("  sound qual : \(state.soundQuality?.title ?? "—")")
        print("  auto pause : \(state.autoPauseEnabled.map(String.init) ?? "—")")
        print("  dual conn  : \(state.dualConnectEnabled.map(String.init) ?? "—")")
        print("  dbl tap    : L=\(state.gestures.doubleTapLeft.map(String.init) ?? "—") R=\(state.gestures.doubleTapRight.map(String.init) ?? "—") options=\(state.gestures.availableTapActions)")
        print("  trp tap    : L=\(state.gestures.tripleTapLeft.map(String.init) ?? "—") R=\(state.gestures.tripleTapRight.map(String.init) ?? "—")")
        print("  hold       : L=\(state.gestures.holdLeft.map(String.init) ?? "—") R=\(state.gestures.holdRight.map(String.init) ?? "—") options=\(state.gestures.availableHoldActions)")
        print("  noise cycle: L=\(state.gestures.noiseCycleLeft.map(String.init) ?? "—") R=\(state.gestures.noiseCycleRight.map(String.init) ?? "—")")

        if wantsWrite {
            print("")
            print("write round trip")
            let originalMode = state.noiseMode ?? .off
            let target: NoiseMode = originalMode == .cancellation ? .awareness : .cancellation
            print("  set noise mode → \(target.title)")
            let okMode = await controller.setNoiseMode(target)
            print("    applied    → \(okMode ? "yes" : "NO")")
            print("    read back   → \(controller.state.noiseMode?.title ?? "—")")
            await controller.setNoiseMode(originalMode)
            print("  restored     → \(controller.state.noiseMode?.title ?? "—")")

            if let preset = state.equalizerPreset {
                let other = state.availableEqualizerPresets.first { $0 != preset } ?? preset
                print("  set equalizer → \(EqualizerPreset.title(for: other))")
                let okEq = await controller.setEqualizer(other)
                print("    applied    → \(okEq ? "yes" : "NO")")
                print("    read back   → \(controller.state.equalizerPreset.map { EqualizerPreset.title(for: $0) } ?? "—")")
                await controller.setEqualizer(preset)
                print("  restored     → \(controller.state.equalizerPreset.map { EqualizerPreset.title(for: $0) } ?? "—")")
            }

            let latency = state.lowLatencyEnabled ?? false
            print("  set low latency → \((!latency))")
            let okLat = await controller.setLowLatency(!latency)
            print("    applied    → \(okLat ? "yes" : "NO")")
            print("    read back   → \(controller.state.lowLatencyEnabled.map(String.init) ?? "—")")
            await controller.setLowLatency(latency)
            print("  restored     → \(controller.state.lowLatencyEnabled.map(String.init) ?? "—")")

            if let quality = state.soundQuality {
                let other: SoundQuality = quality == .quality ? .connectivity : .quality
                print("  set sound quality → \(other.title)")
                let okQual = await controller.setSoundQuality(other)
                print("    applied    → \(okQual ? "yes" : "NO")")
                print("    read back   → \(controller.state.soundQuality?.title ?? "—")")
                await controller.setSoundQuality(quality)
                print("  restored     → \(controller.state.soundQuality?.title ?? "—")")
            }

            if let current = state.gestures.doubleTapRight {
                let other = state.gestures.availableTapActions.first { $0 != current } ?? current
                print("  set right double tap → \(GestureAction.title(for: other))")
                let okTap = await controller.setDoubleTap(side: .right, action: other)
                print("    applied    → \(okTap ? "yes" : "NO")")
                print("    read back   → \(controller.state.gestures.doubleTapRight.map { GestureAction.title(for: $0) } ?? "—")")
                await controller.setDoubleTap(side: .right, action: current)
                print("  restored     → \(controller.state.gestures.doubleTapRight.map { GestureAction.title(for: $0) } ?? "—")")
            }
        }

        // A one-off override, used to put a value back after an experiment.
        if let assignment = CommandLine.arguments.first(where: { $0.hasPrefix("--set=") }) {
            let payload = String(assignment.dropFirst("--set=".count))
            let parts = payload.split(separator: "=", maxSplits: 1).map(String.init)
            if parts.count != 2 || Int(parts[1]) == nil {
                print("bad --set syntax: \(payload)")
            } else {
                let value = Int(parts[1])!
                switch parts[0] {
                case "doubleTapLeft":
                    await controller.setDoubleTap(side: .left, action: value)
                    print("set doubleTapLeft = \(value) -> \(controller.state.gestures.doubleTapLeft.map(String.init) ?? "—")")
                case "doubleTapRight":
                    await controller.setDoubleTap(side: .right, action: value)
                    print("set doubleTapRight = \(value) -> \(controller.state.gestures.doubleTapRight.map(String.init) ?? "—")")
                case "tripleTapLeft":
                    await controller.setTripleTap(side: .left, action: value)
                    print("set tripleTapLeft = \(value) -> \(controller.state.gestures.tripleTapLeft.map(String.init) ?? "—")")
                case "tripleTapRight":
                    await controller.setTripleTap(side: .right, action: value)
                    print("set tripleTapRight = \(value) -> \(controller.state.gestures.tripleTapRight.map(String.init) ?? "—")")
                case "holdLeft":
                    await controller.setLongTap(side: .left, action: value)
                    print("set holdLeft = \(value) -> \(controller.state.gestures.holdLeft.map(String.init) ?? "—")")
                case "holdRight":
                    await controller.setLongTap(side: .right, action: value)
                    print("set holdRight = \(value) -> \(controller.state.gestures.holdRight.map(String.init) ?? "—")")
                case "equalizer":
                    await controller.setEqualizer(value)
                    print("set equalizer = \(value) -> \(controller.state.equalizerPreset.map(String.init) ?? "—")")
                default:
                    print("unknown key '\(parts[0])'")
                }
            }
        }

        if let error = controller.lastError {
            print("")
            print("last error: \(error)")
        }
        print("")
        print("done")
        exit(0)
    }
}
