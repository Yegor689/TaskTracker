import SwiftUI

struct BackupView: View {
    @Environment(BackupManager.self) private var backupManager
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
            Text("Backups")
                .font(.title2)
                .fontWeight(.semibold)
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 4)

            Text("Auto-backups run once per day (last 10 kept). Restoring requires a relaunch.")
                .font(.caption)
                .foregroundStyle(.secondary)
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
        .frame(width: 480, height: 420)
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
                Text("This will replace all current data with the backup from \(Self.dateFormatter.string(from: b.date)). The app will relaunch.")
            }
        }
        .alert("Restore Failed", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
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
            .replacingOccurrences(of: "^(auto|manual)-", with: "", options: .regularExpression)
        // withoutKind is now "yyyy-MM-dd HH-mm-ss optional label"
        let parts = withoutKind.split(separator: " ", maxSplits: 2)
        if parts.count > 2 {
            return String(parts[2])
        }
        return formatter.string(from: backup.date)
    }
}
