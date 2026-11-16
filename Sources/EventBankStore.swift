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
    var categoryID: UUID?
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

struct BankCategory: Identifiable, Codable, Equatable {
    static let uncategorizedID = UUID(uuidString:"00000000-0000-0000-0000-000000000001")!
    static let uncategorized = BankCategory(id:uncategorizedID,title:"Uncategorized",position:0)
    var id = UUID()
    var title: String
    var position = Date().timeIntervalSince1970
    var revision = UUID()
    var version = 1
    var updatedAt = Date()
    var deleted = false
    var isValid: Bool { !title.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty && position.isFinite }
    static func preferred(_ a: Self, _ b: Self) -> Self {
        if a.deleted != b.deleted { return a.deleted ? a : b }
        if a.version != b.version { return a.version > b.version ? a : b }
        if a.updatedAt != b.updatedAt { return a.updatedAt > b.updatedAt ? a : b }
        return a.revision.uuidString > b.revision.uuidString ? a : b
    }
}
struct BankSection: Identifiable {
    let category: BankCategory
    let tasks: [BankTask]
    var id: UUID { category.id }
    var totalMinutes: Int { tasks.reduce(0) { $0+$1.minutes } }
}
enum BankCategoryDrag {
    static let identifier = "com.devon.calendarstudio.bank-category"
    static func provider(_ id: UUID) -> NSItemProvider {
        let provider = NSItemProvider()
        provider.registerDataRepresentation(forTypeIdentifier:identifier,visibility:.ownProcess) { completion in
            completion(Data(id.uuidString.utf8),nil); return nil
        }
        return provider
    }
}
struct BankDropDestination: Equatable {
    let categoryID: UUID
    let before: UUID?
}
enum BankSectionDropLayout {
    static func destination(at point: CGPoint, sections: [BankSection], sectionFrames: [UUID: CGRect], taskFrames: [UUID: CGRect]) -> BankDropDestination {
        let section = sections.first { sectionFrames[$0.id].map { point.y <= $0.maxY+4 } ?? false } ?? sections.last
        guard let section else { return BankDropDestination(categoryID:BankCategory.uncategorizedID,before:nil) }
        let measured = section.tasks.contains { taskFrames[$0.id] != nil }
        let before = measured ? BankDropLayout.before(at:point,orderedIDs:section.tasks.map(\.id),frames:taskFrames) : nil
        return BankDropDestination(categoryID:section.id,before:before)
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

enum BankDropLayout {
    static func before(at point: CGPoint, orderedIDs: [UUID], frames: [UUID: CGRect]) -> UUID? {
        let measured = orderedIDs.enumerated().compactMap { index,id -> (Int,UUID,CGRect)? in
            guard let frame = frames[id], frame.height > 0, frame.midY.isFinite else { return nil }
            return (index,id,frame)
        }
        for (_,id,frame) in measured where point.y < frame.midY { return id }
        // A lazy list may not have measured the next offscreen task yet.
        // Insert after the last measured card, rather than skipping to the end.
        guard let last = measured.last else { return orderedIDs.first }
        return last.0+1 < orderedIDs.count ? orderedIDs[last.0+1] : nil
    }
}

@MainActor final class EventBankStore: ObservableObject {
    @Published private(set) var records: [UUID: BankTask] = [:] {
        didSet { orderedTasks = nil }
    }
    private var orderedTasks: [BankTask]?
    @Published private(set) var categoryRecords: [UUID: BankCategory] = [:] {
        didSet { orderedTasks = nil }
    }
    private var loadedCategoryFiles: Set<URL> = []
    var categories: [BankCategory] {
        var values = categoryRecords.values.filter { !$0.deleted && $0.id != BankCategory.uncategorizedID }
        values.append(categoryRecords[BankCategory.uncategorizedID] ?? .uncategorized)
        return values.sorted { $0.position == $1.position ? $0.id.uuidString < $1.id.uuidString : $0.position < $1.position }
    }
    func categoryID(for task: BankTask) -> UUID {
        guard let id = task.categoryID, categoryRecords[id]?.deleted == false else { return BankCategory.uncategorizedID }
        return id
    }
    var sections: [BankSection] {
        let groups = Dictionary(grouping:tasks,by:categoryID(for:))
        return categories.map { BankSection(category:$0,tasks:groups[$0.id] ?? []) }
    }
    func appendPosition(in category: UUID) -> Double {
        guard let last = tasks.last(where:{ categoryID(for:$0) == category }) else { return 0 }
        return (last.position ?? last.createdAt.timeIntervalSince1970)+1
    }
    @Published private(set) var folder: URL?
    @Published private(set) var storageStatus = "Choose a sync folder"
    @Published private(set) var syncProblem: String?
    var onHistoryChange: ((String, BankTask?, BankTask?) -> Void)?
    var recordingHistory = true
    private var loadedFiles: Set<URL> = []
    private var pendingWrites: [UUID: BankTask] = [:] {
        didSet { orderedTasks = nil }
    }
    private var timer: Timer?
    private let preferences: UserDefaults
    private let persistFolderChoice: Bool
    var tasks: [BankTask] {
        if let orderedTasks { return orderedTasks }
        let categoryOrder = Dictionary(uniqueKeysWithValues:categories.enumerated().map { ($0.element.id,$0.offset) })
        let result = records.values.filter { $0.state == .pending && pendingWrites[$0.id]?.state != .scheduled }
            .sorted {
                let ca = categoryOrder[categoryID(for:$0)] ?? 0, cb = categoryOrder[categoryID(for:$1)] ?? 0
                if ca != cb { return ca < cb }
                let a = $0.position ?? $0.createdAt.timeIntervalSince1970
                let b = $1.position ?? $1.createdAt.timeIntervalSince1970
                return a == b ? $0.id.uuidString < $1.id.uuidString : a < b
            }
        orderedTasks = result
        return result
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
        try FileManager.default.createDirectory(at:url.appendingPathComponent("category-records"),withIntermediateDirectories:true)
        // Merge the existing bank into the new folder without overwriting its records.
        if let current = folder, current != url {
            for task in records.values { try write(task,to:url) }
            for category in categoryRecords.values { try writeCategory(category,to:url) }
        }
        folder = url
        if persistFolderChoice { preferences.set(url.path,forKey:"eventBankFolder") }
        loadedFiles = []
        loadedCategoryFiles = []
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
            let categoryDirectory = folder.appendingPathComponent("category-records")
            if FileManager.default.fileExists(atPath:categoryDirectory.path) {
                var mergedCategories = categoryRecords
                for file in try FileManager.default.contentsOfDirectory(at:categoryDirectory,includingPropertiesForKeys:nil,options:.skipsHiddenFiles) where file.pathExtension == "json" && !loadedCategoryFiles.contains(file) {
                    do {
                        let value = try JSONDecoder().decode(BankCategory.self,from:Data(contentsOf:file))
                        guard value.isValid else { unreadable = true; continue }
                        mergedCategories[value.id] = mergedCategories[value.id].map { BankCategory.preferred($0,value) } ?? value
                        loadedCategoryFiles.insert(file)
                    } catch { unreadable = true }
                }
                if mergedCategories != categoryRecords { categoryRecords = mergedCategories }
            }
            let problem = unreadable ? "Some bank files haven’t loaded yet. They will be retried." : nil
            if syncProblem != problem { syncProblem = problem }
            let status = "Google Drive folder · \(tasks.count) task\(tasks.count == 1 ? "" : "s")"
            if storageStatus != status { storageStatus = status }
        } catch {
            let problem = "Bank changes are waiting to save. \(error.localizedDescription)"
            if syncProblem != problem { syncProblem = problem }
            if storageStatus != "Sync folder unavailable" { storageStatus = "Sync folder unavailable" }
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
    private func writeCategory(_ category: BankCategory, to folder: URL) throws {
        let destination = folder.appendingPathComponent("category-records").appendingPathComponent("\(category.id.uuidString)-\(category.revision.uuidString).json")
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted,.sortedKeys]
        try encoder.encode(category).write(to:destination,options:.atomic)
        loadedCategoryFiles.insert(destination)
    }
    func saveCategory(_ draft: BankCategory, expectedRevision: UUID? = nil) throws {
        refresh()
        guard let folder else { throw failure("Choose a bank folder before adding categories.") }
        var category = draft
        category.title = category.title.trimmingCharacters(in:.whitespacesAndNewlines)
        guard category.isValid else { throw failure("Enter a category name.") }
        if category.id == BankCategory.uncategorizedID { category.title = "Uncategorized"; category.deleted = false }
        if let existing = categoryRecords[category.id] {
            guard !existing.deleted else { throw failure("This category was removed on another Mac.") }
            if let expectedRevision, expectedRevision != existing.revision { throw failure("This category changed on another Mac. Open it again before saving.") }
        }
        category.version = (categoryRecords[category.id]?.version ?? 0)+1
        category.updatedAt = Date(); category.revision = UUID()
        try writeCategory(category,to:folder)
        categoryRecords[category.id] = category
    }
    func removeCategory(_ id: UUID) throws {
        guard id != BankCategory.uncategorizedID, var category = categoryRecords[id], !category.deleted else { return }
        category.deleted = true
        try saveCategory(category,expectedRevision:category.revision)
    }
    func reorderCategory(_ id: UUID, before target: UUID?) throws {
        refresh()
        guard id != target, var category = categories.first(where:{ $0.id == id }) else { return }
        let others = categories.filter { $0.id != id }
        guard target == nil || others.contains(where:{ $0.id == target }) else { return }
        let index = target.flatMap { target in others.firstIndex(where:{ $0.id == target }) } ?? others.count
        var reordered = others; reordered.insert(category,at:index)
        guard reordered.map(\.id) != categories.map(\.id) else { return }
        let lower = index > 0 ? others[index-1].position : nil
        let upper = index < others.count ? others[index].position : nil
        if let lower, let upper { category.position = lower+(upper-lower)/2 }
        else if let lower { category.position = lower+1 }
        else if let upper { category.position = upper-1 }
        try saveCategory(category,expectedRevision:categoryRecords[id]?.revision)
    }
    func save(_ draft: BankTask, expectedRevision: UUID? = nil) throws {
        refresh()
        guard let folder else { throw failure("Choose a Google Drive folder before adding tasks.") }
        guard draft.isValid else { throw failure("Enter a title and a duration between 1 minute and 7 days.") }
        if let existing = records[draft.id] {
            guard existing.state == .pending else { throw failure("This task was already scheduled or removed on another Mac.") }
            if let expectedRevision, expectedRevision != existing.revision { throw failure("This task changed on another Mac. Close the editor and open it again.") }
        }
        let previous = records[draft.id]
        var task = draft
        task.version = (records[task.id]?.version ?? 0) + 1
        task.updatedAt = Date(); task.revision = UUID()
        try write(task,to:folder)
        records[task.id] = task
        syncProblem = nil
        storageStatus = "Google Drive folder · \(tasks.count) tasks"
        if recordingHistory { onHistoryChange?(task.state == .removed ? "Delete Bank Task" : (previous == nil ? "Add Bank Task" : "Edit Bank Task"),previous,task) }
    }
    func reorder(_ id: UUID, before target: UUID?, categoryID destination: UUID? = nil) throws {
        refresh()
        let original = tasks.map(\.id)
        guard var task = tasks.first(where:{ $0.id == id }), target != id else { return }
        let category = destination ?? target.flatMap { records[$0].map { categoryID(for:$0) } } ?? categoryID(for:task)
        guard categories.contains(where:{ $0.id == category }) else { throw failure("This category is no longer available.") }
        let oldCategory = categoryID(for:task)
        task.categoryID = category == BankCategory.uncategorizedID ? nil : category
        var remaining = tasks.filter { $0.id != id && categoryID(for:$0) == category }
        let index: Int
        if let target {
            guard let found = remaining.firstIndex(where:{ $0.id == target }) else { return }
            index = found
        } else { index = remaining.count }
        remaining.insert(task,at:index)
        guard remaining.map(\.id) != original.filter({ records[$0].map { categoryID(for:$0) == category } ?? false }) || oldCategory != category else { return }
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
    func validateRestoration(_ change: BankRestoration) throws {
        refresh()
        guard pendingWrites.isEmpty, folder != nil else { throw failure("Wait for Event Bank to finish syncing, then try again.") }
        if let current = change.handle.current, records[current.id] != current {
            throw failure("This task changed on another Mac. Refresh the bank before trying again.")
        }
    }
    func restore(_ change: BankRestoration, undo: Bool) throws {
        guard let folder else { throw failure("The bank folder is unavailable.") }
        let desired = undo ? change.before : change.after
        let current = change.handle.current
        var task: BankTask
        if let desired {
            task = desired
            if let current { task.id = current.id }
            // Never revive a tombstone: older offline clients must still see it.
            if desired.state == .pending, current?.state != .pending { task.id = UUID() }
        } else if let current { task = current; task.state = .removed }
        else { return }
        task.version = (records[task.id]?.version ?? 0)+1
        task.updatedAt = Date(); task.revision = UUID()
        try write(task,to:folder)
        records[task.id] = task; change.handle.current = task
        syncProblem = nil
        storageStatus = "Google Drive folder · \(tasks.count) tasks"
    }
    private func failure(_ message: String) -> NSError { NSError(domain:"EventBank",code:1,userInfo:[NSLocalizedDescriptionKey:message]) }
}

// Bank cards use the same time-to-height scale as the calendar.
enum BankTaskResize {
    static func minutes(original: Int, translation: CGFloat, top: Bool, fine: Bool) -> Int {
        let step = Double(fine ? 1 : CalendarMath.defaultSnapMinutes)
        let delta = Double(translation/CalendarMath.hourHeight*60)*(top ? -1 : 1)
        return min(10080,max(1,Int(((Double(original)+delta)/step).rounded()*step)))
    }
}

@MainActor final class BankEditorSession: ObservableObject {
    @Published var task: BankTask
    @Published var error: String?
    let model: CalendarModel
    let bank: EventBankStore
    let initial: BankTask
    let expectedRevision: UUID?
    init(model: CalendarModel, bank: EventBankStore, task: BankTask) {
        self.model = model; self.bank = bank
        var resolved = task
        resolved.calendarID = model.calendar(for:task)?.id ?? ""
        self.task = resolved; initial = resolved
        expectedRevision = bank.records[task.id]?.revision
    }
    func commit() -> Bool {
        if task == initial && expectedRevision != nil { return true }
        if expectedRevision == nil && task.title.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty { return true }
        guard let source = model.sources.first(where:{ $0.id == task.calendarID && $0.writable && !$0.title.hasPrefix("- ") }) else { error = "Choose an editable calendar."; return false }
        var saved = task
        saved.title = saved.title.trimmingCharacters(in:.whitespacesAndNewlines)
        saved.calendarTitle = source.title; saved.account = source.account
        if expectedRevision == nil || bank.categoryID(for:saved) != bank.categoryID(for:initial) {
            saved.position = bank.appendPosition(in:bank.categoryID(for:saved))
        }
        do { try bank.save(saved,expectedRevision:expectedRevision); return true }
        catch { self.error = error.localizedDescription; return false }
    }
}
