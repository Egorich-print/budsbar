// BudsBar — protocol command catalogue
// SPDX-License-Identifier: MIT
//
// Command IDs and field semantics were determined by black-box observation of a
// locally owned device and cross-checked against published interoperability
// documentation. All code here is original.

import Foundation

/// A readable request: command id plus the TLV tags the device should fill in.
public struct ReadRequest: Sendable {
    public let command: UInt16
    public let tags: [UInt8]

    public init(_ command: UInt16, _ tags: [UInt8]) {
        self.command = command
        self.tags = tags
    }
}

/// A writable request: command id plus the TLV payload to send.
public struct WriteRequest: Sendable {
    public let command: UInt16
    public let fields: [UInt8: [UInt8]]

    public init(_ command: UInt16, _ fields: [UInt8: [UInt8]]) {
        self.command = command
        self.fields = fields
    }
}

/// Noise-control mode reported and accepted by the device.
public enum NoiseMode: Int, Sendable, CaseIterable, Identifiable {
    case off = 0
    case cancellation = 1
    case awareness = 2

    public var id: Int { rawValue }

    public var title: String {
        switch self {
        case .off: "Noise Off"
        case .cancellation: "Noise Canceling"
        case .awareness: "Awareness"
        }
    }

}

/// Cancellation strength. The device reports 0-3 depending on model support.
public enum CancellationLevel: Int, Sendable, CaseIterable, Identifiable {
    case balanced = 0
    case comfortable = 1
    case deep = 2
    case dynamic = 3

    public var id: Int { rawValue }

    public var title: String {
        switch self {
        case .balanced: "Balanced"
        case .comfortable: "Comfortable"
        case .deep: "Deep"
        case .dynamic: "Dynamic"
        }
    }
}

/// Built-in equalizer preset. The device advertises the ids it actually
/// supports in field 3 of the equalizer response, so the UI is driven by the
/// device rather than by a hardcoded list.
public enum EqualizerPreset: Int, Sendable, CaseIterable, Identifiable {
    case defaultFlat = 0
    case bass = 2
    case treble = 3
    case voices = 9

    public var id: Int { rawValue }

    public var title: String {
        switch self {
        case .defaultFlat: "Flat"
        case .bass: "Bass"
        case .treble: "Treble"
        case .voices: "Voices"
        }
    }

    /// Human title for a preset id reported by the device.
    public static func title(for id: Int) -> String {
        EqualizerPreset(rawValue: id)?.title ?? "Preset \(id)"
    }
}

/// Sound-quality preference exposed by the device (connectivity vs quality).
public enum SoundQuality: Int, Sendable, CaseIterable, Identifiable {
    case connectivity = 0
    case quality = 1

    public var id: Int { rawValue }

    public var title: String {
        switch self {
        case .connectivity: "Connectivity"
        case .quality: "Quality"
        }
    }
}

/// Gesture action codes, shared by tap gestures.
public enum GestureAction: Int, Sendable, CaseIterable, Identifiable {
    case assistant = 0
    case playPause = 1
    case next = 2
    case previous = 7
    case disabled = 255

    public var id: Int { rawValue }

    public var title: String {
        switch self {
        case .assistant: "Voice Assistant"
        case .playPause: "Play / Pause"
        case .next: "Next Track"
        case .previous: "Previous Track"
        case .disabled: "Do Nothing"
        }
    }

    public static func title(for id: Int) -> String {
        GestureAction(rawValue: id)?.title ?? "Action \(id)"
    }
}

/// Long-press (hold) gesture action codes.
public enum HoldAction: Int, Sendable, CaseIterable, Identifiable {
    case assistant = 0
    case switchNoiseMode = 10
    case volumeUp = 18
    case volumeDown = 19
    case disabled = 255

    public var id: Int { rawValue }

    public var title: String {
        switch self {
        case .assistant: "Voice Assistant"
        case .switchNoiseMode: "Switch Noise Mode"
        case .volumeUp: "Volume Up"
        case .volumeDown: "Volume Down"
        case .disabled: "Do Nothing"
        }
    }

    public static func title(for id: Int) -> String {
        HoldAction(rawValue: id)?.title ?? "Action \(id)"
    }
}

/// Noise-mode cycling options, stored separately from the hold action.
public enum NoiseCycleOption: Int, Sendable, CaseIterable, Identifiable {
    case offToCancel = 1
    case offCancelAwareness = 2
    case cancelToAwareness = 3
    case offToAwareness = 4

    public var id: Int { rawValue }

    public var title: String {
        switch self {
        case .offToCancel: "Off ⇄ Canceling"
        case .offCancelAwareness: "Off / Canceling / Awareness"
        case .cancelToAwareness: "Canceling ⇄ Awareness"
        case .offToAwareness: "Off ⇄ Awareness"
        }
    }

    public static func title(for id: Int) -> String {
        NoiseCycleOption(rawValue: id)?.title ?? "Cycle \(id)"
    }
}

/// Which earbud a gesture applies to.
public enum EarbudSide: UInt8, Sendable, CaseIterable, Identifiable {
    case left = 1
    case right = 2

    public var id: UInt8 { rawValue }
    public var title: String { self == .left ? "Left" : "Right" }
}

