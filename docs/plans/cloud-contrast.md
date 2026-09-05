# The cloud goes black or white against what is behind it

## Problem

The cloud's tint follows the system appearance: white in dark mode, dark grey
in light mode (`CloudView.tint`). It ignores what is actually under it, so a
white cloud over a white page in dark mode, or a dark cloud over a dark editor
in light mode, disappears. A user-chosen colour has the same problem.

## Decision

Sample the screen under the cloud and pick white or dark from its luminance.
This needs Screen Recording, which macOS grants for the whole screen or not at
all; there is no region-scoped permission. The grant is optional. Without it
the cloud keeps its appearance-based tint.

Considered and rejected:

- **Vibrancy** (`NSVisualEffectView`, `.behindWindow`). Free, but it produces a
  blurred material, not a crisp shape, and the puff shader would have to
  become a mask over it. Worth revisiting if the Screen Recording ask proves
  too costly in onboarding.
- **Accessibility.** Exposes no appearance information. The only signal is the
  per-app `NSRequiresAquaSystemAppearance` override, which almost nobody sets.
- **Sequoia's content picker.** Needs no grant but asks the user to choose a
  window each time. Useless for a passive indicator.

## Design

### Sampling

`ScreenSampler` (new, `TypeMeIt/Overlay/ScreenSampler.swift`), an actor:

1. `SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)`
   to find the display under the panel and our own overlay window.
2. `SCContentFilter(display:excludingWindows:)` excluding the overlay panel.
3. `SCScreenshotManager.captureImage` with `sourceRect` set to the cloud's
   rectangle (the `Circle().scale(0.45)` hit area, in display coordinates) and
   `width`/`height` of 8 x 8 pixels. `showsCursor` off.
4. Average the relative luminance of the pixels. Return `.light` above 0.5,
   `.dark` below.

The sample is 64 pixels; nothing is stored, logged or kept beyond the call.

### When to sample

- Once when the cloud arrives, before the first frame if the capture returns
  within 50 ms, else the appearance tint is used for the first frame and the
  sampled tint fades in over 0.2 s.
- While pinned, every 1 s, since the user may switch windows under it.
- Never while transcribing or cleaning up; the cloud is leaving.
- Skipped when `CGPreflightScreenCaptureAccess()` is false.

### Tint

`CloudView.tint` gains a `backdrop: Backdrop?` input from `OverlayModel`.
When set, the base is white for `.dark` and `NSColor(white: 0.25)` for
`.light`, replacing the `scheme` check. The green lean for clean-up and the
user's chosen colour are unchanged; a chosen colour is not sampled against,
since the user picked it deliberately. Whether to darken or lighten a chosen
colour for contrast is a later question.

### Permission

- Settings gains a toggle under the cloud section, "Match the cloud to what is
  behind it", off by default. Turning it on calls
  `CGRequestScreenCaptureAccess()`; if the grant is refused the toggle stays off
  and a line under it points at System Settings, as the Accessibility step in
  onboarding does.
- Onboarding does not ask. The app works without it, and a fourth permission
  in the first-run flow is the wrong place for an optional one.
- The dev app keeps its grant across rebuilds because its signature is
  stable, as with the other three.

### Privacy page

`web/privacy.html` gains one paragraph: when the option is on, the app reads
a few pixels of the screen under the cloud to choose its colour. The pixels
are averaged in memory and discarded. Nothing is stored or sent. macOS asks
for Screen Recording because that is the only permission that allows it.

## Cost

- Sequoia and later remind the user periodically that the app can see the
  screen. The Settings toggle's description should say this so the reminder is
  not a surprise.
- One 8 x 8 capture per second while pinned. Measure; ScreenCaptureKit
  screenshots are cheap but not free, and the cloud is on screen for the
  length of a dictation.

## Steps

1. `ScreenSampler` with a unit test on the luminance average over a synthetic
   `CGImage`.
2. `OverlayModel.backdrop`, sampled by `OverlayPanel.show` and a repeating
   task while pinned, cancelled on hide.
3. `CloudView.tint` reads the backdrop.
4. Settings toggle and the request-permission flow.
5. Privacy page paragraph.
6. Try it against a white page in dark mode, a dark editor in light mode, and
   with the grant refused.
