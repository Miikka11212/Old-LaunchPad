import Foundation

func checkAppVisibility() {
    assert(AppVisibility.isHidden(bundleIdentifier: "com.apple.ActivityMonitor", path: "/System/Applications/Utilities/Activity Monitor.app"))
    for identifier in ["com.apple.Automator", "com.apple.Preview", "com.apple.TextEdit", "com.apple.Dictionary", "com.adobe.Install"] {
        assert(AppVisibility.isHidden(bundleIdentifier: identifier, path: "/Applications/Test.app"))
    }
    assert(AppVisibility.isHidden(bundleIdentifier: "com.example.helper", path: "/Applications/Helper.app", isAgent: true))
    assert(AppVisibility.isHidden(bundleIdentifier: "com.example.background", path: "/Applications/Background.app", isBackgroundOnly: true))
    for identifier in ["com.apple.Safari", "com.apple.mail", "com.apple.Notes", "com.apple.calculator", "com.apple.Photos", "com.example.myutility"] {
        assert(!AppVisibility.isHidden(bundleIdentifier: identifier, path: "/Applications/Everyday App.app"))
    }
    print("Passed app visibility checks: system tools and helpers hidden; everyday apps retained.")
}
