import AppKit
import SwiftUI

struct BankTask: Identifiable, Codable, Equatable {
    enum State: String, Codable { case pending, scheduled, removed }
    var schemaVersion = 1
    var id = UUID()
    var title: String
    var minutes: Int
    var calendarID: String
    var calendarTitle: String
    var account: String
    var notes = ""
    var position: Double?
    var createdAt = Date()
    var updatedAt = Date()
    var revision = UUID()
    var version = 1
    var state: State = .pending
    var scheduledStart: Date?
    var scheduledEventID: String?

    var isValid: Bool {
        schemaVersion == 1 && !title.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty && (1...10080).contains(minutes)
    }
    static func durationLabel(_ minutes: Int) -> String {
        let hours = minutes / 60, remainder = minutes % 60
        if hours == 0 { return "\(minutes)m" }
        return remainder == 0 ? "\(hours)h" : "\(hours)h \(remainder)m"
    }
    // Terminal records win over stale edits from a Mac that was offline.
    static func preferred(_ a: BankTask, _ b: BankTask) -> BankTask {
        if (a.state == .pending) != (b.state == .pending) { return a.state == .pending ? b : a }
        if a.version != b.version { return a.version > b.version ? a : b }
        if a.updatedAt != b.updatedAt { return a.updatedAt > b.updatedAt ? a : b }
        return a.revision.uuidString > b.revision.uuidString ? a : b
    }
}

enum NewTaskDrag {
    static let identifier = "com.devon.calendarstudio.new-task"
    static let pasteboardType = NSPasteboard.PasteboardType(identifier)
    static func provider() -> NSItemProvider {
        let provider = NSItemProvider()
        provider.registerDataRepresentation(forTypeIdentifier:identifier,visibility:.ownProcess) { completion in
            completion(Data("new-task".utf8),nil); return nil
        }
        return provider
    }
}

enum CalendarEventDrag {
    static let identifier = "com.devon.calendarstudio.calendar-events"
    static let pasteboardType = NSPasteboard.PasteboardType(identifier)
}

enum BankDrag {
    static let identifier = "com.devon.calendarstudio.bank-task"
    static let pasteboardType = NSPasteboard.PasteboardType(identifier)
    static func provider(for id: UUID) -> NSItemProvider {
        let provider = NSItemProvider()
        provider.registerDataRepresentation(forTypeIdentifier:identifier,visibility:.ownProcess) { completion in
            completion(id.uuidString.data(using:.utf8),nil)
            return nil
        }
        return provider
    }
}

@MainActor final class EventBankStore: ObservableObject {
    @Published private(set) var records: [UUID: BankTask] = [:]
    @Published private(set) var folder: URL?
    @Published private(set) var storageStatus = "Choose a sync folder"
    @Published private(set) var syncProblem: String?
    private var loadedFiles: Set<URL> = []
    private var pendingWrites: [UUID: BankTask] = [:]
    private var timer: Timer?
    private let preferences: UserDefaults
    private let persistFolderChoice: Bool
    var tasks: [BankTask] {
        records.values.filter { $0.state == .pending && pendingWrites[$0.id]?.state != .scheduled }
            .sorted {
                let a = $0.position ?? $0.createdAt.timeIntervalSince1970
                let b = $1.position ?? $1.createdAt.timeIntervalSince1970
                return a == b ? $0.id.uuidString < $1.id.uuidString : a < b
            }
    }
    var totalMinutes: Int { tasks.reduce(0) { $0 + $1.minutes } }
    var ready: Bool { folder != nil }

    static func defaultFolder(preferences: UserDefaults = .standard) -> URL? {
        if let path = preferences.string(forKey:"eventBankFolder") { return URL(fileURLWithPath:path,isDirectory:true) }
        let cloud = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/CloudStorage",isDirectory:true)
        let drives = (try? FileManager.default.contentsOfDirectory(at:cloud,includingPropertiesForKeys:nil))?.filter { $0.lastPathComponent.hasPrefix("GoogleDrive-") } ?? []
        guard drives.count == 1 else { return nil }
        return drives[0].appendingPathComponent("My Drive/Calendar Studio/Event Bank",isDirectory:true)
    }
    init(folder: URL?, watch: Bool = true, preferences: UserDefaults = .standard, persistFolderChoice: Bool = false) {
        self.preferences = preferences
        self.persistFolderChoice = persistFolderChoice
        if let folder {
            do { try configure(folder) }
            catch { syncProblem = error.localizedDescription; storageStatus = "Sync folder unavailable" }
        }
        if watch {
            timer = Timer.scheduledTimer(withTimeInterval:3,repeats:true) { [weak self] _ in
                Task { @MainActor in self?.refresh() }
            }
        }
    }
    convenience init() { self.init(folder:Self.defaultFolder(),persistFolderChoice:true) }
    deinit { timer?.invalidate() }

