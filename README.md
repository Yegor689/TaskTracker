# Quillpoint

A native macOS task manager built with SwiftUI and SwiftData.

![Platform](https://img.shields.io/badge/platform-macOS-lightgrey)
![Swift](https://img.shields.io/badge/swift-6.0-orange)
![License](https://img.shields.io/badge/license-MIT-blue)

Organize work into projects and tasks, with rich-text notes, subtasks,
priorities, reminders, and drag-and-drop ordering — all backed by automatic,
restorable backups.

## Features

- **Projects & tasks** — group tasks into projects, with one level of subtasks and rich-text titles and descriptions (bold, italic, links).
- **Priorities** — Critical, Normal, and Low, each color-coded; completed tasks sink to the bottom.
- **Drag and drop** — reorder tasks by dragging, drop one onto another to nest it, or drag a subtask out to promote it.
- **Reminders** — attach a date/time to any task and get a macOS notification with a "Mark Done" action.
- **Two views** — a focused per-project list, or an All Projects view grouped by project or priority.
- **Keyboard-first** — arrow keys, Enter, and Tab/Shift+Tab to navigate, create, and nest without the mouse.
- **Settings** — theme, accent color, and default behaviors (⌘,).
- **Safe by default** — full undo/redo, automatic backups, and one-click restore that snapshots your current data first.

## Requirements

- macOS 15 or later
- Xcode 16 or later

## Getting Started

```bash
git clone https://github.com/Yegor689/Quillpoint.git
```

Open `TaskTracker.xcodeproj` in Xcode and run (⌘R). No dependencies — pure
SwiftUI and SwiftData.

## Architecture

The app is a SwiftUI `NavigationSplitView` over a SwiftData store. UI lives in
`Views/`, with `@Observable` stores (`TaskStore`, `ProjectStore`,
`BackupManager`, `ReminderManager`, `AppSettings`) handling mutations and
side effects. See [docs/MODEL.md](docs/MODEL.md) for the data model and a
view/manager breakdown.

## License

MIT
