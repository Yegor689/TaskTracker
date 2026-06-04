import SwiftUI
import SwiftData
import AppKit


enum TaskFilter: String, CaseIterable {
    case all    = "All"
    case active = "Active"
    case done   = "Done"
}

// MARK: - Task List

struct TaskListView: View {
    @Environment(TaskStore.self) private var taskStore
    @Environment(\.undoManager) private var undoManager
    var project: Project
    @Binding var selection: SidebarSelection?

    @State private var path = NavigationPath()
    @State private var focusedTaskID: UUID?
    @State private var filter: TaskFilter = .active
    @State private var searchText = ""
    @State private var taskPendingDelete: Task?

    // Flat ordered list: each root task followed by its visible subtasks.
    var flatTasks: [Task] {
        filteredTasks.flatMap { task -> [Task] in
            let subs = task.subtasks.sorted { $0.createdAt < $1.createdAt }.filter { sub in
                switch filter {
                case .all:    return true
                case .active: return !sub.isDone
                case .done:   return sub.isDone
                }
            }
            return [task] + subs
        }
    }

    var filteredTasks: [Task] {
        let root = project.tasks.filter { $0.parent == nil }
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

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(filteredTasks) { task in
                        TaskRowView(
                            task: task,
                            isSubtask: false,
                            focusedID: $focusedTaskID,
                            onReturn:           { addTaskAfter(task) },
                            onDeleteIfEmpty:    { deleteIfEmpty(task) },
                            onDelete:           { taskStore.deleteTask(task) },
                            onIndent:           { indentTask(task) },
                            onUnindent:         { },
                            onNavigateUp:       { navigateTo(task, direction: -1) },
                            onNavigateDown:     { navigateTo(task, direction: +1) },
                            onNavigateDownFrom: { navigateTo($0, direction: +1) },
                            navigate:           { t in path.append(t) }
                        )
                        .onTapGesture(count: 2) { path.append(task) }
                    }

                    if filter != .done && searchText.isEmpty {
                        NewItemButton { addTask() }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                TaskStatsFooter(tasks: project.tasks, filter: filter)
            }
            .navigationTitle("")
            .toolbarTitleDisplayMode(.inline)
            .navigationDestination(for: Task.self) { task in
                TaskDetailView(task: task)
            }
            .searchable(text: $searchText, prompt: "Search tasks")
            .overlay {
                if filteredTasks.isEmpty {
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
                ToolbarItem {
                    Button { addTask() } label: {
                        Label("Add Task", systemImage: "plus")
                    }
                    .help("New Item (⌘N)")
                    .keyboardShortcut("n", modifiers: .command)
                }
            }
        }
        .alert("Delete Task?", isPresented: Binding(
            get: { taskPendingDelete != nil },
            set: { if !$0 { taskPendingDelete = nil } }
        )) {
            Button("Delete", role: .destructive) {
                if let t = taskPendingDelete { confirmDelete(t) }
            }
            Button("Cancel", role: .cancel) { taskPendingDelete = nil }
        } message: {
            if let t = taskPendingDelete {
                Text("\"\(t.plainTitle)\" has \(t.subtasks.count) subtask\(t.subtasks.count == 1 ? "" : "s") that will also be deleted.")
            }
        }
        .onChange(of: project.id) {
            path = NavigationPath()
            focusedTaskID = nil
        }
        .onAppear { taskStore.undoManager = undoManager }
        .onChange(of: undoManager) { taskStore.undoManager = undoManager }
    }

    private func addTask() {
        let task = taskStore.addTask(to: project)
        if filter == .done { filter = .active }
        focus(task.id)
    }

    private func addTaskAfter(_ task: Task) {
        let newTask = taskStore.addTask(priority: task.priority, to: project, after: task)
        focus(newTask.id)
    }

