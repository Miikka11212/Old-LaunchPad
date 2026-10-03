import Foundation
import CoreFoundation
import Darwin

private struct ControlMessage: Codable {
    var hotkey: Bool
    var gestures: Bool
}

private struct ControlReply: Codable {
    var ok: Bool
    var error: String?
}

enum ControlSessionError: LocalizedError {
    case failure(String)
    var errorDescription: String? {
        switch self { case .failure(let message): return message }
    }
}

/// All preference writes live in a child process. EOF on its input means the
/// app quit or crashed, so cleanup does not depend on AppKit termination hooks.
actor SystemControlConnection {
    private var process: Process?
    private var input: FileHandle?
    private var output: FileHandle?
    private var stopped = false
    private var revision = -1

    func start() throws {
        guard !stopped, process == nil, let executable = Bundle.main.executableURL else {
            throw ControlSessionError.failure("The shortcut session could not start.")
        }
        let child = Process()
        let commands = Pipe()
        let replies = Pipe()
        child.executableURL = executable
        child.arguments = ["--guard-system-controls"]
        child.standardInput = commands
        child.standardOutput = replies
        child.standardError = FileHandle.standardError
        try child.run()
        commands.fileHandleForReading.closeFile()
        replies.fileHandleForWriting.closeFile()
        input = commands.fileHandleForWriting
        output = replies.fileHandleForReading
        process = child
        // A dead helper must return an error rather than terminate the app.
        _ = fcntl(commands.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
        do { try readReply() }
        catch {
            stop()
            throw error
        }
    }

    func update(hotkey: Bool, gestures: Bool, revision next: Int) throws {
        guard !stopped, next > revision else { return }
        guard let input else { throw ControlSessionError.failure("The shortcut helper is unavailable.") }
        revision = next
        var data = try JSONEncoder().encode(ControlMessage(hotkey: hotkey, gestures: gestures))
        data.append(0x0a)
        try input.write(contentsOf: data)
        try readReply()
    }

    func stop() {
        guard !stopped else { return }
        stopped = true
        try? input?.close()
        input = nil
        // The helper normally restores in under a second. If macOS takes
        // longer, leave it alive to finish restoring after the app exits.
        let deadline = ProcessInfo.processInfo.systemUptime + 10
        while process?.isRunning == true, ProcessInfo.processInfo.systemUptime < deadline {
            usleep(20_000)
        }
        try? output?.close()
        output = nil
        process = nil
    }

    private func readReply() throws {
        guard let output else { throw ControlSessionError.failure("The shortcut helper is unavailable.") }
        let deadline = ProcessInfo.processInfo.systemUptime + 8
        var data = Data()
        while ProcessInfo.processInfo.systemUptime < deadline, data.count < 8192 {
            var descriptor = pollfd(fd: output.fileDescriptor, events: Int16(POLLIN), revents: 0)
            let status = poll(&descriptor, 1, 100)
            if status < 0, errno == EINTR { continue }
            guard status >= 0 else { break }
            if status == 0 { continue }
            guard let byte = try output.read(upToCount: 1), !byte.isEmpty else { break }
            if byte[0] == 0x0a {
                let reply = try JSONDecoder().decode(ControlReply.self, from: data)
                guard reply.ok else {
                    throw ControlSessionError.failure(reply.error ?? "Could not update macOS controls.")
                }
                return
            }
            data.append(byte)
        }
        throw ControlSessionError.failure("The shortcut helper stopped responding.")
    }
}

/// Injectable preference access keeps recovery tests away from real settings.
struct ControlPreferences {
    var read: (String, String) -> Any?
    var write: (String, String, Any?) throws -> Void
    var reload: () throws -> Void

    static func system() -> Self {
        Self(read: { domain, key in
            CFPreferencesAppSynchronize(domain as CFString)
            return CFPreferencesCopyAppValue(key as CFString, domain as CFString)
        }, write: { domain, key, value in
            CFPreferencesSetAppValue(key as CFString, value as CFPropertyList?, domain as CFString)
            guard CFPreferencesAppSynchronize(domain as CFString) else {
                throw ControlSessionError.failure("Could not save \(domain).")
            }
        }, reload: {
            let apply = Process()
            apply.executableURL = URL(fileURLWithPath: "/System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings")
            apply.arguments = ["-u"]
            // Keep stdout reserved for the parent/helper protocol.
            apply.standardOutput = FileHandle.standardError
            try apply.run()
            apply.waitUntilExit()
            guard apply.terminationStatus == 0 else {
                throw ControlSessionError.failure("macOS could not reload its shortcut settings.")
            }
        })
    }
}

final class SystemControlLease {
    private let preferences: ControlPreferences
    private let journalURL: URL
    private var lockDescriptor: Int32 = -1
    private var saved: [String: Any] = [:]
    private let symbolicDomain = "com.apple.symbolichotkeys"
    private let symbolicKey = "AppleSymbolicHotKeys"
    private let gestureKeys = [
        ("com.apple.AppleMultitouchTrackpad", "TrackpadFourFingerPinchGesture"),
        ("com.apple.driver.AppleBluetoothMultitouch.trackpad", "TrackpadFourFingerPinchGesture"),
        ("com.apple.dock", "showLaunchpadGestureEnabled")
    ]

    init(directory: URL, preferences: ControlPreferences = .system()) throws {
        self.preferences = preferences
        journalURL = directory.appendingPathComponent("active-controls.plist")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        lockDescriptor = open(directory.appendingPathComponent("controls.lock").path, O_CREAT | O_RDWR | O_CLOEXEC, 0o600)
        guard lockDescriptor >= 0, flock(lockDescriptor, LOCK_EX | LOCK_NB) == 0 else {
            if lockDescriptor >= 0 { close(lockDescriptor); lockDescriptor = -1 }
            throw ControlSessionError.failure("Another OldLaunchpad is already managing these controls.")
        }
        do {
            if FileManager.default.fileExists(atPath: journalURL.path) {
                let data = try Data(contentsOf: journalURL)
                guard let journal = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                      journal["version"] as? Int == 1,
                      let values = journal["saved"] as? [String: Any],
                      Self.validSnapshot(values) else {
                    throw ControlSessionError.failure("The saved control settings are unreadable; they have been preserved.")
                }
                saved = values
                try restore()
            }
        } catch {
            close(lockDescriptor)
            lockDescriptor = -1
            throw error
        }
    }

    deinit {
        if lockDescriptor >= 0 { close(lockDescriptor) }
    }

    private static func validSnapshot(_ values: [String: Any]) -> Bool {
        let known = Set(["spotlight", "gestures"])
        guard Set(values.keys).isSubset(of: known) else { return false }
        func validRecord(_ item: Any?) -> Bool {
            guard let record = item as? [String: Any], let present = record["present"] as? Bool else { return false }
            return !present || record["value"] != nil
        }
        if let value = values["spotlight"], !validRecord(value) { return false }
        if let value = values["gestures"] {
            guard let items = value as? [String: Any], items.count == 3 else { return false }
            for domain in ["com.apple.AppleMultitouchTrackpad", "com.apple.driver.AppleBluetoothMultitouch.trackpad", "com.apple.dock"] {
                if !validRecord(items[domain]) { return false }
            }
        }
        return true
    }

    func update(hotkey: Bool, gestures: Bool) throws {
        let hadHotkey = saved["spotlight"] != nil
        let hadGestures = saved["gestures"] != nil
        guard hotkey != hadHotkey || gestures != hadGestures else { return }
        if hotkey, !hadHotkey {
            let shortcuts = preferences.read(symbolicDomain, symbolicKey) as? [String: Any] ?? [:]
            saved["spotlight"] = record(shortcuts["64"])
        }
        if gestures, !hadGestures {
            var values: [String: Any] = [:]
            for (domain, key) in gestureKeys { values[domain] = record(preferences.read(domain, key)) }
            saved["gestures"] = values
        }
        // Journal the original values before the first write, including partial
        // transitions. A subsequent launch can recover after power loss too.
        try persist()
        if hotkey != hadHotkey {
            if hotkey {
                var shortcuts = preferences.read(symbolicDomain, symbolicKey) as? [String: Any] ?? [:]
                var spotlight = shortcuts["64"] as? [String: Any] ?? Self.defaultSpotlight
                spotlight["enabled"] = false
                shortcuts["64"] = spotlight
                try preferences.write(symbolicDomain, symbolicKey, shortcuts)
            } else { try restoreSpotlight() }
        }
        if gestures != hadGestures {
            if gestures {
                for (domain, key) in gestureKeys {
                    try preferences.write(domain, key, key == "showLaunchpadGestureEnabled" ? false : 0)
                }
            } else { try restoreGestures() }
        }
        try preferences.reload()
        if !hotkey { saved.removeValue(forKey: "spotlight") }
        if !gestures { saved.removeValue(forKey: "gestures") }
        try persist()
    }

    func restore() throws {
        guard !saved.isEmpty else { return }
        // Try both independent groups, even if one preference domain fails.
        var firstError: Error?
        for operation in [restoreSpotlight, restoreGestures, preferences.reload] {
            do { try operation() } catch { if firstError == nil { firstError = error } }
        }
        if let firstError { throw firstError }
        saved = [:]
        try persist()
    }

    private static var defaultSpotlight: [String: Any] {
        ["enabled": true, "value": ["type": "standard", "parameters": [32, 49, 1048576]]]
    }

    private func restoreSpotlight() throws {
        guard let record = saved["spotlight"] as? [String: Any] else { return }
        // Merge into the latest dictionary so unrelated keyboard changes survive.
        var shortcuts = preferences.read(symbolicDomain, symbolicKey) as? [String: Any] ?? [:]
        // Absence means the macOS default. Writing it explicitly also clears the
        // runtime disabled registration, which deleting key 64 alone does not.
        shortcuts["64"] = record["present"] as? Bool == true ? record["value"] : Self.defaultSpotlight
        try preferences.write(symbolicDomain, symbolicKey, shortcuts)
    }

    private func restoreGestures() throws {
        guard let records = saved["gestures"] as? [String: Any] else { return }
        var firstError: Error?
        for (domain, key) in gestureKeys {
            let record = records[domain] as! [String: Any]
            do { try preferences.write(domain, key, record["present"] as? Bool == true ? record["value"] : nil) }
            catch { if firstError == nil { firstError = error } }
        }
        if let firstError { throw firstError }
    }

    private func record(_ value: Any?) -> [String: Any] {
        var result: [String: Any] = ["present": value != nil]
        if let value { result["value"] = value }
        return result
    }

    private func persist() throws {
        if saved.isEmpty {
            if FileManager.default.fileExists(atPath: journalURL.path) { try FileManager.default.removeItem(at: journalURL) }
        } else {
            let data = try PropertyListSerialization.data(fromPropertyList: ["version": 1, "saved": saved], format: .binary, options: 0)
            try data.write(to: journalURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: journalURL.path)
        }
    }
}

enum SystemControlGuardian {
    static func run() -> Int32 {
        signal(SIGPIPE, SIG_IGN)
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("OldLaunchpad/local.oldlaunchpad")
        var lease: SystemControlLease?
        do {
            lease = try SystemControlLease(directory: directory)
            try reply(ok: true)
            while let line = readLine() {
                let command = try JSONDecoder().decode(ControlMessage.self, from: Data(line.utf8))
                try lease?.update(hotkey: command.hotkey, gestures: command.gestures)
                try reply(ok: true)
            }
            try lease?.restore()
            return 0
        } catch {
            // Preserve the journal if restoration fails, for recovery next launch.
            do { try lease?.restore() }
            catch { NSLog("OldLaunchpad: control recovery needs another attempt: %@", error.localizedDescription) }
            try? reply(ok: false, error: error.localizedDescription)
            NSLog("OldLaunchpad: control helper: %@", error.localizedDescription)
            return 1
        }
    }

    private static func reply(ok: Bool, error: String? = nil) throws {
        var data = try JSONEncoder().encode(ControlReply(ok: ok, error: error))
        data.append(0x0a)
        try FileHandle.standardOutput.write(contentsOf: data)
    }
}
