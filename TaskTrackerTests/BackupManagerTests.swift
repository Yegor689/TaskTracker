import Testing
import Foundation
import SwiftData
@testable import TaskTracker

/// Black-box tests for BackupManager. They exercise only the public API
/// (createBackup / restore / backups), run against an isolated temporary store
/// and backup directory (never production data or preferences), and focus on
/// the one thing that matters here: a backup → mutate → restore round-trip must
/// preserve user data exactly. A bug here means data loss.
@MainActor
struct BackupManagerTests {

    // MARK: - Isolated fixture

    /// An isolated app-like environment: a SwiftData store and a BackupManager
    /// whose backup directory and defaults live in a unique temp folder.
    @MainActor
    final class Fixture {
        let dir: URL
        let storeURL: URL
        let container: ModelContainer
        let manager: BackupManager

        init() throws {
            dir = FileManager.default.temporaryDirectory
                .appendingPathComponent("TTTest-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            storeURL = dir.appendingPathComponent("Test.store")

            let schema = Schema([Project.self, Task.self])
            container = try ModelContainer(
                for: schema,
                configurations: ModelConfiguration(schema: schema, url: storeURL))

            let suiteName = "TTTest-\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suiteName)!
            manager = BackupManager(
                storeURL: storeURL,
                backupDir: dir.appendingPathComponent("Backups", isDirectory: true),
                defaults: defaults)
            manager.liveContainer = container
        }

        var context: ModelContext { container.mainContext }

        /// Persists pending changes to disk so a backup (which reads the file)
        /// sees them.
        func save() throws { try context.save() }

        func tasks() throws -> [Task] { try context.fetch(FetchDescriptor<Task>()) }
        func projects() throws -> [Project] { try context.fetch(FetchDescriptor<Project>()) }

        func cleanup() { try? FileManager.default.removeItem(at: dir) }
    }

    /// A snapshot of a task's user-visible fields, for asserting integrity by id.
    struct Snap: Equatable {
        let title: String
        let desc: String
        let isDone: Bool
        let priority: Int
        let sortIndex: Int
        let hasCompletedAt: Bool
        let parentID: UUID?
        let projectTitle: String?
        init(_ t: Task) {
            title = t.plainTitle
            desc = t.plainDesc
            isDone = t.isDone
            priority = t.priority
            sortIndex = t.sortIndex
            hasCompletedAt = t.completedAt != nil
            parentID = t.parent?.id
            projectTitle = t.project?.title
        }
    }

    private func snapshot(_ f: Fixture) throws -> [UUID: Snap] {
        Dictionary(uniqueKeysWithValues: try f.tasks().map { ($0.id, Snap($0)) })
    }

    /// Seeds a representative dataset covering every field/edge: multiple
    /// projects, critical/normal/low priorities, completed + incomplete tasks,
    /// subtasks, and rich-text descriptions.
    @discardableResult
    private func seed(_ f: Fixture) throws -> Void {
        let ctx = f.context
        let personal = Project(title: "Personal", desc: "home")
        let work = Project(title: "Work", desc: "job")
        ctx.insert(personal); ctx.insert(work)

        func task(_ title: String, _ project: Project, priority: Int, done: Bool,
                  parent: Task? = nil, sortIndex: Int = 0, desc: String = "") -> Task {
            let t = Task(plainTitle: title, plainDesc: desc, priority: priority,
                         project: project, parent: parent)
            t.setDone(done)
            t.sortIndex = sortIndex
            ctx.insert(t)
            project.tasks.append(t)
            if let parent { parent.subtasks.append(t) }
            return t
        }

        let clean = task("Clean flat", personal, priority: 0, done: false, sortIndex: 0, desc: "deep clean")
        _ = task("Vacuum", personal, priority: 1, done: false, parent: clean, sortIndex: 0)
        _ = task("Dishes", personal, priority: 2, done: true, parent: clean, sortIndex: 1)
        _ = task("Dentist", personal, priority: 0, done: true, sortIndex: 1)
        _ = task("Ship release", work, priority: 0, done: false, sortIndex: 0, desc: "v2")
        _ = task("Email client", work, priority: 2, done: false, sortIndex: 1)
        try f.save()
    }

