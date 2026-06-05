# TaskTracker

A native macOS task manager built with SwiftUI and SwiftData.

![Platform](https://img.shields.io/badge/platform-macOS-lightgrey)
![Swift](https://img.shields.io/badge/swift-6.0-orange)
![License](https://img.shields.io/badge/license-MIT-blue)

## Features

**Tasks & Projects**
- Organize tasks into projects with progress tracking
- Subtasks with one level of nesting
- Rich text titles and descriptions — bold, italic, links (Cmd+B / Cmd+I)
- Three priority levels: Critical, Normal, and Low, each with its own color accent
- Mark tasks and subtasks complete individually or all at once
- Completed tasks sink to the bottom of the list, newest completion on top

**Reminders**
- Attach an optional date/time reminder to any task
- Fires a macOS notification with a "Mark Done" action, plus an in-app toast
- Reminders auto-clear when they fire, when the task is completed, or when expired

**Reordering & nesting (drag and drop)**
- Drag a task by its bullet to reorder; rows reflow live under the cursor
- Drag a task right onto another to nest it as a subtask
- Drag a subtask to reorder among siblings, or left to promote it back to a task

**Navigation**
- Full keyboard navigation — arrow keys move between tasks and subtasks
- Enter creates a new task (at the start of a title, it inserts one before); Tab to indent, Shift+Tab to unindent
- Double-tap any task to open its detail view
- Project switcher in the toolbar — switch projects without opening the sidebar

**Views**
- Per-project task list with Active / All / Done filter
- All Projects view grouped by project or priority (with a project badge per row when grouped by priority)
- Task detail panel with status chips, description, and subtask progress
- Pinned stats footer showing completion count and progress bar

**Settings** (⌘,)
- Appearance: System / Light / Dark theme and accent color
- Default new-task priority and a confirm-before-delete toggle
- On launch: reopen the last-used project and/or default filter
- Backup frequency and back-up-on-launch options

**Data**
- Full undo/redo (Cmd+Z / Cmd+Shift+Z) for all mutations, including reorders
- Automatic backups on a configurable interval (and/or on launch), keeping the last 10
- Manual backups with optional labels
- A "Before Restore" snapshot is taken automatically so any restore can be undone
- One-click restore with safe rollback on failure

## Requirements

- macOS 15 or later
- Xcode 16 or later

## Getting Started

1. Clone the repo:
   ```bash
   git clone https://github.com/Yegor689/TaskTracker.git
   ```
2. Open `TaskTracker.xcodeproj` in Xcode
3. Select the **TaskTracker** scheme and press **Run** (Cmd+R)

No dependencies — pure SwiftUI and SwiftData, no package manager required.

## Project Structure

```
TaskTracker/
├── Models/
│   ├── Task.swift             # SwiftData model, self-referential for subtasks
│   └── Project.swift          # SwiftData model
├── Views/
│   ├── TaskListView.swift     # Per-project task list + row component
│   ├── TaskDragController.swift # Drag-to-reorder/nest engine
│   ├── AllTasksView.swift     # Cross-project view with group-by
│   ├── TaskDetailView.swift   # Task properties panel
│   ├── ProjectListView.swift  # Sidebar project list
│   ├── ProjectTitleMenu.swift # Toolbar project switcher
│   ├── BackupView.swift       # Backup management sheet
│   ├── SettingsView.swift     # Settings window (General + Backups tabs)
│   ├── ReminderPopover.swift  # Date/time reminder picker
│   ├── ReminderToast.swift    # In-app reminder banner
│   └── RichTextView.swift     # NSTextView wrappers for rich text editing
├── TaskStore.swift            # Task mutations, ordering + undo registration
├── ProjectStore.swift         # Project mutations
├── BackupManager.swift        # Auto/manual/pre-restore backup logic
├── ReminderManager.swift      # Local notification scheduling
├── AppSettings.swift          # Persisted user preferences
├── ContentView.swift          # Root NavigationSplitView
└── TaskTrackerApp.swift       # App entry point + SwiftData container + Settings scene
```

## License

MIT
