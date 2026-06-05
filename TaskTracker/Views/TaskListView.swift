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
    @Environment(ReminderManager.self) private var reminderManager
    @Environment(\.undoManager) private var undoManager
    var project: Project
    @Binding var selection: SidebarSelection?

    @State private var path = NavigationPath()
    @State private var focusedTaskID: UUID?
    @AppStorage("taskFilter") private var filter: TaskFilter = .active
    @State private var searchText = ""
    @State private var taskPendingDelete: Task?

    // Custom drag-to-reorder state.
    @State private var draggingTaskID: UUID?
    @State private var dragOffset: CGFloat = 0
    // The dragged row's slot midpoint at the moment the drag began. The row tracks
    // the cursor as anchorMidY + translation, independent of array reshuffling.
    @State private var dragAnchorMidY: CGFloat = 0
    // Measured vertical midpoint of each root row (in the list's coordinate space),
    // so reorder decisions respect real row heights (tall rows with subtasks).
    @State private var rowMidYs: [UUID: CGFloat] = [:]
    // While dragging, the root task the dragged item would be nested under if
    // released now (set when the user drags far enough to the right over a row).
    @State private var nestTargetID: UUID?
    // While dragging a subtask, set when dragged far enough left to promote it.
    @State private var promoteTargetID: UUID?
    private static let dragSpace = "taskListDragSpace"
    // How far right you must drag to switch from "reorder" to "nest under".
    private static let nestThreshold: CGFloat = 28
    // Approx. one row height; used to extend the subtask reorder band so the first
    // and last slots are reachable without wandering into another task.
    private let rowApprox: CGFloat = 30

    // Flat ordered list: each root task followed by its visible subtasks.
    var flatTasks: [Task] {
        filteredTasks.flatMap { task -> [Task] in
            let subs = task.subtasks.sorted(by: Self.taskOrder).filter { sub in
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
        return filtered.sorted(by: Self.taskOrder)
    }

    /// Ordering shared by the list: incomplete tasks first in their manual
    /// (sortIndex) order, then completed tasks grouped at the bottom with the
    /// most recently completed on top.
    static func taskOrder(_ lhs: Task, _ rhs: Task) -> Bool {
        if lhs.isDone != rhs.isDone { return !lhs.isDone }
        if lhs.isDone {
            // Both done: newest completion first (on top of the done group).
            let l = lhs.completedAt ?? lhs.createdAt
            let r = rhs.completedAt ?? rhs.createdAt
            return l > r
        }
        // Incomplete: manual order. (Priority no longer forces position now that
        // tasks can be dragged; the priority accent still marks them visually.)
        if lhs.sortIndex != rhs.sortIndex { return lhs.sortIndex < rhs.sortIndex }
        return lhs.createdAt < rhs.createdAt
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
                            navigate:           { t in path.append(t) },
                            dragGesture:        dragGesture(for: task),
                            dragContext:        DragContext(
                                draggingTaskID: draggingTaskID,
                                dragOffset: dragOffset,
                                promoteTargetID: promoteTargetID,
                                coordinateSpace: Self.dragSpace,
                                subtaskGesture: { parent, sub in subtaskDragGesture(for: sub, parent: parent) }
                            )
                        )
                        .overlay {
                            // Highlight the row the dragged task would nest under.
                            if nestTargetID == task.id {
                                RoundedRectangle(cornerRadius: 6)
                                    .strokeBorder(Color.accentColor, lineWidth: 2)
                            }
                        }
                        .offset(
                            x: (draggingTaskID == task.id && nestTargetID != nil) ? 20 : 0,
                            y: draggingTaskID == task.id ? dragOffset : 0
                        )
                        .zIndex(draggingTaskID == task.id ? 1 : 0)
                        // Non-dragged rows slide smoothly into new slots; the dragged
                        // row tracks the cursor without animation lag.
                        .animation(draggingTaskID == task.id ? nil : .spring(duration: 0.25),
                                   value: filteredTasks.map(\.id))
                        .onTapGesture(count: 2) { path.append(task) }
                        .background(
                            GeometryReader { geo in
                                Color.clear.preference(
                                    key: RowMidYKey.self,
                                    value: [task.id: geo.frame(in: .named(Self.dragSpace)).midY]
                                )
                            }
                        )
                    }

                    if filter != .done && searchText.isEmpty {
                        NewItemButton { addTask() }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                .coordinateSpace(name: Self.dragSpace)
                .onPreferenceChange(RowMidYKey.self) { rowMidYs = $0 }
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
        .onAppear {
            taskStore.undoManager = undoManager
            taskStore.reminderManager = reminderManager
        }
        .onChange(of: undoManager) { taskStore.undoManager = undoManager }
    }

    private func addTask() {
        let task = taskStore.addTask(to: project)
        if filter == .done { filter = .active }
        focus(task.id)
    }

    /// A drag gesture for the bullet handle of a root task. Live-reorders the list
    /// as the dragged row's cursor crosses neighbouring rows' measured midpoints,
    /// then commits on release. Using real midpoints (not a fixed row height) keeps
    /// reordering correct across tall rows (parents with subtasks/descriptions).
    private func dragGesture(for task: Task) -> AnyGesture<Void>? {
        // Only incomplete root tasks are draggable, and only in the unfiltered list
        // (reordering a filtered subset is ambiguous).
        guard !task.isDone, filter == .all || filter == .active, searchText.isEmpty else { return nil }

        let gesture = DragGesture(minimumDistance: 4, coordinateSpace: .named(Self.dragSpace))
            .onChanged { value in
                if draggingTaskID != task.id {
                    draggingTaskID = task.id
                    // Anchor to this row's current slot so the row tracks the cursor
                    // 1:1 regardless of how the array reshuffles underneath.
                    dragAnchorMidY = rowMidYs[task.id] ?? value.location.y
                }

                // The row's desired screen midpoint = where it started + how far the
                // cursor moved. Its visual offset is that minus its current slot mid.
                let desiredMidY = dragAnchorMidY + value.translation.height
                let currentSlotMid = rowMidYs[task.id] ?? desiredMidY
                dragOffset = desiredMidY - currentSlotMid

                let rows = filteredTasks
                guard let from = rows.firstIndex(where: { $0.id == task.id }) else { return }

                // Nest intent: dragged far enough right while hovering another root
                // task that can accept children. The row directly under the cursor
                // is the one whose vertical band contains desiredMidY.
                if value.translation.width >= Self.nestThreshold,
                   let hovered = rowUnder(desiredMidY, excluding: task.id),
                   task.subtasks.isEmpty, hovered.parent == nil {
                    nestTargetID = hovered.id
                    return   // hold position; don't reorder while aiming to nest
                }
                nestTargetID = nil

                // Reorder: move the dragged task to the slot whose midpoint the
                // cursor has crossed, comparing against the OTHER rows' real mids.
                var target = from
                for (i, row) in rows.enumerated() where row.id != task.id {
                    guard let mid = rowMidYs[row.id] else { continue }
                    if i < from, desiredMidY < mid { target = min(target, i) }
                    if i > from, desiredMidY > mid { target = max(target, i) }
                }
                if target != from {
                    move(task, in: rows, to: target)
                }
            }
            .onEnded { _ in
                if let nestID = nestTargetID,
                   let parent = filteredTasks.first(where: { $0.id == nestID }) {
                    withAnimation(.spring(duration: 0.2)) {
                        taskStore.nestTask(task, under: parent)
                    }
                }
                withAnimation(.spring(duration: 0.2)) { dragOffset = 0 }
                draggingTaskID = nil
                nestTargetID = nil
            }
        return AnyGesture(gesture.map { _ in () })
    }

    /// Drag gesture for a subtask: reorder among its siblings, or drag left past a
    /// threshold to promote it back to a root task.
    private func subtaskDragGesture(for subtask: Task, parent: Task) -> AnyGesture<Void>? {
        guard !subtask.isDone, filter == .all || filter == .active, searchText.isEmpty else { return nil }

        let gesture = DragGesture(minimumDistance: 4, coordinateSpace: .named(Self.dragSpace))
            .onChanged { value in
                if draggingTaskID != subtask.id {
                    draggingTaskID = subtask.id
                    dragAnchorMidY = rowMidYs[subtask.id] ?? value.location.y
                }
                let desiredMidY = dragAnchorMidY + value.translation.height
                let currentSlotMid = rowMidYs[subtask.id] ?? desiredMidY
                dragOffset = desiredMidY - currentSlotMid

                // Promote intent: dragged far enough LEFT → becomes a root task.
                if value.translation.width <= -Self.nestThreshold {
                    promoteTargetID = subtask.id
                    return
                }
                promoteTargetID = nil

                // Live-reorder among siblings. Clamp the effective position into the
                // sibling range so dragging above the first row targets the first
                // slot and below the last targets the last — but don't run if the
                // cursor has wandered far past the band (heading toward another task).
                let sibs = parent.subtasks.sorted { $0.sortIndex < $1.sortIndex }
                guard let from = sibs.firstIndex(where: { $0.id == subtask.id }) else { return }
                let mids = sibs.compactMap { rowMidYs[$0.id] }
                if let lo = mids.min(), let hi = mids.max(),
                   desiredMidY >= lo - rowApprox, desiredMidY <= hi + rowApprox {
                    var target = from
                    for (i, s) in sibs.enumerated() where s.id != subtask.id {
                        guard let mid = rowMidYs[s.id] else { continue }
                        if i < from, desiredMidY < mid { target = min(target, i) }
                        if i > from, desiredMidY > mid { target = max(target, i) }
                    }
                    if target != from {
                        var reordered = sibs
                        let moved = reordered.remove(at: from)
                        reordered.insert(moved, at: target)
                        taskStore.reorderSubtasks(reordered, of: parent)
                    }
                }
            }
            .onEnded { _ in
                if promoteTargetID == subtask.id {
                    withAnimation(.spring(duration: 0.2)) { taskStore.unindentTask(subtask) }
                }
                withAnimation(.spring(duration: 0.2)) { dragOffset = 0 }
                draggingTaskID = nil
                promoteTargetID = nil
            }
        return AnyGesture(gesture.map { _ in () })
    }

    /// The root row whose vertical band contains `y` (nearest midpoint), if any.
    private func rowUnder(_ y: CGFloat, excluding id: UUID) -> Task? {
        filteredTasks
            .filter { $0.id != id }
            .min(by: { abs((rowMidYs[$0.id] ?? .infinity) - y) < abs((rowMidYs[$1.id] ?? .infinity) - y) })
    }

    /// Moves `task` to `target` index within the visible roots and persists order.
    private func move(_ task: Task, in rows: [Task], to target: Int) {
        guard let from = rows.firstIndex(where: { $0.id == task.id }), from != target else { return }
        var reordered = rows
        let moved = reordered.remove(at: from)
        reordered.insert(moved, at: target)
        taskStore.reorderRoots(reordered, in: project)
    }

    private func addTaskAfter(_ task: Task) {
        // New tasks always start at Normal priority — they don't inherit the
        // priority of the task they were created after.
        let newTask = taskStore.addTask(to: project, after: task)
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

/// Everything a subtask row needs to take part in dragging, passed down from
/// TaskListView (which owns the drag state).
struct DragContext {
    let draggingTaskID: UUID?
    let dragOffset: CGFloat
    let promoteTargetID: UUID?
    let coordinateSpace: String
    /// Produces a drag gesture for (parent, subtask).
    let subtaskGesture: (Task, Task) -> AnyGesture<Void>?
}

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
    /// Drag-to-reorder gesture, attached to the bullet. Nil = not draggable.
    var dragGesture: AnyGesture<Void>? = nil
    /// Shared drag context so subtask rows can take part in dragging too.
    var dragContext: DragContext? = nil

    @Environment(ReminderManager.self) private var reminderManager
    @State private var isHovered = false
    @State private var showReminderPopover = false

    private var isFocused: Bool { focusedID == task.id }
    private var subtaskFocused: Bool { sortedSubtasks.contains { $0.id == focusedID } }
    private var anyFocused: Bool     { isFocused || subtaskFocused }
    // Same ordering as root tasks: manual order, with completed subtasks sunk to
    // the bottom (newest completion on top of the done group).
    private var sortedSubtasks: [Task] { task.subtasks.sorted(by: TaskListView.taskOrder) }

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
                    // The bullet doubles as the reorder handle. It's not a Button so
                    // the drag and tap don't conflict: a tap toggles done, a drag
                    // (≥4pt) reorders/nests and suppresses the toggle.
                    Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(task.isDone ? .green : (task.priorityLevel.isAccented ? task.priorityLevel.color : .secondary))
                        .font(.system(size: iconSize))
                        .frame(height: lineHeight)
                        .contentShape(Rectangle())
                        .modifier(BulletGestureModifier(
                            dragGesture: dragGesture,
                            onTap: { withAnimation(.spring(duration: 0.25)) { task.toggleDone() } }
                        ))

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
                        .frame(maxWidth: .infinity, minHeight: lineHeight, alignment: .leading)

                        if !task.plainDesc.isEmpty {
                            Text(task.plainDesc)
                                .font(isSubtask ? .caption : .callout)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    if isHovered || anyFocused || showReminderPopover {
                        Spacer(minLength: 40)
                    }
                }

                if isHovered || anyFocused || showReminderPopover {
                    HStack(spacing: 4) {
                        Menu {
                            ForEach(Priority.allCases) { level in
                                Button {
                                    withAnimation(.spring(duration: 0.2)) { task.priorityLevel = level }
                                } label: {
                                    Label(level.label, systemImage: task.priorityLevel == level ? "checkmark" : level.iconName)
                                }
                            }
                        } label: {
                            Image(systemName: task.priorityLevel.iconName)
                                .foregroundStyle(task.priorityLevel.isAccented ? task.priorityLevel.color : Color.secondary.opacity(0.4))
                                .font(.system(size: infoSize))
                        }
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.hidden)
                        .fixedSize()
                        .help("Priority: \(task.priorityLevel.label)")

                        Divider().frame(height: infoSize)

                        Button { showReminderPopover = true } label: {
                            Image(systemName: task.reminderDate != nil ? "bell.fill" : "bell")
                                .foregroundStyle(task.reminderDate != nil ? Color.accentColor : Color.secondary.opacity(0.4))
                                .font(.system(size: infoSize))
                        }
                        .buttonStyle(.plain)
                        .help(task.reminderDate != nil ? "Edit Reminder" : "Set Reminder")
                        .popover(isPresented: $showReminderPopover, arrowEdge: .bottom) {
                            ReminderPopover(task: task, reminderManager: reminderManager)
                        }

                        Divider().frame(height: infoSize)

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
                // Accent bar marking non-normal, not-yet-done tasks, colored by level.
                if task.priorityLevel.isAccented && !task.isDone {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(task.priorityLevel.color)
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
                            navigate:           navigate,
                            dragGesture:        dragContext?.subtaskGesture(task, subtask)
                        )
                        // Promote highlight: dragged left to become a root task.
                        .overlay(alignment: .leading) {
                            if dragContext?.promoteTargetID == subtask.id {
                                RoundedRectangle(cornerRadius: 6)
                                    .strokeBorder(Color.accentColor, lineWidth: 2)
                            }
                        }
                        .offset(
                            x: (dragContext?.draggingTaskID == subtask.id && dragContext?.promoteTargetID != nil) ? -20 : 0,
                            y: dragContext?.draggingTaskID == subtask.id ? (dragContext?.dragOffset ?? 0) : 0
                        )
                        .zIndex(dragContext?.draggingTaskID == subtask.id ? 1 : 0)
                        .background(
                            GeometryReader { geo in
                                Color.clear.preference(
                                    key: RowMidYKey.self,
                                    value: [subtask.id: geo.frame(in: .named(dragContext?.coordinateSpace ?? "")).midY]
                                )
                            }
                        )
                    }
                }
                .padding(.leading, 26)
            }
        }
        .contextMenu {
            Button("Open Properties") { navigate(task) }
            Divider()
            Picker("Priority", selection: $task.priorityLevel) {
                ForEach(Priority.allCases) { level in
                    Label(level.label, systemImage: level.iconName).tag(level)
                }
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
    private var critical: Int     { allTasks.filter { $0.priorityLevel == .critical && !$0.isDone }.count }

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
                withAnimation(.spring(duration: 0.25)) { task.toggleDone() }
            } label: {
                Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(task.isDone ? .green : (task.priorityLevel == .critical ? .red : .secondary))
                    .imageScale(.large)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    Text(task.plainTitle)
                        .strikethrough(task.isDone)
                        .foregroundStyle(task.isDone ? .secondary : .primary)
                        .fontWeight(task.priorityLevel == .critical && !task.isDone ? .semibold : .regular)
                    if task.priorityLevel != .normal && !task.isDone {
                        Image(systemName: task.priorityLevel.iconName)
                            .foregroundStyle(task.priorityLevel.color)
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


/// The bullet's gestures. The drag (minimumDistance 4) handles reorder/nest; a
/// separate tap toggles completion. Because the drag needs 4pt of movement to
/// start, a click only triggers the tap and a drag only triggers the drag —
/// SwiftUI arbitrates between them, so a drag never toggles the task.
private struct BulletGestureModifier: ViewModifier {
    let dragGesture: AnyGesture<Void>?
    let onTap: () -> Void

    func body(content: Content) -> some View {
        if let dragGesture {
            content
                .onTapGesture(perform: onTap)
                .gesture(dragGesture)
        } else {
            content.onTapGesture(perform: onTap)
        }
    }
}

/// Collects each root row's measured vertical midpoint, keyed by task id.
private struct RowMidYKey: PreferenceKey {
    static var defaultValue: [UUID: CGFloat] { [:] }
    static func reduce(value: inout [UUID: CGFloat], nextValue: () -> [UUID: CGFloat]) {
        value.merge(nextValue()) { _, new in new }
    }
}
