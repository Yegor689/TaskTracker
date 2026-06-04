import Foundation

enum BackupKind: String {
    case auto   = "auto"
    case manual = "manual"
}

struct Backup: Identifiable, Comparable {
    let id = UUID()
    let url: URL
    let date: Date
    let name: String
    let kind: BackupKind

    static func < (lhs: Backup, rhs: Backup) -> Bool { lhs.date > rhs.date }
}

@Observable
final class BackupManager {
    private let storeURL: URL
    private let backupDir: URL

    private static let maxAutoBackups = 10
    private static let intervalDefaultsKey = "autoBackupIntervalHours"

    /// Selectable auto-backup intervals. `nil` rawValue (0) means disabled.
    static let intervalOptions = [0, 1, 6, 12, 24]

    private(set) var backups: [Backup] = []
    private var timer: Timer?

    /// How often to auto-back-up, in hours. 0 = off. Persisted in UserDefaults.
    var autoBackupIntervalHours: Int {
        didSet {
            UserDefaults.standard.set(autoBackupIntervalHours, forKey: Self.intervalDefaultsKey)
            scheduleTimer()
        }
    }

    var autoBackups:   [Backup] { backups.filter { $0.kind == .auto   } }
    var manualBackups: [Backup] { backups.filter { $0.kind == .manual } }

    init(storeURL: URL) {
        self.storeURL = storeURL
        self.backupDir = URL.applicationSupportDirectory
            .appending(component: "TaskTrackerBackups", directoryHint: .isDirectory)
        // Default to daily (24h) on first run if nothing stored yet.
        if UserDefaults.standard.object(forKey: Self.intervalDefaultsKey) == nil {
            self.autoBackupIntervalHours = 24
        } else {
            self.autoBackupIntervalHours = UserDefaults.standard.integer(forKey: Self.intervalDefaultsKey)
        }
        try? FileManager.default.createDirectory(at: backupDir, withIntermediateDirectories: true)
        refresh()
    }

    // Called on launch — backs up if enough time has elapsed since the last auto-backup,
    // then arms the timer so backups keep running while the app stays open.
    func startAutoBackup() {
        createAutoBackupIfDue()
        scheduleTimer()
    }

    /// Creates an auto-backup if the configured interval has elapsed since the last one.
    private func createAutoBackupIfDue() {
        guard autoBackupIntervalHours > 0 else { return }
        let interval = TimeInterval(autoBackupIntervalHours) * 3600
        if let latest = autoBackups.first, Date().timeIntervalSince(latest.date) < interval { return }
        createBackup(kind: .auto)
        pruneAutoBackups()
    }

    private func scheduleTimer() {
        timer?.invalidate()
        timer = nil
        guard autoBackupIntervalHours > 0 else { return }
        let interval = TimeInterval(autoBackupIntervalHours) * 3600
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.createBackup(kind: .auto)
            self.pruneAutoBackups()
        }
        // Tolerance lets the OS batch the timer for power efficiency; exact timing isn't critical.
        t.tolerance = interval * 0.1
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func refresh() {
        let fm = FileManager.default
        let files = (try? fm.contentsOfDirectory(at: backupDir, includingPropertiesForKeys: [.creationDateKey])) ?? []
        backups = files.compactMap { url -> Backup? in
            guard url.pathExtension == "store" else { return nil }
            let date = (try? url.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date.distantPast
            let stem = url.deletingPathExtension().lastPathComponent
            let kind: BackupKind = stem.hasPrefix("auto-") ? .auto : .manual
            return Backup(url: url, date: date, name: stem, kind: kind)
        }.sorted()
    }

    @discardableResult
    func createBackup(label: String = "", kind: BackupKind = .manual) -> Backup? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: storeURL.path) else { return nil }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH-mm-ss"
        let timestamp = formatter.string(from: Date())
        let prefix = kind == .auto ? "auto" : "manual"
        let name = label.isEmpty ? "\(prefix)-\(timestamp)" : "\(prefix)-\(timestamp) \(label)"
        let dest = backupDir.appending(component: "\(name).store")

        let walSrc  = storeURL.appendingPathExtension("wal")
        let shmSrc  = storeURL.appendingPathExtension("shm")
        let walDest = dest.appendingPathExtension("wal")
        let shmDest = dest.appendingPathExtension("shm")

        do {
            try fm.copyItem(at: storeURL, to: dest)
            if fm.fileExists(atPath: walSrc.path)  { try? fm.copyItem(at: walSrc,  to: walDest) }
            if fm.fileExists(atPath: shmSrc.path)  { try? fm.copyItem(at: shmSrc,  to: shmDest) }
        } catch {
            return nil
        }

        refresh()
        return backups.first
    }

    func restore(backup: Backup) throws {
        let fm = FileManager.default

        // Stage the current store aside so a failed copy can't leave us with no
        // store at all. Only remove the staged copy once the restore succeeds.
        let staged = storeURL.appendingPathExtension("restoring-backup")
        try? fm.removeItem(at: staged)
        if fm.fileExists(atPath: storeURL.path) {
            try fm.moveItem(at: storeURL, to: staged)
        }

        let walDest = storeURL.appendingPathExtension("wal")
        let shmDest = storeURL.appendingPathExtension("shm")
        try? fm.removeItem(at: walDest)
        try? fm.removeItem(at: shmDest)

        do {
            try fm.copyItem(at: backup.url, to: storeURL)
            let walSrc = backup.url.appendingPathExtension("wal")
            let shmSrc = backup.url.appendingPathExtension("shm")
            if fm.fileExists(atPath: walSrc.path) { try? fm.copyItem(at: walSrc, to: walDest) }
            if fm.fileExists(atPath: shmSrc.path) { try? fm.copyItem(at: shmSrc, to: shmDest) }
        } catch {
            // Restore failed — put the original store back.
            try? fm.removeItem(at: storeURL)
            if fm.fileExists(atPath: staged.path) {
                try? fm.moveItem(at: staged, to: storeURL)
            }
            throw error
        }

        try? fm.removeItem(at: staged)
    }

    func delete(backup: Backup) {
        let fm = FileManager.default
        try? fm.removeItem(at: backup.url)
        try? fm.removeItem(at: backup.url.appendingPathExtension("wal"))
        try? fm.removeItem(at: backup.url.appendingPathExtension("shm"))
        refresh()
    }

    private func pruneAutoBackups() {
        let autos = autoBackups // already sorted newest first
        let excess = autos.dropFirst(Self.maxAutoBackups)
        excess.forEach { delete(backup: $0) }
    }
}
