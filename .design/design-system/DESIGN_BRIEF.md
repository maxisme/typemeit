# Design Brief: Type Me It Design System

## Problem

A Mac user who types all day hears about Type Me It and opens the website. They need to know, in under thirty seconds, three things: what the app does, that speech never leaves their Mac, and where the download is. Competing dictation apps answer those questions under gradients, feature grids and paragraphs of copy, so the reader has to work to find them.

There is no website today. The app has a visual language — a System Settings-style panel, akar icons, SF type, monospaced digits — but none of it is written down. Anything built for the web now would be invented separately and drift from the app.

## Solution

A black-and-white token set and component library with one source of truth. `design/tokens.json` holds every colour, type, spacing, radius and motion value, and generates two outputs: a Tailwind v4 `@theme` stylesheet for the website and a `DesignTokens.swift` of `Color`, `Font` and `CGFloat` constants for the app. Web components are built with Tailwind against those tokens and documented on a single reference page that uses specimen labels rather than copy.

The landing page is the first consumer of the components; it is not part of this brief. The Swift settings panel adopts the generated constants in a later pass; this brief does not change it.

## Experience Principles

1. **Show before tell** — The pill, the meter and the keycap demonstrate the product. Text appears only where a demonstration cannot carry the point. Resolves clarity against copy volume.
2. **Structure from line and space, not surface** — Grouping and hierarchy come from hairline rules and whitespace. No fills, no gradients, and one shadow, reserved for the recording pill because it is the only element that floats above the desktop. Resolves hierarchy against minimalism.
3. **Two emphasis moves, no accent** — Inversion (a solid ink slab) marks the primary action and the selected state. Serif italic marks emphasis in text. Nothing else signals importance. Resolves emphasis against the absence of colour.

## Aesthetic Direction

