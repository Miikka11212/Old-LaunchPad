# OldLaunchpad

A native macOS app launcher with the classic Launchpad layout, larger icons,
blurred desktop wallpaper, smooth page slides, and subtle opening/closing motion.

## Run

Double-click `OldLaunchpad.app` on the Desktop. While it is running,
**Command + Space** toggles the launcher, a **four-finger pinch inward** opens it,
and a **four-finger spread outward** closes it and invokes macOS Show Desktop.
Its Dock icon, menu bar grid icon, and **Control + Option + Command + Space**
also remain available. The menu bar reports whether the shortcut and trackpad
listener are ready; **Show Desktop** is available from the menus as well.

Development: `swift run OldLaunchpad`. Requires macOS 13+ and Swift 6+.

### System shortcut setup

This Mac has been configured to release Spotlight's Command–Space and the system
four-finger pinch to OldLaunchpad. Two-finger zoom and four-finger swipes retain
their existing settings. To configure another Mac, run
`swift Scripts/configure-system-shortcuts.swift`; to restore the saved original
bindings, quit OldLaunchpad and run the same script with `--restore`.
The script saves only the affected values and preserves other shortcuts.

macOS exposes no public global four-finger gesture API. The listener dynamically
loads MultitouchSupport and restarts after wake; if it is unavailable, the keyboard
shortcut still works. Finger positions are used only to recognize gestures and
are not saved. Native Show Desktop uses the Dock's notification entry point.
These system interfaces are private and may need updates with future macOS releases.

## Organize apps

- **Reorder:** drag an icon between other icons. A white insertion line shows where it will go.
- **Change pages while dragging:** hold near the left or right edge of the grid.
- **Create a folder:** hold an app over the center of another app for about half a second, then release when the target highlights and the folder hint appears.
- **Add to a folder:** drop an app onto an existing folder.
- **Open a folder:** click it to reveal a compact 3×3 panel, with extra pages for more apps. Click its name at the top and press Return to rename, or right-click the folder and choose **Rename Folder…**.
- **Close a folder:** click outside the panel, choose **‹ All Apps**, or press Escape. The panel animates closed and returns to the same main page.
- **Move an app out:** drag it outside the folder panel and release. It returns to the main grid beside the folder. Dropping onto **‹ All Apps** or choosing **Move Out of Folder** also works.
- **Ungroup:** right-click a folder and choose **Ungroup Folder** to return its apps to the main grid.
- New folders are named **Folder**, **Folder 2**, and so on. Folders cannot be nested.
- Clear search before dragging to rearrange. Search can find apps inside folders.

## Add apps

Choose **Add Apps…** beside Search or from the empty-space right-click menu,
then select one or more installed `.app` bundles. Apps are added to the open
folder, or to the main grid if no folder is open. This also lets you bring back
an individually hidden app or explicitly include a filtered system utility.
Manually added apps are remembered across restarts, including apps outside the
usual Applications folders.

## Right-click menu

App icons offer **Open**, **Show in Finder**, **Get Info**, **Quick Look**,
**Share…**, and **Remove from Launchpad**. Get Info displays app metadata in an
inspector; Quick Look and Share use native macOS components.

Removing an app only hides its launcher entry. It does not uninstall or delete
anything. Right-click an empty part of the grid and choose **Restore Removed
Apps** to bring back apps removed using this menu. System utilities filtered by
the launcher stay filtered.

Order, folders, names, and removed apps save automatically to
`~/Library/Application Support/OldLaunchpad/local.oldlaunchpad/layout.json`.
Saves are atomic; an unreadable existing file is preserved instead of overwritten.

## Keyboard and navigation

- Type to search; matching ignores case and accents.
- **Return** opens the first search result. **Down** selects an icon; arrows move the selection and **Return** opens it.
- **Command + Left/Right**, horizontal swipes, or page dots change pages.
- **Command + F** focuses and selects the search text.
- Standard copy, paste, select-all, undo, and cursor shortcuts work in text fields.
- **Escape** leaves an open folder, then dismisses Launchpad. **Command + Q** quits.
- Hover over a truncated label to see its full name; ordinary hover does not highlight icons.
- Only the visible icon and label open an app. Clicking empty space on the main grid closes Launchpad.

The grid adapts to smaller displays and opens on the display containing the
pointer. The search field clears the menu bar/notch. Opening and closing use a
zoom and blur fade. Folder creation has a gentle pop, and folder panels zoom and
fade when opening or closing. Reduce Motion disables zoom and page slides.

## Validation

Run `./Scripts/test-navigation.sh` for organization, persistence, corruption
protection, legacy layout migration, manually added apps, app visibility, compact
folder pagination, icon hit targets, responsive bounds, keyboard boundaries,
and gesture checks. The checks run directly with the Swift compiler and require
no external test framework.

Run `./Scripts/test-pinch.sh` for pinch/spread direction, finger counts, swipe
rejection, and one-trigger-per-gesture checks. Run
`./Scripts/test-trackpad-callback.sh` for the Swift 6 background callback
regression check. Wallpaper decoding runs off the main thread so a slow image
file cannot block opening the launcher or its shortcuts.

Build with `swift build -c release`. On prerelease toolchains with signing/dSYM
issues in the default build engine, use `swift build --build-system native -c release`.

## App discovery

Apps are discovered from `/Applications`, `~/Applications`, and
`/System/Applications`, with system lookups for Safari and Finder. Selected
system utilities and background helpers are hidden from the catalog. App icons
and wallpaper come from this Mac. The Dock remains under macOS control.
