import Foundation
import SwiftData

/// Exports all user data (projects, tasks, subtasks) to a single JSON document so
/// users can keep their own portable copy or move it elsewhere. Unlike a .store
/// backup this is human-readable and tool-agnostic. Rich text is exported both as
/// plain text (readable) and as the raw RTF in base64 (lossless), so the file
/// preserves everything without depending on SwiftData/SQLite internals.
enum DataExport {

    // MARK: - DTOs

    enum ImportMode { case merge, replace }

    enum ImportError: LocalizedError {
        case unreadable
        case malformed(String)
        var errorDescription: String? {
            switch self {
            case .unreadable:        return "The file could not be read."
            case .malformed(let d):  return "The file isn't a valid Quillpoint export.\n\(d)"
            }
        }
    }

    private struct Document: Codable {
        var app = "Quillpoint"
        var formatVersion = 1
        var exportedAt: Date
        let projects: [ProjectDTO]
    }

    private struct ProjectDTO: Codable {
        let id: UUID
        let title: String
        let desc: String
        let createdAt: Date
        let tasks: [TaskDTO]   // root tasks only; subtasks nested within
    }

    private struct TaskDTO: Codable {
        let id: UUID
        let title: String          // plain text, for readability
        let titleRTF: String       // base64 of the raw RTF, for lossless round-trip
        let notes: String          // plain text of the description
        let notesRTF: String       // base64 of the raw RTF
        let isDone: Bool
        let priority: Int
        let createdAt: Date
        let sortIndex: Int
        let completedAt: Date?
        let reminderDate: Date?
        let subtasks: [TaskDTO]
    }

    /// Snapshot a Task (and its subtasks) into a DTO for export.
    private static func dto(from task: Task) -> TaskDTO {
        TaskDTO(
            id: task.id,
            title: task.plainTitle,
            titleRTF: task.titleRTF.base64EncodedString(),
            notes: task.plainDesc,
            notesRTF: task.descRTF.base64EncodedString(),
            isDone: task.isDone,
            priority: task.priority,
            createdAt: task.createdAt,
            sortIndex: task.sortIndex,
            completedAt: task.completedAt,
            reminderDate: task.reminderDate,
            subtasks: TaskStore.orderedSubtasks(of: task).map(dto(from:)))
    }

    // MARK: - Encoding

    /// Builds the pretty-printed JSON for everything in the store. Read-only: it
    /// only fetches and encodes, never mutates.
    @MainActor
    static func json(from context: ModelContext) throws -> Data {
        // Fetch unsorted, then sort in Swift. A keypath SortDescriptor inside the
        // FetchDescriptor traps on this toolchain; ordering here avoids that and the
        // export order isn't load-bearing anyway.
        let fetched = (try? context.fetch(FetchDescriptor<Project>())) ?? []
        let projects = fetched.sorted { $0.title.localizedCompare($1.title) == .orderedAscending }
        let document = Document(
            exportedAt: Date(),
            projects: projects.map { project in
                ProjectDTO(
                    id: project.id,
                    title: project.title,
                    desc: project.desc,
                    createdAt: project.createdAt,
                    tasks: TaskStore.orderedRoots(of: project).map(dto(from:)))
            })

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(document)
    }

    // MARK: - Import

    /// Decodes and validates a JSON export. Throws ImportError on a bad file and
    /// does NOT touch any data — call this first so a malformed file is rejected
    /// before anything is changed. Returns the number of projects/tasks for a
    /// confirmation prompt.
    static func validate(_ data: Data) throws -> (projects: Int, tasks: Int) {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let doc: Document
        do {
            doc = try decoder.decode(Document.self, from: data)
        } catch {
            throw ImportError.malformed(error.localizedDescription)
        }
        guard doc.app == "Quillpoint" else {
            throw ImportError.malformed("Unrecognized file (app = \"\(doc.app)\").")
        }
        func count(_ tasks: [TaskDTO]) -> Int { tasks.reduce(0) { $0 + 1 + count($1.subtasks) } }
        let taskCount = doc.projects.reduce(0) { $0 + count($1.tasks) }
        return (doc.projects.count, taskCount)
    }

    /// Applies a validated import into `context`. In `.replace` mode the caller is
    /// responsible for having taken a safety backup first; this wipes all existing
    /// projects/tasks. In `.merge` mode imported items are added alongside existing
    /// data with fresh ids so nothing collides. Saves on success.
    @MainActor
    static func importing(_ data: Data, into context: ModelContext, mode: ImportMode) throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let doc: Document
        do { doc = try decoder.decode(Document.self, from: data) }
        catch { throw ImportError.malformed(error.localizedDescription) }

        if mode == .replace {
            for project in (try? context.fetch(FetchDescriptor<Project>())) ?? [] {
                context.delete(project) // cascade removes its tasks
            }
        }

        // Merge gives every imported object a fresh id so it can't collide with
        // existing data; replace can keep the file's ids (the store is now empty).
        let freshIDs = (mode == .merge)

        for pdto in doc.projects {
            let project = Project(title: pdto.title, desc: pdto.desc)
            if !freshIDs { project.id = pdto.id }
            project.createdAt = pdto.createdAt
            context.insert(project)
            for tdto in pdto.tasks {
                insertTask(tdto, into: project, parent: nil, context: context, freshIDs: freshIDs)
            }
        }
        try context.save()
    }

    /// Recreates a task (and its subtasks) from a DTO under `project` / `parent`,
    /// mirroring how the app wires these relationships elsewhere.
    @MainActor
    private static func insertTask(_ dto: TaskDTO, into project: Project, parent: Task?,
                                   context: ModelContext, freshIDs: Bool) {
        let task = Task(project: project, parent: parent)
        if !freshIDs { task.id = dto.id }
        task.titleRTF = Data(base64Encoded: dto.titleRTF) ?? Task.rtf(from: dto.title)
        task.descRTF = Data(base64Encoded: dto.notesRTF) ?? Task.rtf(from: dto.notes)
        task.isDone = dto.isDone
        task.priority = dto.priority
        task.createdAt = dto.createdAt
        task.sortIndex = dto.sortIndex
        task.completedAt = dto.completedAt
        task.reminderDate = dto.reminderDate
        context.insert(task)
        project.tasks.append(task)
        if let parent { parent.subtasks.append(task) }
        for sub in dto.subtasks {
            insertTask(sub, into: project, parent: task, context: context, freshIDs: freshIDs)
        }
    }
}
