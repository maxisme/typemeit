# Type Me It

## Running a build locally

Debug builds are a separate app, `Type Me It Dev` (bundle id `it.typeme.typemeit.dev`),
signed with the Developer ID certificate. Run it straight from DerivedData; never copy
a build over `/Applications/Type Me It.app`, which is the user's release install.

```sh
DEVELOPMENT_TEAM=Z28DW76Y3W xcodegen generate
xcodebuild -project TypeMeIt.xcodeproj -scheme TypeMeIt -configuration Debug -derivedDataPath build/dd build
open "build/dd/Build/Products/Debug/Type Me It Dev.app"
```

Because the signature is stable, macOS keeps the dev app's Input Monitoring, Microphone
and Accessibility grants across rebuilds. They are granted once through the dev app's
own onboarding. The dev app has its own UserDefaults, so settings and onboarding state
do not carry over from the release app.

The settings window opens from the menu bar puff → "Type Me It"; the app menu has no
settings item. `open -a "Type Me It Dev"` on a running instance also reopens it.
