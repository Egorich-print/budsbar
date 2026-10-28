// BudsBar — per-model feature support
// SPDX-License-Identifier: MIT

import Foundation

/// Which noise-control options a model really offers.
///
/// The earbuds do not advertise their options. The reply to the noise-mode
/// read carries only the current level and mode, and the firmware happily
/// accepts any value — including modes the hardware does not implement, so
/// the app cannot tell "supported" from "accepted" by asking the device.
///
/// The set of real options is therefore a property of the model, and lives
/// here. Only models that are known to differ from the common case are
/// listed; every other model gets the full set, so an unknown model shows
/// a complete panel rather than an empty one.
public struct DeviceCapabilities: Equatable, Sendable {
    /// Noise-control modes the model offers.
    public var noiseModes: [NoiseMode]
    /// Cancellation levels the model offers, as raw values.
    public var cancellationLevels: [Int]

    public init(
        noiseModes: [NoiseMode] = NoiseMode.allCases,
        cancellationLevels: [Int] = CancellationLevel.allCases.map(\.rawValue)
    ) {
        self.noiseModes = noiseModes
        self.cancellationLevels = cancellationLevels
    }

    /// Every mode and every level.
    public static let full = DeviceCapabilities()

    /// The capabilities of a model.
    ///
    /// - Parameter modelCode: the model code the device reports, for example
    ///   `BTFT0020`. `nil` yields the full set.
    public static func forModel(_ modelCode: String?) -> DeviceCapabilities {
        guard let modelCode else { return .full }
        switch modelCode {
        case "BTFT0020":
            // HUAWEI FreeBuds 6. No transparency mode — the vendor app
            // offers only noise cancelling — and the deepest cancellation
            // level is not implemented, although the firmware accepts it.
            return DeviceCapabilities(
                noiseModes: [.off, .cancellation],
                cancellationLevels: [
                    CancellationLevel.balanced.rawValue,
                    CancellationLevel.comfortable.rawValue,
                    CancellationLevel.dynamic.rawValue
                ]
            )
        default:
            return .full
        }
    }
}
