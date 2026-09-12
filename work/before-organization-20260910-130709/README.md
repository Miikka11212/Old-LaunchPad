# OldLaunchpad

A native macOS launcher with the classic Launchpad layout: a compact search field,
up to seven columns and five rows of larger app icons, readable labels, clickable page dots, and
a blurred version of your desktop wallpaper. Smaller displays adapt the grid to
keep the icons visible. The category bar has been removed from the main view.

## Run

Double-click `OldLaunchpad.app` on the Desktop. Reopen it using its Dock icon,
the menu bar grid icon, or **Control + Option + Command + Space**.

For development, run `swift run OldLaunchpad`. Requires macOS 13+ and Swift 6+.

## Controls

- Type to search installed applications; matching ignores case and accents.
- Click an icon to launch, or press **Return** to open the first search result.
- Press **Down** from search to select an app, then use the arrow keys and **Return**.
- Use **Command + Left/Right**, swipe horizontally, or click a page dot to change pages.
- Use **Command + F** to focus and select the search text.
- Standard copy, paste, select-all, undo, and text-cursor shortcuts work in search.
- Press **Escape** to dismiss the launcher, or **Command + Q** to quit.
- Hover over a truncated label to see its full application name.

The launcher opens on the display containing the pointer. It refreshes the catalog
when reopened and reports launch failures without dismissing the launcher.
Page animations respect the system Reduce Motion setting.

## Validation

Run `./Scripts/test-navigation.sh` to check responsive grid bounds, pagination,
keyboard selection boundaries, and trackpad/mouse-wheel gesture handling.
The checks use the Swift compiler directly, so they also run with Command Line
Tools installations that do not include XCTest or Swift Testing macros.

Build an optimized executable with `swift build -c release`. If a prerelease
Swift toolchain's default build engine fails during signing or dSYM generation,
`swift build --build-system native -c release` provides a compatibility fallback.

## Scope

Apps are discovered from `/Applications`, `~/Applications`, and
`/System/Applications`, with system lookups for Safari and Finder. App icons and
wallpaper come from the current Mac. The native macOS Dock stays under system
control. Custom folders, drag-to-reorder, and a global pinch gesture are not
implemented.

System utility apps shown in the reference (including Activity Monitor, Automator,
Preview, QuickTime Player, and TextEdit) are hidden from the grid and search, as
are background agents and Adobe installer/diagnostic helpers. This only filters
the launcher; the installed apps remain available through macOS. The search bar
sits below the menu bar and display notch.

Opening and closing use a subtle zoom, window fade, and a crossfade between
sharp and blurred wallpaper. Pages slide together with a 0.38-second eased
transition; rapid navigation is queued. Hovering does not highlight icons.
Keyboard selection and pressed feedback remain visible. Reduce Motion uses
a short fade without zoom or page sliding.
