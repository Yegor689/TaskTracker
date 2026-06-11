import Foundation
import SwiftData

@Model
class Project {
    var id: UUID
    var title: String
    var desc: String
    var createdAt: Date
    // Explicit inverse so SwiftData deterministically maintains both sides of the
    // Project.tasks ↔ Task.project relationship. Without it the inverse is inferred,
    // and because Task.project is optional SwiftData won't auto-maintain tasks when
    // only the to-one side is set — which forced fragile manual array bookkeeping in
    // the store that intermittently lost tasks on a cross-project move.
    @Relationship(deleteRule: .cascade, inverse: \Task.project) var tasks: [Task]

    init(title: String, desc: String = "") {
        self.id = UUID()
        self.title = title
        self.desc = desc
        self.createdAt = Date()
        self.tasks = []
    }

    /// Returns a detached copy carrying every SCALAR field of this project — used
    /// by backup restore to recreate a project in another store. The `tasks`
    /// relationship is NOT copied; the caller wires tasks by id in the destination
    /// store. Update this when a field is added — see the backup integrity test.
    func cloneScalars() -> Project {
        let copy = Project(title: title, desc: desc)
        copy.id = id
        copy.createdAt = createdAt
        return copy
    }
}
