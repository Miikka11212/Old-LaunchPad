# OldLaunchpad

A native macOS app launcher with the classic Launchpad layout, larger icons,
blurred desktop wallpaper, smooth page slides, and subtle opening/closing motion.

## Run

Double-click `OldLaunchpad.app` on the Desktop. Reopen using its Dock icon,
the menu bar grid icon, or **Control + Option + Command + Space**.

Development: `swift run OldLaunchpad`. Requires macOS 13+ and Swift 6+.

## Organize apps

- **Reorder:** drag an icon between other icons. A white insertion line shows where it will go.
- **Change pages while dragging:** hold near the left or right edge of the grid.
- **Create a folder:** hold an app over the center of another app for about half a second, then release when the target highlights and the folder hint appears.
- **Add to a folder:** drop an app onto an existing folder.
- **Open a folder:** click it. Click its name at the top and press Return to rename, or right-click the folder and choose **Rename Folder…**.
- **Move an app out:** drag it onto **‹ All Apps** or choose **Move Out of Folder** from its context menu.
- **Ungroup:** right-click a folder and choose **Ungroup Folder** to return its apps to the main grid.
- New folders are named **Folder**, **Folder 2**, and so on. Folders cannot be nested.
- Clear search before dragging to rearrange. Search can find apps inside folders.

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

The grid adapts to smaller displays and opens on the display containing the
pointer. The search field clears the menu bar/notch. Opening and closing use a
zoom and blur fade; Reduce Motion disables zoom and page slides.

## Validation

Run `./Scripts/test-navigation.sh` for organization, persistence, corruption
protection, app visibility, responsive bounds, pagination, keyboard boundaries,
and gesture checks. The checks run directly with the Swift compiler and require
no external test framework.

Build with `swift build -c release`. On prerelease toolchains with signing/dSYM
issues in the default build engine, use `swift build --build-system native -c release`.

## App discovery

Apps are discovered from `/Applications`, `~/Applications`, and
`/System/Applications`, with system lookups for Safari and Finder. Selected
system utilities and background helpers are hidden from the catalog. App icons
and wallpaper come from this Mac. The Dock remains under macOS control; a global
pinch gesture is not implemented.
