import Foundation
import SwiftData

/// Exports all user data (projects, tasks, subtasks) to a single JSON document so
/// users can keep their own portable copy or move it elsewhere. Unlike a .store
/// backup this is human-readable and tool-agnostic. Rich text is exported both as
/// plain text (readable) and as the raw RTF in base64 (lossless), so the file
/// preserves everything without depending on SwiftData/SQLite internals.
enum DataExport {

    /// ISO8601 WITH fractional seconds, used for both encoding and decoding so dates
    /// round-trip to the exact same value. Plain `.iso8601` truncates to whole
    /// seconds, which made a re-imported task's createdAt differ by sub-second and
    /// look "new", breaking merge idempotency.
    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static var dateEncoding: JSONEncoder.DateEncodingStrategy {
        .custom { date, encoder in
            var c = encoder.singleValueContainer()
            try c.encode(isoFormatter.string(from: date))
        }
    }

    private static var dateDecoding: JSONDecoder.DateDecodingStrategy {
        .custom { decoder in
            let s = try decoder.singleValueContainer().decode(String.self)
            guard let date = isoFormatter.date(from: s) else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                    debugDescription: "Invalid ISO8601 date: \(s)"))
            }
            return date
        }
    }

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
        encoder.dateEncodingStrategy = dateEncoding
        return try encoder.encode(document)
    }

    // MARK: - Import

    /// Decodes and validates a JSON export. Throws ImportError on a bad file and
    /// does NOT touch any data — call this first so a malformed file is rejected
    /// before anything is changed. Returns the number of projects/tasks for a
    /// confirmation prompt.
    static func validate(_ data: Data) throws -> (projects: Int, tasks: Int) {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = dateDecoding
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
        decoder.dateDecodingStrategy = dateDecoding
        let doc: Document
        do { doc = try decoder.decode(Document.self, from: data) }
        catch { throw ImportError.malformed(error.localizedDescription) }

        switch mode {
        case .replace:
            for project in (try? context.fetch(FetchDescriptor<Project>())) ?? [] {
                context.delete(project) // cascade removes its tasks
            }
            // Empty store: recreate verbatim, keeping the file's ids.
            for pdto in doc.projects {
                let project = Project(title: pdto.title, desc: pdto.desc)
                project.id = pdto.id
                project.createdAt = pdto.createdAt
                context.insert(project)
                for tdto in pdto.tasks {
                    insertTask(tdto, into: project, parent: nil, context: context, keepID: true)
                }
            }

        case .merge:
            let existing = (try? context.fetch(FetchDescriptor<Project>())) ?? []
            for pdto in doc.projects {
                // Reuse an existing project with the same scalar fields rather than
                // duplicating it; otherwise create a new one (fresh id).
                let project = existing.first(where: { matches($0, pdto) }) ?? {
                    let p = Project(title: pdto.title, desc: pdto.desc)
                    p.createdAt = pdto.createdAt
                    context.insert(p)
                    return p
                }()
                for tdto in pdto.tasks {
                    mergeTask(tdto, into: project, parent: nil, context: context)
                }
            }
        }
        try context.save()
    }

    // MARK: Merge matching

    /// Dates are exported as millisecond-precision ISO8601, so a stored Date and its
    /// round-tripped copy can differ by sub-millisecond. Compare at millisecond
    /// granularity so a re-imported item matches its original (idempotent merge)
    /// rather than looking "new" and duplicating.
    private static func sameInstant(_ a: Date, _ b: Date) -> Bool {
        abs(a.timeIntervalSinceReferenceDate - b.timeIntervalSinceReferenceDate) < 0.001
    }

    private static func sameInstant(_ a: Date?, _ b: Date?) -> Bool {
        switch (a, b) {
        case (nil, nil): return true
        case let (x?, y?): return sameInstant(x, y)
        default: return false
        }
    }

    /// A project matches an import DTO when its scalar fields are identical. Tasks
    /// are compared separately, so a matching project can still gain new tasks.
    private static func matches(_ project: Project, _ dto: ProjectDTO) -> Bool {
        project.title == dto.title && project.desc == dto.desc && sameInstant(project.createdAt, dto.createdAt)
    }

    /// A task matches an import DTO when EVERY scalar field is identical (RTF bytes
    /// included). Any difference makes it a distinct task that should be added.
    /// Subtasks are matched separately by the recursive merge.
    private static func matches(_ task: Task, _ dto: TaskDTO) -> Bool {
        task.titleRTF == (Data(base64Encoded: dto.titleRTF) ?? Task.rtf(from: dto.title))
            && task.descRTF == (Data(base64Encoded: dto.notesRTF) ?? Task.rtf(from: dto.notes))
            && task.isDone == dto.isDone
            && task.priority == dto.priority
            && sameInstant(task.createdAt, dto.createdAt)
            && task.sortIndex == dto.sortIndex
            && sameInstant(task.completedAt, dto.completedAt)
            && sameInstant(task.reminderDate, dto.reminderDate)
    }

    /// Merge a task DTO under `project`/`parent`: if an identical task already exists
    /// at this level, keep it (and recurse into its subtasks so new children are
    /// still added); otherwise add the task and all its subtasks.
    @MainActor
    private static func mergeTask(_ dto: TaskDTO, into project: Project, parent: Task?, context: ModelContext) {
        let siblings = parent?.subtasks ?? project.tasks.filter { $0.parent == nil }
        if let match = siblings.first(where: { matches($0, dto) }) {
            // Same task already present — skip it, but still merge its subtasks so
            // newly added children come across.
            for sub in dto.subtasks {
                mergeTask(sub, into: project, parent: match, context: context)
            }
        } else {
            insertTask(dto, into: project, parent: parent, context: context, keepID: false)
        }
    }

    /// Recreates a task (and its subtasks) from a DTO under `project` / `parent`,
    /// mirroring how the app wires these relationships elsewhere.
    @MainActor
    private static func insertTask(_ dto: TaskDTO, into project: Project, parent: Task?,
                                   context: ModelContext, keepID: Bool) {
        let task = Task(project: project, parent: parent)
        if keepID { task.id = dto.id }
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
            insertTask(sub, into: project, parent: task, context: context, keepID: keepID)
        }
    }
}
