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
