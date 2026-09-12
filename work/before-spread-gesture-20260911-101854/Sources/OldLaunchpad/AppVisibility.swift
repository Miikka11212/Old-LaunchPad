import Foundation

/// Hide launcher clutter without treating all third-party “Utilities” apps as system tools.
enum AppVisibility {
    static let hiddenBundleIdentifiers: Set<String> = [
        "com.apple.Automator", "com.apple.Dictionary", "com.apple.FontBook",
        "com.apple.Image_Capture", "com.apple.exposelauncher", "com.apple.Preview",
        "com.apple.QuickTimePlayerX", "com.apple.shortcuts", "com.apple.Stickies",
        "com.apple.TextEdit", "com.apple.backup.launcher", "com.apple.helpviewer",
        "com.apple.appleseed.FeedbackAssistant", "com.apple.apps.launcher",
        "com.adobe.Install", "com.adobe.ACCC.Uninstaller",
        "com.adobe.cc.Adobe-Creative-Cloud-Diagnostics"
    ]

    static func isHidden(bundleIdentifier: String, path: String,
                         isAgent: Bool = false, isBackgroundOnly: Bool = false) -> Bool {
        isAgent || isBackgroundOnly
            || hiddenBundleIdentifiers.contains(bundleIdentifier)
            || path.hasPrefix("/System/Applications/Utilities/")
    }
}
