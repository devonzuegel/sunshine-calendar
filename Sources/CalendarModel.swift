import AppKit
import EventKit
import SwiftUI

struct CalendarEntry: Identifiable {
    var id: String
    var title: String
    var start: Date
    var end: Date
    var calendarID: String
    var color: NSColor
    var allDay = false
    var writable = true
    var recurring = false
    var hasGuests = false
}
struct CalendarSource: Identifiable {
    var id: String
    var title: String
    var account: String
    var color: NSColor
    var writable: Bool
}
struct EventDraft: Identifiable {
    var id = UUID()
    var original: CalendarEntry?
    var title: String = ""
    var start = Date()
    var end = Date().addingTimeInterval(3600)
    var calendarID = ""
    var allDay = false
    var location = ""
    var notes = ""
}
struct EventChange {
    var entry: CalendarEntry
    var start: Date
    var end: Date
}

enum CalendarMath {
    static let hourHeight: CGFloat = 64
    static func snappedMinutes(_ height: CGFloat) -> Int {
        Int((height / hourHeight * 60 / 15).rounded()) * 15
    }
    static func creationRange(from first: CGFloat, to last: CGFloat) -> ClosedRange<Int> {
        let a = max(0,min(1425,snappedMinutes(first)))
        let b = max(0,min(1440,snappedMinutes(last)))
        let lower = min(a,b), upper = max(a,b)
        return lower...min(1440,max(lower+15,upper))
    }
    static func shifted(_ entries: [CalendarEntry], minutes: Int) -> [EventChange] {
        entries.map { EventChange(entry: $0, start: $0.start.addingTimeInterval(Double(minutes) * 60), end: $0.end.addingTimeInterval(Double(minutes) * 60)) }
    }
}

@MainActor final class CalendarModel: ObservableObject {
    @Published var anchor = Date()
    @Published private(set) var firstVisibleDay = Calendar.current.dateInterval(of:.weekOfYear,for:Date())!.start
    @Published var entries: [CalendarEntry] = []
    @Published var sources: [CalendarSource] = []
    @Published var visible: Set<String> = []
    @Published var selected: Set<String> = []
    @Published private(set) var creationCalendarID: String?
    @Published var live = false
    @Published var connecting = false
    @Published var message: String?
    @Published var draft: EventDraft?
    @Published var status = "Sample calendars · Changes stay in this preview"
    @Published var undoChanges: [EventChange] = []
    @Published var redoChanges: [EventChange] = []
    var restoredScrollY: CGFloat?
    let daylight = DaylightLocation()
    let store = EKEventStore()
    let bank: EventBankStore
    private var observer: NSObjectProtocol?
    private var sampleEntries: [CalendarEntry] = []
    private var ekEvents: [String: EKEvent] = [:]
    private var knownSources: Set<String> = []
    private var restoredCalendarVisibility = false
    var weekStart: Date { firstVisibleDay }
    var weekEnd: Date { Calendar.current.date(byAdding: .day, value: 7, to: weekStart)! }
    var shown: [CalendarEntry] {
        let activeIDs = Set(sources.filter { !$0.title.hasPrefix("- ") }.map(\.id))
        return entries.filter { visible.contains($0.calendarID) && activeIDs.contains($0.calendarID) }
    }
    var selection: [CalendarEntry] { shown.filter { selected.contains($0.id) } }

