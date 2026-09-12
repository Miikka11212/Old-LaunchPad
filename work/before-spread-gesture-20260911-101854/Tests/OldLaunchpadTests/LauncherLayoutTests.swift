import Foundation

@MainActor
func checkLauncherLayout() throws {
    var layout = LauncherLayout()
    layout.reconcile(["A", "B", "C", "D", "A"])
    assert(layout.entries.map(\.id) == ["A", "B", "C", "D"])
    assert(layout.move("A", before: "D"))
    assert(layout.entries.map(\.id) == ["B", "C", "A", "D"])
    let folder = layout.group("C", with: "B")!
    assert(layout.entries.map(\.id) == [folder, "A", "D"])
    assert(layout.folder(folder)?.apps == ["B", "C"])
    assert(layout.move("A", before: nil, into: folder))
    assert(layout.folder(folder)?.apps == ["B", "C", "A"])
    assert(layout.move("A", before: "B", into: folder))
    assert(layout.folder(folder)?.apps == ["A", "B", "C"])
    layout.renameFolder(folder, to: "  Work  ")
    layout.renameFolder(folder, to: " \n ")
    assert(layout.folder(folder)?.name == "Work")
    assert(layout.move("C", before: "D"))
    assert(layout.entries.map(\.id) == [folder, "C", "D"])
    layout.hide("B")
    assert(layout.hiddenApps.contains("B"))
    layout.reconcile(["A", "B", "C", "D", "E"])
    assert(!layout.entries.flatMap(\.appIDs).contains("B"))
    assert(layout.folder(folder)?.apps == ["A"])
    layout.restoreHidden(["A", "B", "C", "D", "E"])
    assert(layout.entries.last?.id == "B")
    let other = layout.group("E", with: "D")!
    let unchanged = layout
    assert(!layout.move(folder, before: nil, into: other))
    assert(layout.group(folder, with: other) == nil)
    assert(!layout.move("missing", before: "A"))
    assert(layout == unchanged)
    assert(layout.move(folder, before: nil))
    layout.ungroup(folder)
    assert(layout.folder(folder) == nil)
    assert(layout.entries.last?.id == "A")
    assert(Set(layout.entries.flatMap(\.appIDs)).count == layout.entries.flatMap(\.appIDs).count)

    let legacy = Data(#"{"entries":[{"app":{"_0":"A"}}],"hiddenApps":["B"]}"#.utf8)
    var migrated = try JSONDecoder().decode(LauncherLayout.self, from: legacy)
    assert(migrated.customAppPaths.isEmpty && migrated.entries.first?.id == "A")
    migrated.addApp("B")
    migrated.addApp("B")
    migrated.addApp("/Elsewhere/Custom.app")
    assert(migrated.hiddenApps.isEmpty)
    assert(migrated.customAppPaths == ["B", "/Elsewhere/Custom.app"])
    assert(migrated.entries.filter { $0.id == "B" }.count == 1)
    let addedFolder = migrated.group("A", with: "B")!
    migrated.addApp("/Another.app", into: addedFolder)
    assert(migrated.folder(addedFolder)?.apps.contains("/Another.app") == true)
    let importedRoundtrip = try JSONDecoder().decode(LauncherLayout.self, from: JSONEncoder().encode(migrated))
    assert(importedRoundtrip == migrated)
    print("Passed legacy layout migration and manually added app persistence checks.")

    let testDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("oldlaunchpad-layout-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: testDirectory) }
    let url = testDirectory.appendingPathComponent("layout.json")
    let store = LauncherLayoutStore(url: url)
    store.layout = layout
    try store.save()
    let reloaded = LauncherLayoutStore(url: url)
    assert(reloaded.layout == layout)
    try Data("invalid json".utf8).write(to: url)
    let damaged = LauncherLayoutStore(url: url)
    assert(damaged.loadError != nil)
    do { try damaged.save(); assertionFailure("Must preserve unreadable settings") } catch {}
    let preserved = try String(contentsOf: url, encoding: .utf8)
    assert(preserved == "invalid json")

    var names = LauncherLayout()
    names.reconcile(["A", "B", "C", "D"])
    let first = names.group("A", with: "B")!
    let second = names.group("C", with: "D")!
    assert(names.folder(first)?.name == "Folder")
    assert(names.folder(second)?.name == "Folder 2")
    assert(names.group("A", with: second) == second)
    assert(names.folder(first)?.apps == ["B"])
    assert(names.folder(second)?.apps == ["D", "C", "A"])

    var single = LauncherLayout()
    single.reconcile(["A", "B"])
    let small = single.group("A", with: "B")!
    single.hide("A")
    single.hide("B")
    assert(single.folder(small) == nil)
    assert(single.entries.isEmpty)
    print("Passed organization checks: reorder, folders, rename, move out, hide/restore, restart persistence, and corrupt-file protection.")
}
