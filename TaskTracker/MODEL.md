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
| `priority` | `Int` | `0` = critical, `1` = normal |
| `createdAt` | `Date` | Timestamp set on creation; used for ordering |
| `project` | `Project?` | Owning project (SwiftData relationship) |
| `parent` | `Task?` | `nil` for root tasks; set to parent task for subtasks |
| `subtasks` | `[Task]` | Child tasks (cascade-delete on parent delete) |

### Computed properties

| Property | Type | Notes |
|----------|------|-------|
| `plainTitle` | `String` | Plain text extracted from `titleRTF` |
| `plainDesc` | `String` | Plain text extracted from `descRTF` |

### Static helpers

| Helper | Notes |
|--------|-------|
| `Task.rtf(from:font:)` | Converts a plain `String` to RTF `Data` with default label color |
| `Task.plain(from:)` | Extracts plain text from RTF `Data` |

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

---

## Views

| View | Purpose |
|------|---------|
| `TaskListView` | Tasks for a single selected project; supports filter (All/Active/Done), search, inline editing, indent/unindent |
| `AllTasksView` | Tasks across all projects; supports filter, search, and group-by (Project or Priority) |
| `TaskDetailView` | Full detail for a single task — rich text title/description, subtask list, priority, completion |
| `ProjectListView` | Sidebar list of projects plus an "All Projects" entry at the top |
