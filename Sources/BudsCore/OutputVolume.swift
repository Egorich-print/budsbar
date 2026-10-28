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

    /// The "virtual main volume" selector.
    ///
    /// Bluetooth audio devices expose their software volume through this
    /// property rather than through `kAudioDevicePropertyVolumeScalar`: it
    /// is the single value CoreAudio keeps for the sink, and the one the
    /// earbuds follow. The constant is not part of the public SDK headers,
    /// but it is the value CoreAudio itself uses for Bluetooth devices.
    static let virtualMainVolume: AudioObjectPropertySelector = 0x766D7663  // 'vmvc'

    /// The properties that can carry a device's output volume, in the order
    /// they are tried.
    ///
    /// The virtual main volume comes first because it is the only one a
    /// Bluetooth sink is guaranteed to have. The per-channel scalars follow
    /// for devices that expose no aggregate volume.
    static let volumeProperties: [(selector: AudioObjectPropertySelector, element: AudioObjectPropertyElement)] = [
        (virtualMainVolume, 0),
        (kAudioDevicePropertyVolumeScalar, kAudioObjectPropertyElementMain),
        (kAudioDevicePropertyVolumeScalar, 1),
        (kAudioDevicePropertyVolumeScalar, 0)
    ]

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
        for property in volumeProperties {
            var address = AudioObjectPropertyAddress(
                mSelector: property.selector,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: property.element
            )
            guard AudioObjectHasProperty(device, &address) else { continue }
            var value: Float32 = 0
            var size = UInt32(MemoryLayout<Float32>.size)
            guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr else { continue }
            return min(max(value, 0), 1)
        }
        return nil
    }

    /// Sets the output volume of a device. `level` is between 0 and 1.
    public static func setLevel(_ level: Float, of device: AudioObjectID) -> Bool {
        let clamped = min(max(level, 0), 1)
        for property in volumeProperties {
            var address = AudioObjectPropertyAddress(
                mSelector: property.selector,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: property.element
            )
            guard AudioObjectHasProperty(device, &address) else { continue }
            var value = Float32(clamped)
            var size = UInt32(MemoryLayout<Float32>.size)
            if AudioObjectSetPropertyData(device, &address, 0, nil, size, &value) == noErr {
                return true
            }
        }
        return false
    }

    /// Whether a device has an output stream.
    ///
    /// A pair of Bluetooth earbuds shows up as two devices with the same
    /// name: one carries the microphone and one carries the speakers. Only
    /// the second one has a volume worth driving.
    public static func isOutputDevice(_ device: AudioObjectID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size = propertySize(device, &address)
        guard size > 0 else { return false }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, raw) == noErr else { return false }
        let list = raw.assumingMemoryBound(to: AudioBufferList.self)
        for buffer in UnsafeMutableAudioBufferListPointer(list) where buffer.mNumberChannels > 0 {
            return true
        }
        return false
    }

    /// What CoreAudio knows about the output the earbuds play to.
    ///
    /// A pair of Bluetooth earbuds shows up as two devices with the same
    /// name: one carries the microphone and one carries the speakers. The
    /// one with the output stream is the sink the music goes to.
    public struct OutputInfo: Equatable, Sendable {
        /// The name of the device, exactly as CoreAudio spells it.
        public var name: String?
        /// The nominal sample rate of its output stream, in hertz.
        public var sampleRate: Double?
        /// Whether the device speaks over Bluetooth.
        public var isBluetooth: Bool

        public init(name: String? = nil, sampleRate: Double? = nil, isBluetooth: Bool = false) {
            self.name = name
            self.sampleRate = sampleRate
            self.isBluetooth = isBluetooth
        }
    }

    /// Looks up the audio output that plays to the named device.
    ///
    /// - Parameter name: the name of the device, for example
    ///   `HUAWEI FreeBuds 6`.
    public static func outputInfo(named name: String?) -> OutputInfo {
        guard let name, !name.isEmpty else { return OutputInfo() }
        let wanted = name.lowercased()
        let matches = allDevices().filter { self.name(of: $0).lowercased() == wanted }
        guard !matches.isEmpty else { return OutputInfo() }

        var best = OutputInfo(name: name)
        for device in matches {
            guard isOutputDevice(device) else { continue }
            let rate = nominalSampleRate(of: device)
            // The microphone half of a headset reports a narrow rate; the
            // half that carries the music is the one worth showing.
            guard best.sampleRate == nil || (rate ?? 0) > (best.sampleRate ?? 0) else { continue }
            best = OutputInfo(
                name: self.name(of: device),
                sampleRate: rate,
                isBluetooth: isBluetooth(device)
            )
        }
        return best
    }

    /// The nominal sample rate of the output stream of a device.
    public static func nominalSampleRate(of device: AudioObjectID) -> Double? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: Float64 = 0
        var size = UInt32(MemoryLayout<Float64>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr else {
            return nil
        }
        return value
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
