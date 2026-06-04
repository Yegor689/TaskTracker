import Foundation
import SwiftData

@Observable
final class ProjectStore {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    @discardableResult
    func createProject(title: String, desc: String = "") -> Project {
        let project = Project(title: title, desc: desc)
        context.insert(project)
        return project
    }

    func updateProject(_ project: Project, title: String? = nil, desc: String? = nil) {
        if let title { project.title = title }
        if let desc  { project.desc  = desc  }
    }

    func deleteProject(_ project: Project) {
        context.delete(project)
    }
}
