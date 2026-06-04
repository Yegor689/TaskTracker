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
- Priority levels: Normal and Critical (with a red accent in the list)
- Mark tasks and subtasks complete individually or all at once

**Navigation**
- Full keyboard navigation — arrow keys move between tasks and subtasks
- Press Enter to create a new task, Tab to indent, Shift+Tab to unindent
- Double-tap any task to open its detail view
- Project switcher in the toolbar — switch projects without opening the sidebar

**Views**
- Per-project task list with Active / All / Done filter
- All Projects view grouped by project or priority
- Task detail panel with status chips, description, and subtask progress
- Pinned stats footer showing completion count and progress bar

**Data**
- Full undo/redo (Cmd+Z / Cmd+Shift+Z) for all mutations
- Automatic daily backups, keep last 10
- Manual backups with optional labels
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
│   ├── Task.swift          # SwiftData model, self-referential for subtasks
│   └── Project.swift       # SwiftData model
├── Views/
│   ├── TaskListView.swift   # Per-project task list + row component
│   ├── AllTasksView.swift   # Cross-project view with group-by
│   ├── TaskDetailView.swift # Task properties panel
│   ├── ProjectListView.swift# Sidebar project list
│   ├── ProjectTitleMenu.swift # Toolbar project switcher
│   ├── BackupView.swift     # Backup management sheet
│   └── RichTextView.swift   # NSTextView wrappers for rich text editing
├── TaskStore.swift          # Mutations + undo registration
├── ProjectStore.swift       # Project mutations
├── BackupManager.swift      # Auto/manual backup logic
├── ContentView.swift        # Root NavigationSplitView
└── TaskTrackerApp.swift     # App entry point + SwiftData container
```

## License

MIT
