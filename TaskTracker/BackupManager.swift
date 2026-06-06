import Foundation

enum BackupKind: String {
    case auto       = "auto"
    case manual     = "manual"
    /// A snapshot of the store taken automatically right before a restore, so a
    /// destructive restore is always reversible. Never auto-pruned.
    case preRestore = "prerestore"
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

    /// The timestamp format embedded in every backup's filename. This — not the
    /// file's creation date — is the source of truth for when a backup was made,
    /// because copyItem preserves the source store's creation date, so on-disk
    /// metadata would make every backup look as old as the original store.
    private static let nameTimestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH-mm-ss"
        return f
    }()

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

    var autoBackups:       [Backup] { backups.filter { $0.kind == .auto       } }
    var manualBackups:     [Backup] { backups.filter { $0.kind == .manual     } }
    var preRestoreBackups: [Backup] { backups.filter { $0.kind == .preRestore } }

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

    // Called on launch: backs up if the configured interval has elapsed since the
    // last auto-backup, then arms the timer so interval backups keep running while
    // the app stays open. (Launch backups are simply "is one due?" — no separate
    // toggle.)
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

    /// How often we wake up to check whether an auto-backup is due. We poll rather
    /// than scheduling a single fire at the full interval so that a backup happens
    /// `interval` after the *last backup* (not after launch), and so it still fires
    /// for a long-running app even across system sleep, where a one-shot long timer
    /// is unreliable.
    private static let dueCheckCadence: TimeInterval = 5 * 60

    private func scheduleTimer() {
        timer?.invalidate()
        timer = nil
        guard autoBackupIntervalHours > 0 else { return }
        let t = Timer(timeInterval: Self.dueCheckCadence, repeats: true) { [weak self] _ in
            self?.createAutoBackupIfDue()
        }
        t.tolerance = Self.dueCheckCadence * 0.5
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func refresh() {
        let fm = FileManager.default
        let files = (try? fm.contentsOfDirectory(at: backupDir, includingPropertiesForKeys: [.creationDateKey])) ?? []
        backups = files.compactMap { url -> Backup? in
            guard url.pathExtension == "store" else { return nil }
            let stem = url.deletingPathExtension().lastPathComponent
            let kind: BackupKind
            if stem.hasPrefix("prerestore-") { kind = .preRestore }
            else if stem.hasPrefix("auto-")   { kind = .auto }
            else                              { kind = .manual }
            // Prefer the timestamp baked into the filename; the file's creation
            // date is unreliable because copyItem inherits the source store's.
            let date = Self.date(fromStem: stem)
                ?? (try? url.resourceValues(forKeys: [.creationDateKey]))?.creationDate
                ?? Date.distantPast
            return Backup(url: url, date: date, name: stem, kind: kind)
        }.sorted()
    }

    /// Parses the "yyyy-MM-dd HH-mm-ss" timestamp out of a backup filename stem
    /// like "auto-2026-06-06 14-30-00 optional label".
    private static func date(fromStem stem: String) -> Date? {
        let withoutKind = stem.replacingOccurrences(
            of: "^(auto|manual|prerestore)-", with: "", options: .regularExpression)
        // The timestamp is the first two space-separated fields ("date time").
        let fields = withoutKind.split(separator: " ")
        guard fields.count >= 2 else { return nil }
        return nameTimestampFormatter.date(from: "\(fields[0]) \(fields[1])")
    }

    @discardableResult
    func createBackup(label: String = "", kind: BackupKind = .manual) -> Backup? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: storeURL.path) else { return nil }

        let timestamp = Self.nameTimestampFormatter.string(from: Date())
        let prefix = kind.rawValue
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

        // Restore replaces ALL current data with the snapshot. First take a
        // pre-restore safety backup of the current store so the user can always
        // undo a restore. It's a real saved backup (never auto-pruned), distinct
        // from the transient staging copy below. Skip if restoring a pre-restore
        // backup itself, to avoid stacking redundant safety copies on undo.
        if fm.fileExists(atPath: storeURL.path) && backup.kind != .preRestore {
            createBackup(label: "before restore", kind: .preRestore)
        }

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
