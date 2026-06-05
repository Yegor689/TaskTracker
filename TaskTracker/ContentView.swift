import SwiftUI
import SwiftData

enum SidebarSelection: Hashable {
    case all
    case project(Project)
}

struct ContentView: View {
    @Query(sort: \Project.title) private var projects: [Project]
    @Environment(BackupManager.self) private var backupManager
    @Environment(AppSettings.self) private var settings
    @State private var selection: SidebarSelection?
    @State private var showBackup = false
    // Persisted sidebar selection: "all", or a project UUID string.
    @AppStorage("sidebarSelection") private var savedSelection = ""

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
                SettingsLink {
                    Label("Settings", systemImage: "gearshape")
                }
                .help("Settings (⌘,)")
            }
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
                if settings.restoreLastProject {
                    selection = restoredSelection() ?? projects.first.map { .project($0) } ?? .all
                } else {
                    selection = .all
                }
            }
        }
        .onChange(of: selection) { persistSelection() }
    }

    /// Resolves the persisted selection string back into a SidebarSelection,
    /// or nil if it can't be matched (e.g. the project was deleted).
    private func restoredSelection() -> SidebarSelection? {
        if savedSelection == "all" { return .all }
        guard let uuid = UUID(uuidString: savedSelection),
              let project = projects.first(where: { $0.id == uuid }) else { return nil }
        return .project(project)
    }

    private func persistSelection() {
        switch selection {
        case .all:                   savedSelection = "all"
        case .project(let project):  savedSelection = project.id.uuidString
        case nil:                    break
        }
    }
}
