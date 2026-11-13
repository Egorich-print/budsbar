# BudsBar design notes

## Surface

`MenuBarExtra` with the `.window` style, minimum macOS 27.2.

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

## Native macOS direction

The panel stays in the menu bar, following the compact interaction model of
Control Center. Native SwiftUI pickers, switches, sliders, progress indicators
and group boxes own their appearance, focus behavior and accessibility.
Semantic text styles and system materials follow the selected macOS appearance.

Connecting uses the system indeterminate progress indicator. Decorative rings,
equalizer curves and volume arcs have been removed. Device details sit behind
a disclosure control; left and right gesture pickers have visible side labels.
The header's options menu includes Quit BudsBar. The TWS earbud symbol is
larger in the header and uses the native `earbuds` symbol in the menu bar.

Without an active connection, the panel shows a system empty state and a
Connect action. Cached identity or battery data never enables device controls
while disconnected or connecting.

The cancellation-strength selector is withheld because the current protocol
reader does not distinguish the reported effect code from physical strength.
Noise-mode selection still uses the verified read-back behavior.

This follows Apple's guidance to adopt the system appearance through standard
components: [Adopting Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass).

## Menu bar symbol

The menu bar uses the transparent PNG monogram chosen from Felipe's reference,
stored in `Sources/BudsBar/Resources/MenuBarMonogram.png`. Swift Package Manager
packages it as a resource bundle, which `build-app.sh` copies into the app.
`MenuBarIcon` loads the PNG with `Bundle.module`, sizes it to 22 × 22 points,
and enables `isTemplate` so macOS supplies the foreground color in light and
dark appearances. `MenuBarExtra` receives an actual `Image(nsImage:)`.
Battery levels remain inside the panel. The panel uses SF Symbols for its
header and section labels.

The original earbud illustration remains available in the library, but is
not used as the menu bar label.

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

## Standard controls

`SegmentedChoice` wraps a segmented `Picker`, `ValueMenu` wraps a menu-style
`Picker`, and `BudsSwitch` wraps a switch-style `Toggle`. These wrappers retain
the existing bindings while delegating drawing, keyboard navigation, selection
and accessibility to macOS. Unknown or unread settings remain unavailable.

Offscreen captures can omit native control layers. Documentation renderer
images are layout aids; live light and dark appearance, keyboard and VoiceOver
checks are required before calling the UI visually verified.

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
≤2 s one-shot reaction animation. The current panel uses system control
transitions rather than decorative motion.

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
content, including when device information is expanded or an error appears.

The panel is 360 pt wide, and the scroll area never grows past the height
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