    private func indentTask(_ task: Task) {
        // Subtasks only nest one level deep; indenting a task that already has
        // subtasks would hide those grandchildren, so disallow it.
        guard task.subtasks.isEmpty else { return }
        let roots = filteredTasks
        guard let idx = roots.firstIndex(where: { $0.id == task.id }), idx > 0 else { return }
        taskStore.indentTask(task, previousTask: roots[idx - 1])
        focus(task.id)
    }

    private func deleteIfEmpty(_ task: Task) {
        guard task.subtasks.isEmpty else {
            taskPendingDelete = task
            return
        }
        performDelete(task)
    }

    private func confirmDelete(_ task: Task) {
        taskPendingDelete = nil
        performDelete(task)
    }

    private func performDelete(_ task: Task) {
        let tasks = filteredTasks
        if let idx = tasks.firstIndex(where: { $0.id == task.id }) {
            let prevID = idx > 0 ? tasks[idx - 1].id : nil
            taskStore.deleteTask(task)
            DispatchQueue.main.async { focusedTaskID = prevID }
        }
    }

    private func focus(_ id: UUID) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { focusedTaskID = id }
    }

    private func navigateTo(_ task: Task, direction: Int) {
        let flat = flatTasks
        guard let idx = flat.firstIndex(where: { $0.id == task.id }) else { return }
        let next = idx + direction
        guard next >= 0 && next < flat.count else { return }
        focusedTaskID = flat[next].id
    }
}

// MARK: - Task Row (root + subtask, unified)

struct TaskRowView: View {
    @Bindable var task: Task
    var isSubtask: Bool
    @Environment(TaskStore.self) private var taskStore
    @Binding var focusedID: UUID?
    var onReturn:        () -> Void
    var onDeleteIfEmpty: () -> Void
    var onDelete:        () -> Void
    var onIndent:        () -> Void
    var onUnindent:      () -> Void
    var onNavigateUp:       () -> Void
    var onNavigateDown:     () -> Void
    var onNavigateDownFrom: (Task) -> Void
    var navigate:           (Task) -> Void

    @State private var isHovered = false

    private var isFocused: Bool { focusedID == task.id }
    private var subtaskFocused: Bool { sortedSubtasks.contains { $0.id == focusedID } }
    private var anyFocused: Bool     { isFocused || subtaskFocused }
    private var sortedSubtasks: [Task] { task.subtasks.sorted { $0.createdAt < $1.createdAt } }

    private var iconSize: CGFloat  { isSubtask ? 18 : 22 }
    private var titleFont: NSFont  { isSubtask ? .preferredFont(forTextStyle: .body) : .preferredFont(forTextStyle: .title3) }
    // Match the title field's frame to the font's natural line height so the text
    // fills it exactly (no vertical slack for the top-aligned glyphs to float in).
    private var lineHeight: CGFloat { ceil(titleFont.ascender - titleFont.descender + titleFont.leading) }
    private var infoSize: CGFloat  { isSubtask ? 13 : 15 }

