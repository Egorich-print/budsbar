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
            if !controller.linkState.isConnected {
                ContentUnavailableView {
                    Label("No earbuds connected", systemImage: "earbuds")
                } description: {
                    if case .failed(let message) = controller.linkState {
                        Text(message)
                    } else if controller.linkState == .connecting {
                        Text("Waiting for the connection to complete…")
                    } else {
                        Text("Connect your earbuds to see their battery and controls.")
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            } else if controller.state.isIdentified {
                batterySection
                noiseSection
                soundSection
                gestureSection
                deviceSection
            } else {
                ProgressView("Reading earbud state…")
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 12)
            }
        }
        .onChange(of: controller.state.identity.modelCode) { _, _ in
            volume.reload()
        }
    }

    // MARK: - Sections

    private var batterySection: some View {
        SectionCard(title: "Battery", icon: { Image(systemName: "battery.100") }) {
            VStack(spacing: 6) {
                BatteryRow(
                    label: "Left",
                    level: controller.state.battery.left,
                    isCharging: controller.state.isChargingLeft
                )
                BatteryRow(
                    label: "Right",
                    level: controller.state.battery.right,
                    isCharging: controller.state.isChargingRight
                )
                if let caseLevel = controller.state.battery.caseLevel {
                    BatteryRow(label: "Case", level: caseLevel, isCharging: controller.state.isChargingCase)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var noiseSection: some View {
        SectionCard(title: "Noise control", icon: { Image(systemName: "waveform") }) {
            VStack(alignment: .leading, spacing: 10) {
                SegmentedChoice(
                    options: noiseOptions,
                    selection: noiseBinding,
                    label: "Noise control"
                )
                .disabled(controller.state.noiseMode == nil)
            }
        }
    }

    private var soundSection: some View {
        SectionCard(title: "Sound", icon: { Image(systemName: "waveform") }) {
            VStack(alignment: .leading, spacing: 10) {
                if !controller.codecInfo.isEmpty {
                    InfoLine(label: "Codec", value: controller.codecInfo.summary)
                }

                LabeledContent("Equalizer") {
                    ValueMenu(
                        options: equalizerPresets.map { ChoiceOption(value: $0, title: EqualizerPreset.title(for: $0)) },
                        selection: equalizerBinding,
                        label: "Equalizer preset"
                    )
                    .disabled(controller.state.equalizerPreset == nil)
                }

                BudsSwitch(isOn: lowLatencyBinding, label: "Low latency")
                    .disabled(controller.state.lowLatencyEnabled == nil)

                Text("Sound preference")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                SegmentedChoice(
                    options: SoundQuality.allCases.map { ChoiceOption(value: $0, title: $0.title) },
                    selection: soundQualityBinding,
                    label: "Sound preference"
                )
                .disabled(controller.state.soundQuality == nil)

                volumeControl
            }
        }
    }

    private var volumeControl: some View {
        HStack(spacing: 8) {
            Image(systemName: volume.level > 0.5 ? "speaker.wave.2.fill" : (volume.level > 0 ? "speaker.wave.1.fill" : "speaker.slash.fill"))
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(width: 14)
            Slider(value: volumeBinding, in: 0...1)
                .controlSize(.small)
                .accessibilityLabel("Earbud volume")
                .disabled(!volume.isAvailable)
            Text(volume.isAvailable ? "\(Int(volume.level * 100))%" : "—")
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 40, alignment: .trailing)
        }
    }

    private var gestureSection: some View {
        SectionCard(title: "Gestures", icon: { Image(systemName: "hand.tap") }) {
            VStack(alignment: .leading, spacing: 8) {
                GestureRow(
                    title: "Double tap",
                    left: controller.state.gestures.doubleTapLeft,
                    right: controller.state.gestures.doubleTapRight,
                    options: controller.state.gestures.availableTapActions,
                    titleFor: { GestureAction.title(for: $0) }
                ) { side, value in
                    Task { await controller.setDoubleTap(side: side, action: value) }
                }

                GestureRow(
                    title: "Triple tap",
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
        DisclosureGroup("Device information") {
            VStack(alignment: .leading, spacing: 8) {
                InfoLine(label: "Model", value: controller.state.identity.modelCode)
                InfoLine(label: "Firmware", value: controller.state.identity.firmware)
                InfoLine(label: "Serial", value: controller.state.identity.serialNumber)
            }
            .padding(.top, 8)
        }
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
        return modes.map { mode in
            ChoiceOption(value: mode, title: mode == .off ? "Off" : mode.title)
        }
    }

    private var equalizerPresets: [Int] {
        let available = controller.state.availableEqualizerPresets
        var presets = available
        if let current = controller.state.equalizerPreset, !presets.contains(current) {
            presets.append(current)
        }
        return presets
    }

    private var noiseBinding: Binding<NoiseMode> {
        Binding(
            get: { controller.state.noiseMode ?? .off },
            set: { mode in Task { await controller.setNoiseMode(mode, level: nil) } }
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

