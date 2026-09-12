# OldLaunchpad

A macOS Launchpad-style app launcher prototype inspired by the older macOS Launchpad layout.

## Run

For normal use, double-click `OldLaunchpad.app` on the Desktop.

For development:

```sh
swift run OldLaunchpad
```

After launch, OldLaunchpad shows immediately. You can reopen it later with either:

- Menu bar grid icon
- `Control + Option + Command + Space`

Controls:

- Type in the search field to filter apps
- Click a category pill to filter
- Click an app icon to open it
- Press `Esc` to close the overlay

## Current MVP

- Full-screen dark translucent overlay
- Real app icons from installed `.app` bundles
- App discovery from:
  - `/Applications`
  - `~/Applications`
  - `/System/Applications`
  - `/System/Applications/Utilities`
- Basic category mapping from `LSApplicationCategoryType`
- Global hotkey with Carbon `RegisterEventHotKey`

## Gesture Note

macOS does not provide a reliable public API for a global four-finger pinch gesture trigger. The likely next steps are:

1. Keep the public-API version with a configurable global shortcut.
2. Add a preferences window so users can choose the shortcut.
3. Experiment with accessibility/event-tap based gesture detection.
4. If you only need a personal tool and accept private APIs, evaluate private multitouch APIs separately.

The first route is safest for signing, distribution, and long-term maintenance.
