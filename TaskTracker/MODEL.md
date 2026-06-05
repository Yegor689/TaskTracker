# Data Model

## Project

Represents a top-level grouping of tasks.

| Field | Type | Notes |
|-------|------|-------|
| `id` | `UUID` | Unique identifier |
| `title` | `String` | Display name |
| `desc` | `String` | Optional details |
| `createdAt` | `Date` | Timestamp set on creation |
| `tasks` | `[Task]` | All tasks belonging to this project (SwiftData relationship) |

---

## Task

Tasks belong to a project and can be nested one level deep (subtasks via `parent`).

| Field | Type | Notes |
|-------|------|-------|
| `id` | `UUID` | Unique identifier |
| `titleRTF` | `Data` | Rich text title serialized as RTF |
| `descRTF` | `Data` | Rich text description serialized as RTF |
| `isDone` | `Bool` | Completion state |
| `priority` | `Int` | Raw `Priority` value: `0` = critical, `1` = normal, `2` = low |
| `createdAt` | `Date` | Timestamp set on creation; tiebreaker / migration fallback for ordering |
| `completedAt` | `Date?` | When most recently marked done; `nil` while incomplete. Orders the completed group (newest on top) |
| `sortIndex` | `Int` | Manual position within the parent context (project for roots, parent task for subtasks). Primary ordering key |
| `reminderDate` | `Date?` | Optional reminder time; `nil` when no reminder is set |
| `project` | `Project?` | Owning project (SwiftData relationship) |
| `parent` | `Task?` | `nil` for root tasks; set to parent task for subtasks |
| `subtasks` | `[Task]` | Child tasks (cascade-delete on parent delete) |

`Priority` is an `Int`-backed enum (`critical`/`normal`/`low`) and the single source of truth for each level's label, color, icon, and accent. `task.priorityLevel` is the typed accessor over the stored `priority` Int.

### Computed properties

| Property | Type | Notes |
|----------|------|-------|
| `plainTitle` | `String` | Plain text extracted from `titleRTF` |
| `plainDesc` | `String` | Plain text extracted from `descRTF` |
| `priorityLevel` | `Priority` | Typed get/set over `priority`; falls back to `.normal` for bad values |

### Methods & static helpers

| Helper | Notes |
|--------|-------|
| `setDone(_:)` / `toggleDone()` | Sets completion and stamps `completedAt` — always use instead of mutating `isDone` directly |
| `Task.rtf(from:font:)` | Converts a plain `String` to RTF `Data` with default label color |
| `Task.plain(from:)` | Extracts plain text from RTF `Data` |
| `Task.resizingFontRTF(_:to:)` | Re-renders title RTF at a new font size (used when a task changes level) |

---

## Hierarchy

Tasks form a two-level tree within each project. Root tasks have `parent == nil`. Subtasks point to their parent task.

```
Project
├── Task (parent: nil)
├── Task (parent: nil)
└── Task (parent: nil)
    ├── SubTask (parent: task)
    └── SubTask (parent: task)
```

---

## Relationships

```
Project 1 ──< Task (root)
                └──< SubTask
Project 2 ──< Task (root)
```

- One project has many tasks (`project` back-reference on `Task`)
- One task optionally has many subtasks (`parent` self-reference on `Task`, cascade-delete)
- Deleting a project cascade-deletes its tasks
- Deleting a task cascade-deletes its subtasks

---

## Storage

Rich text fields (`titleRTF`, `descRTF`) are the single source of truth. There is no separate plain-text field — `plainTitle` and `plainDesc` are derived on demand. RTF (not RTFD) is used so the data round-trips cleanly through SwiftData without attachment blobs.

## Ordering

Tasks are ordered by `sortIndex` within their context (root tasks within a project, subtasks within their parent), set by drag-and-drop and by insert position. The shared `TaskListView.taskOrder` comparator sorts incomplete tasks by `sortIndex`, then sinks completed tasks to the bottom ordered by `completedAt` (newest first). `createdAt` is only a tiebreaker and the basis for a one-time `sortIndex` backfill of pre-existing data.

---

## Views

| View | Purpose |
|------|---------|
| `TaskListView` | Tasks for a single selected project; filter (All/Active/Done), search, inline editing, indent/unindent, and drag-to-reorder/nest |
| `TaskDragController` | `@Observable` engine holding all drag state + logic for reorder/nest/promote |
| `AllTasksView` | Tasks across all projects; filter, search, group-by (Project or Priority), and a "Completed" section at the bottom |
| `TaskDetailView` | Full detail for a single task — rich text title/description, subtask list, priority, reminder, completion |
| `ProjectListView` | Sidebar list of projects plus an "All Projects" entry at the top |
| `SettingsView` | Settings window (General + Backups tabs), opened via ⌘, |
| `BackupView` | Backup management sheet — view, create, restore |
| `ReminderPopover` / `ReminderToast` | Reminder date/time picker and the in-app banner shown when one fires |

## Non-model managers

| Type | Purpose |
|------|---------|
| `TaskStore` | All task mutations (add/delete/complete/indent/reorder) with undo registration |
| `ProjectStore` | Project mutations |
| `BackupManager` | Auto / manual / pre-restore backups; restore with rollback |
| `ReminderManager` | Schedules local notifications and handles their actions |
| `AppSettings` | Persisted user preferences (theme, accent, defaults), surfaced in Settings |
