import SwiftUI
import SwiftData

struct ProjectListView: View {
    @Environment(ProjectStore.self) private var projectStore
    @Query(sort: \Project.title) private var projects: [Project]

    @Binding var selection: SidebarSelection?
    @State private var isAddingProject = false
    @State private var newProjectTitle = ""
    @State private var projectToRename: Project?
    @State private var renameTitle = ""
    @State private var projectToDelete: Project?

    var body: some View {
        // A native List (not a custom ScrollView) so the sidebar reserves space
        // under the translucent title bar and content can't scroll up behind it.
        // Selection is driven entirely by the rows' own highlight + tap gestures;
        // the List itself has no `selection:` binding, so no native highlight is
        // drawn (that native highlight was the earlier "bleed" bug).
        List {
            AllProjectsRow(isSelected: selection == .all)
                .onTapGesture { selection = .all }
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 1, leading: 6, bottom: 1, trailing: 6))
                .listRowBackground(Color.clear)

            Section {
                ForEach(projects) { project in
                    ProjectRowView(project: project, isSelected: selection == .project(project))
                        .onTapGesture { selection = .project(project) }
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 1, leading: 6, bottom: 1, trailing: 6))
                        .listRowBackground(Color.clear)
                        .contextMenu {
                            Button("Rename") {
                                renameTitle = project.title
                                projectToRename = project
                            }
                            Divider()
                            Button("Delete", role: .destructive) {
                                projectToDelete = project
                            }
                        }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Projects")
        .overlay {
            if projects.isEmpty {
                ContentUnavailableView {
                    Label("No Projects", systemImage: "folder.badge.plus")
                } description: {
                    Text("Create a project to start tracking tasks.")
                } actions: {
                    Button("New Project") { isAddingProject = true }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .toolbar {
            ToolbarItem {
                Button { isAddingProject = true } label: {
                    Label("Add Project", systemImage: "plus")
                }
                .help("New Project (⌘N)")
                .keyboardShortcut("n", modifiers: .command)
            }
        }
        .confirmationDialog(
            "Delete \"\(projectToDelete?.title ?? "")\"?",
            isPresented: Binding(
                get: { projectToDelete != nil },
                set: { if !$0 { projectToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Project", role: .destructive) {
                guard let project = projectToDelete else { return }
                if selection == .project(project) { selection = .all }
                projectStore.deleteProject(project)
                projectToDelete = nil
            }
            Button("Cancel", role: .cancel) { projectToDelete = nil }
        } message: {
            Text("All tasks in this project will also be deleted. This cannot be undone.")
        }
        .sheet(isPresented: $isAddingProject) {
            ProjectFormSheet(heading: "New Project", value: $newProjectTitle) {
                projectStore.createProject(title: newProjectTitle)
                newProjectTitle = ""
            }
        }
        .sheet(item: $projectToRename) { project in
            ProjectFormSheet(heading: "Rename Project", value: $renameTitle) {
                projectStore.updateProject(project, title: renameTitle)
            }
        }
    }
}

private struct AllProjectsRow: View {
    var isSelected: Bool
    @State private var isHovered = false

    var body: some View {
        Label("All Projects", systemImage: "tray.2")
            .fontWeight(.medium)
            .foregroundStyle(isSelected ? .white : .primary)
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(isSelected ? Color.accentColor : (isHovered ? Color.primary.opacity(0.07) : Color.clear))
            )
            .contentShape(Rectangle())
            .onHover { isHovered = $0 }
    }
}

private struct ProjectRowView: View {
    var project: Project
    var isSelected: Bool
    @State private var isHovered = false

    private var rootTasks: [Task] { project.tasks.filter { $0.parent == nil } }
    private var total: Int  { rootTasks.count }
    private var done: Int   { rootTasks.filter(\.isDone).count }
    private var pending: Int { total - done }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(project.title)
                    .fontWeight(.medium)
                    .foregroundStyle(isSelected ? .white : .primary)
                Spacer()
                if pending > 0 {
                    Text("\(pending)")
                        .font(.caption2.monospacedDigit())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(isSelected ? Color.white.opacity(0.25) : Color.secondary.opacity(0.15))
                        .clipShape(Capsule())
                        .foregroundStyle(isSelected ? .white : .secondary)
                }
            }
            if !project.desc.isEmpty {
                Text(project.desc)
                    .font(.caption)
                    .foregroundStyle(isSelected ? Color.white.opacity(0.75) : .secondary)
                    .lineLimit(1)
            }
            if total > 0 {
                ProgressView(value: Double(done), total: Double(total))
                    .progressViewStyle(.linear)
                    .tint(done == total ? .green : (isSelected ? Color.white.opacity(0.9) : .accentColor))
                    .animation(.easeInOut, value: done)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(isSelected ? Color.accentColor : (isHovered ? Color.primary.opacity(0.07) : Color.clear))
        )
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
    }
}

private struct ProjectFormSheet: View {
    let heading: String
    @Binding var value: String
    let onConfirm: () -> Void
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 16) {
            Text(heading).font(.headline)
            TextField("Title", text: $value)
                .textFieldStyle(.roundedBorder)
                .onSubmit(submit)
                .focused($isFocused)
            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Save", action: submit)
                    .buttonStyle(.borderedProminent)
                    .disabled(value.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding()
        .frame(width: 300)
        .onAppear { isFocused = true }
    }

    private func submit() {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        value = trimmed
        onConfirm()
        dismiss()
    }
}
