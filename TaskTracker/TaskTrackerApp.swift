import SwiftUI
import SwiftData

@main
struct TaskTrackerApp: App {
    let container: ModelContainer
    let projectStore: ProjectStore
    let taskStore: TaskStore
    let backupManager: BackupManager
    let reminderManager: ReminderManager
    let settings = AppSettings()

    init() {
        let schema = Schema([Project.self, Task.self])
        let storeURL = URL.applicationSupportDirectory
            .appending(component: "TaskTracker.store")
        let config = ModelConfiguration(schema: schema, url: storeURL)

        do {
            container = try ModelContainer(for: schema, configurations: config)
        } catch {
            try? FileManager.default.removeItem(at: storeURL)
            do {
                container = try ModelContainer(for: schema, configurations: config)
            } catch {
                fatalError("Failed to create ModelContainer: \(error)")
            }
        }

        projectStore    = ProjectStore(context: container.mainContext)
        taskStore       = TaskStore(context: container.mainContext)
        backupManager   = BackupManager(storeURL: storeURL)
        backupManager.liveContainer = container
        reminderManager = ReminderManager()
        taskStore.backfillSortIndicesIfNeeded()
        backupManager.startAutoBackup()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(projectStore)
                .environment(taskStore)
                .environment(backupManager)
                .environment(reminderManager)
                .environment(settings)
                .tint(settings.accent.color)
                .frame(minWidth: 720, minHeight: 480)
                .onAppear {
                    setApplicationIcon()
                    settings.applyAppearance()
                    clearExpiredReminders()
                    applyDefaultFilter()
                }
                .onReceive(NotificationCenter.default.publisher(for: .markTaskDone)) { note in
                    guard let idStr = note.object as? String,
                          let uuid  = UUID(uuidString: idStr) else { return }
                    // Find the task by ID and mark it done through the store so it's undoable.
                    let descriptor = FetchDescriptor<Task>(
                        predicate: #Predicate { $0.id == uuid }
                    )
                    if let task = try? container.mainContext.fetch(descriptor).first {
                        taskStore.completeTask(task)
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: .reminderFired)) { note in
                    guard let idStr = note.object as? String,
                          let uuid  = UUID(uuidString: idStr) else { return }
                    // The reminder fired; clear its date so the UI stops showing it.
                    let descriptor = FetchDescriptor<Task>(
                        predicate: #Predicate { $0.id == uuid }
                    )
                    if let task = try? container.mainContext.fetch(descriptor).first {
                        task.reminderDate = nil
                    }
                }
        }
        .defaultSize(width: 960, height: 620)
        .modelContainer(container)
        .commands {
            CommandGroup(after: .appSettings) {
                Button("Backups…") {
                    NotificationCenter.default.post(name: .showBackups, object: nil)
                }
            }
        }

        Settings {
            SettingsView()
                .environment(settings)
                .tint(settings.accent.color)
        }
    }

    /// Ensure the About panel shows the real app icon. macOS loads the icon from
    /// the compiled asset catalog (AppIcon.icns) at launch; we only force it from
    /// that same .icns file. NSImage(named: "AppIcon") is NOT used here because on
    /// macOS that lookup can resolve to a generic template image, which would
    /// override the correct icon with a placeholder (the source of issue #10's
    /// recurrence). If the .icns can't be loaded we leave the system default in
    /// place rather than risk replacing it with something worse.
    private func setApplicationIcon() {
        guard let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
              let icon = NSImage(contentsOf: url) else { return }
        NSApplication.shared.applicationIconImage = icon
    }

    /// If the user picked a fixed startup filter (not "remember last used"), apply
    /// it once at launch by writing the shared taskFilter default that the task
    /// views read via @AppStorage.
    private func applyDefaultFilter() {
        if let f = settings.defaultFilter {
            UserDefaults.standard.set(f.rawValue, forKey: "taskFilter")
        }
    }

    /// Clears reminders whose time has already passed (e.g. fired or were missed while the app was closed)
    /// so the UI never shows a stale past reminder.
    private func clearExpiredReminders() {
        let now = Date()
        let descriptor = FetchDescriptor<Task>(
            predicate: #Predicate { $0.reminderDate != nil && $0.reminderDate! < now }
        )
        guard let expired = try? container.mainContext.fetch(descriptor) else { return }
        for task in expired {
            task.reminderDate = nil
            reminderManager.cancel(taskID: task.id)
        }
    }
}
