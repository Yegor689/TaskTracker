import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gearshape") }
            BackupSettingsView()
                .tabItem { Label("Backups", systemImage: "externaldrive") }
        }
        .frame(width: 460)
    }
}

// MARK: - General

private struct GeneralSettingsView: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section("Appearance") {
                Picker("Theme", selection: $settings.theme) {
                    ForEach(AppSettings.Theme.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)

                Picker("Accent color", selection: $settings.accent) {
                    ForEach(AppSettings.Accent.allCases) { accent in
                        HStack {
                            Circle().fill(accent.color).frame(width: 12, height: 12)
                            Text(accent.label)
                        }
                        .tag(accent)
                    }
                }
            }

            Section("Tasks") {
                Picker("New tasks default to", selection: $settings.defaultPriority) {
                    ForEach(Priority.allCases) { Text($0.label).tag($0.rawValue) }
                }

                Toggle("Confirm before deleting tasks with subtasks", isOn: $settings.confirmBeforeDelete)
            }

            Section("On launch") {
                Toggle("Reopen the last-used project", isOn: $settings.restoreLastProject)

                Picker("Show filter", selection: $settings.defaultFilterRaw) {
                    Text("Remember last used").tag("")
                    ForEach(TaskFilter.allCases, id: \.self) { Text($0.rawValue).tag($0.rawValue) }
                }
            }
        }
        .formStyle(.grouped)
        .frame(height: 360)
    }
}

// MARK: - Backups (preferences only; the backup list/restore lives in BackupView)

private struct BackupSettingsView: View {
    @Environment(BackupManager.self) private var backupManager

    var body: some View {
        Form {
            Section("Automatic backups") {
                Picker("Frequency", selection: intervalBinding) {
                    ForEach(BackupManager.intervalOptions, id: \.self) { hours in
                        Text(intervalLabel(hours)).tag(hours)
                    }
                }
                Toggle("Back up when opening the app", isOn: backupOnLaunchBinding)
            }

            Section {
                Text("Automatic backups keep the last 10 snapshots. Open the Backups window from the toolbar to view, restore, or create backups.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(height: 360)
    }

    private var intervalBinding: Binding<Int> {
        Binding(get: { backupManager.autoBackupIntervalHours },
                set: { backupManager.autoBackupIntervalHours = $0 })
    }
    private var backupOnLaunchBinding: Binding<Bool> {
        Binding(get: { backupManager.backupOnLaunch },
                set: { backupManager.backupOnLaunch = $0 })
    }
    private func intervalLabel(_ hours: Int) -> String {
        switch hours {
        case 0:  return "Off"
        case 1:  return "Every hour"
        case 24: return "Daily"
        default: return "Every \(hours) hours"
        }
    }
}
