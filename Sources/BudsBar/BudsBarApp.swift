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
        if let level = state.battery.lowest {
            HStack(spacing: 2) {
                Image(systemName: symbolName)
                Text("\(level)")
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
            }
        } else {
            Image(systemName: symbolName)
        }
    }

    private var symbolName: String {
        switch link {
        case .connecting: "earbuds"
        case .connected:
            state.noiseMode?.symbol ?? "earbuds"
        default: "earbuds"
        }
    }
}