    private var rowFill: Color {
        if isFocused { return Color.primary.opacity(0.06) }
        if isHovered { return Color.primary.opacity(0.035) }
        return .clear
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .trailing) {
                HStack(alignment: .top, spacing: isSubtask ? 8 : 10) {
                    Button {
                        withAnimation(.spring(duration: 0.25)) { task.isDone.toggle() }
                    } label: {
                        Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(task.isDone ? .green : (task.priority == 0 ? .red : .secondary))
                            .font(.system(size: iconSize))
                    }
                    .buttonStyle(.plain)
                    .frame(height: lineHeight)

                    VStack(alignment: .leading, spacing: 1) {
                        RichTitleField(
                            rtf: $task.titleRTF,
                            font: titleFont,
                            isFocused: isFocused,
                            onFocus:         { focusedID = task.id },
                            onReturn:        onReturn,
                            onDeleteIfEmpty: onDeleteIfEmpty,
                            onBlurIfEmpty:   onDeleteIfEmpty,
                            onTab:           onIndent,
                            onShiftTab:      onUnindent,
                            onNavigateUp:    onNavigateUp,
                            onNavigateDown:  onNavigateDown
                        )
                        .frame(height: lineHeight)

                        if !task.plainDesc.isEmpty {
                            Text(task.plainDesc)
                                .font(isSubtask ? .caption : .callout)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    if isHovered || anyFocused {
                        Spacer(minLength: 40)
                    }
                }

                if isHovered || anyFocused {
                    HStack(spacing: 4) {
                        Button {
                            withAnimation(.spring(duration: 0.2)) { task.priority = task.priority == 0 ? 1 : 0 }
                        } label: {
                            Image(systemName: task.priority == 0 ? "exclamationmark.circle.fill" : "exclamationmark.circle")
                                .foregroundStyle(task.priority == 0 ? Color.red : Color.secondary.opacity(0.4))
                                .font(.system(size: infoSize))
                        }
                        .buttonStyle(.plain)
                        .help(task.priority == 0 ? "Mark Normal" : "Mark Critical")

                        Divider()
                            .frame(height: infoSize)

                        Button { navigate(task) } label: {
                            Image(systemName: "info.circle")
                                .foregroundStyle(.tertiary)
                                .font(.system(size: infoSize))
                        }
                        .buttonStyle(.plain)
                        .help("Open Properties")
                    }
                    .transition(.opacity.animation(.easeInOut(duration: 0.1)))
                }
            }
            .padding(.vertical, isSubtask ? 5 : 7)
            .padding(.horizontal, isSubtask ? 6 : 8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(rowFill)
            )
            .overlay(alignment: .leading) {
                // Accent bar marking critical, not-yet-done tasks.
                if task.priority == 0 && !task.isDone {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Color.red)
                        .frame(width: 3)
                        .padding(.vertical, isSubtask ? 4 : 5)
                }
            }
            .animation(.easeInOut(duration: 0.12), value: isHovered)

            if !isSubtask && !sortedSubtasks.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(sortedSubtasks) { subtask in
                        TaskRowView(
                            task: subtask,
                            isSubtask: true,
                            focusedID: $focusedID,
                            onReturn:           { addSubtaskAfter(subtask) },
                            onDeleteIfEmpty:    { deleteSubtaskIfEmpty(subtask) },
                            onDelete:           { taskStore.deleteTask(subtask) },
                            onIndent:           { },
                            onUnindent:         { unindent(subtask) },
                            onNavigateUp:       { navigateSubtask(subtask, direction: -1) },
                            onNavigateDown:     { navigateSubtask(subtask, direction: +1) },
                            onNavigateDownFrom: { _ in navigateSubtask(subtask, direction: +1) },
                            navigate:           navigate
                        )
                    }
                }
                .padding(.leading, 26)
            }
        }
        .contextMenu {
            Button("Open Properties") { navigate(task) }
            Divider()
            Picker("Priority", selection: $task.priority) {
                Label("Critical", systemImage: "exclamationmark.circle.fill").tag(0)
                Text("Normal").tag(1)
            }
            Divider()
            Button("Delete", role: .destructive, action: onDelete)
        }
        .onHover { isHovered = $0 }
    }

    private func addSubtaskAfter(_ subtask: Task) {
        let sub = taskStore.addSubtask(to: task, after: subtask)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            self.focusedID = sub.id
        }
    }

    private func deleteSubtaskIfEmpty(_ subtask: Task) {
        let subs = sortedSubtasks
        if let idx = subs.firstIndex(where: { $0.id == subtask.id }) {
            let prevID: UUID? = idx > 0 ? subs[idx - 1].id : task.id
            taskStore.deleteTask(subtask)
            DispatchQueue.main.async { self.focusedID = prevID }
        }
    }

    private func unindent(_ subtask: Task) {
        taskStore.unindentTask(subtask)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            self.focusedID = subtask.id
        }
    }

    // Flat list for this parent: [parent] + sortedSubtasks.
    // `next == 0` lands on the parent task itself; that's handled by flat[0].
    private func navigateSubtask(_ subtask: Task, direction: Int) {
        let flat: [Task] = [task] + sortedSubtasks
        guard let idx = flat.firstIndex(where: { $0.id == subtask.id }) else { return }
        let next = idx + direction
        if next >= 0 && next < flat.count {
            // next == 0 selects the parent task
            focusedID = flat[next].id
        } else {
            // Below last subtask — navigate from the subtask's position in the full flat list
            onNavigateDownFrom(subtask)
        }
    }
}

