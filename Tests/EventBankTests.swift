import Foundation
import AppKit

@MainActor enum EventBankTests {
    static func run() throws -> Int {
        var count = 0
        func check(_ value: @autoclosure () -> Bool, _ label: String) { precondition(value(),label); count += 1 }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("event-bank-tests-"+UUID().uuidString,isDirectory:true)
        defer { try? FileManager.default.removeItem(at:root) }
        let dropIDs = (0..<3).map { _ in UUID() }
        let dropFrames = [dropIDs[0]:CGRect(x:12,y:40,width:180,height:20),dropIDs[1]:CGRect(x:12,y:70,width:180,height:80),dropIDs[2]:CGRect(x:12,y:160,width:180,height:30)]
        func insertion(_ y: CGFloat) -> UUID? { BankDropLayout.before(at:CGPoint(x:100,y:y),orderedIDs:dropIDs,frames:dropFrames) }
        check(insertion(10) == dropIDs[0], "Dropping in the bank header inserts before the first task")
        check(insertion(49) == dropIDs[0] && insertion(51) == dropIDs[1], "The upper and lower halves of a task choose the adjacent insertion positions")
        check(insertion(65) == dropIDs[1], "Gaps between bank cards are valid ordered drop positions")
        check(insertion(100) == dropIDs[1] && insertion(130) == dropIDs[2], "Variable-height tasks use their actual measured midpoint")
        check(insertion(200) == nil, "Dropping in the creation area below the cards appends to the bank")
        check(BankDropLayout.before(at:CGPoint(x:0,y:65),orderedIDs:dropIDs,frames:dropFrames) == dropIDs[1] && BankDropLayout.before(at:CGPoint(x:220,y:65),orderedIDs:dropIDs,frames:dropFrames) == dropIDs[1], "The full bank width uses the same insertion order")
        check(BankDropLayout.before(at:CGPoint(x:10,y:100),orderedIDs:dropIDs,frames:[dropIDs[1]:CGRect(x:0,y:0,width:26,height:66)]) == dropIDs[2], "A lazy or collapsed list inserts before the next unmeasured task instead of jumping to the end")
        check(BankDropLayout.before(at:.zero,orderedIDs:[],frames:[:]) == nil, "An empty bank accepts an append drop")
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
        // Do not depend on yesterday's preview event: on Sundays it lies
        // outside the currently loaded week.
        let readOnly = CalendarEntry(id:"readonly-transfer-fixture",title:"Shared event",start:Date(),end:Date().addingTimeInterval(3600),calendarID:"shared",color:.systemOrange,writable:false)
        transferModel.entries.append(readOnly)
        check(!transferModel.moveEventsToBank([readOnly.id]), "Read-only events cannot be removed into the bank")
        let unavailable = EventBankStore(folder:nil,watch:false)
        let unavailableModel = CalendarModel(bank:unavailable,reconnectIfAuthorized:false)
        let untouched = unavailableModel.entries.first(where:{ $0.writable && !$0.allDay })!
        check(!unavailableModel.moveEventsToBank([untouched.id]) && unavailableModel.entries.contains(where:{ $0.id == untouched.id }), "Missing bank storage leaves original calendar event untouched")
        let positionedFolder = root.appendingPathComponent("positioned-transfers")
        let positionedStore = EventBankStore(folder:positionedFolder,watch:false)
        var existingTasks: [BankTask] = []
        for index in 0..<3 {
            var task = BankTask(title:"Existing \(index)",minutes:30,calendarID:"work",calendarTitle:"Work",account:"Preview")
            task.position = 2_000_000_000+Double(index)*100
            try positionedStore.save(task); existingTasks.append(task)
        }
        let positionedModel = CalendarModel(bank:positionedStore,reconnectIfAuthorized:false)
        let insertedEvents = Array(positionedModel.entries.filter { $0.writable && !$0.allDay }.prefix(2))
        check(positionedModel.moveEventsToBank(insertedEvents.map(\.id),before:existingTasks[1].id), "Calendar events can be dropped between existing bank tasks")
        let expectedTitles = [existingTasks[0].title]+insertedEvents.map(\.title)+[existingTasks[1].title,existingTasks[2].title]
        check(positionedStore.tasks.map(\.title) == expectedTitles, "A group drop inserts all events together in their original order")
        check(positionedModel.undoTitle == "Undo Move to Event Bank", "Positioning and transfer form one undo action")
        positionedModel.undo()
        check(positionedStore.tasks.map(\.id) == existingTasks.map(\.id) && insertedEvents.allSatisfy { event in positionedModel.entries.contains(where:{ $0.id == event.id }) }, "Undo restores calendar events and the original bank order together")
        positionedModel.redo()
        check(positionedStore.tasks.map(\.title) == expectedTitles && positionedStore.tasks.count == 5, "Redo restores the group at its drop position without duplicates")
        check(EventBankStore(folder:positionedFolder,watch:false).tasks.map(\.title) == expectedTitles, "Calendar-event drop positions survive reloading the synced bank")
        let remainingIndex = positionedModel.entries.firstIndex { $0.writable && !$0.allDay }!
        positionedModel.entries[remainingIndex].notes = "Bring a notebook"
        positionedModel.entries[remainingIndex].location = "Community garden"
        let tailEvent = positionedModel.entries[remainingIndex]
        check(positionedModel.moveEventsToBank([tailEvent.id]), "The creation area accepts calendar-event transfers to the end")
        check(positionedStore.tasks.last?.title == tailEvent.title, "End drops append even when existing tasks have explicit reordered positions")
        check(positionedStore.tasks.last?.notes == "Bring a notebook\n\nLocation: Community garden", "Dropped events retain their notes and location")
        positionedModel.undo()
        check(positionedModel.moveEventsToBank([tailEvent.id],before:existingTasks[0].id) && positionedStore.tasks.first?.title == tailEvent.title, "A drop above the first task inserts at the start of the bank")
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
        let categoryFolder = root.appendingPathComponent("categories")
        let categoryStore = EventBankStore(folder:categoryFolder,watch:false)
        let categoryRemote = EventBankStore(folder:categoryFolder,watch:false)
        var legacy = BankTask(title:"Existing task",minutes:40,calendarID:"work",calendarTitle:"Work",account:"Preview",notes:"Keep these notes")
        legacy.createdAt = Date(timeIntervalSince1970:100)
        try categoryStore.save(legacy)
        let oldJSON = try JSONEncoder().encode(legacy)
        let decodedLegacy = try JSONDecoder().decode(BankTask.self,from:oldJSON)
        check(decodedLegacy.categoryID == nil, "Existing bank files decode without category metadata")
        check(categoryStore.sections.count == 1 && categoryStore.sections[0].id == BankCategory.uncategorizedID && categoryStore.sections[0].tasks[0].id == legacy.id, "Existing tasks appear in Uncategorized without rewriting or duplicating them")
        let project = BankCategory(title:"Projects",position:10)
        let personal = BankCategory(title:"Personal",position:20)
        try categoryStore.saveCategory(project); try categoryStore.saveCategory(personal)
        categoryRemote.refresh()
        check(categoryRemote.categories.map(\.title) == ["Uncategorized","Projects","Personal"], "New category names and order sync to another bank instance")
        check(categoryRemote.records.count == 1 && categoryRemote.syncProblem == nil, "Category files are separate from event records and do not become unreadable tasks")
        try categoryStore.reorder(legacy.id,before:nil,categoryID:project.id)
        check(categoryStore.sections.first(where:{ $0.id == project.id })?.tasks.first?.id == legacy.id && categoryStore.records.count == 1, "Moving into a category preserves task identity")
        check(categoryStore.records[legacy.id]?.notes == legacy.notes && categoryStore.records[legacy.id]?.calendarID == legacy.calendarID, "Changing a category preserves notes and the event calendar")
        var secondProject = BankTask(title:"Second project task",minutes:20,calendarID:"personal",calendarTitle:"Personal",account:"Preview")
        secondProject.categoryID = project.id; secondProject.position = 200
        try categoryStore.save(secondProject)
        try categoryStore.reorder(secondProject.id,before:legacy.id,categoryID:project.id)
        check(categoryStore.sections.first(where:{ $0.id == project.id })?.tasks.map(\.id) == [secondProject.id,legacy.id], "Task ordering works inside a category across different calendars")
        let categoryModel = CalendarModel(bank:categoryStore,reconnectIfAuthorized:false)
        categoryModel.selectedBankTasks = [legacy.id,secondProject.id]
        try categoryModel.moveSelectedBankTasks(to:personal.id)
        check(categoryStore.sections.first(where:{ $0.id == personal.id })?.tasks.map(\.id) == [secondProject.id,legacy.id], "Selected tasks move between categories together in their displayed order")
        check(categoryModel.undoTitle == "Undo Move Bank Tasks", "A grouped category move has one undo action")
        categoryModel.undo()
        check(categoryStore.sections.first(where:{ $0.id == project.id })?.tasks.map(\.id) == [secondProject.id,legacy.id], "Undo restores category membership and task order")
        categoryModel.redo()
        check(categoryStore.sections.first(where:{ $0.id == personal.id })?.tasks.map(\.id) == [secondProject.id,legacy.id], "Redo moves the group without duplicates")
        try categoryStore.reorderCategory(personal.id,before:BankCategory.uncategorizedID)
        check(categoryStore.categories.first?.id == personal.id && categoryStore.tasks.first?.id == secondProject.id, "Dragging a category moves its tasks with it")
        categoryRemote.refresh()
        check(categoryRemote.categories.map(\.id) == categoryStore.categories.map(\.id) && categoryRemote.tasks.map(\.id) == categoryStore.tasks.map(\.id), "Category and task order persist together across devices")
        let categoryRevision = categoryStore.categoryRecords[personal.id]!.revision
        try categoryStore.reorderCategory(personal.id,before:personal.id)
        check(categoryStore.categoryRecords[personal.id]?.revision == categoryRevision, "Dropping a category onto itself does not save a redundant edit")
        var renamed = categoryStore.categoryRecords[personal.id]!
        let staleCategory = renamed
        renamed.title = " Personal errands "
        try categoryStore.saveCategory(renamed,expectedRevision:renamed.revision)
        check(categoryStore.categories.first?.title == "Personal errands", "Category renaming trims whitespace and preserves its position")
        var staleRenameRejected = false
        do { try categoryStore.saveCategory(staleCategory,expectedRevision:staleCategory.revision) } catch { staleRenameRejected = true }
        check(staleRenameRejected, "Stale category edits cannot overwrite a newer name")
        let draft = BankTask(title:"New categorized task",minutes:25,calendarID:"work",calendarTitle:"Work",account:"Preview",categoryID:personal.id)
        let categorySession = BankEditorSession(model:categoryModel,bank:categoryStore,task:draft)
        check(categorySession.commit() && categoryStore.sections.first(where:{ $0.id == personal.id })?.tasks.last?.id == draft.id, "New tasks append within their chosen category")
        let editSession = BankEditorSession(model:categoryModel,bank:categoryStore,task:categoryStore.records[draft.id]!)
        editSession.task.categoryID = project.id
        check(editSession.commit() && categoryStore.sections.first(where:{ $0.id == project.id })?.tasks.last?.id == draft.id, "The task editor can move a task to another category")
        let eventsForCategory = Array(categoryModel.entries.filter { $0.writable && !$0.allDay }.prefix(2))
        let countBeforeCategoryDrop = categoryStore.tasks.count
        check(categoryModel.moveEventsToBank(eventsForCategory.map(\.id),before:legacy.id,categoryID:personal.id), "Calendar events can be dropped directly into a category")
        check(categoryStore.sections.first(where:{ $0.id == personal.id })?.tasks.map(\.title) == [secondProject.title]+eventsForCategory.map(\.title)+[legacy.title], "Calendar-event group drops respect the category and exact insertion position")
        categoryModel.undo()
        check(categoryStore.tasks.count == countBeforeCategoryDrop && eventsForCategory.allSatisfy { event in categoryModel.entries.contains(where:{ $0.id == event.id }) }, "Undo of a categorized calendar transfer restores the original events")
        categoryModel.redo()
        check(categoryStore.sections.first(where:{ $0.id == personal.id })?.tasks.count == 4, "Redo restores a calendar group to the original category")
        let beforeRemoval = categoryStore.tasks.count
        let projectTask = categoryStore.sections.first(where:{ $0.id == project.id })!.tasks.first!
        try categoryStore.removeCategory(project.id)
        check(categoryStore.tasks.count == beforeRemoval && categoryStore.categoryID(for:categoryStore.records[projectTask.id]!) == BankCategory.uncategorizedID, "Removing a category keeps all its tasks in Uncategorized")
        categoryRemote.refresh()
        check(!categoryRemote.categories.contains(where:{ $0.id == project.id }) && categoryRemote.tasks.count == beforeRemoval, "Category removal syncs without deleting tasks")
        var deletedCategoryRejected = false
        do { try categoryRemote.saveCategory(project) } catch { deletedCategoryRejected = true }
        check(deletedCategoryRejected, "An old client cannot revive a removed category")
        try categoryStore.removeCategory(BankCategory.uncategorizedID)
        check(categoryStore.categories.contains(where:{ $0.id == BankCategory.uncategorizedID }), "The fallback category remains available")
        let movedCategoryFolder = root.appendingPathComponent("migrated-categories")
        try categoryStore.configure(movedCategoryFolder)
        let migratedCategories = EventBankStore(folder:movedCategoryFolder,watch:false)
        check(migratedCategories.categories.map(\.title) == categoryStore.categories.map(\.title) && migratedCategories.tasks.map(\.title) == categoryStore.tasks.map(\.title), "Changing the bank folder preserves category names, order and task membership")
        let sectionA = BankSection(category:personal,tasks:[legacy,secondProject])
        let sectionB = BankSection(category:project,tasks:[])
        let sectionFrames = [personal.id:CGRect(x:0,y:10,width:200,height:150),project.id:CGRect(x:0,y:175,width:200,height:45)]
        let taskFrames = [legacy.id:CGRect(x:12,y:45,width:170,height:40),secondProject.id:CGRect(x:12,y:95,width:170,height:50)]
        check(BankSectionDropLayout.destination(at:CGPoint(x:50,y:20),sections:[sectionA,sectionB],sectionFrames:sectionFrames,taskFrames:taskFrames) == BankDropDestination(categoryID:personal.id,before:legacy.id), "An expanded section header accepts insertion at the start of that category")
        check(BankSectionDropLayout.destination(at:CGPoint(x:50,y:100),sections:[sectionA,sectionB],sectionFrames:sectionFrames,taskFrames:taskFrames) == BankDropDestination(categoryID:personal.id,before:secondProject.id), "Task midpoints choose insertion within the correct category")
        check(BankSectionDropLayout.destination(at:CGPoint(x:50,y:180),sections:[sectionA,sectionB],sectionFrames:sectionFrames,taskFrames:taskFrames) == BankDropDestination(categoryID:project.id,before:nil), "Empty categories accept task drops")
        check(BankSectionDropLayout.destination(at:CGPoint(x:50,y:20),sections:[sectionA,sectionB],sectionFrames:sectionFrames,taskFrames:[:]) == BankDropDestination(categoryID:personal.id,before:nil), "Collapsed categories accept an append drop without exposing hidden tasks")
        check(BankSectionDropLayout.destination(at:CGPoint(x:50,y:300),sections:[sectionA,sectionB],sectionFrames:sectionFrames,taskFrames:taskFrames).categoryID == project.id, "Creation-area drops append to the final category")
        let delayedFolder = root.appendingPathComponent("delayed-category-download")
        let delayed = EventBankStore(folder:delayedFolder,watch:false)
        var delayedTask = BankTask(title:"Waiting for category",minutes:20,calendarID:"work",calendarTitle:"Work",account:"Preview",categoryID:personal.id)
        delayedTask.position = 0
        try delayed.save(delayedTask)
        check(delayed.sections.first?.tasks.first?.id == delayedTask.id, "Tasks remain accessible while their category metadata is still downloading")
        let files = try FileManager.default.contentsOfDirectory(at:movedCategoryFolder.appendingPathComponent("category-records"),includingPropertiesForKeys:nil)
        for file in files { try FileManager.default.copyItem(at:file,to:delayedFolder.appendingPathComponent("category-records").appendingPathComponent(file.lastPathComponent)) }
        delayed.refresh()
        check(delayed.categoryID(for:delayed.records[delayedTask.id]!) == personal.id, "Arriving category metadata automatically restores task grouping")
        return count
    }
}
