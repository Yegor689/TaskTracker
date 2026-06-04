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
            HStack {
                Text("Backups")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 4)

            Text("A backup is a full snapshot of all projects. Restoring replaces all current data with that snapshot, but saves a “Before Restore” copy first so you can undo. Automatic backups keep the last 10 snapshots.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)
                .padding(.bottom, 12)

            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    Text("Automatic backup")
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

                Toggle(isOn: backupOnLaunchBinding) {
                    Text("Back up when opening the app")
                        .font(.callout)
                }
                .toggleStyle(.switch)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)

            Divider()

            HStack(spacing: 10) {
                TextField("Label (optional)", text: $labelText)
                    .textFieldStyle(.roundedBorder)

                Button {
                    backupManager.createBackup(label: labelText)
                    labelText = ""
                } label: {
                    Label("Create Backup", systemImage: "plus.circle")
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            Divider()

            if backupManager.backups.isEmpty {
                ContentUnavailableView("No Backups", systemImage: "externaldrive")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    if !backupManager.preRestoreBackups.isEmpty {
                        Section("Before Restore") {
                            ForEach(backupManager.preRestoreBackups) { backup in
                                BackupRow(backup: backup, formatter: Self.dateFormatter) {
                                    backupToRestore = backup
                                    showRestoreConfirm = true
                                } onDelete: {
                                    backupManager.delete(backup: backup)
                                }
                            }
                        }
                    }

                    if !backupManager.manualBackups.isEmpty {
                        Section("Manual") {
                            ForEach(backupManager.manualBackups) { backup in
                                BackupRow(backup: backup, formatter: Self.dateFormatter) {
                                    backupToRestore = backup
                                    showRestoreConfirm = true
                                } onDelete: {
                                    backupManager.delete(backup: backup)
                                }
                            }
                        }
                    }

                    if !backupManager.autoBackups.isEmpty {
                        Section("Automatic") {
                            ForEach(backupManager.autoBackups) { backup in
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
                .listStyle(.inset)
            }
        }
        .frame(width: 480, height: 460)
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

    private var intervalBinding: Binding<Int> {
        Binding(
            get: { backupManager.autoBackupIntervalHours },
            set: { backupManager.autoBackupIntervalHours = $0 }
        )
    }

    private var backupOnLaunchBinding: Binding<Bool> {
        Binding(
            get: { backupManager.backupOnLaunch },
            set: { backupManager.backupOnLaunch = $0 }
        )
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

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(displayName)
                    .font(.body)
                Text(formatter.string(from: backup.date))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Restore", action: onRestore)
                .buttonStyle(.bordered)
                .controlSize(.small)

            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.red.opacity(0.8))
        }
        .padding(.vertical, 2)
    }

    private var displayName: String {
        // Strip "manual-" / "auto-" prefix and timestamp, show just the label if present
        let withoutKind = backup.name
            .replacingOccurrences(of: "^(auto|manual|prerestore)-", with: "", options: .regularExpression)
        // withoutKind is now "yyyy-MM-dd HH-mm-ss optional label"
        let parts = withoutKind.split(separator: " ", maxSplits: 2)
        if parts.count > 2 {
            return String(parts[2])
        }
        return formatter.string(from: backup.date)
    }
}
