// BudsBar — panel content
// SPDX-License-Identifier: MIT

import SwiftUI
import BudsCore

/// The scrollable body of the control panel.
///
/// Split out from `ControlPanel` so it can be rendered on its own for
/// documentation and visual review.
public struct PanelContent<Model: BudsViewModel>: View {
    @ObservedObject var controller: Model
    @StateObject private var volume = VolumeModel()

    public init(controller: Model) {
        self.controller = controller
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if case .failed(let message) = controller.linkState {
                connectionError(message)
            }
            if controller.state.isIdentified {
                batterySection
                noiseSection
                soundSection
                gestureSection
                deviceSection
            } else if controller.linkState.isConnected {
                ProgressView("Reading earbud state…")
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 12)
            }
        }
    }

    // MARK: - Sections

    private var batterySection: some View {
        SectionCard(title: "Battery", icon: { Image(systemName: "battery.100") }) {
            VStack(spacing: 6) {
                BatteryPill(
                    label: "L",
                    level: controller.state.battery.left,
                    isCharging: controller.state.isChargingLeft
                )
                BatteryPill(
                    label: "R",
                    level: controller.state.battery.right,
                    isCharging: controller.state.isChargingRight
                )
                if let caseLevel = controller.state.battery.caseLevel {
                    BatteryPill(label: "Case", level: caseLevel, isCharging: controller.state.isChargingCase)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var noiseSection: some View {
        SectionCard(title: "Noise Control", icon: { EarbudIcon(filled: true).frame(width: 11, height: 11) }) {
            VStack(alignment: .leading, spacing: 10) {
                SegmentedChoice(
                    options: noiseOptions,
                    selection: noiseBinding,
                    label: "Noise control"
                )

                if controller.state.noiseMode == .cancellation {
                    SegmentedChoice(
                        options: levelOptions,
                        selection: levelBinding,
                        label: "Cancellation level"
                    )
                }
            }
        }
    }

    private var soundSection: some View {
        SectionCard(title: "Sound", icon: { Image(systemName: "waveform") }) {
            VStack(alignment: .leading, spacing: 10) {
                if !controller.codecInfo.isEmpty {
                    InfoLine(label: "Codec", value: controller.codecInfo.summary)
                }

                HStack(spacing: 8) {
                    BandGraph(preset: controller.state.equalizerPreset)
                    ValueMenu(
                        options: equalizerPresets.map { ChoiceOption(value: $0, title: EqualizerPreset.title(for: $0)) },
                        selection: equalizerBinding,
                        label: "Equalizer preset"
                    )
                }

                BudsSwitch(isOn: lowLatencyBinding, label: "Low Latency Mode")

                SegmentedChoice(
                    options: SoundQuality.allCases.map { ChoiceOption(value: $0, title: $0.title) },
                    selection: soundQualityBinding,
                    label: "Sound quality"
                )

                volumeControl
            }
        }
    }

    private var volumeControl: some View {
        HStack(spacing: 8) {
            Image(systemName: volume.level > 0.5 ? "speaker.wave.2.fill" : (volume.level > 0 ? "speaker.wave.1.fill" : "speaker.slash.fill"))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 14)
            Slider(value: volumeBinding, in: 0...1)
                .controlSize(.small)
            LevelArc(level: volume.level, progress: 1, size: 20, lineWidth: 2.5)
            Text("\(Int(volume.level * 100))")
                .font(.system(size: 10, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 24, alignment: .trailing)
        }
    }

    private var gestureSection: some View {
        SectionCard(title: "Gestures", icon: { Image(systemName: "hand.tap") }) {
            VStack(alignment: .leading, spacing: 8) {
                GestureRow(
                    title: "Double Tap",
                    left: controller.state.gestures.doubleTapLeft,
                    right: controller.state.gestures.doubleTapRight,
                    options: controller.state.gestures.availableTapActions,
                    titleFor: { GestureAction.title(for: $0) }
                ) { side, value in
                    Task { await controller.setDoubleTap(side: side, action: value) }
                }

                GestureRow(
                    title: "Triple Tap",
                    left: controller.state.gestures.tripleTapLeft,
                    right: controller.state.gestures.tripleTapRight,
                    options: controller.state.gestures.availableTapActions,
                    titleFor: { GestureAction.title(for: $0) }
                ) { side, value in
                    Task { await controller.setTripleTap(side: side, action: value) }
                }

                GestureRow(
                    title: "Hold",
                    left: controller.state.gestures.holdLeft,
                    right: controller.state.gestures.holdRight,
                    options: controller.state.gestures.availableHoldActions,
                    titleFor: { HoldAction.title(for: $0) }
                ) { side, value in
                    Task { await controller.setLongTap(side: side, action: value) }
                }
            }
        }
    }

    private var deviceSection: some View {
        SectionCard(title: "Device", icon: { Image(systemName: "info.circle") }) {
            VStack(alignment: .leading, spacing: 3) {
                InfoLine(label: "Model", value: controller.state.identity.modelCode)
                InfoLine(label: "Firmware", value: controller.state.identity.firmware)
                InfoLine(label: "Serial", value: controller.state.identity.serialNumber)
            }
        }
    }

    private func connectionError(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(message)
                    .font(.system(size: 11))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button("Try Again") {
                Task { await controller.connect() }
            }
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Bindings

    /// The noise modes the model offers.
    ///
    /// The current mode is always kept, even when the model does not list
    /// it: the panel must show what the earbuds are actually doing.
    private var noiseOptions: [ChoiceOption<NoiseMode>] {
        var modes = controller.state.capabilities.noiseModes
        if let current = controller.state.noiseMode, !modes.contains(current) {
            modes.append(current)
        }
        return modes.map { ChoiceOption(value: $0, title: $0.title) }
    }

    /// The cancellation levels the model offers.
    private var levelOptions: [ChoiceOption<CancellationLevel>] {
        var levels = controller.state.capabilities.cancellationLevels
            .compactMap { CancellationLevel(rawValue: $0) }
        if let current = controller.state.cancellationLevel,
           let level = CancellationLevel(rawValue: current),
           !levels.contains(level) {
            levels.append(level)
        }
        return levels
            .sorted { $0.rawValue < $1.rawValue }
            .map { ChoiceOption(value: $0, title: $0.title) }
    }

    private var equalizerPresets: [Int] {
        let available = controller.state.availableEqualizerPresets
        guard !available.isEmpty else { return [0, 2, 3, 9] }
        return available
    }

    private var noiseBinding: Binding<NoiseMode> {
        Binding(
            get: { controller.state.noiseMode ?? .off },
            set: { mode in Task { await controller.setNoiseMode(mode, level: nil) } }
        )
    }

    private var levelBinding: Binding<CancellationLevel> {
        Binding(
            get: { CancellationLevel(rawValue: controller.state.cancellationLevel ?? 0) ?? .balanced },
            set: { level in Task { await controller.setNoiseMode(.cancellation, level: level.rawValue) } }
        )
    }

    private var equalizerBinding: Binding<Int> {
        Binding(
            get: { controller.state.equalizerPreset ?? 0 },
            set: { preset in Task { await controller.setEqualizer(preset) } }
        )
    }

    private var lowLatencyBinding: Binding<Bool> {
        Binding(
            get: { controller.state.lowLatencyEnabled ?? false },
            set: { enabled in Task { await controller.setLowLatency(enabled) } }
        )
    }

    private var soundQualityBinding: Binding<SoundQuality> {
        Binding(
            get: { controller.state.soundQuality ?? .connectivity },
            set: { quality in Task { await controller.setSoundQuality(quality) } }
        )
    }

    private var volumeBinding: Binding<Double> {
        Binding(
            get: { volume.level },
            set: { volume.level = $0 }
        )
    }
}