// MARK: - Stats Footer

private struct TaskStatsFooter: View {
    var tasks: [Task]
    var filter: TaskFilter

    // Always show whole-project stats so numbers are stable regardless of filter
    private var allTasks: [Task]  { tasks + tasks.flatMap(\.subtasks) }
    private var total:    Int     { allTasks.count }
    private var done:     Int     { allTasks.filter(\.isDone).count }
    private var critical: Int     { allTasks.filter { $0.priority == 0 && !$0.isDone }.count }

    private var fraction: Double { total > 0 ? Double(done) / Double(total) : 0 }

    var body: some View {
        if total > 0 {
            VStack(spacing: 0) {
                Divider()
                HStack(spacing: 14) {
                    HStack(spacing: 6) {
                        Image(systemName: done == total ? "checkmark.circle.fill" : "checkmark.circle")
                            .foregroundStyle(done == total ? .green : .secondary)
                        Text("\(done) / \(total) done")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }

                    // Compact progress track
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.primary.opacity(0.08))
                        GeometryReader { geo in
                            Capsule()
                                .fill(done == total ? Color.green : Color.accentColor)
                                .frame(width: max(0, geo.size.width * fraction))
                        }
                    }
                    .frame(width: 120, height: 5)
                    .animation(.easeInOut, value: fraction)

                    if critical > 0 {
                        Label("\(critical) critical", systemImage: "exclamationmark.circle.fill")
                            .foregroundStyle(.red.opacity(0.8))
                    }

                    Spacer()

                    if done == total {
                        Label("All done", systemImage: "party.popper.fill")
                            .foregroundStyle(.green)
                    }
                }
                .font(.caption)
                .padding(.horizontal, 20)
                .padding(.vertical, 9)
            }
            .background(.bar)
        }
    }
}

// MARK: - New Item Button

private struct NewItemButton: View {
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: "plus.circle")
                    .foregroundStyle(isHovered ? .primary : .tertiary)
                    .font(.system(size: 16))
                Text("New item")
                    .foregroundStyle(isHovered ? .secondary : .tertiary)
                    .font(.body)
            }
            .padding(.vertical, 5)
            .padding(.horizontal, 8)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Task Row (used in TaskDetailView subtask list)

struct TaskDetailRowView: View {
    var task: Task

    private var doneCount: Int  { task.subtasks.filter(\.isDone).count }
    private var totalCount: Int { task.subtasks.count }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button {
                withAnimation(.spring(duration: 0.25)) { task.isDone.toggle() }
            } label: {
                Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(task.isDone ? .green : (task.priority == 0 ? .red : .secondary))
                    .imageScale(.large)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    Text(task.plainTitle)
                        .strikethrough(task.isDone)
                        .foregroundStyle(task.isDone ? .secondary : .primary)
                        .fontWeight(task.priority == 0 && !task.isDone ? .semibold : .regular)
                    if task.priority == 0 && !task.isDone {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
                if totalCount > 0 {
                    HStack(spacing: 5) {
                        ProgressView(value: Double(doneCount), total: Double(totalCount))
                            .progressViewStyle(.linear)
                            .tint(doneCount == totalCount ? .green : .secondary)
                            .frame(width: 56)
                        Text("\(doneCount)/\(totalCount)")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }
}
