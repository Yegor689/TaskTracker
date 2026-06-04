import SwiftUI
import SwiftData

enum SidebarSelection: Hashable {
    case all
    case project(Project)
}

struct ContentView: View {
    @Query(sort: \Project.title) private var projects: [Project]
    @Environment(BackupManager.self) private var backupManager
    @State private var selection: SidebarSelection?
    @State private var showBackup = false

    var body: some View {
        NavigationSplitView {
            ProjectListView(selection: $selection)
                .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 300)
        } detail: {
            switch selection {
            case .all:
                AllTasksView(selection: $selection)
            case .project(let project):
                TaskListView(project: project, selection: $selection)
            case nil:
                ContentUnavailableView("Select a Project", systemImage: "folder")
            }
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button { showBackup = true } label: {
                    Label("Backups", systemImage: "externaldrive")
                }
                .help("Manage Backups")
            }
        }
        .toolbarBackground(.visible, for: .windowToolbar)
        .reminderToast()
        .sheet(isPresented: $showBackup) {
            BackupView()
                .environment(backupManager)
        }
        .onAppear {
            if selection == nil {
                selection = projects.first.map { .project($0) } ?? .all
            }
        }
    }
}