- **Philosophy**: Editorial serif contrast on a monochrome instrument. Display type is a sourced serif with a real italic and an optical-size axis. UI and body type is the platform face (`-apple-system`, which renders as SF on the audience's machines), chosen because the site documents a Mac app whose voice is SF. Measurement — durations, counts, keycaps — is set in SF Mono.
- **Display face**: DM Mono (300/400/500, italic), loaded from Google Fonts; also the measurement face. Newsreader and Instrument Serif were considered and rejected: the serif read as editorial rather than as a tool. All text is set lowercase.
- **Tone**: Quiet, exact, unhurried. It should be obvious what the product does with very little copy.
- **Reference points**: Apple System Settings (the panel's source), iA Writer, Teenage Engineering documentation, Braun product manuals.
- **Anti-references**: Gradient and glassmorphism AI-startup landing pages. "Supercharge" copy. Grids of same-size icon-and-heading cards. The marketing aesthetics of Wispr Flow and Superwhisper.

## Existing Patterns

Read from `TypeMeIt/SettingsUI/*.swift` and `TypeMeIt/Overlay/PillView.swift`. Nothing exists on the web side: no `package.json`, no CSS, no fonts loaded.

- **Typography**: SF system font. Row label 13pt; subtitle 11pt secondary; group title 11pt semibold uppercase; stat value 26pt semibold with monospaced digits; metadata 10pt tertiary; pill text 12pt; badge 10pt semibold.
- **Colours**: `controlBackgroundColor` surfaces; `.secondary` and `.tertiary` text; `Color.accentColor` (system blue) on word chips, the heatmap, the WPM gauge and the starred icon; black at 0.04–0.18 opacity for fills and borders; a red meter (`0.824, 0.271, 0.231` light / `1, 0.412, 0.38` dark); seven category colours in Insights. All of this colour is removed. The meter becomes ink; the heatmap and gauge become a tonal ramp of ink.
- **Spacing**: 20pt page padding; 18pt between groups; 12pt horizontal and 9–10pt vertical row padding; 6pt between chips; 14pt stat-card padding; 16pt between a row's label and its control.
- **Radii**: 10 for groups and stat cards; 7 for the search field; 6 for the HEARD box and edit box; 5 for keycaps; 4 for the Edited badge; capsule for the pill, chips and pill buttons.
- **Borders**: 0.5pt at black 0.12 (groups), 0.18 (keycap), 0.20 (search field).
- **Components**: `SettingsGroup`, `SettingsRow`, `Keycap`, `FlowLayout` word chips with a remove button, `PillView` (40pt capsule, HUD blur, 8-bar meter at 4pt width and 3pt gap, 22–24pt circular chip buttons, capsule text buttons), stat card, WPM gauge with a typing marker, category distribution bar, ranked top-apps list, 16-week heatmap (11pt cells, 3pt gap, 2.5 radius), Edited badge, HEARD box, empty states, search field, icon buttons (14pt glyph in a 24pt hit area).
- **Icons**: 17 akar icons — arrow-forward-thick, check, chevron-down, circle-check, clipboard, clock, copy, cross, gear, microphone, pencil, pin, search, star, statistic-up, text-align-left, trash-can. 24 viewBox, stroke 2, round caps and joins, `currentColor`. These port to the web unchanged.

## Component Inventory

Every web component is new. "Swift counterpart" names the app view that already implements the same pattern; the web version matches its measurements.

| Component | Status | Notes |
| --- | --- | --- |
| `design/tokens.json` | New | Single source of truth |
| Tailwind v4 `@theme` stylesheet | New | Generated from tokens.json |
| `DesignTokens.swift` | New | Generated from tokens.json; added to the target, not yet used by any view |
| Reference page | New | One HTML page, specimen labels only, light and dark |
| Type scale: Display 1–3, Title, Heading, Body, UI, Label, Micro | New | Label and UI match the panel's 11pt and 13pt |
| Button: primary, secondary, quiet, critical | New | DM Mono label, radius sm, ink outline; sizes sm/md/lg; icon-only variant; hover, active, focus, disabled, loading |
| Link | New | Inline, underline with offset |
| Rule | New | Grouping hairline and control boundary are separate tokens |
| Icon sprite | New | The 17 akar icons |
| Text field, textarea | New | Swift counterpart: `TextField(.roundedBorder)`, `TextEditor` |
| Select | New | Swift counterpart: `Picker` |
| Search field | New | Swift counterpart: History search |
| Toggle | New | Swift counterpart: `Toggle(.switch)` |
| Checkbox, radio, segmented control | New | No counterpart yet |
| Keycap | New | Swift counterpart: `Keycap`; rendered as `<kbd>` |
| Settings group | New | Swift counterpart: `SettingsGroup`; web version is a square inset list with an ink border and the title as an inverted tab |
| Settings row | New | Swift counterpart: `SettingsRow`; label, subtitle, trailing control |
| Tab bar | New | Swift counterpart: `TabView` with five tabs |
| Chip (removable) | New | Swift counterpart: custom-word chips |
| Badge | New | Swift counterpart: Edited badge |
| Icon button | New | Swift counterpart: `iconButton` in HistoryTab |
| Footer bar | New | Swift counterpart: History's "Keep the last" bar |
| Empty state | New | Swift counterpart: History and Insights empty text |
| Pill | New | Swift counterpart: `PillView`; states recording, pinned, transcribing, cleaning up, copy prompt, learned, undone |
| Meter (8-bar) | New | Swift counterpart: `meter` in PillView |
| Gauge | New | Swift counterpart: `wpmCard` |
| Stat block | New | Swift counterpart: `statCard` |
| Heatmap | New | Swift counterpart: `calendar` in InsightsTab |
| Distribution bar | New | Swift counterpart: `categories`; tonal ramp with direct labels, no colour legend |
| Ranked list | New | Swift counterpart: `topApps` |

## Key Interactions

- **Button**: secondary and quiet gain an `ink-a04` fill on hover over 120ms; primary shifts its slab to `ink-a88`. Active state darkens one step further; no scale transform. Loading replaces the label with the dots animation from the pill at the same width, so the button does not resize. Disabled drops to `ink-3` text with no fill and `not-allowed` cursor.
- **Focus**: 2px ink ring, 2px offset, on `:focus-visible` only. Same ring on every interactive element.
- **Toggle**: the knob travels 16px over 180ms ease-out. On is the slab fill with an inverted knob; off is a `rule-control` outline with an ink knob. State is carried by position and inversion, never colour.
- **Chip remove**: the chip collapses its width and fades over 180ms; neighbours reflow.
- **Settings row expansion** (History): the HEARD box reveals with height and opacity over 320ms.
- **Pill**: width animates between states over 560ms on an exponential ease-out. Meter bars follow the input level at 80ms linear. The transcribing wave and cleaning-up dots loop. Under `prefers-reduced-motion` all three are static.
- **Theme**: follows `prefers-color-scheme`; a `data-theme` attribute on the root overrides it.
- **The one authored motion moment** on the reference page is the live pill meter. Every other transition is functional and under 320ms.

## Responsive Behavior

- Reference page: two columns above 720px (token or component name left, specimen right); one column below.
- Display sizes clamp between 3rem and 5.5rem; nothing exceeds 6rem.
- Settings group stays full width at every size. Below 480px the row's control wraps beneath its label.
- Stat blocks sit three across at 900px and above, one across below.
- Heatmap scrolls horizontally inside its own container below 640px.
- Pill is 40px tall at every size; width comes from content.
- The page body never scrolls horizontally.

## Accessibility Requirements

- **Text contrast**: on light paper, `ink-2` (#4a4a4a) 8.9:1 and `ink-3` (#6e6e6e) 5.1:1; on dark paper, `ink-2` (#b4b4b4) 9.5:1 and `ink-3` (#8a8a8a) 5.7:1. No text is set lighter than `ink-3`.
- **Control boundaries**: `rule-control` is #949494 on light (3.03:1) and #6e6e6e on dark (3.86:1), meeting WCAG 1.4.11. The grouping `rule` token (#e4e4e4 / #262626) is decorative and exempt; it is never the only thing identifying a control.
- **State not by colour**: toggles and checkboxes carry state through knob position, fill inversion and `aria-checked`. The distribution bar labels each segment directly with its name and percentage. Heatmap cells carry a `title` with date and count.
- **Keyboard**: every interactive element is reachable and shows the focus ring. Tabs use arrow keys; the segmented control uses arrow keys.
- **Reduced motion**: meter, wave and dots render static; nothing loops.
- **Semantics**: keycaps are `<kbd>`; icons are `aria-hidden` beside a text label, or the icon-only button carries `aria-label`.
- **Hit targets**: icon buttons are 24×24 on desktop, matching the app; 44×44 where the layout is touch-first.

## Out of Scope

- Landing page copy, layout and imagery. A separate brief covers the page; this one supplies the components it will use.
- Any edit to `TypeMeIt/SettingsUI/*.swift`, `PillView.swift` or other app views. `DesignTokens.swift` is generated and added to the target but nothing references it yet.
- Colour of any kind: no accent, no semantic red or green, no category palette. Destructive actions are identified by their label and a confirmation step, not by hue.
- Documentation, help, release notes and comparison pages.
- A React, Vue or Svelte component library. Output is Tailwind classes on plain HTML.
- Token tooling beyond one Node script that writes the two generated files. Style Dictionary is not adopted.
