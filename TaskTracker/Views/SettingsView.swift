import SwiftUI

struct SettingsView: View {
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
        .frame(width: 460, height: 360)
    }
}
