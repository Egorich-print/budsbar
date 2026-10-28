// BudsBar — raw frame dump
// SPDX-License-Identifier: MIT
//
// Connects to the earbuds and prints every field of every frame the device
// answers with, so the protocol can be inspected without guessing which
// tags carry which information.
//
//   swift run --sdk ... Tools/dump-frames.swift
//
// The app must not be running: only one RFCOMM client can hold the
// control channel at a time.

import Foundation
import BudsCore

/// Commands to interrogate, with the tags to ask for.
let probes: [(command: UInt16, name: String, tags: [UInt8])] = [
    (Command.noiseMode, "noise mode", [1, 2, 3, 4, 5, 6]),
    (Command.capabilities, "capabilities", [1, 2, 3, 4, 5, 6, 7, 8, 9]),
    (Command.equalizer, "equalizer", [1, 2, 3, 4]),
    (Command.doubleTap, "double tap", [1, 2, 3, 4]),
    (Command.longTap, "hold", [1, 2, 3, 4]),
    (Command.noiseCycle, "noise cycle", [1, 2, 3, 4]),
    (Command.swipe, "swipe", [1, 2, 3, 4]),
    (Command.lowLatency, "low latency", [1, 2, 3]),
    (Command.soundQuality, "sound quality", [1, 2, 3]),
    (Command.autoPause, "auto pause", [1, 2, 3]),
    (Command.dualConnect, "dual connect", [1, 2, 3])
]

func describe(_ frame: Frame) -> String {
    let fields = frame.fields
        .sorted { $0.key < $1.key }
        .map { tag, bytes in
            let hex = bytes.map { String(format: "%02x", $0) }.joined(separator: " ")
            return "tag \(tag): [\(hex)]"
        }
        .joined(separator: ", ")
    return "cmd 0x\(String(format: "%04x", frame.command)) fields { \(fields) }"
}

@MainActor
func run() async {
    guard case .success(let device) = RFCommLink.findDevice(preferredAddress: nil) else {
        print("device not found")
        exit(1)
    }
    let link = RFCommLink(device: device)
    print("connecting to \(link.deviceName)…")
    link.onFrame = { frame in
        print("  ← \(describe(frame))")
    }
    do {
        try await link.open()
    } catch {
        print("open failed: \(error)")
        exit(1)
    }
    print("connected\n")

    for probe in probes {
        print("── \(probe.name) (0x\(String(format: "%04x", probe.command)))")
        let fields = Dictionary(uniqueKeysWithValues: probe.tags.map { ($0, [UInt8]()) })
        do {
            try link.write(WireFormat.encode(command: probe.command, fields: fields))
        } catch {
            print("  write failed: \(error)")
            continue
        }
        // Give the device a moment to answer before the next request.
        try? await Task.sleep(for: .milliseconds(700))
    }

    print("\ndone")
    link.close()
    exit(0)
}

// `IOBluetoothRFCOMMChannel` delivers its callbacks on the main thread's
// NSRunLoop, so the run loop has to keep turning underneath the work.
Task { @MainActor in
    await run()
}
RunLoop.current.run()
