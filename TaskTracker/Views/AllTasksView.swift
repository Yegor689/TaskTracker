import SwiftUI
import SwiftData

enum TaskGrouping: String, CaseIterable {
    case project  = "Project"
    case priority = "Priority"
}

struct AllTasksView: View {
    @Environment(TaskStore.self) private var taskStore
    @Environment(ReminderManager.self) private var reminderManager
    @Environment(\.undoManager) private var undoManager
    @Query(sort: \Project.title) private var projects: [Project]
    @Binding var selection: SidebarSelection?

    @State private var path = NavigationPath()
    @State private var filter: TaskFilter = .active
    @State private var searchText = ""
    @State private var grouping: TaskGrouping = .project
    @State private var focusedTaskID: UUID?
    @State private var taskPendingDelete: Task?

    var allTasks: [Task] {
        let root = projects.flatMap { $0.tasks.filter { $0.parent == nil } }
        let searched = searchText.isEmpty ? root : root.filter {
            $0.plainTitle.localizedCaseInsensitiveContains(searchText) ||
            $0.plainDesc.localizedCaseInsensitiveContains(searchText)
        }
        let filtered: [Task]
        switch filter {
        case .all:    filtered = searched
        case .active: filtered = searched.filter { !$0.isDone }
        case .done:   filtered = searched.filter {  $0.isDone }
        }
        return filtered.sorted { lhs, rhs in
            if lhs.priority != rhs.priority { return lhs.priority < rhs.priority }
            return lhs.createdAt < rhs.createdAt
        }
    }

    var groupedSections: [(header: String, tasks: [Task])] {
        switch grouping {
        case .project:
            return projects.compactMap { project in
                let tasks = allTasks.filter { $0.project?.id == project.id }
                guard !tasks.isEmpty else { return nil }
                return (header: project.title, tasks: tasks)
            }
        case .priority:
            let critical = allTasks.filter { $0.priority == 0 }
            let normal   = allTasks.filter { $0.priority != 0 }
            var sections: [(header: String, tasks: [Task])] = []
            if !critical.isEmpty { sections.append((header: "Critical", tasks: critical)) }
            if !normal.isEmpty   { sections.append((header: "Normal",   tasks: normal))   }
            return sections
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(groupedSections, id: \.header) { section in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                if grouping == .priority {
                                    Image(systemName: section.header == "Critical"
                                          ? "exclamationmark.circle.fill" : "circle")
                                        .foregroundStyle(section.header == "Critical" ? .red : .secondary)
                                        .font(.caption)
                                }
                                Text(section.header)
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.secondary)
                                    .textCase(.uppercase)
                                Text("\(section.tasks.count)")
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.horizontal, 8)
                            .padding(.bottom, 2)

                            ForEach(section.tasks) { task in
                                TaskRowView(
                                    task: task,
                                    isSubtask: false,
                                    focusedID: $focusedTaskID,
                                    onReturn:           { },
                                    onDeleteIfEmpty:    { deleteIfEmpty(task) },
                                    onDelete:           { taskStore.deleteTask(task) },
                                    onIndent:           { },
                                    onUnindent:         { },
                                    onNavigateUp:       { navigateTo(task, direction: -1) },
                                    onNavigateDown:     { navigateTo(task, direction: +1) },
                                    onNavigateDownFrom: { navigateTo($0, direction: +1) },
                                    navigate:           { t in path.append(t) }
                                )
                                .onTapGesture(count: 2) { path.append(task) }
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("")
            .toolbarTitleDisplayMode(.inline)
            .navigationDestination(for: Task.self) { task in
                TaskDetailView(task: task)
            }
            .searchable(text: $searchText, prompt: "Search all tasks")
            .overlay {
                if allTasks.isEmpty {
                    if !searchText.isEmpty {
                        ContentUnavailableView {
                            Label("No Results", systemImage: "magnifyingglass")
                        } description: {
                            Text("No tasks match \"\(searchText)\".")
                        }
                    } else if filter != .all {
                        ContentUnavailableView {
                            Label("No \(filter.rawValue) Tasks", systemImage: "checklist")
                        }
                    } else {
                        ContentUnavailableView {
                            Label("No Tasks", systemImage: "checklist")
                        } description: {
                            Text("Add tasks to your projects to see them here.")
                        }
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    ProjectTitleMenu(selection: $selection)
                }
                ToolbarItem(placement: .principal) {
                    Picker("Filter", selection: $filter) {
                        ForEach(TaskFilter.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 220)
                }
                ToolbarItem(placement: .primaryAction) {
                    Picker("Group By", selection: $grouping) {
                        ForEach(TaskGrouping.allCases, id: \.self) { g in
                            Text(g.rawValue).tag(g)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 160)
                    .help("Group by")
                }
            }
        }
        .onAppear {
            taskStore.undoManager = undoManager
            taskStore.reminderManager = reminderManager
        }
        .onChange(of: undoManager) { taskStore.undoManager = undoManager }
        .alert("Delete Task?", isPresented: Binding(
            get: { taskPendingDelete != nil },
            set: { if !$0 { taskPendingDelete = nil } }
        )) {
            Button("Delete", role: .destructive) {
                if let t = taskPendingDelete { taskStore.deleteTask(t); taskPendingDelete = nil }
            }
            Button("Cancel", role: .cancel) { taskPendingDelete = nil }
        } message: {
            if let t = taskPendingDelete {
                Text("\"\(t.plainTitle)\" has \(t.subtasks.count) subtask\(t.subtasks.count == 1 ? "" : "s") that will also be deleted.")
            }
        }
    }

    private func deleteIfEmpty(_ task: Task) {
        guard task.subtasks.isEmpty else { taskPendingDelete = task; return }
        taskStore.deleteTask(task)
    }

    private func navigateTo(_ task: Task, direction: Int) {
        let flat = groupedSections.flatMap { $0.tasks }.flatMap { [$0] + $0.subtasks.sorted { $0.createdAt < $1.createdAt } }
        guard let idx = flat.firstIndex(where: { $0.id == task.id }) else { return }
        let next = idx + direction
        guard next >= 0 && next < flat.count else { return }
        focusedTaskID = flat[next].id
    }
}
