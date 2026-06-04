import Foundation
import SwiftData
import AppKit

// Snapshot of a task used to reconstruct it on undo of a delete.
private struct TaskSnapshot {
    let titleRTF:  Data
    let descRTF:   Data
    let isDone:    Bool
    let priority:  Int
    let createdAt: Date
    let subtasks:  [TaskSnapshot]

    init(_ task: Task) {
        titleRTF  = task.titleRTF
        descRTF   = task.descRTF
        isDone    = task.isDone
        priority  = task.priority
        createdAt = task.createdAt
        subtasks  = task.subtasks.sorted { $0.createdAt < $1.createdAt }.map { TaskSnapshot($0) }
    }
}

@Observable
final class TaskStore {
    private let context: ModelContext
    var undoManager: UndoManager?

    init(context: ModelContext) {
        self.context = context
    }

    @discardableResult
    func addTask(plainTitle: String = "", priority: Int = 1, to project: Project, after afterTask: Task? = nil) -> Task {
        let task = Task(plainTitle: plainTitle, priority: priority, project: project)
        if let afterTask {
            for t in project.tasks where t.parent == nil && t.createdAt > afterTask.createdAt {
                t.createdAt = t.createdAt.addingTimeInterval(0.001)
            }
            task.createdAt = afterTask.createdAt.addingTimeInterval(0.001)
        }
        context.insert(task)
        project.tasks.append(task)

        undoManager?.registerUndo(withTarget: self) { [weak project] store in
            guard let project else { return }
            store.undoManager?.setActionName("Add Task")
            store.deleteTask(task, in: project)
        }
        undoManager?.setActionName("Add Task")
        return task
    }

    func indentTask(_ task: Task, previousTask: Task?) {
        guard let parent = previousTask, let project = task.project else { return }
        task.parent = parent
        if !parent.subtasks.contains(where: { $0.id == task.id }) {
            parent.subtasks.append(task)
        }
        project.tasks.removeAll { $0.id == task.id }
        context.insert(task)

        undoManager?.registerUndo(withTarget: self) { [weak parent, weak project] store in
            guard let parent, let project else { return }
            store.undoManager?.setActionName("Indent")
            store.unindentTask(task, fromParent: parent, into: project)
        }
        undoManager?.setActionName("Indent")
    }

    func unindentTask(_ task: Task) {
        guard let parent = task.parent, let project = task.project else { return }
        unindentTask(task, fromParent: parent, into: project)

        undoManager?.registerUndo(withTarget: self) { [weak parent] store in
            guard let parent else { return }
            store.undoManager?.setActionName("Unindent")
            store.indentTask(task, previousTask: parent)
        }
        undoManager?.setActionName("Unindent")
    }

    @discardableResult
    func addSubtask(plainTitle: String = "", priority: Int = 1, to parent: Task, after afterSubtask: Task? = nil) -> Task {
        let subtask = Task(plainTitle: plainTitle, priority: priority, project: parent.project, parent: parent)
        if let after = afterSubtask,
           let idx = parent.subtasks.firstIndex(where: { $0.id == after.id }) {
            // Bump createdAt of everything after so the new subtask sorts right after `after`
            for s in parent.subtasks where s.createdAt > after.createdAt {
                s.createdAt = s.createdAt.addingTimeInterval(0.001)
            }
            subtask.createdAt = after.createdAt.addingTimeInterval(0.001)
            parent.subtasks.insert(subtask, at: idx + 1)
        } else {
            parent.subtasks.append(subtask)
        }
        context.insert(subtask)

        undoManager?.registerUndo(withTarget: self) { [weak parent] store in
            guard let parent else { return }
            store.undoManager?.setActionName("Add Subtask")
            store.deleteSubtask(subtask, from: parent)
        }
        undoManager?.setActionName("Add Subtask")
        return subtask
    }

    func completeTask(_ task: Task) {
        let wasParentDone = task.isDone
        let subtaskStates = task.subtasks.map { ($0, $0.isDone) }
        task.isDone = true
        for subtask in task.subtasks { subtask.isDone = true }

        undoManager?.registerUndo(withTarget: self) { store in
            store.undoManager?.setActionName("Complete Task")
            task.isDone = wasParentDone
            for (subtask, wasDone) in subtaskStates { subtask.isDone = wasDone }
        }
        undoManager?.setActionName("Complete Task")
    }

    func deleteTask(_ task: Task) {
        guard let project = task.project else { return }
        deleteTask(task, in: project)
    }

    func deleteTask(_ task: Task, in project: Project) {
        let snapshot   = TaskSnapshot(task)
        let createdAt  = task.createdAt
        let afterIndex = project.tasks.firstIndex(where: { $0.id == task.id }).map { $0 - 1 }
        let afterTask  = afterIndex.flatMap { $0 >= 0 ? project.tasks[$0] : nil }

        task.parent?.subtasks.removeAll { $0.id == task.id }
        project.tasks.removeAll { $0.id == task.id }
        context.delete(task)

        undoManager?.registerUndo(withTarget: self) { [weak project] store in
            guard let project else { return }
            store.undoManager?.setActionName("Delete Task")
            store.restore(snapshot: snapshot, into: project, after: afterTask, at: createdAt)
        }
        undoManager?.setActionName("Delete Task")
    }

    // MARK: - Private helpers

    fileprivate func deleteSubtask(_ subtask: Task, from parent: Task) {
        parent.subtasks.removeAll { $0.id == subtask.id }
        subtask.project?.tasks.removeAll { $0.id == subtask.id }
        context.delete(subtask)
    }

    fileprivate func unindentTask(_ task: Task, fromParent parent: Task, into project: Project) {
        task.parent = nil
        parent.subtasks.removeAll { $0.id == task.id }
        if !project.tasks.contains(where: { $0.id == task.id }) {
            project.tasks.append(task)
        }
    }

    private func restore(snapshot: TaskSnapshot, into project: Project, after afterTask: Task?, at createdAt: Date) {
        let task = Task(priority: snapshot.priority, project: project)
        task.titleRTF  = snapshot.titleRTF
        task.descRTF   = snapshot.descRTF
        task.isDone    = snapshot.isDone
        task.createdAt = createdAt
        if let afterTask {
            task.createdAt = afterTask.createdAt.addingTimeInterval(0.001)
        }
        context.insert(task)
        project.tasks.append(task)

        for sub in snapshot.subtasks {
            let subtask = Task(priority: sub.priority, project: project, parent: task)
            subtask.titleRTF  = sub.titleRTF
            subtask.descRTF   = sub.descRTF
            subtask.isDone    = sub.isDone
            subtask.createdAt = sub.createdAt
            context.insert(subtask)
            task.subtasks.append(subtask)
        }

        undoManager?.registerUndo(withTarget: self) { [weak project] store in
            guard let project else { return }
            store.undoManager?.setActionName("Add Task")
            store.deleteTask(task, in: project)
        }
        undoManager?.setActionName("Delete Task")
    }
}
