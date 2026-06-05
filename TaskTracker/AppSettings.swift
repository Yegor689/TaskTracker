import SwiftUI

/// User-facing app preferences, persisted in UserDefaults and surfaced in the
/// Settings window. Injected into the environment so views can read defaults.
@Observable
final class AppSettings {

    // MARK: Appearance

    enum Theme: String, CaseIterable, Identifiable {
        case system, light, dark
        var id: String { rawValue }
        var label: String {
            switch self {
            case .system: return "System"
            case .light:  return "Light"
            case .dark:   return "Dark"
            }
        }
        /// AppKit appearance to apply app-wide. nil = follow the system.
        var nsAppearance: NSAppearance? {
            switch self {
            case .system: return nil
            case .light:  return NSAppearance(named: .aqua)
            case .dark:   return NSAppearance(named: .darkAqua)
            }
        }
    }

    enum Accent: String, CaseIterable, Identifiable {
        case blue, purple, pink, red, orange, green, teal, graphite
        var id: String { rawValue }
        var label: String { rawValue.capitalized }
        var color: Color {
            switch self {
            case .blue:     return .blue
            case .purple:   return .purple
            case .pink:     return .pink
            case .red:      return .red
            case .orange:   return .orange
            case .green:    return .green
            case .teal:     return .teal
            case .graphite: return .gray
            }
        }
    }

    var theme: Theme {
        didSet {
            defaults.set(theme.rawValue, forKey: Keys.theme)
            applyAppearance()
        }
    }

    /// Sets the app-wide AppKit appearance so every window (main + Settings)
    /// updates immediately, including switching back to System (nil).
    func applyAppearance() {
        NSApp.appearance = theme.nsAppearance
    }
    var accent: Accent {
        didSet { defaults.set(accent.rawValue, forKey: Keys.accent) }
    }

    // MARK: Behavior

    /// Priority new tasks start at (raw Priority value).
    var defaultPriority: Int {
        didSet { defaults.set(defaultPriority, forKey: Keys.defaultPriority) }
    }
    /// Whether to confirm before deleting a task that has subtasks.
    var confirmBeforeDelete: Bool {
        didSet { defaults.set(confirmBeforeDelete, forKey: Keys.confirmDelete) }
    }
    /// Filter the app opens to. Empty = remember the last-used filter.
    var defaultFilterRaw: String {
        didSet { defaults.set(defaultFilterRaw, forKey: Keys.defaultFilter) }
    }
    /// On launch, open the last-used project (true) or always All Projects (false).
    var restoreLastProject: Bool {
        didSet { defaults.set(restoreLastProject, forKey: Keys.restoreProject) }
    }

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let theme           = "settings.theme"
        static let accent          = "settings.accent"
        static let defaultPriority = "settings.defaultPriority"
        static let confirmDelete   = "settings.confirmBeforeDelete"
        static let defaultFilter   = "settings.defaultFilter"
        static let restoreProject  = "settings.restoreLastProject"
    }

    init() {
        let d = UserDefaults.standard
        theme  = Theme(rawValue: d.string(forKey: Keys.theme) ?? "") ?? .system
        accent = Accent(rawValue: d.string(forKey: Keys.accent) ?? "") ?? .blue
        defaultPriority     = d.object(forKey: Keys.defaultPriority) as? Int ?? Priority.normal.rawValue
        confirmBeforeDelete = d.object(forKey: Keys.confirmDelete) as? Bool ?? true
        defaultFilterRaw    = d.string(forKey: Keys.defaultFilter) ?? ""   // "" = remember last
        restoreLastProject  = d.object(forKey: Keys.restoreProject) as? Bool ?? true
    }

    /// The filter a fresh launch should use, or nil to keep the last-used one.
    var defaultFilter: TaskFilter? { TaskFilter(rawValue: defaultFilterRaw) }
}
