// BudsBar — hand-drawn controls
// SPDX-License-Identifier: MIT
//
// The panel is drawn with SwiftUI primitives rather than AppKit-backed
// `Picker` styles and the system switch, for two reasons:
//
//  1. `NSSegmentedControl`, `NSPopUpButton` and `NSSwitch` draw their
//     labels and states on layers that an offscreen capture does not reach —
//     the documentation renders would show empty pills and a permanently
//     off switch.
//  2. Drawing the controls ourselves lets them use the project's own
//     visual language, instead of the stock macOS chrome.
//
// The controls keep their native semantics for assistive technologies:
// the switch exposes a `Toggle`, the segments are buttons carrying the
// selected trait, and the menus report their value.

import SwiftUI

/// The fill of the selected segment.
private let selectionFill = LinearGradient(
    colors: [Color.accentColor, Color.accentColor.opacity(0.82)],
    startPoint: .top,
    endPoint: .bottom
)

/// One selectable entry.
struct ChoiceOption<Value: Hashable>: Identifiable {
    let value: Value
    let title: String

    var id: Value { value }
}

/// A segmented control drawn entirely in SwiftUI.
struct SegmentedChoice<Value: Hashable>: View {
    let options: [ChoiceOption<Value>]
    @Binding var selection: Value
    /// Name of the group, for assistive technologies.
    var label: String = ""

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options) { option in
                let isSelected = option.value == selection
                Button {
                    selection = option.value
                } label: {
                    Text(option.title)
                        .font(.system(size: 10, weight: isSelected ? .semibold : .medium))
                        .foregroundStyle(isSelected ? Color.white : Color.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(isSelected ? AnyShapeStyle(selectionFill) : AnyShapeStyle(.clear))
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(option.title)
                .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.primary.opacity(0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
    }
}

/// A switch drawn in SwiftUI, matching the rest of the panel.
///
/// The system switch is backed by `NSSwitch`, whose on-state an offscreen
/// capture does not record — the documentation renders would show every
/// switch as off. The control exposes a native `Toggle` to assistive
/// technologies through `accessibilityRepresentation`, so VoiceOver still
/// announces it as a checkbox.
struct BudsSwitch: View {
    @Binding var isOn: Bool
    var label: String = ""

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            HStack(spacing: 8) {
                Text(label)
                    .font(.system(size: 12))
                    .foregroundStyle(.primary)
                Spacer(minLength: 8)
                track
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityRepresentation {
            Toggle(label, isOn: $isOn)
        }
    }

    private var track: some View {
        ZStack(alignment: isOn ? .trailing : .leading) {
            RoundedRectangle(cornerRadius: 7.5, style: .continuous)
                .fill(isOn ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color.primary.opacity(0.16)))
            Circle()
                .fill(Color.white)
                .frame(width: 12, height: 12)
                .shadow(color: .black.opacity(0.22), radius: 1, y: 0.5)
                .padding(.horizontal, 1.5)
        }
        .frame(width: 26, height: 15)
        .animation(.spring(response: 0.28, dampingFraction: 0.75), value: isOn)
    }
}

/// A compact control that shows the current value and opens a menu.
struct ValueMenu<Value: Hashable>: View {
    let options: [ChoiceOption<Value>]
    @Binding var selection: Value
    /// Name of the group, for assistive technologies.
    var label: String = ""
    /// What the chip shows when nothing is selected.
    var placeholder: String = "—"

    var body: some View {
        Menu {
            ForEach(options) { option in
                Button {
                    selection = option.value
                } label: {
                    Text(option.title)
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(currentTitle)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 2)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 7, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(0.07))
            )
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(maxWidth: .infinity)
        .accessibilityLabel(label)
        .accessibilityValue(currentTitle)
    }

    private var currentTitle: String {
        options.first(where: { $0.value == selection })?.title ?? placeholder
    }
}
