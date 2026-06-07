import Foundation

/// Plain-data, `Codable` mirrors of the persistent models, used as the single
/// source of truth for what a backup/restore must carry. Restore builds these
/// from a backup store and applies them to live models, so the set of copied
/// fields is declared in exactly one place. Adding a stored property to `Task`
/// or `Project` that isn't added here is a compile error in `init(_:)` (the
/// memberwise initializer requires every field), which prevents silently
/// dropping data on restore. Relationships are carried by id, not by reference.
///
/// `Equatable` is synthesized, so tests can compare round-tripped data directly.
/// `Codable` is intentional even though restore currently copies in memory: it
/// fixes these as the serializable shape of a backup, ready for a portable
/// (e.g. JSON) backup format without reworking the field list.

struct ProjectDTO: Codable, Equatable {
    var id: UUID
    var title: String
    var desc: String
    var createdAt: Date

    init(_ p: Project) {
        id = p.id
        title = p.title
        desc = p.desc
        createdAt = p.createdAt
    }

    /// Builds a fresh model from this snapshot. Relationships are wired by the caller.
    func makeModel() -> Project {
        let p = Project(title: title, desc: desc)
        p.id = id
        p.createdAt = createdAt
        return p
    }
}

struct TaskDTO: Codable, Equatable {
    var id: UUID
    var titleRTF: Data
    var descRTF: Data
    var isDone: Bool
    var priority: Int
    var createdAt: Date
    var sortIndex: Int
    var completedAt: Date?
    var reminderDate: Date?
    var projectID: UUID?
    var parentID: UUID?

    init(_ t: Task) {
        id = t.id
        titleRTF = t.titleRTF
        descRTF = t.descRTF
        isDone = t.isDone
        priority = t.priority
        createdAt = t.createdAt
        sortIndex = t.sortIndex
        completedAt = t.completedAt
        reminderDate = t.reminderDate
        projectID = t.project?.id
        parentID = t.parent?.id
    }

    /// Builds a fresh model carrying every scalar field. The caller wires the
    /// project / parent relationships (both sides) using `projectID` / `parentID`.
    func makeModel() -> Task {
        let t = Task()
        t.id = id
        t.titleRTF = titleRTF
        t.descRTF = descRTF
        t.isDone = isDone
        t.priority = priority
        t.createdAt = createdAt
        t.sortIndex = sortIndex
        t.completedAt = completedAt
        t.reminderDate = reminderDate
        return t
    }
}
