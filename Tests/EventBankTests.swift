import Foundation
import AppKit

@MainActor enum EventBankTests {
    static func run() throws -> Int {
        var count = 0
        func check(_ value: @autoclosure () -> Bool, _ label: String) { precondition(value(),label); count += 1 }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("event-bank-tests-"+UUID().uuidString,isDirectory:true)
        defer { try? FileManager.default.removeItem(at:root) }
        let folder = root.appendingPathComponent("bank",isDirectory:true)
        let firstMac = EventBankStore(folder:folder,watch:false)
        let secondMac = EventBankStore(folder:folder,watch:false)
        let task = BankTask(title:"Plan a workshop",minutes:25,calendarID:"work",calendarTitle:"Work",account:"Preview",notes:"Bring the outline")
        try firstMac.save(task)
        secondMac.refresh()
        check(secondMac.tasks.count == 1, "Another Mac can load a saved bank task")
        check(secondMac.tasks[0].minutes == 25 && secondMac.tasks[0].notes == task.notes, "Custom duration and notes survive syncing")
        let second = BankTask(title:"Read proposals",minutes:90,calendarID:"work",calendarTitle:"Work",account:"Preview")
        try secondMac.save(second)
        firstMac.refresh()
        check(firstMac.tasks.count == 2, "Independent task creation from two Macs merges without losing a task")
        let originalRevision = firstMac.records[task.id]!.revision
        var edited = firstMac.records[task.id]!
        edited.minutes = 45
        try firstMac.save(edited,expectedRevision:originalRevision)
        var rejectedStaleEdit = false
        do { try secondMac.save(task,expectedRevision:originalRevision) } catch { rejectedStaleEdit = true }
        check(rejectedStaleEdit, "Concurrent stale editor cannot silently replace a newer task")
        check(secondMac.records[task.id]!.minutes == 45, "Rejected editor retains the newer duration")
        let recordsURL = folder.appendingPathComponent("records")
        let revisionFiles = try FileManager.default.contentsOfDirectory(atPath:recordsURL.path)
        check(revisionFiles.count == 3, "Each edit is saved as a separate immutable revision")
        var attempts = 0
        do {
            try firstMac.schedule(task.id,at:Date()) { _ in
                attempts += 1
                throw NSError(domain:"MockCalendar",code:1)
            }
        } catch { }
        check(attempts == 1 && firstMac.tasks.contains(where:{ $0.id == task.id }), "A failed calendar save keeps the task in the bank")
        let scheduledAt = Date(timeIntervalSince1970:100000)
        try firstMac.schedule(task.id,at:scheduledAt) { value in
            attempts += 1
            check(value.minutes == 45 && value.notes == task.notes, "Scheduling receives the latest duration and notes")
            return "test-event-identifier"
        }
        check(!firstMac.tasks.contains(where:{ $0.id == task.id }), "Successful scheduling removes the task from the visible bank")
        check(firstMac.records[task.id]!.scheduledStart == scheduledAt && firstMac.records[task.id]!.scheduledEventID == "test-event-identifier", "A scheduling receipt is retained")
        secondMac.refresh()
        check(!secondMac.tasks.contains(where:{ $0.id == task.id }), "Scheduling removal propagates to another Mac")
        do { try firstMac.schedule(task.id,at:scheduledAt) { _ in attempts += 1; return nil } } catch { }
        check(attempts == 2, "Scheduling the same task twice does not create a second event")
        // An old offline task edit must not resurrect an already scheduled task.
        var stale = task
        stale.version = 100
        stale.updatedAt = Date().addingTimeInterval(10000)
        stale.revision = UUID()
        try JSONEncoder().encode(stale).write(to:recordsURL.appendingPathComponent("offline-edit.json"))
        firstMac.refresh()
        check(!firstMac.tasks.contains(where:{ $0.id == task.id }), "Offline edits cannot resurrect a scheduled task")
        try secondMac.remove(second.id)
        firstMac.refresh()
        check(firstMac.tasks.isEmpty, "Explicit removals propagate across Macs")
        let restart = EventBankStore(folder:folder,watch:false)
        check(restart.tasks.isEmpty && restart.records.count == 2, "Scheduled and removed tasks stay removed after relaunch")
        let third = BankTask(title:"Folder outage",minutes:15,calendarID:"work",calendarTitle:"Work",account:"Preview")
        try firstMac.save(third)
        let moved = root.appendingPathComponent("temporarily-unavailable")
        try FileManager.default.moveItem(at:folder,to:moved)
        var outageSaveCount = 0
        do { try firstMac.schedule(third.id,at:scheduledAt) { _ in outageSaveCount += 1; return "outage-test-event" } } catch { }
        check(outageSaveCount == 1 && firstMac.records[third.id]?.state == .scheduled, "A calendar save is retained if the bank folder goes offline")
        check(!firstMac.tasks.contains(where:{ $0.id == third.id }), "A scheduled task cannot be scheduled again while its removal waits to sync")
        try FileManager.default.moveItem(at:moved,to:folder)
        firstMac.refresh()
        let afterOutage = EventBankStore(folder:folder,watch:false)
        check(afterOutage.records[third.id]?.state == .scheduled, "Pending bank removal is saved when the folder returns")
        try Data("unfinished cloud download".utf8).write(to:recordsURL.appendingPathComponent("not-ready.json"))
        afterOutage.refresh()
        check(afterOutage.records.count == 3 && afterOutage.syncProblem != nil, "An unreadable cloud file does not erase existing records")
        check(BankTask.durationLabel(25) == "25m" && BankTask.durationLabel(90) == "1h 30m", "Estimates remain readable for custom and preset durations")
        let model = CalendarModel(bank:firstMac,reconnectIfAuthorized:false)
        var anotherDevice = task
        anotherDevice.calendarID = "a-different-local-calendar-id"
        check(model.calendar(for:anotherDevice)?.id == "work", "Calendar names and accounts map tasks across device-specific identifiers")
        model.sources.append(CalendarSource(id:"ambiguous",title:"Work",account:"Preview",color:.systemBlue,writable:true))
        check(model.calendar(for:anotherDevice) == nil, "Ambiguous calendar mapping requires the user to choose")
        model.sources.append(CalendarSource(id:"archived",title:"- Facebook",account:"Preview",color:.systemBlue,writable:true))
        model.entries.append(CalendarEntry(id:"archived-event",title:"Old event",start:Date(),end:Date().addingTimeInterval(3600),calendarID:"archived",color:.systemBlue))
        model.visible.insert("archived")
        model.selected.insert("archived-event")
        check(!model.shown.contains(where:{ $0.id == "archived-event" }) && !model.selection.contains(where:{ $0.id == "archived-event" }), "Archived events remain hidden even with stale visibility and selection")
        let archivedTask = BankTask(title:"Old task",minutes:30,calendarID:"archived",calendarTitle:"- Facebook",account:"Preview")
        check(model.calendar(for:archivedTask) == nil, "Archived calendars cannot receive scheduled bank tasks")
        let transferStore = EventBankStore(folder:root.appendingPathComponent("transfers"),watch:false)
        let transferModel = CalendarModel(bank:transferStore,reconnectIfAuthorized:false)
        let editable = transferModel.entries.filter { $0.writable && !$0.allDay }
        let pair = Array(editable.prefix(2))
        check(pair.count == 2, "Preview provides a group for transfer testing")
        check(transferModel.moveEventsToBank(pair.map(\.id)), "A group can move from calendar to bank")
        check(pair.allSatisfy { event in !transferModel.entries.contains(where:{ $0.id == event.id }) }, "Transferred events no longer occupy calendar slots")
        check(transferStore.tasks.count == 2, "Each selected event becomes one bank task")
        check(pair.allSatisfy { event in transferStore.tasks.contains(where:{ $0.title == event.title && $0.calendarID == event.calendarID && $0.minutes == max(1,Int(ceil(event.end.timeIntervalSince(event.start)/60))) }) }, "Transfer preserves event title, calendar and duration")
        check(!transferModel.moveEventsToBank(pair.map(\.id)) && transferStore.tasks.count == 2, "Repeated drop cannot duplicate an already transferred event")
        let readOnly = transferModel.entries.first(where:{ !$0.writable })!
        check(!transferModel.moveEventsToBank([readOnly.id]), "Read-only events cannot be removed into the bank")
        let unavailable = EventBankStore(folder:nil,watch:false)
        let unavailableModel = CalendarModel(bank:unavailable,reconnectIfAuthorized:false)
        let untouched = unavailableModel.entries.first(where:{ $0.writable && !$0.allDay })!
        check(!unavailableModel.moveEventsToBank([untouched.id]) && unavailableModel.entries.contains(where:{ $0.id == untouched.id }), "Missing bank storage leaves original calendar event untouched")
        let ordering = EventBankStore(folder:root.appendingPathComponent("ordering"),watch:false)
        var orderedTasks: [BankTask] = []
        for index in 0..<3 {
            var item = BankTask(title:"Task \(index)",minutes:30,calendarID:"work",calendarTitle:"Work",account:"Preview")
            item.createdAt = Date(timeIntervalSince1970:Double(100+index))
            try ordering.save(item); orderedTasks.append(item)
        }
        try ordering.reorder(orderedTasks[2].id,before:orderedTasks[0].id)
        check(ordering.tasks.map(\.id) == [orderedTasks[2].id,orderedTasks[0].id,orderedTasks[1].id], "Dragging a task before another updates bank order")
        try ordering.reorder(orderedTasks[2].id,before:nil)
        check(ordering.tasks.map(\.id) == orderedTasks.map(\.id), "Dropping in empty space moves a task to the end")
        try ordering.reorder(orderedTasks[2].id,before:orderedTasks[1].id)
        let reloadedOrder = EventBankStore(folder:root.appendingPathComponent("ordering"),watch:false)
        check(reloadedOrder.tasks.map(\.id) == [orderedTasks[0].id,orderedTasks[2].id,orderedTasks[1].id], "Task order persists and syncs through saved bank records")
        let revision = ordering.records[orderedTasks[2].id]!.revision
        try ordering.reorder(orderedTasks[2].id,before:orderedTasks[2].id)
        check(ordering.records[orderedTasks[2].id]!.revision == revision, "Dropping onto itself does not create a redundant saved edit")
        return count
    }
}
