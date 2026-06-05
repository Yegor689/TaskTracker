import SwiftUI

// MARK: - Drag-to-reorder engine
//
// Encapsulates all custom drag-and-drop state and logic for the per-project task
// list: live reordering of root tasks, drag-right-to-nest, and subtask reordering
// / drag-left-to-promote. TaskListView owns one of these and feeds it the current
// store, project, and visible roots. Rows report their measured midpoints via
// RowMidYKey so reordering respects real row heights.

@Observable
final class TaskDragController {
    /// The task currently being dragged (root or subtask), or nil.
    var draggingTaskID: UUID?
    /// Vertical offset applied to the dragged row so it follows the cursor.
    var dragOffset: CGFloat = 0
    /// Root task the dragged item would nest under if released now.
    var nestTargetID: UUID?
    /// Subtask that would be promoted to a root task if released now.
    var promoteTargetID: UUID?
    /// Measured vertical midpoint of each visible row, keyed by task id.
    var rowMidYs: [UUID: CGFloat] = [:]

    /// The dragged row's slot midpoint when the drag began; the row tracks the
    /// cursor as anchorMidY + translation, independent of array reshuffling.
    private var dragAnchorMidY: CGFloat = 0

    /// Name of the coordinate space the list measures rows in.
    static let coordinateSpace = "taskListDragSpace"
    /// How far right/left you must drag to switch to nest / promote.
    private static let nestThreshold: CGFloat = 28
    /// Approx. one row height; extends the subtask reorder band so the first and
    /// last slots are reachable without wandering into another task.
    private static let rowApprox: CGFloat = 30

    // MARK: Root task drag

    /// A drag gesture for a root task's bullet. Live-reorders as the dragged row's
    /// cursor crosses neighbours' measured midpoints; drag right to nest. Returns
    /// nil when the task isn't draggable.
    func rootGesture(for task: Task, roots: @escaping () -> [Task], store: TaskStore, project: Project) -> AnyGesture<Void>? {
        guard isDraggable(task) else { return nil }

        let gesture = DragGesture(minimumDistance: 4, coordinateSpace: .named(Self.coordinateSpace))
            .onChanged { [self] value in
                let desiredMidY = beginAndTrack(task.id, value: value)

                let rows = roots()
                guard let from = rows.firstIndex(where: { $0.id == task.id }) else { return }

                // Nest intent: dragged far enough right while over another root task
                // that can accept children.
                if value.translation.width >= Self.nestThreshold,
                   let hovered = rowUnder(desiredMidY, in: rows, excluding: task.id),
                   task.subtasks.isEmpty, hovered.parent == nil {
                    nestTargetID = hovered.id
                    return
                }
                nestTargetID = nil

                if let target = targetIndex(for: task.id, desiredMidY: desiredMidY, in: rows, from: from), target != from {
                    var reordered = rows
                    let moved = reordered.remove(at: from)
                    reordered.insert(moved, at: target)
                    store.reorderRoots(reordered, in: project)
                }
            }
            .onEnded { [self] _ in
                if let nestID = nestTargetID, let parent = roots().first(where: { $0.id == nestID }) {
                    withAnimation(.spring(duration: 0.2)) { store.nestTask(task, under: parent) }
                }
                endDrag()
                nestTargetID = nil
            }
        return AnyGesture(gesture.map { _ in () })
    }

    // MARK: Subtask drag

