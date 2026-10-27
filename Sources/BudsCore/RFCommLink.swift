// BudsBar — Bluetooth RFCOMM transport
// SPDX-License-Identifier: MIT

import Foundation
import IOBluetooth

/// Errors surfaced by the transport layer.
public enum TransportError: LocalizedError, Sendable {
    case deviceNotFound
    case notConnected
    case serviceUnavailable
    case channelOpenFailed(Int)
    case closed
    case timedOut
    case writeFailed(Int)

    public var errorDescription: String? {
        switch self {
        case .deviceNotFound:
            "No paired Huawei earbuds found. Pair them in System Settings › Bluetooth first."
        case .notConnected:
            "The earbuds are not connected to this Mac. Connect them and try again."
        case .serviceUnavailable:
            "The earbuds did not advertise a control channel. Reconnect the Bluetooth link."
        case .channelOpenFailed(let code):
            "Could not open the control channel (status \(code)). Close other apps using the earbuds and retry."
        case .closed:
            "The connection to the earbuds was closed."
        case .timedOut:
            "The earbuds did not answer in time."
        case .writeFailed(let code):
            "Could not send data to the earbuds (status \(code))."
        }
    }
}

/// Handles the RFCOMM channel callbacks.
///
/// `IOBluetoothRFCOMMChannel` delivers its delegate callbacks on the main
/// thread's run loop, so the owner must keep that run loop pumping.
final class ChannelDelegate: NSObject, IOBluetoothRFCOMMChannelDelegate {
    var onOpen: ((IOReturn) -> Void)?
    var onData: (([UInt8]) -> Void)?
    var onClosed: (() -> Void)?

    func rfcommChannelOpenComplete(_ channel: IOBluetoothRFCOMMChannel!, status: IOReturn) {
        onOpen?(status)
    }

    func rfcommChannelData(_ channel: IOBluetoothRFCOMMChannel!, data pointer: UnsafeMutableRawPointer!, length: Int) {
        guard let pointer, length > 0 else { return }
        let bytes = Array(UnsafeBufferPointer(start: pointer.assumingMemoryBound(to: UInt8.self), count: length))
        onData?(bytes)
    }

    func rfcommChannelClosed(_ channel: IOBluetoothRFCOMMChannel!) {
        onClosed?()
    }
}

/// Owns the RFCOMM control channel to the earbuds.
///
/// The channel is opened asynchronously; its delegate callbacks arrive on the
/// main run loop, so this type is main-actor isolated.
@MainActor
public final class RFCommLink {
    private let device: IOBluetoothDevice
    private var channel: IOBluetoothRFCOMMChannel?
    private let delegate = ChannelDelegate()
    private var decoder = FrameStreamDecoder()

    /// Frames received from the device.
    public var onFrame: ((Frame) -> Void)?
    /// Called when the channel closes unexpectedly.
    public var onDisconnect: (() -> Void)?

    public init(device: IOBluetoothDevice) {
        self.device = device
    }

    public var isOpen: Bool { channel?.isOpen() == true }
    public var deviceName: String { device.name ?? "Huawei Earbuds" }
    public var deviceAddress: String { device.addressString ?? "" }

    /// Resolves the paired Huawei earbuds device.
    ///
    /// - Parameter preferredAddress: address remembered from a previous session.
    public static func findDevice(preferredAddress: String?) -> Result<IOBluetoothDevice, TransportError> {
        let paired = (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice]) ?? []
        if let preferredAddress, !preferredAddress.isEmpty,
           let match = paired.first(where: { $0.addressString == preferredAddress }) {
            return .success(match)
        }
        let candidates = paired.filter { device in
            let name = (device.name ?? "").lowercased()
            return name.contains("huawei") && (name.contains("freebuds") || name.contains("free clip"))
        }
        if candidates.count == 1, let match = candidates.first {
            return .success(match)
        }
        if let connected = candidates.first(where: { $0.isConnected() }) {
            return .success(connected)
        }
        if let match = candidates.first {
            return .success(match)
        }
        return .failure(.deviceNotFound)
    }

    /// Asks the system to bring up a baseband link to the earbuds.
    ///
    /// Earbuds sleep aggressively. When they are asleep the RFCOMM channel
    /// cannot be opened, so a connection request is issued first.
    public func requestConnection() {
        guard !device.isConnected() else { return }
        device.openConnection(nil)
    }

    /// Waits for the earbuds to come online, then opens the control channel.
    ///
    /// Earbuds sleep when idle, so a baseband connection is requested first
    /// and the open is retried for a while before giving up.
    public func open() async throws {
        if !device.isConnected() {
            device.openConnection(nil)
            let deadline = Date().addingTimeInterval(12)
            while !device.isConnected() && Date() < deadline {
                try? await Task.sleep(for: .milliseconds(400))
            }
        }
        guard device.isConnected() else { throw TransportError.notConnected }

        let services = device.services as? [IOBluetoothSDPServiceRecord] ?? []
        guard let service = services.first(where: { $0.matchesUUID16(0x1101) }) else {
            throw TransportError.serviceUnavailable
        }
        var port: BluetoothRFCOMMChannelID = 0
        guard service.getRFCOMMChannelID(&port) == kIOReturnSuccess else {
            throw TransportError.serviceUnavailable
        }

        // Install the handlers first: the open callback can arrive immediately.
        delegate.onData = { [weak self] bytes in
            guard let self else { return }
            for frame in self.decoder.consume(bytes) { self.onFrame?(frame) }
        }
        delegate.onClosed = { [weak self] in
            guard let self else { return }
            self.channel = nil
            self.decoder.reset()
            self.onDisconnect?()
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            var newChannel: IOBluetoothRFCOMMChannel?
            self.delegate.onOpen = { status in
                self.delegate.onOpen = nil
                if status == kIOReturnSuccess {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: TransportError.channelOpenFailed(Int(status)))
                }
            }
            let status = self.device.openRFCOMMChannelAsync(&newChannel, withChannelID: port, delegate: self.delegate)
            guard status == kIOReturnSuccess, let newChannel else {
                self.delegate.onOpen = nil
                continuation.resume(throwing: TransportError.channelOpenFailed(Int(status)))
                return
            }
            self.channel = newChannel
        }

        // Give the device a moment to start pushing notifications.
        try? await Task.sleep(for: .milliseconds(250))
    }

    /// Closes the control channel.
    public func close() {
        let existing = channel
        channel = nil
        decoder.reset()
        existing?.setDelegate(nil)
        existing?.close()
    }

    /// Writes raw bytes to the control channel.
    public func write(_ bytes: [UInt8]) throws {
        guard let channel, channel.isOpen() else { throw TransportError.closed }
        var payload = bytes
        let count = UInt16(payload.count)
        let status = payload.withUnsafeMutableBytes {
            channel.writeSync($0.baseAddress, length: count)
        }
        guard status == kIOReturnSuccess else { throw TransportError.writeFailed(Int(status)) }
    }
}
