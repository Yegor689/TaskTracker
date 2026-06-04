import SwiftUI

/// A transient in-app banner shown when a reminder fires while the app is open.
/// Listens for `.reminderFired` and auto-dismisses after a few seconds.
struct ReminderToast: ViewModifier {
    @State private var title: String?
    @State private var dismissTask: _Concurrency.Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if let title {
                    toast(title)
                        .padding(.top, 12)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .zIndex(1)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .reminderFired)) { note in
                let text = note.userInfo?["title"] as? String ?? "Task Reminder"
                show(text)
            }
    }

    private func toast(_ text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "bell.fill")
                .foregroundStyle(.white)
                .font(.system(size: 14, weight: .semibold))

            VStack(alignment: .leading, spacing: 1) {
                Text("Reminder")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.8))
                    .textCase(.uppercase)
                Text(text)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white.opacity(0.7))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: 360)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.accentColor)
                .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
        )
        .onTapGesture { dismiss() }
    }

    private func show(_ text: String) {
        dismissTask?.cancel()
        withAnimation(.spring(duration: 0.35)) { title = text }
        dismissTask = _Concurrency.Task {
            try? await _Concurrency.Task.sleep(for: .seconds(5))
            guard !_Concurrency.Task.isCancelled else { return }
            dismiss()
        }
    }

    private func dismiss() {
        dismissTask?.cancel()
        withAnimation(.spring(duration: 0.3)) { title = nil }
    }
}

extension View {
    /// Shows an in-app banner when a task reminder fires.
    func reminderToast() -> some View {
        modifier(ReminderToast())
    }
}