    func configure(_ url: URL) throws {
        let directory = url.appendingPathComponent("records",isDirectory:true)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        // Merge the existing bank into the new folder without overwriting its records.
        if let current = folder, current != url {
            for task in records.values { try write(task,to:url) }
        }
        folder = url
        if persistFolderChoice { preferences.set(url.path,forKey:"eventBankFolder") }
        loadedFiles = []
        refresh()
    }
    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.title = "Choose an Event Bank folder in Google Drive"
        panel.message = "Choose a private folder in Google Drive. Use this same folder on your other Mac."
        panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.canCreateDirectories = true
        panel.prompt = "Use This Folder"
        panel.directoryURL = folder ?? Self.defaultFolder()?.deletingLastPathComponent()
        if panel.runModal() == .OK, let url = panel.url {
            do { try configure(url) } catch { syncProblem = error.localizedDescription }
        }
    }
    func refresh() {
        guard let folder else { return }
        do {
            for (id,task) in pendingWrites {
                try write(task,to:folder)
                records[id] = task
                pendingWrites.removeValue(forKey:id)
            }
            let files = try FileManager.default.contentsOfDirectory(at:folder.appendingPathComponent("records"),includingPropertiesForKeys:nil,options:.skipsHiddenFiles)
            var merged = records
            var unreadable = false
            for file in files where file.pathExtension == "json" && !loadedFiles.contains(file) {
                do {
                    let task = try JSONDecoder().decode(BankTask.self,from:Data(contentsOf:file))
                    guard task.isValid else { unreadable = true; continue }
                    merged[task.id] = merged[task.id].map { BankTask.preferred($0,task) } ?? task
                    loadedFiles.insert(file)
                } catch { unreadable = true }
            }
            if merged != records { records = merged }
            syncProblem = unreadable ? "Some bank files haven’t loaded yet. They will be retried." : nil
            storageStatus = "Google Drive folder · \(tasks.count) task\(tasks.count == 1 ? "" : "s")"
        } catch {
            syncProblem = "Bank changes are waiting to save. \(error.localizedDescription)"
            storageStatus = "Sync folder unavailable"
        }
    }
    private func write(_ task: BankTask, to folder: URL) throws {
        let filename = "\(task.id.uuidString)-\(task.revision.uuidString).json"
        let destination = folder.appendingPathComponent("records").appendingPathComponent(filename)
        // Every revision gets a new file, so edits on different Macs never overwrite files.
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted,.sortedKeys]
        try encoder.encode(task).write(to:destination,options:.atomic)
        loadedFiles.insert(destination)
    }
    func save(_ draft: BankTask, expectedRevision: UUID? = nil) throws {
        refresh()
        guard let folder else { throw failure("Choose a Google Drive folder before adding tasks.") }
        guard draft.isValid else { throw failure("Enter a title and a duration between 1 minute and 7 days.") }
        if let existing = records[draft.id] {
            guard existing.state == .pending else { throw failure("This task was already scheduled or removed on another Mac.") }
            if let expectedRevision, expectedRevision != existing.revision { throw failure("This task changed on another Mac. Close the editor and open it again.") }
        }
        var task = draft
        task.version = (records[task.id]?.version ?? 0) + 1
        task.updatedAt = Date(); task.revision = UUID()
        try write(task,to:folder)
        records[task.id] = task
        syncProblem = nil
        storageStatus = "Google Drive folder · \(tasks.count) tasks"
    }
    func reorder(_ id: UUID, before target: UUID?) throws {
        refresh()
        let original = tasks.map(\.id)
        guard var task = tasks.first(where:{ $0.id == id }), target != id else { return }
        var remaining = tasks.filter { $0.id != id }
        let index: Int
        if let target {
            guard let found = remaining.firstIndex(where:{ $0.id == target }) else { return }
            index = found
        } else { index = remaining.count }
        remaining.insert(task,at:index)
        guard remaining.map(\.id) != original else { return }
        func rank(_ task: BankTask) -> Double { task.position ?? task.createdAt.timeIntervalSince1970 }
        let lower = index > 0 ? rank(remaining[index-1]) : nil
        let upper = index+1 < remaining.count ? rank(remaining[index+1]) : nil
        if let lower, let upper { task.position = lower + (upper-lower)/2 }
        else if let lower { task.position = lower+1 }
        else if let upper { task.position = upper-1 }
        try save(task,expectedRevision:task.revision)
    }
    func remove(_ id: UUID) throws {
        guard var task = records[id], task.state == .pending else { return }
        task.state = .removed
        try save(task,expectedRevision:task.revision)
    }
    func schedule(_ id: UUID, at start: Date, createEvent: (BankTask) throws -> String?) throws {
        refresh()
        guard let task = records[id], task.state == .pending, pendingWrites[id] == nil else {
            throw failure("This task was already scheduled or removed. Refresh the bank before trying again.")
        }
        let eventID = try createEvent(task)
        try didSchedule(id,at:start,eventID:eventID)
    }
    // Called only after EventKit confirms that the calendar event was saved.
    func didSchedule(_ id: UUID, at start: Date, eventID: String?) throws {
        guard var task = records[id] else { throw failure("The bank task could not be found.") }
        task.state = .scheduled; task.scheduledStart = start; task.scheduledEventID = eventID
        task.version += 1; task.updatedAt = Date(); task.revision = UUID()
        // Hide immediately after scheduling, even if Drive is temporarily unavailable.
        records[id] = task
        pendingWrites[id] = task
        guard let folder else { throw failure("The event was saved, but the bank folder is unavailable.") }
        do {
            try write(task,to:folder)
            pendingWrites.removeValue(forKey:id)
        } catch {
            syncProblem = "The event is scheduled. Its removal from the bank is waiting to sync."
            throw error
        }
    }
    private func failure(_ message: String) -> NSError { NSError(domain:"EventBank",code:1,userInfo:[NSLocalizedDescriptionKey:message]) }
}
