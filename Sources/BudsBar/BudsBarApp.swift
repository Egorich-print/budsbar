// BudsBar — application entry point
// SPDX-License-Identifier: MIT

import SwiftUI
import BudsCore
import BudsUI

@main
struct BudsBarApp: App {
    @StateObject private var controller = DeviceController()
    @State private var didConnect = false

    var body: some Scene {
        MenuBarExtra {
            ControlPanel(controller: controller)
                .onAppear {
                    guard !didConnect else { return }
                    didConnect = true
                    Task { await controller.connect() }
                }
        } label: {
            MenuBarLabel(state: controller.state, link: controller.linkState)
        }
        .menuBarExtraStyle(.window)
    }
}

/// The menu bar glyph: an earbud with a live battery readout.
struct MenuBarLabel: View {
    let state: DeviceState
    let link: LinkState

    var body: some View {
        Group {
            if let level = state.battery.lowest {
                HStack(spacing: 2) {
                    bud
                    Text("\(level)")
                        .font(.system(size: 11, weight: .medium))
                        .monospacedDigit()
                }
            } else {
                bud
            }
        }
        .accessibilityLabel(accessibilityLabel)
    }

    /// The bud itself: solid while noise cancelling, an outline otherwise.
    private var bud: some View {
        EarbudIcon(filled: link == .connected && state.noiseMode == .cancellation)
            .frame(width: 15, height: 15)
    }

    private var accessibilityLabel: String {
        switch link {
        case .connecting:
            return "BudsBar, connecting"
        case .connected:
            let mode = state.noiseMode == .cancellation ? "noise cancelling" : "noise off"
            return "BudsBar, \(mode)"
        default:
            return "BudsBar"
        }
    }
}
