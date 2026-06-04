import Foundation
import SwiftData

@Model
class Project {
    var id: UUID
    var title: String
    var desc: String
    var createdAt: Date
    @Relationship(deleteRule: .cascade) var tasks: [Task]

    init(title: String, desc: String = "") {
        self.id = UUID()
        self.title = title
        self.desc = desc
        self.createdAt = Date()
        self.tasks = []
    }
}
