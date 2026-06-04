import SwiftUI
import SwiftData

@main
struct TaskTrackerApp: App {
    let container: ModelContainer
    let projectStore: ProjectStore
    let taskStore: TaskStore
    let backupManager: BackupManager

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

        projectStore  = ProjectStore(context: container.mainContext)
        taskStore     = TaskStore(context: container.mainContext)
        backupManager = BackupManager(storeURL: storeURL)
        backupManager.createAutoBackupIfNeeded()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(projectStore)
                .environment(taskStore)
                .environment(backupManager)
                .frame(minWidth: 720, minHeight: 480)
        }
        .defaultSize(width: 960, height: 620)
        .modelContainer(container)
    }
}
