// BudsBar — view model contract
// SPDX-License-Identifier: MIT

import Foundation
import Combine

/// The contract the control panel needs from a device driver.
///
/// The live driver is `DeviceController`; the preview renderer supplies a
/// scripted stand-in, so the panel can be rendered without a device.
@MainActor
public protocol BudsViewModel: ObservableObject {
    /// Latest known device state.
    var state: DeviceState { get }
    /// Current link status.
    var linkState: LinkState { get }
    /// Last error, if any.
    var lastError: String? { get }

    /// Connects to the earbuds.
    func connect() async
    /// Re-reads every value from the earbuds.
    func refresh() async

    /// Each setter returns true when the earbuds confirmed the new value.
    @discardableResult
    func setNoiseMode(_ mode: NoiseMode, level: Int?) async -> Bool
    @discardableResult
    func setEqualizer(_ preset: Int) async -> Bool
    @discardableResult
    func setLowLatency(_ enabled: Bool) async -> Bool
    @discardableResult
    func setSoundQuality(_ quality: SoundQuality) async -> Bool
    @discardableResult
    func setDoubleTap(side: EarbudSide, action: Int) async -> Bool
    @discardableResult
    func setTripleTap(side: EarbudSide, action: Int) async -> Bool
    @discardableResult
    func setLongTap(side: EarbudSide, action: Int) async -> Bool
    @discardableResult
    func setAutoPause(_ enabled: Bool) async -> Bool
}
