import SwiftUI

struct ReminderPopover: View {
    @Bindable var task: Task
    var reminderManager: ReminderManager

    @State private var pickedDate: Date = defaultDate()
    @Environment(\.dismiss) private var dismiss

    private static func defaultDate() -> Date {
        Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Set Reminder")
                .font(.headline)

            DatePicker("", selection: $pickedDate, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                .labelsHidden()
                .datePickerStyle(.stepperField)

            HStack(spacing: 8) {
                if task.reminderDate != nil {
                    Button("Remove") {
                        task.reminderDate = nil
                        reminderManager.cancel(taskID: task.id)
                        dismiss()
                    }
                    .foregroundStyle(.red)
                }
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") {
                    task.reminderDate = pickedDate
                    reminderManager.schedule(task: task)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
        .frame(width: 280)
        .onAppear {
            pickedDate = task.reminderDate ?? Self.defaultDate()
            _Concurrency.Task { await reminderManager.requestPermissionIfNeeded() }
        }
    }
}
