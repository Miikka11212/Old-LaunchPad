import Foundation

private final class FakePreferences {
    var values: [String: [String: Any]] = [
        "com.apple.symbolichotkeys": ["AppleSymbolicHotKeys": [
            "64": ["enabled": true, "value": ["type": "standard", "parameters": [32, 49, 1048576]]],
            "99": ["enabled": true]
        ]],
        "com.apple.AppleMultitouchTrackpad": ["TrackpadFourFingerPinchGesture": 2],
        "com.apple.driver.AppleBluetoothMultitouch.trackpad": ["TrackpadFourFingerPinchGesture": 2]
    ]
    var reloads = 0
    var failDomain: String?
    var failReload = false

    var access: ControlPreferences {
        ControlPreferences(read: { self.values[$0]?[$1] }, write: { domain, key, value in
            if self.failDomain == domain {
                self.failDomain = nil
                throw ControlSessionError.failure("Simulated write failure")
            }
            self.values[domain, default: [:]][key] = value
        }, reload: {
            self.reloads += 1
            if self.failReload {
                self.failReload = false
                throw ControlSessionError.failure("Simulated activation failure")
            }
        })
    }

    var shortcuts: [String: Any] {
        get { values["com.apple.symbolichotkeys"]?["AppleSymbolicHotKeys"] as? [String: Any] ?? [:] }
        set { values["com.apple.symbolichotkeys", default: [:]]["AppleSymbolicHotKeys"] = newValue }
    }

    var enabled: Bool? { (shortcuts["64"] as? [String: Any])?["enabled"] as? Bool }
    var pinch: Int? { values["com.apple.AppleMultitouchTrackpad"]?["TrackpadFourFingerPinchGesture"] as? Int }
}

@main struct SystemControlSessionChecks {
    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("oldlaunchpad-controls-tests-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        func location() -> URL { root.appendingPathComponent(UUID().uuidString) }

        do {
            let fake = FakePreferences()
            let directory = location()
            let lease = try SystemControlLease(directory: directory, preferences: fake.access)
            try lease.update(hotkey: false, gestures: false)
            precondition(fake.reloads == 0)
            try lease.update(hotkey: true, gestures: true)
            precondition(fake.enabled == false && fake.pinch == 0)
            fake.shortcuts["101"] = ["enabled": false]
            try lease.update(hotkey: true, gestures: false)
            precondition(fake.enabled == false && fake.pinch == 2)
            try lease.restore()
            precondition(fake.enabled == true && fake.shortcuts["101"] != nil)
            precondition(fake.values["com.apple.dock"]?["showLaunchpadGestureEnabled"] == nil)
            precondition(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("active-controls.plist").path))
            try lease.restore()
            precondition(fake.reloads == 3)
        }

        do {
            let fake = FakePreferences()
            let original: [String: Any] = ["enabled": false, "value": ["type": "standard", "parameters": [32, 49, 1572864]]]
            fake.shortcuts["64"] = original
            let lease = try SystemControlLease(directory: location(), preferences: fake.access)
            try lease.update(hotkey: true, gestures: false)
            precondition(fake.pinch == 2)
            try lease.restore()
            precondition(NSDictionary(dictionary: fake.shortcuts["64"] as! [String: Any]).isEqual(to: original))
        }

        do {
            let fake = FakePreferences()
            fake.values = [:]
            let lease = try SystemControlLease(directory: location(), preferences: fake.access)
            try lease.update(hotkey: true, gestures: true)
            try lease.restore()
            precondition(fake.enabled == true && fake.pinch == nil)
        }

        do {
            let fake = FakePreferences()
            let directory = location()
            var lease: SystemControlLease? = try SystemControlLease(directory: directory, preferences: fake.access)
            try lease!.update(hotkey: true, gestures: true)
            do {
                _ = try SystemControlLease(directory: directory, preferences: fake.access)
                preconditionFailure("A second running copy must not overwrite the saved settings")
            } catch {}
            withExtendedLifetime(lease) {}
            // Simulate the helper dying before cleanup; restart must restore
            // the journal before capturing any new baseline.
            lease = nil
            let recovered = try SystemControlLease(directory: directory, preferences: fake.access)
            precondition(fake.enabled == true && fake.pinch == 2)
            try recovered.update(hotkey: false, gestures: true)
            precondition(fake.enabled == true && fake.pinch == 0)
            try recovered.restore()
            precondition(fake.pinch == 2)
        }

        for failure in ["write", "reload"] {
            let fake = FakePreferences()
            let lease = try SystemControlLease(directory: location(), preferences: fake.access)
            if failure == "write" { fake.failDomain = "com.apple.driver.AppleBluetoothMultitouch.trackpad" }
            else { fake.failReload = true }
            do {
                try lease.update(hotkey: true, gestures: true)
                preconditionFailure("The simulated failure should propagate")
            } catch {}
            try lease.restore()
            precondition(fake.enabled == true && fake.pinch == 2)
        }

        do {
            let fake = FakePreferences()
            let directory = location()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let journal = directory.appendingPathComponent("active-controls.plist")
            let damaged = Data("unreadable recovery settings".utf8)
            try damaged.write(to: journal)
            do {
                _ = try SystemControlLease(directory: directory, preferences: fake.access)
                preconditionFailure("A damaged recovery file must be preserved")
            } catch {}
            let after = try Data(contentsOf: journal)
            precondition(after == damaged && fake.reloads == 0)
        }

        print("Passed temporary controls, exact restoration, independent gestures, unrelated shortcuts, duplicate instances, interrupted-session recovery, partial failures, and corrupt-journal checks.")
    }
}
