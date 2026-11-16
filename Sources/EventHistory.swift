import AppKit
import EventKit
import SwiftUI
import Combine

// Handles are shared by all actions affecting an event. Restoring a deletion may
// assign a new EventKit identifier; earlier moves and edits must follow that ID.
final class EventHandle {
    var id: String?
    init(_ id: String) { self.id = id }
}
struct EventRestoration {
    let handle: EventHandle
    let before: EventSnapshot?
    let after: EventSnapshot?
    let span: EKSpan
}
struct CalendarAction {
    let name: String
    let changes: [EventRestoration]
    var bankChanges: [BankRestoration] = []
}
struct EventSnapshot {
    let entry: CalendarEntry
    let draft: EventDraft?
    var location: String?
    var structuredLocation: EKStructuredLocation?
    var notes: String?
    var url: URL?
    var timeZone: TimeZone?
    var alarms: [EKAlarm]?
    var rules: [EKRecurrenceRule]?
    var availability: EKEventAvailability = .notSupported
    var capturesRecurrence = true
    init(entry: CalendarEntry, draft: EventDraft? = nil) {
        self.entry = entry; self.draft = draft
    }
    init(_ event: EKEvent, entry: CalendarEntry, occurrenceOnly: Bool = false) {
        self.entry = entry; self.draft = nil
        location = event.location; notes = event.notes; url = event.url; timeZone = event.timeZone
        structuredLocation = event.structuredLocation?.copy() as? EKStructuredLocation
        alarms = event.alarms?.compactMap { $0.copy() as? EKAlarm }
        // A deleted occurrence is recreated as one event, never a duplicate series.
        capturesRecurrence = !occurrenceOnly
        rules = occurrenceOnly ? nil : event.recurrenceRules?.compactMap { $0.copy() as? EKRecurrenceRule }
        availability = event.availability
    }
    func apply(to event: EKEvent, calendar: EKCalendar) {
        event.calendar = calendar; event.title = entry.title
        event.startDate = entry.start; event.endDate = entry.end; event.isAllDay = entry.allDay
        event.timeZone = timeZone; event.location = location
        event.structuredLocation = structuredLocation?.copy() as? EKStructuredLocation
        event.notes = notes; event.url = url
        event.alarms = alarms?.compactMap { $0.copy() as? EKAlarm }
        if capturesRecurrence { event.recurrenceRules = rules?.compactMap { $0.copy() as? EKRecurrenceRule } }
        if availability != .notSupported { event.availability = availability }
    }
    func matches(_ event: EKEvent) -> Bool {
        event.title == entry.title && event.startDate == entry.start && event.endDate == entry.end &&
        event.calendar.calendarIdentifier == entry.calendarID && event.isAllDay == entry.allDay &&
        event.location == location && event.notes == notes && event.url == url && event.timeZone == timeZone &&
        event.availability == availability &&
        (event.structuredLocation?.isEqual(structuredLocation) ?? (structuredLocation == nil)) &&
        (!capturesRecurrence || NSArray(array:event.recurrenceRules ?? []).isEqual(to:rules ?? [])) &&
        NSArray(array:event.alarms ?? []).isEqual(to:alarms ?? [])
    }
}

final class BankHistoryHandle {
    var current: BankTask?
    init(_ task: BankTask?) { current = task }
}
struct BankRestoration {
    let handle: BankHistoryHandle
    let before: BankTask?
    let after: BankTask?
}

// Let the standard macOS Edit menu and responder chain select typing history
// or event history. Native menu validation supplies titles and enabled states.
@MainActor final class CalendarUndoManager: UndoManager {
    weak var model: CalendarModel?
    override var canUndo: Bool { model?.canUndo == true && model?.draft == nil }
    override var canRedo: Bool { model?.canRedo == true && model?.draft == nil }
    override var undoActionName: String { model?.undoHistory.last?.name ?? "" }
    override var redoActionName: String { model?.redoHistory.last?.name ?? "" }
    override var undoMenuItemTitle: String { model?.undoTitle ?? "Undo" }
    override var redoMenuItemTitle: String { model?.redoTitle ?? "Redo" }
    override func undo() { model?.undo() }
    override func redo() { model?.redo() }
}

