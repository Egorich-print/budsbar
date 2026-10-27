// BudsBar — output volume control
// SPDX-License-Identifier: MIT
//
// The earbuds do not expose a volume command over their control channel:
// the in-ear volume is the volume macOS sends to the Bluetooth audio
// sink. This module therefore drives the CoreAudio output device that
// matches the earbuds.

import Foundation
import CoreAudio
import AudioToolbox

/// Reads and writes the system output volume for a named audio device.
public enum OutputVolume {

    /// Errors raised by the volume bridge.
    public enum Failure: LocalizedError {
        case deviceNotFound(String)
        case unsupported

        public var errorDescription: String? {
            switch self {
            case .deviceNotFound(let name):
                "No audio output named “\(name)”. Connect the earbuds and try again."
            case .unsupported:
                "This audio device does not expose a software volume control."
            }
        }
    }

    private static func propertySize(_ device: AudioObjectID, _ address: inout AudioObjectPropertyAddress) -> UInt32 {
        var size: UInt32 = 0
        AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size)
        return size
    }

    private static func propertyData(_ device: AudioObjectID, _ address: inout AudioObjectPropertyAddress, _ size: UInt32) -> Data? {
        var buffer = Data(count: Int(size))
        var mutableSize = size
        let status = buffer.withUnsafeMutableBytes {
            AudioObjectGetPropertyData(device, &address, 0, nil, &mutableSize, $0.baseAddress!)
        }
        return status == noErr ? buffer : nil
    }

    /// All CoreAudio devices known to the system.
    public static func allDevices() -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size = propertySize(AudioObjectID(kAudioObjectSystemObject), &address)
        guard size > 0 else { return [] }
        var buffer = Data(count: Int(size))
        let status = buffer.withUnsafeMutableBytes {
            AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, $0.baseAddress!)
        }
        guard status == noErr else { return [] }
        return buffer.withUnsafeBytes { Array($0.bindMemory(to: AudioDeviceID.self)) }
    }

    /// Human readable name of an audio device.
    public static func name(of device: AudioObjectID) -> String {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        // The property carries a CFStringRef, so it is read as a managed
        // reference rather than as a byte buffer.
        var reference: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = withUnsafeMutablePointer(to: &reference) { pointer in
            AudioObjectGetPropertyData(device, &address, 0, nil, &size, pointer)
        }
        guard status == noErr, let reference else { return "" }
        return reference.takeUnretainedValue() as String
    }

    /// Transport type of an audio device.
    public static func transport(of device: AudioObjectID) -> UInt32 {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value)
        return value
    }

    private static func isBluetooth(_ device: AudioObjectID) -> Bool {
        let transport = transport(of: device)
        return transport == UInt32(kAudioDeviceTransportTypeBluetooth)
            || transport == UInt32(kAudioDeviceTransportTypeBluetoothLE)
    }

    /// Finds the output device that belongs to the given Bluetooth device name.
    ///
    /// - Parameter matching: a name to match case-insensitively.
    public static func device(named matching: String) -> AudioObjectID? {
        let devices = allDevices()
        let wanted = matching.lowercased()

        // Exact match first.
        if let exact = devices.first(where: { name(of: $0).lowercased() == wanted }) {
            return exact
        }
        // Then a prefix match, which covers the "HUAWEI FreeBuds 6" style names.
        if let prefix = devices.first(where: { name(of: $0).lowercased().hasPrefix(wanted) }) {
            return prefix
        }
        // Then any Bluetooth device whose name contains the earbud family name.
        if let loose = devices.first(where: { device in
            isBluetooth(device) && name(of: device).lowercased().contains(wanted)
        }) {
            return loose
        }
        return nil
    }

    /// Current output volume as a value between 0 and 1.
    public static func level(of device: AudioObjectID) -> Float? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(device, &address) else { return nil }
        var value: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr else { return nil }
        return min(max(value, 0), 1)
    }

    /// Sets the output volume of a device. `level` is between 0 and 1.
    public static func setLevel(_ level: Float, of device: AudioObjectID) -> Bool {
        let clamped = min(max(level, 0), 1)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(device, &address) else { return false }
        var value = Float32(clamped)
        var size = UInt32(MemoryLayout<Float32>.size)
        return AudioObjectSetPropertyData(device, &address, 0, nil, size, &value) == noErr
    }

    /// Converts a decibel value to the linear scalar CoreAudio expects.
    public static func scalar(fromDecibels decibels: Float) -> Float {
        let clamped = min(max(decibels, -96), 0)
        return pow(10, clamped / 20)
    }

    /// Converts a linear scalar to decibels.
    public static func decibels(fromScalar scalar: Float) -> Float {
        guard scalar > 0 else { return -96 }
        return 20 * log10(scalar)
    }
}
