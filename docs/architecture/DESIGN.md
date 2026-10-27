# BudsBar design notes

## Surface

`MenuBarExtra` with the `.window` style, minimum macOS 14.

Why this and not the alternatives:

- **WidgetKit accessory widgets are not an option on macOS.**
  `accessoryCircular`, `accessoryRectangular` and `accessoryInline` are
  marked `@available(macOS, unavailable)` in the SDK — they are iOS and
  watchOS families. On macOS the available families are `systemSmall`,
  `systemMedium`, `systemLarge` and `systemExtraLarge`.
- **`MenuBarExtra(.menu)`** renders a plain `NSMenu`, so it cannot host
  sliders, segmented pickers or custom drawing.
- **`MenuBarExtra(.window)`** gives a popover-style panel that accepts
  standard controls, and it is the surface a macOS user expects for a
  rich control panel.
- There is no `MenuBarExtraStyle.section`; only `.window`, `.menu` and
  `.automatic` exist.

The app sets `LSUIElement` so it has no Dock icon, and
`NSBluetoothAlwaysUsageDescription` in `Info.plist`. That key is **not
optional**: without it macOS refuses the Bluetooth request without
prompting and kills the process with SIGABRT. The app must also be
launched through LaunchServices (`open`), so the bundle — not the
terminal — is the process responsible for the privacy grant.

## Motion design

All artwork and animation in this project is original. The design borrows
the general motion vocabulary of modern Bluetooth device interfaces —
expanding rings, inward wave collapse, band morphs — and implements it
from scratch with SwiftUI `Canvas` and shape primitives.

| Event | Motion | Timing |
|---|---|---|
| Connect | A conic sweep spins behind the glyph while three rings radiate outward, staggered by 0.18 s | 0.72 s per ring |
| Disconnect | Glyph desaturates, the sweep stops | 0.30 s |
| Noise control | Waves collapse inward when cancelling, drift outward otherwise; a halo blooms behind the glyph | 0.35 s |
| Equalizer | Five bars re-shape to the new curve, left to right | 0.36 s |
| Volume | A 240° arc fills to the new level, turning red above 85 % | 0.12 s |
| Gesture change | The picker row cross-fades and the glyph springs | 0.24 s |

Guidelines followed:

- **No animation while idle.** A looping animation in the menu bar is
  noise. Motion is a reaction to a state change, then it settles.
- **Indeterminate progress is a spinner, never a fake determinate bar.**
  While connecting, the panel shows radiating rings.
- **Volume is silent.** macOS already animates its own volume slider;
  repeating it is a UX smell. The panel shows the value, and the arc
  is a readout rather than a celebration.
- **Alerts are static.** A low battery is a colour, not a motion.

## Hand-drawn controls

The segmented controls, value menus and the switch are drawn in SwiftUI
rather than taken from AppKit. Two reasons:

- **Rendering.** `NSSegmentedControl`, `NSPopUpButton` and `NSSwitch` draw
  their labels on layers that an offscreen capture does not reach, so the
  documentation renders showed empty pills and a permanently off switch.
  Drawing the controls in SwiftUI makes the captured image identical to
  what the app shows.
- **Consistency.** The panel already speaks its own visual language —
  accent-tinted segments, rounded chips, a blooming halo. Stock chrome sat
  awkwardly next to it.

Accessibility is not lost: the hand-drawn switch exposes a native `Toggle`
through `accessibilityRepresentation`, the segments are buttons carrying the
selected trait, and the value menus report their current value as the
accessibility value. The live panel's accessibility tree was checked
against the running app.

## WidgetKit

A WidgetKit extension is deliberately **not** part of v1:

- Building an `.appex` needs an Xcode target, and the extension must be
  embedded and signed alongside the app.
- Widget animations are capped at **2 seconds** and cannot use
  `NSViewRepresentable`, so no Core Animation layer tree, no `CAEmitterLayer`,
  no continuous `TimelineView(.animation)`.
- A menu-bar app needs no extension point and no special signing, which
  keeps the install path to a single `cp`.

If a glanceable tile is wanted later, it should be a *status card* with a
≤2 s one-shot reaction animation, while all rich motion stays in the
menu-bar panel.

## State handling

The device sleeps aggressively, and the baseband link drops with it. The
app therefore:

1. Requests a baseband connection before opening the control channel and
   retries for up to 12 s.
2. Polls every 20 s while connected, and the panel can be refreshed
   manually.
3. Treats a dropped channel as a disconnect and re-establishes it.

Reads are serialised: only one request is outstanding at a time, which
matches how the device behaves.

## Volume

The earbuds expose no volume command. The in-ear volume is whatever
macOS sends to the Bluetooth sink, so the slider drives the CoreAudio
output device whose name matches the earbuds. A device-side "sound
quality preference" setting steers the codec preference separately.

Two details make the bridge work on Bluetooth devices:

- A pair of earbuds registers **two** CoreAudio devices under the same
  name — one for the microphone, one for the speakers. Only the one with
  an output stream is a valid volume target, so the input device is
  filtered out before the name is matched.
- Bluetooth sinks expose their software volume through the **virtual main
  volume** property (`'vmvc'`), not through
  `kAudioDevicePropertyVolumeScalar`. The selector is not in the public
  SDK headers, but it is the property CoreAudio itself keeps for a
  Bluetooth device, and the earbuds follow it. The scalar properties are
  still tried as a fallback for other devices.
