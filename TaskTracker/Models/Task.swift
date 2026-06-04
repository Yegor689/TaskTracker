import Foundation
import SwiftData
import AppKit

@Model
class Task {
    var id: UUID
    var titleRTF: Data
    var descRTF: Data
    var isDone: Bool
    var priority: Int  // 0 = critical, 1 = normal
    var createdAt: Date
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
