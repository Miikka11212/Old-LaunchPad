import Foundation

struct LauncherFolder: Codable, Equatable, Identifiable {
    var id: String = "folder:" + UUID().uuidString
    var name: String
    var apps: [String]
}

enum LauncherEntry: Codable, Equatable, Identifiable {
    case app(String)
    case folder(LauncherFolder)

    var id: String {
        switch self { case .app(let id): return id; case .folder(let folder): return folder.id }
    }
    var appIDs: [String] {
        switch self { case .app(let id): return [id]; case .folder(let folder): return folder.apps }
    }
}

struct LauncherLayout: Codable, Equatable {
    var entries: [LauncherEntry] = []
    var hiddenApps: Set<String> = []

    func folder(_ id: String) -> LauncherFolder? {
        for case .folder(let folder) in entries where folder.id == id { return folder }
        return nil
    }

    func contains(_ id: String) -> Bool {
        entries.contains { $0.id == id || $0.appIDs.contains(id) }
    }

    /// Keep saved order, omit duplicate/hidden entries, and append newly discovered apps.
    /// Unavailable apps remain saved so temporary unavailability doesn't erase organization.
    mutating func reconcile(_ available: [String]) {
        var seen = hiddenApps
        entries = entries.compactMap { entry in
            switch entry {
            case .app(let id): return seen.insert(id).inserted ? entry : nil
            case .folder(var folder):
                folder.apps = folder.apps.filter { seen.insert($0).inserted }
                return folder.apps.isEmpty ? nil : .folder(folder)
            }
        }
        for id in available where seen.insert(id).inserted { entries.append(.app(id)) }
    }

    @discardableResult
    mutating func move(_ id: String, before target: String?, into folderID: String? = nil) -> Bool {
        guard contains(id), id != target, id != folderID else { return false }
        let movingFolder = folder(id)
        if let folderID {
            guard movingFolder == nil, folder(folderID) != nil else { return false }
            if let target, folder(folderID)?.apps.contains(target) != true { return false }
        } else if let target, !entries.contains(where: { $0.id == target }) { return false }
        detach(id)
        if let folderID, let index = entries.firstIndex(where: { $0.id == folderID }), case .folder(var folder) = entries[index] {
            let destination = target.flatMap { folder.apps.firstIndex(of: $0) } ?? folder.apps.count
            folder.apps.insert(id, at: destination)
            entries[index] = .folder(folder)
        } else {
            let destination = target.flatMap { target in entries.firstIndex { $0.id == target } } ?? entries.count
            entries.insert(movingFolder.map(LauncherEntry.folder) ?? .app(id), at: destination)
        }
        removeEmptyFolders()
        return true
    }

    @discardableResult
    mutating func group(_ source: String, with target: String) -> String? {
        guard source != target, contains(source), contains(target), folder(source) == nil else { return nil }
        if folder(target) != nil { return move(source, before: nil, into: target) ? target : nil }
        let rootTargetIndex = entries.firstIndex { $0.id == target || $0.appIDs.contains(target) } ?? entries.count
        let oldTargetID = entries.indices.contains(rootTargetIndex) ? entries[rootTargetIndex].id : nil
        let names = Set(entries.compactMap { entry -> String? in
            if case .folder(let folder) = entry { return folder.name }; return nil
        })
        var name = "Folder"
        var suffix = 2
        while names.contains(name) { name = "Folder \(suffix)"; suffix += 1 }
        let newFolder = LauncherFolder(name: name, apps: [target, source])
        // Insert a marker before detaching, so removing an earlier app doesn't shift the destination.
        let insertionIndex = oldTargetID.flatMap { target in entries.firstIndex { $0.id == target } } ?? entries.count
        entries.insert(.folder(newFolder), at: insertionIndex)
        detach(source, excluding: newFolder.id)
        detach(target, excluding: newFolder.id)
        removeEmptyFolders()
        return newFolder.id
    }

    mutating func renameFolder(_ id: String, to name: String) {
        let trimmed = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
        guard !trimmed.isEmpty, let index = entries.firstIndex(where: { $0.id == id }), case .folder(var folder) = entries[index] else { return }
        folder.name = trimmed
        entries[index] = .folder(folder)
    }

    mutating func ungroup(_ id: String) {
        guard let index = entries.firstIndex(where: { $0.id == id }), case .folder(let folder) = entries[index] else { return }
        entries.replaceSubrange(index...index, with: folder.apps.map(LauncherEntry.app))
    }

    mutating func hide(_ id: String) {
        guard folder(id) == nil else { return }
        hiddenApps.insert(id)
        detach(id)
        removeEmptyFolders()
    }

    mutating func restoreHidden(_ available: [String]) {
        hiddenApps.removeAll()
        reconcile(available)
    }

    private mutating func detach(_ id: String, excluding excludedID: String? = nil) {
        entries = entries.compactMap { entry in
            if entry.id == excludedID { return entry }
            if entry.id == id { return nil }
            if case .folder(var folder) = entry {
                folder.apps.removeAll { $0 == id }
                return .folder(folder)
            }
            return entry
        }
    }

    private mutating func removeEmptyFolders() {
        entries.removeAll { if case .folder(let folder) = $0 { return folder.apps.isEmpty }; return false }
    }
}

@MainActor
final class LauncherLayoutStore {
    let url: URL
    private(set) var loadError: Error?
    var layout: LauncherLayout

    init(url: URL? = nil) {
        self.url = url ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("OldLaunchpad", isDirectory: true)
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "local.oldlaunchpad", isDirectory: true)
            .appendingPathComponent("layout.json")
        do {
            if FileManager.default.fileExists(atPath: self.url.path) {
                layout = try JSONDecoder().decode(LauncherLayout.self, from: Data(contentsOf: self.url))
            } else { layout = LauncherLayout() }
        } catch {
            layout = LauncherLayout()
            loadError = error
        }
    }

    func save() throws {
        if let loadError { throw loadError } // Never overwrite an unreadable saved layout.
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(layout)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
}
