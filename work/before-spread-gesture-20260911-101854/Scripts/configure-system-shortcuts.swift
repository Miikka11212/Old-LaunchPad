#!/usr/bin/swift
import Foundation
import CoreFoundation

// Changes only Spotlight's Command–Space entry and the system four-finger pinch.
// Run with --restore to put those specific values back, preserving other settings.
let restore = CommandLine.arguments.contains("--restore")
let backupURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    .appendingPathComponent("OldLaunchpad/local.oldlaunchpad/system-shortcuts-backup.plist")
let symbolicDomain = "com.apple.symbolichotkeys"
let symbolicKey = "AppleSymbolicHotKeys"
let gestureKeys = [
    ("com.apple.AppleMultitouchTrackpad", "TrackpadFourFingerPinchGesture"),
    ("com.apple.driver.AppleBluetoothMultitouch.trackpad", "TrackpadFourFingerPinchGesture"),
    ("com.apple.dock", "showLaunchpadGestureEnabled")
]
func read(_ domain: String, _ key: String) -> Any? {
    CFPreferencesCopyAppValue(key as CFString, domain as CFString)
}
func write(_ domain: String, _ key: String, _ value: Any?) throws {
    CFPreferencesSetAppValue(key as CFString, value as CFPropertyList?, domain as CFString)
    guard CFPreferencesAppSynchronize(domain as CFString) else {
        throw NSError(domain: "OldLaunchpad.Shortcuts", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not save \(domain)"])
    }
}
func record(_ value: Any?) -> [String: Any] {
    var result: [String: Any] = ["present": value != nil]
    if let value { result["value"] = value }
    return result
}

var shortcuts = read(symbolicDomain, symbolicKey) as? [String: Any] ?? [:]
if restore {
    let data = try Data(contentsOf: backupURL)
    let backup = try PropertyListSerialization.propertyList(from: data, format: nil) as! [String: Any]
    let spotlight = backup["spotlight64"] as! [String: Any]
    if spotlight["present"] as? Bool == true { shortcuts["64"] = spotlight["value"] }
    else { shortcuts.removeValue(forKey: "64") }
    try write(symbolicDomain, symbolicKey, shortcuts)
    for (domain, key) in gestureKeys {
        let previous = backup[domain] as! [String: Any]
        try write(domain, key, previous["present"] as? Bool == true ? previous["value"] : nil)
    }
    print("Restored previous Command–Space and four-finger pinch settings.")
} else {
    if !FileManager.default.fileExists(atPath: backupURL.path) {
        var backup: [String: Any] = ["spotlight64": record(shortcuts["64"])]
        for (domain, key) in gestureKeys { backup[domain] = record(read(domain, key)) }
        try FileManager.default.createDirectory(at: backupURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try PropertyListSerialization.data(fromPropertyList: backup, format: .xml, options: 0).write(to: backupURL, options: .atomic)
    }
    var spotlight = shortcuts["64"] as? [String: Any] ?? ["value": ["type": "standard", "parameters": [32, 49, 1048576]]]
    spotlight["enabled"] = false
    shortcuts["64"] = spotlight
    try write(symbolicDomain, symbolicKey, shortcuts)
    for (domain, key) in gestureKeys { try write(domain, key, key == "showLaunchpadGestureEnabled" ? false : 0) }
    print("Freed Command–Space and four-finger pinch for OldLaunchpad. Previous values backed up.")
}

let apply = Process()
apply.executableURL = URL(fileURLWithPath: "/System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings")
apply.arguments = ["-u"]
try apply.run()
apply.waitUntilExit()
if apply.terminationStatus != 0 { print("macOS may need a sign-out to reload the gesture setting.") }