    /// A drag gesture for a subtask: reorder among siblings, or drag left to promote
    /// it back to a root task.
    func subtaskGesture(for subtask: Task, parent: Task, store: TaskStore) -> AnyGesture<Void>? {
        guard isDraggable(subtask) else { return nil }

        let gesture = DragGesture(minimumDistance: 4, coordinateSpace: .named(Self.coordinateSpace))
            .onChanged { [self] value in
                let desiredMidY = beginAndTrack(subtask.id, value: value)

                // Promote intent: dragged far enough left → becomes a root task.
                if value.translation.width <= -Self.nestThreshold {
                    promoteTargetID = subtask.id
                    return
                }
                promoteTargetID = nil

                // Reorder among siblings, clamped to the sibling band (extended by a
                // row each side so the first/last slots are reachable).
                let sibs = parent.subtasks.sorted { $0.sortIndex < $1.sortIndex }
                guard let from = sibs.firstIndex(where: { $0.id == subtask.id }) else { return }
                let mids = sibs.compactMap { rowMidYs[$0.id] }
                guard let lo = mids.min(), let hi = mids.max(),
                      desiredMidY >= lo - Self.rowApprox, desiredMidY <= hi + Self.rowApprox else { return }

                if let target = targetIndex(for: subtask.id, desiredMidY: desiredMidY, in: sibs, from: from), target != from {
                    var reordered = sibs
                    let moved = reordered.remove(at: from)
                    reordered.insert(moved, at: target)
                    store.reorderSubtasks(reordered, of: parent)
                }
            }
            .onEnded { [self] _ in
                if promoteTargetID == subtask.id {
                    withAnimation(.spring(duration: 0.2)) { store.unindentTask(subtask) }
                }
                endDrag()
                promoteTargetID = nil
            }
        return AnyGesture(gesture.map { _ in () })
    }

    // MARK: Shared helpers

    /// Only incomplete tasks are draggable. (Callers also gate on filter/search.)
    private func isDraggable(_ task: Task) -> Bool { !task.isDone }

    /// Begins the drag (anchoring) if needed and updates dragOffset to track the
    /// cursor. Returns the row's desired screen midpoint.
    private func beginAndTrack(_ id: UUID, value: DragGesture.Value) -> CGFloat {
        if draggingTaskID != id {
            draggingTaskID = id
            dragAnchorMidY = rowMidYs[id] ?? value.location.y
        }
        let desiredMidY = dragAnchorMidY + value.translation.height
        let currentSlotMid = rowMidYs[id] ?? desiredMidY
        dragOffset = desiredMidY - currentSlotMid
        return desiredMidY
    }

    private func endDrag() {
        withAnimation(.spring(duration: 0.2)) { dragOffset = 0 }
        draggingTaskID = nil
    }

    /// The index in `rows` the dragged item should move to, given the cursor's
    /// desired midpoint, or nil if unchanged.
    private func targetIndex(for id: UUID, desiredMidY: CGFloat, in rows: [Task], from: Int) -> Int? {
        var target = from
        for (i, row) in rows.enumerated() where row.id != id {
            guard let mid = rowMidYs[row.id] else { continue }
            if i < from, desiredMidY < mid { target = min(target, i) }
            if i > from, desiredMidY > mid { target = max(target, i) }
        }
        return target
    }

    /// The row whose midpoint is nearest `y`, excluding `id`.
    private func rowUnder(_ y: CGFloat, in rows: [Task], excluding id: UUID) -> Task? {
        rows.filter { $0.id != id }
            .min(by: { abs((rowMidYs[$0.id] ?? .infinity) - y) < abs((rowMidYs[$1.id] ?? .infinity) - y) })
    }
}

// MARK: - Row plumbing

/// Everything a subtask row needs to take part in dragging, passed down from
/// TaskListView (which owns the drag controller).
struct DragContext {
    let draggingTaskID: UUID?
    let dragOffset: CGFloat
    let promoteTargetID: UUID?
    let coordinateSpace: String
    /// Produces a drag gesture for (parent, subtask).
    let subtaskGesture: (Task, Task) -> AnyGesture<Void>?
}

/// The bullet's gestures. The drag (minimumDistance 4) handles reorder/nest; a
/// separate tap toggles completion. Because the drag needs 4pt of movement to
/// start, a click only triggers the tap and a drag only triggers the drag —
/// SwiftUI arbitrates between them, so a drag never toggles the task.
struct BulletGestureModifier: ViewModifier {
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

/// Collects each row's measured vertical midpoint, keyed by task id.
struct RowMidYKey: PreferenceKey {
    static var defaultValue: [UUID: CGFloat] { [:] }
    static func reduce(value: inout [UUID: CGFloat], nextValue: () -> [UUID: CGFloat]) {
        value.merge(nextValue()) { _, new in new }
    }
}
