// BudsBar — native macOS controls
// SPDX-License-Identifier: MIT

import SwiftUI

/// One selectable entry.
struct ChoiceOption<Value: Hashable>: Identifiable {
    let value: Value
    let title: String

    var id: Value { value }
}

struct SegmentedChoice<Value: Hashable>: View {
    let options: [ChoiceOption<Value>]
    @Binding var selection: Value
    var label: String = ""

    var body: some View {
        Picker(label, selection: $selection) {
            ForEach(options) { option in
                Text(option.title).tag(option.value)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .accessibilityLabel(label)
    }
}

struct BudsSwitch: View {
    @Binding var isOn: Bool
    var label: String = ""

    var body: some View {
        Toggle(label, isOn: $isOn)
            .toggleStyle(.switch)
    }
}

struct ValueMenu<Value: Hashable>: View {
    let options: [ChoiceOption<Value>]
    @Binding var selection: Value
    var label: String = ""
    var placeholder: String = "Unavailable"

    var body: some View {
        Picker(label, selection: $selection) {
            if !options.contains(where: { $0.value == selection }) {
                Text(placeholder).tag(selection)
            }
            ForEach(options) { option in
                Text(option.title).tag(option.value)
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .frame(maxWidth: .infinity)
        .disabled(options.isEmpty)
        .accessibilityLabel(label)
    }
}

/// Battery state using the system progress indicator and semantic colors.
struct BatteryRow: View {
    let label: String
    let level: Int?
    let isCharging: Bool

    var body: some View {
        HStack(spacing: 10) {
            Text(label)
                .frame(width: 40, alignment: .leading)
            if let level {
                ProgressView(value: Double(level), total: 100)
                    .tint(level <= 20 ? .red : .green)
                    .accessibilityHidden(true)
                if isCharging {
                    Image(systemName: "bolt.fill")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
                Text("\(level)%")
                    .monospacedDigit()
                    .frame(width: 40, alignment: .trailing)
            } else {
                Spacer()
                Text("Unavailable")
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(level.map { "\($0) percent\(isCharging ? ", charging" : "")" } ?? "Unavailable")
    }
}
