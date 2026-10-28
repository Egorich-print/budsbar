// BudsBar — device state model
// SPDX-License-Identifier: MIT

import Foundation

/// Battery reading for one cell (earbud or case).
public struct BatteryReading: Equatable, Sendable {
    public var left: Int?
    public var right: Int?
    public var caseLevel: Int?

    public init(left: Int? = nil, right: Int? = nil, caseLevel: Int? = nil) {
        self.left = left
        self.right = right
        self.caseLevel = caseLevel
    }

    public var isEmpty: Bool { left == nil && right == nil && caseLevel == nil }

    /// Lowest earbud level, used for the menu bar glyph.
    public var lowest: Int? {
        switch (left, right) {
        case let (l?, r?): return min(l, r)
        case let (l?, nil): return l
        case let (nil, r?): return r
        default: return nil
        }
    }
}

/// Device identity and firmware details.
public struct DeviceIdentity: Equatable, Sendable {
    /// Stable model code, for example `BTFT0020`.
    public var modelCode: String?
    /// A build identifier the device rotates over time — not a stable name.
    public var buildId: String?
    /// Firmware version string.
    public var firmware: String?
    public var serialNumber: String?
    public var leftSerial: String?
    public var rightSerial: String?

    public init() {}

    /// A friendly name for the model.
    ///
    /// Derived from the model code, because the device's own product-name
    /// field rotates between reads and cannot be shown as a title.
    public var displayName: String {
        switch modelCode {
        case "BTFT0020": "HUAWEI FreeBuds 6"
        case "BTFT0022": "HUAWEI FreeBuds 6i"
        case "BTFT0021": "HUAWEI FreeBuds 5i"
        case "BTFT0001": "HUAWEI FreeBuds Pro"
        case "BTFT0002": "HUAWEI FreeBuds Pro 2"
        case "BTFT0003": "HUAWEI FreeBuds Pro 3"
        case "BTFT0004": "HUAWEI FreeBuds 4i"
        case "BTFT0005": "HUAWEI FreeBuds SE 4 ANC"
        case "BTFT0006": "HUAWEI FreeBuds 3i"
        case "BTFT0007": "HUAWEI FreeBuds 4"
        case "BTFT0008": "HUAWEI FreeClip"
        case .some(let code): "Huawei Earbuds (\(code))"
        case nil: "Huawei Earbuds"
        }
    }
}

/// Gesture configuration, per side.
public struct GestureSettings: Equatable, Sendable {
    public var doubleTapLeft: Int?
    public var doubleTapRight: Int?
    public var tripleTapLeft: Int?
    public var tripleTapRight: Int?
    public var holdLeft: Int?
    public var holdRight: Int?
    public var noiseCycleLeft: Int?
    public var noiseCycleRight: Int?

    /// Action codes the device advertises as available for tap gestures.
    public var availableTapActions: [Int] = []
    /// Action codes the device advertises as available for hold gestures.
    public var availableHoldActions: [Int] = []

    public init(
        doubleTapLeft: Int? = nil,
        doubleTapRight: Int? = nil,
        tripleTapLeft: Int? = nil,
        tripleTapRight: Int? = nil,
        holdLeft: Int? = nil,
        holdRight: Int? = nil,
        noiseCycleLeft: Int? = nil,
        noiseCycleRight: Int? = nil,
        availableTapActions: [Int] = [],
        availableHoldActions: [Int] = []
    ) {
        self.doubleTapLeft = doubleTapLeft
        self.doubleTapRight = doubleTapRight
        self.tripleTapLeft = tripleTapLeft
        self.tripleTapRight = tripleTapRight
        self.holdLeft = holdLeft
        self.holdRight = holdRight
        self.noiseCycleLeft = noiseCycleLeft
        self.noiseCycleRight = noiseCycleRight
        self.availableTapActions = availableTapActions
        self.availableHoldActions = availableHoldActions
    }
}

/// Complete snapshot of everything the widget can display or change.
public struct DeviceState: Equatable, Sendable {
    public var identity = DeviceIdentity()
    public var battery = BatteryReading()
    public var isChargingLeft = false
    public var isChargingRight = false
    public var isChargingCase = false

    public var noiseMode: NoiseMode?
    public var cancellationLevel: Int?
    public var equalizerPreset: Int?
    public var availableEqualizerPresets: [Int] = []
    public var lowLatencyEnabled: Bool?
    public var soundQuality: SoundQuality?

    public var gestures = GestureSettings()
    public var autoPauseEnabled: Bool?
    public var dualConnectEnabled: Bool?

    /// True once the device answered at least one query.
    public var isIdentified: Bool { identity.modelCode != nil }

    /// The noise-control options this model really offers.
    public var capabilities: DeviceCapabilities {
        DeviceCapabilities.forModel(identity.modelCode)
    }

    public init() {}
}

/// Connection state of the link.
public enum LinkState: Equatable, Sendable {
    case idle
    case connecting
    case connected
    case failed(String)

    public var isConnected: Bool { self == .connected }
}
