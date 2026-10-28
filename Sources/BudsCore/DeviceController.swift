// BudsBar — high level device controller
// SPDX-License-Identifier: MIT

import Foundation
import IOBluetooth

/// Drives the earbuds: connects, polls state, applies changes.
///
/// Every change is read back from the device before it is reported as applied,
/// so the UI never shows a value the earbuds did not accept.
@MainActor
public final class DeviceController: ObservableObject, BudsViewModel {
    /// Latest known state.
    @Published public private(set) var state = DeviceState()
    /// Current link status.
    @Published public private(set) var linkState: LinkState = .idle
    /// Last error message shown in the UI.
    @Published public private(set) var lastError: String?
    /// The audio stream the system sends to the earbuds.
    @Published public private(set) var codecInfo = AudioCodecInfo()

    private var link: RFCommLink?
    private var pollTask: Task<Void, Never>?
    private var pending: [PendingRequest] = []
    private var frameWaiters: [UInt16: [CheckedContinuation<Frame, Error>]] = [:]

    private struct PendingRequest {
        let command: UInt16
        let continuation: CheckedContinuation<Frame, Error>
    }

    public init() {}

    // MARK: - Connection

    /// Connects to the earbuds and performs an initial state refresh.
    public func connect() async {
        guard linkState != .connecting else { return }
        linkState = .connecting
        lastError = nil

        let found = RFCommLink.findDevice(preferredAddress: UserDefaults.standard.string(forKey: "buds.address"))
        let device: IOBluetoothDevice
        switch found {
        case .success(let value): device = value
        case .failure(let error):
            linkState = .failed(error.errorDescription ?? "Could not find the earbuds.")
            return
        }

        let newLink = RFCommLink(device: device)
        link = newLink
        newLink.onFrame = { [weak self] frame in
            self?.handle(frame)
        }
        newLink.onDisconnect = { [weak self] in
            self?.handleDisconnect()
        }

        do {
            try await newLink.open()
            UserDefaults.standard.set(newLink.deviceAddress, forKey: "buds.address")
            linkState = .connected
            await refresh()
            startPolling()
            await refreshCodec()
        } catch {
            linkState = .failed(error.localizedDescription)
            lastError = error.localizedDescription
        }
    }

    /// Disconnects and stops polling.
    public func disconnect() {
        pollTask?.cancel()
        pollTask = nil
        link?.close()
        link = nil
        linkState = .idle
    }

