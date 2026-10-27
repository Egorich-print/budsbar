// BudsBar — output volume model
// SPDX-License-Identifier: MIT

import Foundation
import Combine
import CoreAudio
import BudsCore

/// Bridges the panel's volume slider to the macOS audio output that feeds
/// the earbuds.
@MainActor
final class VolumeModel: ObservableObject {
    /// Current level between 0 and 1.
    @Published var level: Double = 0 {
        didSet {
            guard !isApplying else { return }
            apply()
        }
    }

    /// Name of the audio device currently being controlled.
    @Published private(set) var deviceName: String?

    @Published private(set) var isAvailable = false

    private var device: AudioObjectID?
    private var isApplying = false
    private var pollTask: Task<Void, Never>?

    init() {
        reload()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                guard let self else { return }
                self.syncFromDevice()
            }
        }
    }

    deinit {
        pollTask?.cancel()
    }

    /// Re-resolves the audio output device that belongs to the earbuds.
    func reload() {
        let candidates = OutputVolume.allDevices()
        // Prefer a Bluetooth output whose name mentions the earbuds.
        let earbud = candidates.first { device in
            let name = OutputVolume.name(of: device).lowercased()
            return name.contains("freebuds") || name.contains("huawei")
        }
        let chosen = earbud ?? candidates.first { device in
            let transport = OutputVolume.transport(of: device)
            return transport == UInt32(kAudioDeviceTransportTypeBluetooth)
                || transport == UInt32(kAudioDeviceTransportTypeBluetoothLE)
        }
        device = chosen
        deviceName = chosen.map { OutputVolume.name(of: $0) }
        isAvailable = chosen != nil
        syncFromDevice()
    }

    private func syncFromDevice() {
        guard let device, let current = OutputVolume.level(of: device) else { return }
        isApplying = true
        level = Double(current)
        isApplying = false
    }

    private func apply() {
        guard let device else { return }
        isApplying = true
        _ = OutputVolume.setLevel(Float(level), of: device)
        isApplying = false
    }
}
