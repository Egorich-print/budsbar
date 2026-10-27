# Motion research notes

The brief asked for connection animations inspired by **HUAWEI AI Life**,
while shipping no Huawei or Honor intellectual property. This note records
what was studied, what was deliberately *not* taken, and what was built
instead.

## What was studied

`AI Life 11.0.2.305` (`com.huaweioverseas.smarthome`) ships its earbud UI as a
**runtime plugin**, `assets/plugins/com.huawei.smartaudioplugin.jar` (7.4 MB,
875 classes). The connect animation lives inside that plugin, not in the main
APK — which is why a scan of the outer archive finds no earbud assets at all.

The relevant pieces:

| Artifact | Role |
|---|---|
| `res/drawable/accessory_connect_anim.xml` | `android:animated-rotate`, `fromDegrees="0.0"` → `toDegrees="360.0"`, `pivotX/pivotY = 50%`, wrapping `@mipmap/connect_loading_icon` |
| `res/layout/accessory_ripple_view.xml` | a 100 dp container holding four 33 dp `iv_circle_1…4` images, each `@mipmap/accessory_ripple_circle`, all starting at `alpha=0` |
| `com.huawei.accessory.widget.RippleView` | the driver that animates those circles |

### The motion, in numbers

`RippleView` uses two interpolators:

- fade — `PathInterpolator(0.33, 0.0, 0.67, 1.0)`
- scale — `PathInterpolator(0.2, 0.0, 0.2, 1.0)`

For the connecting sequence it plays, per circle:

- alpha `0 → 1` over ~416 ms
- then scale `1 → 3` together with alpha `1 → 0` over ~833–1167 ms

and the four circles are staggered by roughly 416 ms, so the wave travels
outward. The rotating `animated-rotate` gradient runs continuously behind it
as the "still working" indicator.

The *shape* of the idea: **a continuous conic sweep, plus a set of rings
that expand and dissolve as they travel outward, staggered so the group
reads as one wave.**

## What was deliberately not taken

- No Huawei artwork. The `connect_loading_icon` and `accessory_ripple_circle`
  bitmaps were **not** copied, traced or adapted.
- No Lottie or sprite assets. (There is no Lottie in this APK at all; the
  animation is a plain `animated-rotate` plus `ObjectAnimator`s.)
- No source code. `RippleView` was read to understand *timing and structure*,
  which is interoperability-observable behaviour, not expression.
- The exact numeric constants were not reproduced.

## What was built

`Sources/BudsBar/Motion.swift` implements the same **motion idea** with
original geometry, palette, timing and rendering technique:

| Element | Implementation |
|---|---|
| Working indicator | `SweepRing` — an `AngularGradient` masked into a 28 %-length arc, spun around its centre. The gradient has a bright leading edge and a fading tail, so the travel direction is legible. Rendered with a SwiftUI shape, not an image. |
| Connect wave | `ExpandingRing` ×3 — `strokeBorder` rings, scale `0.5 → 2.1`, cubic ease-out, 0.18 s stagger, 0.72 s per ring. |
| Noise control | `NoiseWaves` — `Canvas` strokes that drift outward in the ambient state and collapse inward when cancellation engages. |
| Equalizer | `BandGraph` — five `Canvas` bars that re-shape to the new curve. |
| Volume | `LevelArc` — a 240° arc that fills to the level, turning red past 85 %. |
| Halo | A `RadialGradient` behind the glyph that blooms with noise control. |

### Why the numbers differ

| | AI Life | BudsBar | Reason |
|---|---|---|---|
| Rings | 4 | 3 | Three fits a 56 pt menu-bar glyph; four would crowd it. |
| Scale | 1 → 3 | 0.5 → 2.1 | A 3× expansion would exceed the panel's breathing room. |
| Stagger | ~416 ms | 180 ms | Faster, so the wave feels like a response rather than a wait. |
| Duration | 833–1167 ms | 720 ms | Matches the pace of a macOS panel, which is quicker than a phone onboarding screen. |
| Sweep | 360° image rotation | conic gradient | A gradient sweep is sharper at small sizes and needs no image asset. |

## Verification of the result

The animations are rendered by the same SwiftUI code in the app and in the
preview harness, so the motion can be inspected at any size without a device
in range. See `docs/architecture/DESIGN.md` for the full rationale.
