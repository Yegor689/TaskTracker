import SwiftUI

struct BackupView: View {
    @Environment(BackupManager.self) private var backupManager
    @Environment(\.dismiss) private var dismiss
    @State private var labelText = ""
    @State private var backupToRestore: Backup?
    @State private var showRestoreConfirm = false
    @State private var showError = false
    @State private var errorMessage = ""

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            controls
            Divider()
            backupList
        }
        .frame(width: 500, height: 520)
        .confirmationDialog(
            "Restore this backup?",
            isPresented: $showRestoreConfirm,
            titleVisibility: .visible
        ) {
            Button("Restore and Relaunch", role: .destructive) {
                guard let backup = backupToRestore else { return }
                do {
                    try backupManager.restore(backup: backup)
                    relaunch()
                } catch {
                    errorMessage = error.localizedDescription
                    showError = true
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let b = backupToRestore {
                Text("This replaces ALL projects and tasks with the snapshot from \(Self.dateFormatter.string(from: b.date)) — it is not a per-project restore. Your current data is saved to a “Before Restore” backup first, so you can undo. The app will relaunch.")
            }
        }
        .alert("Restore Failed", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Backups")
                    .font(.title2.weight(.semibold))
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            Text("Each backup is a full snapshot of every project. Restoring replaces all current data with it — but a “Before Restore” copy is saved first, so you can undo.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
    }

    // MARK: Controls (interval + create)

    private var controls: some View {
        VStack(spacing: 14) {
            HStack {
                Label("Automatic backup", systemImage: "clock.arrow.circlepath")
                    .font(.callout)
                Spacer()
                Picker("Automatic backup", selection: intervalBinding) {
                    ForEach(BackupManager.intervalOptions, id: \.self) { hours in
                        Text(intervalLabel(hours)).tag(hours)
                    }
                }
                .labelsHidden()
                .fixedSize()
            }

            HStack(spacing: 10) {
                TextField("Label (optional)", text: $labelText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(createBackup)

                Button(action: createBackup) {
                    Label("Create Backup", systemImage: "plus.circle.fill")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
    }

    // MARK: List

    @ViewBuilder private var backupList: some View {
        if backupManager.backups.isEmpty {
            ContentUnavailableView("No Backups Yet", systemImage: "externaldrive",
                                   description: Text("Create one above, or wait for the next automatic backup."))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                section("Before Restore", backupManager.preRestoreBackups)
                section("Manual", backupManager.manualBackups)
                section("Automatic", backupManager.autoBackups)
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
        }
    }

    @ViewBuilder
    private func section(_ title: String, _ items: [Backup]) -> some View {
        if !items.isEmpty {
            Section(title) {
                ForEach(items) { backup in
                    BackupRow(backup: backup, formatter: Self.dateFormatter) {
                        backupToRestore = backup
                        showRestoreConfirm = true
                    } onDelete: {
                        backupManager.delete(backup: backup)
                    }
                }
            }
        }
    }

    // MARK: Actions / helpers

    private func createBackup() {
        let trimmed = labelText.trimmingCharacters(in: .whitespaces)
        backupManager.createBackup(label: trimmed)
        labelText = ""
    }

    private var intervalBinding: Binding<Int> {
        Binding(get: { backupManager.autoBackupIntervalHours },
                set: { backupManager.autoBackupIntervalHours = $0 })
    }

    private func intervalLabel(_ hours: Int) -> String {
        switch hours {
        case 0:  return "Off"
        case 1:  return "Every hour"
        case 24: return "Daily"
        default: return "Every \(hours) hours"
        }
    }

    private func relaunch() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-n", Bundle.main.bundlePath]
        try? process.run()
        NSApp.terminate(nil)
    }
}

private struct BackupRow: View {
    let backup: Backup
    let formatter: DateFormatter
    let onRestore: () -> Void
    let onDelete: () -> Void

    @State private var isHovered = false

    private static let relative: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f
    }()

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(iconColor)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.body)
                    .lineLimit(1)
                Text(formatter.string(from: backup.date))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Relative age, fading out when the row is hovered to make room.
            Text(Self.relative.localizedString(for: backup.date, relativeTo: Date()))
                .font(.caption)
                .foregroundStyle(.tertiary)
                .opacity(isHovered ? 0 : 1)

            if isHovered {
                Button("Restore", action: onRestore)
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.red)
                .help("Delete this backup")
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.12), value: isHovered)
    }

    /// A label if the backup has one, otherwise a human description of its kind.
    private var title: String {
        let withoutKind = backup.name
            .replacingOccurrences(of: "^(auto|manual|prerestore)-", with: "", options: .regularExpression)
        // withoutKind is "yyyy-MM-dd HH-mm-ss optional label"
        let parts = withoutKind.split(separator: " ", maxSplits: 2)
        if parts.count > 2 { return String(parts[2]) }
        switch backup.kind {
        case .manual:     return "Manual backup"
        case .auto:       return "Automatic backup"
        case .preRestore: return "Before restore"
        }
    }

    private var icon: String {
        switch backup.kind {
        case .manual:     return "bookmark.fill"
        case .auto:       return "clock.arrow.circlepath"
        case .preRestore: return "arrow.uturn.backward.circle.fill"
        }
    }

    private var iconColor: Color {
        switch backup.kind {
        case .manual:     return .accentColor
        case .auto:       return .secondary
        case .preRestore: return .orange
        }
    }
}