/// Command identifiers observed on the device.
public enum Command {
    // Reads
    public static let deviceInfo: UInt16 = 0x0107
    public static let battery: UInt16 = 0x0108
    public static let batteryNotify: UInt16 = 0x0127
    public static let doubleTap: UInt16 = 0x0120
    public static let tripleTap: UInt16 = 0x0126
    public static let noiseMode: UInt16 = 0x2B2A
    public static let equalizer: UInt16 = 0x2B4A
    public static let longTap: UInt16 = 0x2B17
    public static let noiseCycle: UInt16 = 0x2B19
    public static let swipe: UInt16 = 0x2B1F
    public static let autoPause: UInt16 = 0x2B11
    public static let dualConnect: UInt16 = 0x2B2F
    public static let lowLatency: UInt16 = 0x2B6C
    public static let soundQuality: UInt16 = 0x2BA3
    public static let capabilities: UInt16 = 0x2BAC

    // Writes
    public static let setNoiseMode: UInt16 = 0x2B04
    public static let setEqualizer: UInt16 = 0x2B49
    public static let setDoubleTap: UInt16 = 0x011F
    public static let setTripleTap: UInt16 = 0x0125
    public static let setLongTap: UInt16 = 0x2B16
    public static let setNoiseCycle: UInt16 = 0x2B18
    public static let setSwipe: UInt16 = 0x2B1E
    public static let setAutoPause: UInt16 = 0x2B10
    public static let setDualConnect: UInt16 = 0x2B2E
    public static let setSoundQuality: UInt16 = 0x2BA2
    /// Low latency uses the same command id for read and write.
    public static let setLowLatency: UInt16 = 0x2B6C
}

/// TLV field tags used by the observed commands.
public enum Tag {
    public static let left: UInt8 = 1
    public static let right: UInt8 = 2
    public static let options: UInt8 = 3
    public static let inCall: UInt8 = 4
    public static let status: UInt8 = 5
    public static let charging: UInt8 = 6
}

/// The catalogue of reads and writes the widget exposes.
public enum ProtocolCatalogue {
    public static let reads: [ReadRequest] = [
        ReadRequest(Command.deviceInfo, [3, 7, 10, 15, 24]),
        ReadRequest(Command.battery, [1, 2, 3]),
        ReadRequest(Command.noiseMode, [1, 2]),
        ReadRequest(Command.equalizer, [1, 2, 3]),
        ReadRequest(Command.lowLatency, [2]),
        ReadRequest(Command.soundQuality, [1, 2]),
        ReadRequest(Command.doubleTap, [1, 2, 3, 4]),
        ReadRequest(Command.tripleTap, [1, 2, 3, 4]),
        ReadRequest(Command.longTap, [1, 2, 3, 4]),
        ReadRequest(Command.noiseCycle, [1, 2, 3]),
        ReadRequest(Command.swipe, [1, 2, 3]),
        ReadRequest(Command.autoPause, [1, 2]),
        ReadRequest(Command.dualConnect, [1, 2]),
    ]

    /// Builds the write request for a noise-control mode.
    ///
    /// The write payload is `[mode, strength]`, where a strength of `0xFF`
    /// means "keep the current strength". Turning noise control off carries a
    /// strength of `0x00` instead, which is what the device expects.
    /// Note that the *read* response uses the opposite order, `[strength, mode]`.
    public static func setNoiseMode(_ mode: NoiseMode, level: Int? = nil) -> WriteRequest {
        let strength: UInt8
        if mode == .off {
            strength = 0x00
        } else if let level {
            strength = UInt8(clamping: level)
        } else {
            strength = 0xFF
        }
        return WriteRequest(Command.setNoiseMode, [Tag.left: [UInt8(mode.rawValue), strength]])
    }

    /// Selects a built-in equalizer preset. The payload is the preset id.
    public static func setEqualizer(_ preset: Int) -> WriteRequest {
        WriteRequest(Command.setEqualizer, [Tag.left: [UInt8(clamping: preset)]])
    }

    /// Low latency shares one command id for read and write; the write value
    /// lives in field 1 while the read value lives in field 2.
    public static func setLowLatency(_ enabled: Bool) -> WriteRequest {
        WriteRequest(Command.setLowLatency, [Tag.left: [enabled ? 1 : 0]])
    }

    public static func setSoundQuality(_ quality: SoundQuality) -> WriteRequest {
        WriteRequest(Command.setSoundQuality, [Tag.left: [UInt8(quality.rawValue)]])
    }

    /// Gestures store the action code in the field that selects the earbud.
    public static func setDoubleTap(side: EarbudSide, action: Int) -> WriteRequest {
        WriteRequest(Command.setDoubleTap, [side.rawValue: [UInt8(clamping: action)]])
    }

    public static func setTripleTap(side: EarbudSide, action: Int) -> WriteRequest {
        WriteRequest(Command.setTripleTap, [side.rawValue: [UInt8(clamping: action)]])
    }

    public static func setLongTap(side: EarbudSide, action: Int) -> WriteRequest {
        WriteRequest(Command.setLongTap, [side.rawValue: [UInt8(clamping: action)]])
    }

    public static func setAutoPause(_ enabled: Bool) -> WriteRequest {
        WriteRequest(Command.setAutoPause, [Tag.left: [enabled ? 1 : 0]])
    }
}
