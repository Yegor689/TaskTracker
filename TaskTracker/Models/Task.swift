import Foundation
import SwiftData
import AppKit
import SwiftUI

/// Task priority. Stored as the raw `Int` on `Task.priority` so existing data
/// (0 = critical, 1 = normal) stays valid; 2 = low is the new level.
/// The rawValue doubles as the sort order (lower = more urgent, sorts first).
enum Priority: Int, CaseIterable, Identifiable {
    case critical = 0
    case normal   = 1
    case low      = 2

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .critical: return "Critical"
        case .normal:   return "Normal"
        case .low:      return "Low"
        }
    }

    var color: Color {
        switch self {
        case .critical: return .red
        case .normal:   return .secondary
        case .low:      return .blue
        }
    }

    /// SF Symbol shown on the inline priority button / detail chip.
    var iconName: String {
        switch self {
        case .critical: return "exclamationmark.circle.fill"
        case .normal:   return "flag"
        case .low:      return "arrow.down.circle"
        }
    }

    /// Whether this level warrants a visual accent (color, bold, leading bar).
    var isAccented: Bool { self != .normal }

    /// The next level when cycling via the inline button: Critical → Normal → Low → Critical.
    var next: Priority {
        Priority(rawValue: (rawValue + 1) % Priority.allCases.count) ?? .normal
    }
}

@Model
class Task {
    var id: UUID
    var titleRTF: Data
    var descRTF: Data
    var isDone: Bool
    var priority: Int  // raw value of Priority: 0 = critical, 1 = normal, 2 = low
    var createdAt: Date
    var reminderDate: Date?
    var project: Project?
    @Relationship(inverse: \Task.subtasks) var parent: Task?
    @Relationship(deleteRule: .cascade) var subtasks: [Task]

    init(plainTitle: String = "", plainDesc: String = "", priority: Int = 1, project: Project? = nil, parent: Task? = nil) {
        self.id = UUID()
        self.titleRTF = Task.rtf(from: plainTitle)
        self.descRTF = Task.rtf(from: plainDesc)
        self.isDone = false
        self.priority = priority
        self.createdAt = Date()
        self.project = project
        self.parent = parent
        self.subtasks = []
    }

    /// Typed view over the stored `priority` Int. Falls back to `.normal` for any
    /// unexpected stored value so the UI never breaks on bad data.
    var priorityLevel: Priority {
        get { Priority(rawValue: priority) ?? .normal }
        set { priority = newValue.rawValue }
    }

    var plainTitle: String { Task.plain(from: titleRTF) }
    var plainDesc: String  { Task.plain(from: descRTF) }

    static func rtf(from plain: String, font: NSFont = .preferredFont(forTextStyle: .body)) -> Data {
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.labelColor]
        let attrStr = NSAttributedString(string: plain, attributes: attrs)
        return (try? attrStr.data(from: NSRange(location: 0, length: attrStr.length),
                                  documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])) ?? Data()
    }

    static func plain(from rtf: Data) -> String {
        guard !rtf.isEmpty,
              let attrStr = try? NSAttributedString(data: rtf,
                                                    options: [.documentType: NSAttributedString.DocumentType.rtf],
                                                    documentAttributes: nil)
        else { return "" }
        return attrStr.string
    }
}