    private func handleDisconnect() {
        pollTask?.cancel()
        pollTask = nil
        linkState = .failed(TransportError.closed.localizedDescription)
    }

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(20))
                guard let self, self.linkState.isConnected else { return }
                await self.refresh(silent: true)
            }
        }
    }

    // MARK: - Frame handling

    private func handle(_ frame: Frame) {
        // A waiter registered before a write takes priority: the device
        // pushes the new state straight after a write, and that push — not
        // the answer to a later read — is the freshest value.
        if var waiters = frameWaiters[frame.command], !waiters.isEmpty {
            let waiter = waiters.removeFirst()
            frameWaiters[frame.command] = waiters
            waiter.resume(returning: frame)
            return
        }
        if let index = pending.firstIndex(where: { $0.command == frame.command }) {
            let request = pending.remove(at: index)
            request.continuation.resume(returning: frame)
            return
        }
        // Unsolicited notification (for example a battery push).
        if frame.command == Command.batteryNotify {
            apply(frame)
        }
    }

    /// Registers a waiter for the next frame carrying `command`.
    private func waitForFrame(_ command: UInt16, timeout: Duration = .seconds(3)) async throws -> Frame {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Frame, Error>) in
            frameWaiters[command, default: []].append(continuation)
            Task { [weak self] in
                try? await Task.sleep(for: timeout)
                guard let self else { return }
                guard var waiters = self.frameWaiters[command], !waiters.isEmpty else { return }
                let waiter = waiters.removeFirst()
                self.frameWaiters[command] = waiters
                waiter.resume(throwing: TransportError.timedOut)
            }
        }
    }

    // MARK: - Reading

    /// Queries the device for every supported value and updates the state.
    public func refresh() async {
        await refresh(silent: false)
    }

    /// Queries the device for every supported value and updates the state.
    ///
    /// - Parameter silent: when true, a failed read does not surface an error.
    public func refresh(silent: Bool) async {
        guard link != nil else { return }
        for request in ProtocolCatalogue.reads {
            do {
                let frame = try await read(request)
                apply(frame)
            } catch {
                if !silent { lastError = error.localizedDescription }
            }
        }
    }

    private func read(_ request: ReadRequest) async throws -> Frame {
        guard let link else { throw TransportError.closed }
        let fields = Dictionary(uniqueKeysWithValues: request.tags.map { ($0, [UInt8]()) })
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Frame, Error>) in
            pending.append(PendingRequest(command: request.command, continuation: continuation))
            do {
                try link.write(WireFormat.encode(command: request.command, fields: fields))
            } catch {
                pending.removeAll { $0.command == request.command }
                continuation.resume(throwing: error)
                return
            }
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(3))
                guard let self else { return }
                if let index = self.pending.firstIndex(where: { $0.command == request.command }) {
                    let request = self.pending.remove(at: index)
                    request.continuation.resume(throwing: TransportError.timedOut)
                }
            }
        }
    }

    /// Sends a write request and verifies the change against the state the
    /// device reports afterwards.
    ///
    /// The waiter is registered *before* the write, so the frame that the
    /// device pushes in response to the write is the one that gets checked.
    /// A later read would answer with the same value, but the push is
    /// quicker and unambiguous.
    @discardableResult
    public func apply(_ request: WriteRequest, verify: ReadRequest) async -> Bool {
        guard let link else {
            lastError = TransportError.closed.localizedDescription
            return false
        }

        let waiter = Task { try await self.waitForFrame(verify.command) }
        do {
            try link.write(WireFormat.encode(command: request.command, fields: request.fields))
        } catch {
            waiter.cancel()
            lastError = error.localizedDescription
            return false
        }

        // The device pushes the new state; fall back to an explicit read if
        // it does not.
        var frame: Frame?
        if let pushed = try? await waiter.value {
            frame = pushed
        } else {
            frame = try? await read(verify)
        }

        guard let frame else {
            lastError = "The earbuds did not answer in time."
            return false
        }
        apply(frame)

        if matches(frame, request: request) {
            lastError = nil
            return true
        }

        // The push may have carried the previous value; read once more.
        for _ in 0..<2 {
            try? await Task.sleep(for: .milliseconds(200))
            guard let second = try? await read(verify) else { continue }
            apply(second)
            if matches(second, request: request) {
                lastError = nil
                return true
            }
        }
        lastError = "The earbuds did not confirm the change."
        return false
    }

    /// Checks whether the read-back frame reflects the requested change.
    private func matches(_ frame: Frame, request: WriteRequest) -> Bool {
        switch request.command {
        case Command.setNoiseMode:
            guard let value = frame.fields[Tag.left], value.count == 2,
                  let wanted = request.fields[Tag.left]?.first else { return false }
            return value[1] == wanted
        case Command.setEqualizer:
            guard let wanted = request.fields[Tag.left]?.first else { return false }
            return frame.byte(Tag.right) == wanted
        case Command.setLowLatency:
            guard let wanted = request.fields[Tag.left]?.first else { return false }
            return frame.byte(Tag.right) == wanted
        case Command.setSoundQuality:
            guard let wanted = request.fields[Tag.left]?.first else { return false }
            return frame.byte(Tag.right) == wanted
        case Command.setDoubleTap, Command.setTripleTap, Command.setLongTap:
            // The write stores the action code in the field that selects the
            // earbud: the field key is the side and its value is the action.
            guard let (side, value) = request.fields.first,
                  let action = value.first else { return false }
            return frame.byte(side) == action
        case Command.setAutoPause:
            guard let wanted = request.fields[Tag.left]?.first else { return false }
            return frame.byte(Tag.left) == wanted
        default:
            return true
        }
    }

    // MARK: - Applying observed frames

    private func apply(_ frame: Frame) {
        switch frame.command {
        case Command.deviceInfo:
            applyIdentity(frame)
        case Command.battery, Command.batteryNotify:
            applyBattery(frame)
        case Command.noiseMode:
            if let value = frame.fields[Tag.left], value.count == 2 {
                state.cancellationLevel = Int(value[0])
                state.noiseMode = NoiseMode(rawValue: Int(value[1]))
            }
        case Command.equalizer:
            if let preset = frame.byte(Tag.right) { state.equalizerPreset = Int(preset) }
            if let available = frame.byteList(Tag.options) { state.availableEqualizerPresets = available }
        case Command.lowLatency:
            if let value = frame.byte(Tag.right) { state.lowLatencyEnabled = value == 1 }
        case Command.soundQuality:
            if let value = frame.byte(Tag.right) { state.soundQuality = SoundQuality(rawValue: Int(value)) }
        case Command.doubleTap:
            state.gestures.doubleTapLeft = frame.byte(Tag.left).map(Int.init)
            state.gestures.doubleTapRight = frame.byte(Tag.right).map(Int.init)
            if let available = frame.byteList(Tag.options) { state.gestures.availableTapActions = available }
        case Command.tripleTap:
            state.gestures.tripleTapLeft = frame.byte(Tag.left).map(Int.init)
            state.gestures.tripleTapRight = frame.byte(Tag.right).map(Int.init)
        case Command.longTap:
            state.gestures.holdLeft = frame.byte(Tag.left).map(Int.init)
            state.gestures.holdRight = frame.byte(Tag.right).map(Int.init)
            if let available = frame.byteList(Tag.options) { state.gestures.availableHoldActions = available }
        case Command.noiseCycle:
            state.gestures.noiseCycleLeft = frame.byte(Tag.left).map(Int.init)
            state.gestures.noiseCycleRight = frame.byte(Tag.right).map(Int.init)
        case Command.autoPause:
            state.autoPauseEnabled = frame.byte(Tag.left).map { $0 == 1 }
        case Command.dualConnect:
            state.dualConnectEnabled = frame.byte(Tag.left).map { $0 == 1 }
        default:
            break
        }
    }

    private func applyIdentity(_ frame: Frame) {
        state.identity.modelCode = frame.text(15)
        state.identity.buildId = frame.text(3)
        state.identity.firmware = frame.text(7)
        state.identity.serialNumber = frame.text(9)
        state.identity.leftSerial = frame.text(10)
        if let pair = frame.text(24) {
            let parts = pair.split(separator: ",")
            if parts.count == 2 {
                state.identity.leftSerial = String(parts[0]).replacingOccurrences(of: "L-", with: "")
                state.identity.rightSerial = String(parts[1]).replacingOccurrences(of: "R-", with: "")
            }
        }
    }

    private func applyBattery(_ frame: Frame) {
        if let values = frame.fields[Tag.right], values.count >= 3 {
            state.battery.left = values[0] <= 100 ? Int(values[0]) : nil
            state.battery.right = values[1] <= 100 ? Int(values[1]) : nil
            state.battery.caseLevel = values[2] <= 100 ? Int(values[2]) : nil
        }
        if let flags = frame.fields[Tag.charging], flags.count >= 3 {
            state.isChargingLeft = flags[0] == 1
            state.isChargingRight = flags[1] == 1
            state.isChargingCase = flags[2] == 1
        }
    }

    // MARK: - Public actions

    /// Re-reads the codec and the bitrate of the stream to the earbuds.
    ///
    /// The earbuds do not report their codec: the system negotiates it with
    /// the Bluetooth controller, and the result is only visible in the
    /// system log.
    public func refreshCodec() async {
        codecInfo = await CodecDetector.detect(deviceName: state.identity.displayName)
    }

    /// @return true when the earbuds confirmed the new value.
    @discardableResult
    public func setNoiseMode(_ mode: NoiseMode, level: Int? = nil) async -> Bool {
        await apply(ProtocolCatalogue.setNoiseMode(mode, level: level),
                    verify: ReadRequest(Command.noiseMode, [1, 2]))
    }

    @discardableResult
    public func setEqualizer(_ preset: Int) async -> Bool {
        await apply(ProtocolCatalogue.setEqualizer(preset),
                    verify: ReadRequest(Command.equalizer, [1, 2, 3]))
    }

    @discardableResult
    public func setLowLatency(_ enabled: Bool) async -> Bool {
        await apply(ProtocolCatalogue.setLowLatency(enabled),
                    verify: ReadRequest(Command.lowLatency, [2]))
    }

    @discardableResult
    public func setSoundQuality(_ quality: SoundQuality) async -> Bool {
        await apply(ProtocolCatalogue.setSoundQuality(quality),
                    verify: ReadRequest(Command.soundQuality, [1, 2]))
    }

    @discardableResult
    public func setDoubleTap(side: EarbudSide, action: Int) async -> Bool {
        await apply(ProtocolCatalogue.setDoubleTap(side: side, action: action),
                    verify: ReadRequest(Command.doubleTap, [1, 2, 3, 4]))
    }

    @discardableResult
    public func setTripleTap(side: EarbudSide, action: Int) async -> Bool {
        await apply(ProtocolCatalogue.setTripleTap(side: side, action: action),
                    verify: ReadRequest(Command.tripleTap, [1, 2, 3, 4]))
    }

    @discardableResult
    public func setLongTap(side: EarbudSide, action: Int) async -> Bool {
        await apply(ProtocolCatalogue.setLongTap(side: side, action: action),
                    verify: ReadRequest(Command.longTap, [1, 2, 3, 4]))
    }

    @discardableResult
    public func setAutoPause(_ enabled: Bool) async -> Bool {
        await apply(ProtocolCatalogue.setAutoPause(enabled),
                    verify: ReadRequest(Command.autoPause, [1, 2]))
    }
}