@MainActor final class CalendarUndoWindowDelegate: NSObject, NSWindowDelegate {
    let previous: NSWindowDelegate?
    let model: CalendarModel
    let typingHistory = UndoManager()
    init(previous: NSWindowDelegate?, model: CalendarModel) { self.previous = previous; self.model = model }
    func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? {
        if window.firstResponder is NSTextView {
            return previous?.windowWillReturnUndoManager?(window) ?? typingHistory
        }
        return model.eventUndoManager
    }
    override func responds(to selector: Selector!) -> Bool {
        super.responds(to:selector) || previous?.responds(to:selector) == true
    }
    override func forwardingTarget(for selector: Selector!) -> Any? {
        previous?.responds(to:selector) == true ? previous : super.forwardingTarget(for:selector)
    }
}

// SwiftUI's default Undo commands do not reliably discover our custom history
// manager after the window delegate is attached. Resolve the active editor at
// invocation time, rather than relying on the scene's cached environment manager.
@MainActor final class CalendarHistoryRouting: ObservableObject {
    struct Availability: Equatable {
        var undo = false
        var redo = false
        var undoTitle = "Undo"
        var redoTitle = "Redo"
    }
    @Published private(set) var availability = Availability()
    private let model: CalendarModel
    private var observations: [NSObjectProtocol] = []
    private var modelChanges: AnyCancellable?
    init(model: CalendarModel) {
        self.model = model
        for name in [NSWindow.didUpdateNotification, NSWindow.didBecomeKeyNotification,
                     NSWindow.didResignKeyNotification, NSText.didChangeNotification,
                     Notification.Name.NSUndoManagerDidCloseUndoGroup,
                     Notification.Name.NSUndoManagerDidUndoChange,
                     Notification.Name.NSUndoManagerDidRedoChange] {
            observations.append(NotificationCenter.default.addObserver(forName:name,object:nil,queue:.main) { [weak self] _ in
                Task { @MainActor [weak self] in self?.refresh() }
            })
        }
        modelChanges = model.objectWillChange.sink { [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
        refresh()
    }
    deinit { observations.forEach(NotificationCenter.default.removeObserver) }
    func manager(in window: NSWindow?) -> UndoManager? {
        guard let window else { return nil }
        if let editor = window.firstResponder as? NSTextView { return editor.undoManager }
        if let field = window.firstResponder as? NSTextField { return field.currentEditor()?.undoManager }
        // Never undo a saved event behind an open editor or another modal form.
        guard model.draft == nil, window.attachedSheet == nil, window.sheetParent == nil,
              (window === NSApp.mainWindow || (window.delegate as? CalendarUndoWindowDelegate)?.model === model) else { return nil }
        return model.eventUndoManager
    }
    func refresh() {
        let manager = manager(in:NSApp.keyWindow)
        let next = Availability(undo:manager?.canUndo == true,redo:manager?.canRedo == true,
                                undoTitle:manager?.undoMenuItemTitle ?? "Undo",
                                redoTitle:manager?.redoMenuItemTitle ?? "Redo")
        if next != availability { availability = next }
    }
    func undo(in window: NSWindow?) {
        if let manager = manager(in:window), manager.canUndo { manager.undo() }
        refresh()
    }
    func redo(in window: NSWindow?) {
        if let manager = manager(in:window), manager.canRedo { manager.redo() }
        refresh()
    }
}

struct CalendarHistoryCommands: Commands {
    @StateObject private var routing: CalendarHistoryRouting
    init(model: CalendarModel) { _routing = StateObject(wrappedValue:CalendarHistoryRouting(model:model)) }
    var body: some Commands {
        CommandGroup(replacing:.undoRedo) {
            Button(routing.availability.undoTitle) { routing.undo(in:NSApp.keyWindow) }
                .keyboardShortcut("z",modifiers:.command).disabled(!routing.availability.undo)
            Button(routing.availability.redoTitle) { routing.redo(in:NSApp.keyWindow) }
                .keyboardShortcut("z",modifiers:[.command,.shift]).disabled(!routing.availability.redo)
        }
    }
}