    // MARK: - Round-trip integrity

    @Test func backupThenRestorePreservesAllData() throws {
        let f = try Fixture(); defer { f.cleanup() }
        try seed(f)
        let before = try snapshot(f)
        #expect(before.count == 6)

        let backup = try #require(f.manager.createBackup(label: "snap"))

        // Mutate destructively: flip completion + priority, delete a task, rename.
        let all = try f.tasks()
        let toEdit = try #require(all.first { $0.plainTitle == "Ship release" })
        toEdit.setDone(true)
        toEdit.priority = 2
        let toDelete = try #require(all.first { $0.plainTitle == "Email client" })
        f.context.delete(toDelete)
        try f.save()
        #expect(try f.tasks().count == 5)

        try f.manager.restore(backup: backup)

        // Every task and field must match the pre-backup state exactly.
        let after = try snapshot(f)
        #expect(after == before)
    }

    @Test func restorePreservesPriorityAndCompletion() throws {
        // Directly targets the #18 regression: critical priority and completed
        // flags must survive a restore.
        let f = try Fixture(); defer { f.cleanup() }
        try seed(f)
        let backup = try #require(f.manager.createBackup())

        // Wipe priorities/completion in the live store.
        for t in try f.tasks() { t.priority = 1; t.isDone = false; t.completedAt = nil }
        try f.save()
        #expect(try f.tasks().allSatisfy { $0.priority == 1 && !$0.isDone })

        try f.manager.restore(backup: backup)

        let restored = try f.tasks()
        #expect(restored.filter { $0.priority == 0 }.count == 3) // critical preserved
        #expect(restored.filter { $0.isDone }.count == 2)        // completion preserved
        #expect(restored.filter { $0.completedAt != nil }.count == 2)
    }

    @Test func restorePreservesSubtaskHierarchy() throws {
        let f = try Fixture(); defer { f.cleanup() }
        try seed(f)
        let backup = try #require(f.manager.createBackup())

        for t in try f.tasks() { f.context.delete(t) }
        try f.save()
        #expect(try f.tasks().isEmpty)

        try f.manager.restore(backup: backup)

        let tasks = try f.tasks()
        let clean = try #require(tasks.first { $0.plainTitle == "Clean flat" })
        #expect(clean.subtasks.count == 2)
        #expect(Set(clean.subtasks.map(\.plainTitle)) == ["Vacuum", "Dishes"])
        // Inverse side hydrates too: the project lists its root tasks.
        let personal = try #require(try f.projects().first { $0.title == "Personal" })
        #expect(personal.tasks.filter { $0.parent == nil }.count == 2)
    }

    @Test func restoreReplacesNewerDataEntirely() throws {
        // Restoring must REPLACE current data, not merge: tasks added after the
        // backup are gone afterward.
        let f = try Fixture(); defer { f.cleanup() }
        try seed(f)
        let backup = try #require(f.manager.createBackup())

        let extra = Task(plainTitle: "Added later", project: try f.projects().first!)
        f.context.insert(extra)
        try f.save()
        #expect(try f.tasks().count == 7)

        try f.manager.restore(backup: backup)
        #expect(try f.tasks().count == 6)
        #expect(try f.tasks().contains { $0.plainTitle == "Added later" } == false)
    }

    // MARK: - Backup management

    @Test func restoreCreatesSingleRollingPreRestoreBackup() throws {
        // #16: each restore keeps exactly one "before restore" safety backup.
        let f = try Fixture(); defer { f.cleanup() }
        try seed(f)
        let backup = try #require(f.manager.createBackup())

        try f.manager.restore(backup: backup)
        #expect(f.manager.preRestoreBackups.count == 1)
        try f.manager.restore(backup: backup)
        #expect(f.manager.preRestoreBackups.count == 1) // replaced, not accumulated
    }

    @Test func createBackupAppearsInList() throws {
        let f = try Fixture(); defer { f.cleanup() }
        try seed(f)
        #expect(f.manager.manualBackups.isEmpty)
        _ = try #require(f.manager.createBackup(label: "first"))
        #expect(f.manager.manualBackups.count == 1)
    }
}