    init(bank: EventBankStore? = nil, reconnectIfAuthorized: Bool = true) {
        self.bank = bank ?? EventBankStore()
        if reconnectIfAuthorized && UserDefaults.standard.bool(forKey:"restoreAfterRestart") {
            let preferences = UserDefaults.standard
            if let date = preferences.object(forKey:"restartVisibleDay") as? Date {
                firstVisibleDay = Calendar.current.startOfDay(for:date); anchor = date
            }
            restoredScrollY = CGFloat(preferences.double(forKey:"restartScrollY"))
            preferences.removeObject(forKey:"restoreAfterRestart")
            preferences.removeObject(forKey:"restartVisibleDay")
            preferences.removeObject(forKey:"restartScrollY")
        }
        sources = [CalendarSource(id: "work", title: "Work", account: "Preview", color: .systemBlue, writable: true), CalendarSource(id: "personal", title: "Personal", account: "Preview", color: .systemPurple, writable: true), CalendarSource(id: "shared", title: "Subscribed calendar", account: "Preview", color: .systemOrange, writable: false)]
        visible = Set(sources.map(\.id))
        knownSources = visible
        let today = Calendar.current.startOfDay(for: Date())
        func date(_ day: Int, _ hour: Int) -> Date { Calendar.current.date(byAdding: .hour, value: hour, to: Calendar.current.date(byAdding: .day, value: day, to: today)!)! }
        sampleEntries = [
            CalendarEntry(id: "one", title: "Project time", start: date(0,13), end: date(0,14), calendarID: "work", color: .systemBlue),
            CalendarEntry(id: "two", title: "Planning", start: date(0,14), end: date(0,15), calendarID: "work", color: .systemBlue),
            CalendarEntry(id: "three", title: "Morning walk", start: date(0,9), end: date(0,10), calendarID: "personal", color: .systemPurple),
            CalendarEntry(id: "four", title: "Community event", start: date(-1,11), end: date(-1,12), calendarID: "shared", color: .systemOrange, writable: false)
        ]
        reload()
        observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            Task { @MainActor in if self?.live == true { self?.reload() } }
        }
        if reconnectIfAuthorized && EKEventStore.authorizationStatus(for:.event) == .fullAccess {
            live = true; knownSources = []; visible = []; reload()
        }
    }
    func connect() {
        guard !connecting else { return }
        connecting = true
        Task {
            do {
                let allowed: Bool
                if EKEventStore.authorizationStatus(for:.event) == .fullAccess { allowed = true }
                else { allowed = try await store.requestFullAccessToEvents() }
                guard allowed else {
                    connecting = false
                    message = "Calendar access wasn’t granted. You can enable full access for Sunshine Calendar in System Settings → Privacy & Security → Calendars."
                    return
                }
                selected = []; undoChanges = []; redoChanges = []
                knownSources = []; visible = []
                live = true; connecting = false
                reload()
            } catch { connecting = false; message = error.localizedDescription }
        }
    }
    private func key(_ event: EKEvent) -> String {
        "\(event.calendarItemIdentifier)|\(event.startDate.timeIntervalSince1970)"
    }
    private func entry(_ event: EKEvent) -> CalendarEntry {
        CalendarEntry(id: key(event), title: event.title ?? "Untitled", start: event.startDate, end: event.endDate, calendarID: event.calendar.calendarIdentifier, color: NSColor(cgColor: event.calendar.cgColor) ?? .systemBlue, allDay: event.isAllDay, writable: event.calendar.allowsContentModifications, recurring: event.hasRecurrenceRules || event.isDetached, hasGuests: !(event.attendees ?? []).isEmpty)
    }
    func reload() {
        if live {
            let calendars = store.calendars(for:.event).filter { !$0.title.hasPrefix("- ") }
            sources = calendars.map { CalendarSource(id: $0.calendarIdentifier, title: $0.title, account: $0.source.title, color: NSColor(cgColor: $0.cgColor) ?? .systemBlue, writable: $0.allowsContentModifications) }.sorted { ($0.account, $0.title) < ($1.account, $1.title) }
            let ids = Set(sources.map(\.id))
            if !restoredCalendarVisibility {
                if let saved = UserDefaults.standard.stringArray(forKey:"visibleCalendarIDs") { visible = Set(saved).intersection(ids) }
                else { visible = ids }
                knownSources = ids
                restoredCalendarVisibility = true
            }
            visible.formUnion(ids.subtracting(knownSources)); visible.formIntersection(ids); knownSources = ids
            let events: [EKEvent] = calendars.isEmpty ? [] : store.events(matching:store.predicateForEvents(withStart:weekStart,end:weekEnd,calendars:calendars))
            ekEvents = Dictionary(events.map { (key($0), $0) }, uniquingKeysWith: { a, _ in a })
            entries = events.map(entry)
            UserDefaults.standard.set(Array(visible),forKey:"visibleCalendarIDs")
            status = "Connected to calendars on this Mac"
        } else {
            entries = sampleEntries.filter { $0.start < weekEnd && $0.end > weekStart }
        }
        selected.formIntersection(Set(shown.map(\.id)))
    }
    func navigate(_ weeks: Int) { navigateDays(weeks * 7) }
    func navigateDays(_ days: Int) {
        guard days != 0 else { return }
        jump(to:Calendar.current.date(byAdding:.day,value:days,to:firstVisibleDay)!)
    }
    func jump(to date: Date) {
        firstVisibleDay = Calendar.current.startOfDay(for:date)
        anchor = date
        selected = []
        reload()
    }
    func today() { jump(to:Date()) }
    func toggle(_ id: String) {
        guard sources.contains(where:{ $0.id == id && !$0.title.hasPrefix("- ") }) else { return }
        if visible.contains(id) { visible.remove(id) } else { visible.insert(id) }
        if live { UserDefaults.standard.set(Array(visible),forKey:"visibleCalendarIDs") }
        selected.formIntersection(Set(shown.map(\.id)))
    }
    var creationCalendar: CalendarSource? {
        let editable = sources.filter { $0.writable && !$0.title.hasPrefix("- ") }
        return editable.first(where:{ $0.id == creationCalendarID })
            ?? editable.first(where:{ visible.contains($0.id) }) ?? editable.first
    }
    func select(_ id: String, extending: Bool) {
        if extending { if selected.contains(id) { selected.remove(id) } else { selected.insert(id) } }
        else if !selected.contains(id) { selected = [id] }
        if selected.contains(id), let item = shown.first(where:{ $0.id == id }),
           sources.contains(where:{ $0.id == item.calendarID && $0.writable && !$0.title.hasPrefix("- ") }) {
            creationCalendarID = item.calendarID
        }
    }
    @discardableResult func deleteSelectedEvents() -> Bool {
        let items = selection
        guard !items.isEmpty else { return false }
        guard items.allSatisfy(\.writable) else {
            message = "Read-only calendar events can’t be deleted. Select only editable events."
            return false
        }
        if live {
            let alert = NSAlert()
            alert.messageText = items.count == 1 ? "Delete “\(items[0].title)”?" : "Delete \(items.count) selected events?"
            var details = "These events will be removed from their connected calendars."
            if items.contains(where:\.recurring) { details += " Only the selected occurrences of repeating events will be deleted." }
            if items.contains(where:\.hasGuests) { details += " Events with guests may send cancellations or decline responses." }
            alert.informativeText = details
            alert.addButton(withTitle:"Delete"); alert.addButton(withTitle:"Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return false }
        }
        do {
            if live {
                // Resolve and validate the full selection before staging any removals.
                var resolved: [EKEvent] = []
                for item in items {
                    let predicate = store.predicateForEvents(withStart:item.start.addingTimeInterval(-1),end:item.end.addingTimeInterval(1),calendars:nil)
                    guard let event = store.events(matching:predicate).first(where:{ key($0) == item.id }),
                          event.calendar.allowsContentModifications, event.startDate == item.start,
                          event.endDate == item.end, event.calendar.calendarIdentifier == item.calendarID,
                          event.title == item.title else {
                        throw NSError(domain:"CalendarStudio",code:5,userInfo:[NSLocalizedDescriptionKey:"An event changed or is no longer editable. Refresh and select the events again. No events were deleted."])
                    }
                    resolved.append(event)
                }
                for event in resolved { try store.remove(event,span:.thisEvent,commit:false) }
                try store.commit()
            } else {
                let ids = Set(items.map(\.id))
                sampleEntries.removeAll { ids.contains($0.id) }
            }
            selected = []; undoChanges = []; redoChanges = []; reload()
            status = "Deleted \(items.count) event\(items.count == 1 ? "" : "s")"
            return true
        } catch {
            store.reset(); reload()
            message = "Couldn’t delete the events. " + error.localizedDescription
            return false
        }
    }
    func move(minutes: Int) {
        guard minutes != 0, !selection.isEmpty else { return }
        guard selection.allSatisfy({ $0.writable && !$0.allDay }) else { message = "Select only editable timed events to move a group. Subscribed calendars are read-only."; return }
        if live && selection.contains(where: { $0.recurring || $0.hasGuests }) {
            let alert = NSAlert()
            alert.messageText = "Move \(selection.count) selected event\(selection.count == 1 ? "" : "s")?"
            alert.informativeText = "Only the selected occurrences of repeating events will move. Changes to events with guests may send calendar updates."
            alert.addButton(withTitle: "Move Events"); alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        if let inverse = apply(CalendarMath.shifted(selection, minutes: minutes)) {
            undoChanges = inverse; redoChanges = []
            status = "Moved \(inverse.count) event\(inverse.count == 1 ? "" : "s") · ⌘Z to undo"
        }
    }
    // Validate the complete group before staging changes; commit once, reset on failure.
    private func apply(_ changes: [EventChange]) -> [EventChange]? {
        var inverse: [EventChange] = []
        do {
            if live {
                var resolved: [(EventChange, EKEvent)] = []
                for change in changes {
                    let predicate = store.predicateForEvents(withStart: change.entry.start.addingTimeInterval(-1), end: change.entry.end.addingTimeInterval(1), calendars: nil)
                    guard let event = store.events(matching: predicate).first(where: { key($0) == change.entry.id }), event.calendar.allowsContentModifications,
                          event.startDate == change.entry.start, event.endDate == change.entry.end else {
                        throw NSError(domain: "CalendarStudio", code: 1, userInfo: [NSLocalizedDescriptionKey: "An event changed or is no longer editable. Refresh and select the events again. No group move was saved."])
                    }
                    resolved.append((change, event))
                }
                for (change, event) in resolved {
                    event.startDate = change.start; event.endDate = change.end
                    try store.save(event, span: .thisEvent, commit: false)
                }
                try store.commit()
                for (change, event) in resolved { inverse.append(EventChange(entry: entry(event), start: change.entry.start, end: change.entry.end)) }
            } else {
                for change in changes {
                    guard let index = sampleEntries.firstIndex(where: { $0.id == change.entry.id }) else { continue }
                    sampleEntries[index].start = change.start; sampleEntries[index].end = change.end
                    inverse.append(EventChange(entry: sampleEntries[index], start: change.entry.start, end: change.entry.end))
                }
            }
            reload(); selected = Set(inverse.map { $0.entry.id })
            return inverse
        } catch { store.reset(); reload(); message = "Couldn’t save the change. \(error.localizedDescription)"; return nil }
    }
    func undo() { guard !undoChanges.isEmpty else { return }; if let inverse = apply(undoChanges) { redoChanges = inverse; undoChanges = []; status = "Move undone" } }
    func redo() { guard !redoChanges.isEmpty else { return }; if let inverse = apply(redoChanges) { undoChanges = inverse; redoChanges = []; status = "Move restored" } }
    func calendar(for task: BankTask) -> CalendarSource? {
        let available = sources.filter { $0.writable && !$0.title.hasPrefix("- ") }
        if let exact = available.first(where:{ $0.id == task.calendarID }) { return exact }
        let matches = available.filter { $0.title == task.calendarTitle && $0.account == task.account }
        return matches.count == 1 ? matches[0] : nil
    }
    func canScheduleBankTask(_ id: UUID) -> Bool {
        guard live, let task = bank.records[id], task.state == .pending else { return false }
        return calendar(for:task) != nil
    }
    func scheduleBankTask(_ id: UUID, at date: Date) -> Bool {
        guard live else { message = "Connect your calendars before scheduling a task."; return false }
        do {
            try bank.schedule(id,at:date) { task in
                guard let source = self.calendar(for:task), let calendar = self.store.calendar(withIdentifier:source.id), calendar.allowsContentModifications, !calendar.title.hasPrefix("- ") else {
                    throw NSError(domain:"EventBank",code:2,userInfo:[NSLocalizedDescriptionKey:"Choose an available, editable calendar for this task."])
                }
                let event = EKEvent(eventStore:self.store)
                event.title = task.title
                event.startDate = date
                event.endDate = date.addingTimeInterval(Double(task.minutes)*60)
                event.calendar = calendar
                event.notes = task.notes
                try self.store.save(event,span:.thisEvent,commit:true)
                self.visible.insert(source.id)
                return event.eventIdentifier
            }
            undoChanges = []; redoChanges = []; reload()
            status = "Task scheduled · removed from Event Bank"
            return true
        } catch {
            if bank.records[id]?.state == .scheduled {
                reload(); status = "Task scheduled · bank sync pending"
                message = "The event is on your calendar. Its removal from the bank will sync when the folder is available again."
                return true
            }
            store.reset()
            message = "Couldn’t schedule the task. It is still in the bank. \(error.localizedDescription)"
            return false
        }
    }
    func moveEventsToBank(_ ids: [String]) -> Bool {
        let items = entries.filter { Set(ids).contains($0.id) }
        guard !items.isEmpty, items.count == Set(ids).count,
              items.allSatisfy({ $0.writable && !$0.allDay }), bank.ready else {
            message = "Choose editable timed events and an available bank folder."; return false
        }
        if items.contains(where:{ $0.recurring || $0.hasGuests }) {
            let alert = NSAlert()
            alert.messageText = "Move these events to the Event Bank?"
            alert.informativeText = "Only the selected occurrences of repeating events will be removed. Removing events with guests may send cancellations."
            alert.addButton(withTitle:"Move to Bank"); alert.addButton(withTitle:"Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return false }
        }
        var saved: [UUID] = []
        var calendarRemoved = false
        do {
            var resolved: [EKEvent] = []
            if live {
                for item in items {
                    guard let event = ekEvents[item.id], event.refresh(), event.calendar.allowsContentModifications,
                          event.startDate == item.start, event.endDate == item.end else {
                        throw NSError(domain:"EventBank",code:3,userInfo:[NSLocalizedDescriptionKey:"An event changed. Refresh and drag it again."])
                    }
                    resolved.append(event)
                }
            }
            for item in items {
                guard let source = sources.first(where:{ $0.id == item.calendarID && !$0.title.hasPrefix("- ") }) else {
                    throw NSError(domain:"EventBank",code:4,userInfo:[NSLocalizedDescriptionKey:"The calendar is unavailable."])
                }
                let event = resolved.first(where:{ key($0) == item.id })
                var notes = event?.notes ?? ""
                if let location = event?.location, !location.isEmpty { notes += (notes.isEmpty ? "" : "\n\n") + "Location: " + location }
                let task = BankTask(title:item.title,minutes:max(1,Int(ceil(item.end.timeIntervalSince(item.start)/60))),calendarID:source.id,calendarTitle:source.title,account:source.account,notes:notes)
                // Persist the unscheduled task before removing the original event.
                try bank.save(task); saved.append(task.id)
            }
            if live {
                for event in resolved { try store.remove(event,span:.thisEvent,commit:false) }
                try store.commit()
            } else { sampleEntries.removeAll { Set(ids).contains($0.id) } }
            calendarRemoved = true
            selected = []; undoChanges = []; redoChanges = []; reload()
            status = "Moved \(items.count) event\(items.count == 1 ? "" : "s") to Event Bank"
            return true
        } catch {
            store.reset()
            var rollbackFailed = false
            if !calendarRemoved {
                for id in saved { do { try bank.remove(id) } catch { rollbackFailed = true } }
            }
            reload()
            message = "Couldn’t move to the bank. The original events remain on your calendar. " + error.localizedDescription
            if rollbackFailed { message! += " Some bank copies could not be removed; check the bank before scheduling them." }
            return false
        }
    }
    func newEvent(at date: Date? = nil, durationMinutes: Int = 60) {
        guard let source = creationCalendar else { message = "No editable calendars are available."; return }
        let start = date ?? Calendar.current.date(bySettingHour: 13, minute: 0, second: 0, of: anchor)!
        draft = EventDraft(start: start, end: start.addingTimeInterval(Double(durationMinutes)*60), calendarID: source.id)
    }
    func edit(_ event: CalendarEntry) {
        guard event.writable else { message = "This calendar is read-only."; return }
        let ek = ekEvents[event.id]
        draft = EventDraft(original: event, title: event.title, start: event.start, end: event.end, calendarID: event.calendarID, allDay: event.allDay, location: ek?.location ?? "", notes: ek?.notes ?? "")
    }
    func save(_ draft: EventDraft) -> Bool {
        guard !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, draft.end > draft.start else { message = "Enter a title and an end time after the start time."; return false }
        do {
            if live {
                guard let calendar = store.calendar(withIdentifier: draft.calendarID), calendar.allowsContentModifications else { message = "Choose an editable calendar."; return false }
                let event: EKEvent
                if let original = draft.original {
                    guard let existing = ekEvents[original.id], existing.refresh(), existing.startDate == original.start, existing.endDate == original.end else { message = "This event changed. Close the editor and open it again."; return false }
                    event = existing
                } else { event = EKEvent(eventStore: store) }
                if draft.original?.hasGuests == true {
                    let alert = NSAlert(); alert.messageText = "Save changes to this event?"; alert.informativeText = "This event has guests. Saving may send calendar updates."; alert.addButton(withTitle: "Save"); alert.addButton(withTitle: "Cancel")
                    guard alert.runModal() == .alertFirstButtonReturn else { return false }
                }
                event.title = draft.title; event.calendar = calendar; event.startDate = draft.start; event.endDate = draft.end; event.isAllDay = draft.allDay; event.location = draft.location; event.notes = draft.notes
                try store.save(event, span: .thisEvent, commit: true)
            } else {
                let source = sources.first(where: { $0.id == draft.calendarID })!
                let event = CalendarEntry(id: draft.original?.id ?? UUID().uuidString, title: draft.title, start: draft.start, end: draft.end, calendarID: draft.calendarID, color: source.color, allDay: draft.allDay)
                sampleEntries.removeAll { $0.id == event.id }; sampleEntries.append(event)
            }
            undoChanges = []; redoChanges = []; reload(); status = live ? "Event saved to your calendar" : "Sample event saved"; return true
        } catch { store.reset(); reload(); message = error.localizedDescription; return false }
    }
}
