# type me it

## Running a build locally

Debug builds are a separate app, `type me it dev` (bundle id `it.typeme.typemeit.dev`),
signed with the Developer ID certificate. Run it straight from DerivedData; never copy
a build over `/Applications/type me it.app`, which is the user's release install.

```sh
DEVELOPMENT_TEAM=Z28DW76Y3W xcodegen generate
xcodebuild -project TypeMeIt.xcodeproj -scheme TypeMeIt -configuration Debug -derivedDataPath build/dd build
open "build/dd/Build/Products/Debug/type me it dev.app"
```

Only one dev instance may run at a time. Other worktrees build the same app, so
check for and stop any running copy before launching yours:

```sh
pgrep -fil "type me it dev.app/Contents/MacOS"
pkill -fi "type me it dev.app/Contents/MacOS"
```

Because the signature is stable, macOS keeps the dev app's Input Monitoring, Microphone
and Accessibility grants across rebuilds. They are granted once through the dev app's
own onboarding. The dev app has its own UserDefaults, so settings and onboarding state
do not carry over from the release app.

The settings window opens from the menu bar puff → "type me it"; the app menu has no
settings item. Opening the build path again on a running instance also reopens it.
Avoid `open -a "type me it dev"`: with several worktree builds registered, Launch
Services may start another worktree's copy.

## Copy: less is more

Every string the user sees — group titles, row labels, captions, empty states,
menu items — is written short. Cut hedging and cut throat-clearing before you
cut information; a one-word title beats a three-word one whenever the row it
sits over already tells the reader what the numbers are. When you find yourself
writing an explainer inside a label, the label is wrong. This rule holds even
when a longer version scans fine on its own: on a page of short strings a long
one snags, and the page reads as noisier than it is.

## Eval variants are observed, never predicted

An `alsoAccepted` entry in `Scripts/cleanup-eval/cases.json` records an output
the model actually produced in a run and that was judged fine. Do not add one
because the model might plausibly do something; run `make eval`, read the
output, then add it with a `why` that says what was seen. Behaviour that is
pure code (digits, lists, quotes, the safe contractions) is tested in
`TypeMeItTests`, not with eval cases.
