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

The grant is tied to the signature of the binary, so a locally built app
asks again with every new build. The request is made on the main thread,
where the framework waits for the answer — until the prompt is answered,
the main thread is blocked and the whole panel is frozen. That is macOS
behaviour rather than a choice of this app, but it is worth knowing when
the panel does not open: the Bluetooth prompt is waiting somewhere.

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

## The earbud

The app has no artwork of its own from Apple, so the earbud in the menu bar,
in the panel header and in the section titles is drawn here as a single
`Path` (`Sources/BudsUI/EarbudIcon.swift`).

The system symbol for "ear" was rejected: it says *ear*, not *earbuds*, and
an ear next to a battery percentage looks like a mistake. The same shape is
used in all three places, so the app speaks with one voice.

The silhouette had to survive a 15-point menu bar, where a shape has to be
recognised from its outline alone. Three versions were rendered and
rejected before the current one:

| Version | Read as |
|---|---|
| Round head on a thin stalk | A mushroom |
| Wide body with a diagonal nozzle | A magnifying glass |
| Symmetric head tapering into a stem | A light bulb |

What works is the silhouette everybody knows: a head that is slightly
taller than it is wide, and a straight stem that hangs off it at an angle.
The state is drawn as a solid bud when noise cancelling is on and as an
outline otherwise.

## The codec line

The earbuds do not report their codec — macOS negotiates it with the
Bluetooth controller and keeps the result to itself. The system does write
the outcome into its log, though, and that is where the numbers come from.

The daemon only writes the line when something asks it for the controller
information. `system_profiler SPBluetoothDataType` does exactly that, and
it is cheap: it answers in a tenth of a second. The line is then read back
with `log show --last 20s`, which takes about half a second. The sample
rate comes from CoreAudio instead, because it describes the stream macOS
actually plays.

```
… Bluetoothd: GetControllerInfo: … BtRt 192 Kbps, Codc AAC-LC, … DvNm 'HUAWEI FreeBuds 6' …
```

The daemon writes one line per device, so the line of the earbuds is picked
out by its device name, and the newest such line is the one that describes
the stream that is running now.

The whole read happens in a detached task, and the panel shows the value it
already has until the new one arrives. When the codec cannot be read at
all, the line falls back to the Bluetooth profile and the sample rate, so
it always says something true.

The codec is **read-only**: on macOS the operating system decides which
codec is used, and there is no API to change it. The earbuds' own *sound
quality* setting is a separate, writable preference, and the panel shows
both so they are not confused.

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

## Panel sizing

A `MenuBarExtra(.window)` popover sizes itself to the **ideal** size of its
content, and a `ScrollView` reports an ideal height of roughly zero. Left
alone, the popover collapses to the height of the header and the entire
control area is clipped away — the panel looks like a title bar with
nothing under it, while the accessibility tree still lists every control.

The fix is to give the scroll area an explicit height, and to keep that
height in step with the content. Two things were tried and rejected along the
way:

- **Relying on the ideal size** of the content inside the scroll view does
  not work, for the same reason.
- **Measuring the content** with a plain `GeometryReader` in a background
  inside the scroll view reports a height of `0`, so the area collapses again
  and the measurement never recovers. The scroll view proposes no height of
  its own; pinning the content with `fixedSize(horizontal: false, vertical:
  true)` gives it one, and the measurement then works.

So the content is measured and the scroll area takes that height. The popover
window needs one more step: `MenuBarExtra` sizes its window **once**, when the
popover appears, and never touches it again, so the window keeps whatever
height the panel guessed while the content was still being laid out. The
panel therefore resizes the window itself (`NSWindow.setFrame`) as soon as the
measurement arrives. The measurement happens during the initial layout, so the
user never sees the wrong size, and the panel grows and shrinks with the
content: 619 pt with the earbuds connected and noise control off, 654 pt with
the cancellation level shown.

The panel is 320 pt wide, and the scroll area never grows past the height
that fits on the smallest attached display together with the menu bar — past
that point the area scrolls.

The measurement travels through a preference, and the action of a preference
is a *sendable* closure: it cannot touch the state of the view. The
measurements therefore live in a small main-actor object (`PanelMetrics`),
which is safe to capture, and the view reads them from there. Writing them
straight into `@State` from the preference action compiles with a recent
compiler and fails under strict concurrency on an older one — the build then
passes locally and breaks on CI, which is exactly the kind of difference that
should not depend on the toolchain.

## Feedback on refused changes

Every write is read back from the earbuds, so the app knows whether a change
was accepted. The panel shows a compact banner when it was not: the control
keeps its old value, and the banner explains what happened instead of
failing silently.

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
