import SwiftUI
import SwiftData

struct TaskDetailView: View {
    @Environment(TaskStore.self) private var taskStore
    @Bindable var task: Task

    private var doneCount: Int  { task.subtasks.filter(\.isDone).count }
    private var totalCount: Int { task.subtasks.count }
    private var allDone: Bool   { task.isDone && task.subtasks.allSatisfy(\.isDone) }
    private var sortedSubtasks: [Task] { task.subtasks.sorted { $0.createdAt < $1.createdAt } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {

                // MARK: Title + description
                VStack(alignment: .leading, spacing: 0) {
                    RichDescriptionEditor(rtf: $task.titleRTF, font: .preferredFont(forTextStyle: .title1))
                        .frame(minHeight: 38, maxHeight: 84)

                    Divider().padding(.vertical, 12)

                    ZStack(alignment: .topLeading) {
                        if task.plainDesc.isEmpty {
                            Text("Add a description…")
                                .foregroundStyle(.tertiary)
                                .font(.body)
                                .padding(.leading, 2)
                                .allowsHitTesting(false)
                        }
                        RichDescriptionEditor(rtf: $task.descRTF)
                            .frame(minHeight: 60, maxHeight: 200)
                    }
                }
                .padding(20)
                .background(cardBackground)

                // MARK: Status chips
                HStack(spacing: 12) {
                    Button {
                        withAnimation(.spring(duration: 0.25)) { task.isDone.toggle() }
                    } label: {
                        chip(
                            icon: task.isDone ? "checkmark.circle.fill" : "circle",
                            text: task.isDone ? "Completed" : "Pending",
                            tint: task.isDone ? .green : .secondary,
                            filled: task.isDone
                        )
                    }
                    .buttonStyle(.plain)

                    Button {
                        withAnimation(.spring(duration: 0.2)) {
                            task.priority = task.priority == 0 ? 1 : 0
                        }
                    } label: {
                        chip(
                            icon: task.priority == 0 ? "exclamationmark.circle.fill" : "flag",
                            text: task.priority == 0 ? "Critical" : "Normal",
                            tint: task.priority == 0 ? .red : .secondary,
                            filled: task.priority == 0
                        )
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    Label(task.createdAt.formatted(date: .abbreviated, time: .omitted),
                          systemImage: "calendar")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                if let parent = task.parent {
                    NavigationLink(value: parent) {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.turn.left.up")
                                .foregroundStyle(.secondary)
                            Text("Part of")
                                .foregroundStyle(.secondary)
                            Text(parent.plainTitle)
                                .fontWeight(.medium)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        .font(.callout)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(cardBackground)
                    }
                    .buttonStyle(.plain)
                }

                // MARK: Subtasks
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Subtasks")
                            .font(.headline)
                        Spacer()
                        if totalCount > 0 {
                            Text("\(doneCount) of \(totalCount)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }

                    if totalCount > 0 {
                        ProgressView(value: Double(doneCount), total: Double(totalCount))
                            .progressViewStyle(.linear)
                            .tint(doneCount == totalCount ? .green : .accentColor)
                            .animation(.easeInOut, value: doneCount)
                            .padding(.top, 10)
                            .padding(.bottom, 4)

                        VStack(spacing: 0) {
                            ForEach(sortedSubtasks) { subtask in
                                subtaskRow(subtask)
                                if subtask.id != sortedSubtasks.last?.id {
                                    Divider()
                                }
                            }
                        }
                        .padding(.top, 8)
                    } else {
                        Text("No subtasks yet.")
                            .font(.callout)
                            .foregroundStyle(.tertiary)
                            .padding(.top, 10)
                    }

                    Divider().padding(.vertical, 10)

                    Button {
                        taskStore.addSubtask(to: task)
                    } label: {
                        Label("Add Subtask", systemImage: "plus.circle.fill")
                            .foregroundStyle(Color.accentColor)
                            .font(.callout.weight(.medium))
                    }
                    .buttonStyle(.plain)
                }
                .padding(20)
                .background(cardBackground)
            }
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationTitle(task.plainTitle.isEmpty ? "Untitled" : task.plainTitle)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Complete All") {
                    withAnimation(.spring(duration: 0.3)) { taskStore.completeTask(task) }
                }
                .disabled(allDone)
            }
        }
    }

    // MARK: - Components

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(Color(nsColor: .controlBackgroundColor))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.primary.opacity(0.06))
            )
    }

    private func chip(icon: String, text: String, tint: Color, filled: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .contentTransition(.symbolEffect(.replace))
            Text(text)
        }
        .font(.callout.weight(.medium))
        .foregroundStyle(filled ? tint : .secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(
            Capsule().fill(filled ? tint.opacity(0.14) : Color.primary.opacity(0.05))
        )
        .overlay(
            Capsule().strokeBorder(filled ? tint.opacity(0.25) : Color.primary.opacity(0.08))
        )
    }

    private func subtaskRow(_ subtask: Task) -> some View {
        NavigationLink(value: subtask) {
            HStack(spacing: 12) {
                Button {
                    withAnimation(.spring(duration: 0.25)) { subtask.isDone.toggle() }
                } label: {
                    Image(systemName: subtask.isDone ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(subtask.isDone ? .green : .secondary)
                        .contentTransition(.symbolEffect(.replace))
                        .font(.system(size: 16))
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 2) {
                    Text(subtask.plainTitle.isEmpty ? "Untitled" : subtask.plainTitle)
                        .strikethrough(subtask.isDone)
                        .foregroundStyle(subtask.isDone ? .secondary : .primary)
                    if !subtask.plainDesc.isEmpty {
                        Text(subtask.plainDesc)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
