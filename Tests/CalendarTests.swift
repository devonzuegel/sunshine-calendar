import Foundation
import AppKit

@main struct CalendarTests {
    @MainActor static func main() {
        var count = 0
        func check(_ condition: @autoclosure () -> Bool, _ label: String) {
            precondition(condition(), label); count += 1
        }
        check(CalendarMath.snappedMinutes(64) == 60, "One hour drag")
        check(CalendarMath.snappedMinutes(-64) == -60, "Negative drag")
        check(CalendarMath.snappedMinutes(9) == 15, "Quarter hour snapping")
        check(CalendarMath.snappedMinutes(3) == 0, "Small drag snaps to zero")
        let testRoot = FileManager.default.temporaryDirectory.appendingPathComponent("calendar-studio-tests-"+UUID().uuidString,isDirectory:true)
        defer { try? FileManager.default.removeItem(at:testRoot) }
        let bank = EventBankStore(folder:testRoot,watch:false)
        let model = CalendarModel(bank:bank,reconnectIfAuthorized:false)
        model.selected = ["one", "two"]
        let original = model.selection.sorted { $0.start < $1.start }
        check(original.count == 2, "Both sample events visible")
        model.move(minutes:60)
        let moved = model.selection.sorted { $0.start < $1.start }
        check(moved.count == 2, "Selection preserved after move")
        for index in 0..<2 {
            check(moved[index].start == original[index].start.addingTimeInterval(3600), "Group start shifted equally")
            check(moved[index].end.timeIntervalSince(moved[index].start) == original[index].end.timeIntervalSince(original[index].start), "Duration preserved")
        }
        check(moved[1].start.timeIntervalSince(moved[0].start) == original[1].start.timeIntervalSince(original[0].start), "Spacing preserved")
        model.undo()
        check(model.selection.sorted { $0.start < $1.start }.map(\.start) == original.map(\.start), "Undo restores group")
        model.redo()
        check(model.selection.sorted { $0.start < $1.start }.map(\.start) == moved.map(\.start), "Redo restores group move")
        model.selected = ["one"]
        model.move(minutes:1440)
        check(model.entries.first { $0.id == "one" }!.start == original[0].start.addingTimeInterval(25*3600), "Cross-day shift")
        model.undo()
        model.selected = ["one", "four"]
        let before = model.entries.first { $0.id == "one" }!.start
        // The subscribed event can fall outside the week on the first day; validate when present.
        if model.selection.contains(where: { !$0.writable }) {
            model.move(minutes:60)
            check(model.entries.first { $0.id == "one" }!.start == before, "Mixed read-only selection is not partly moved")
        }
        let base = Date(timeIntervalSince1970:0)
        func interval(_ id: String,_ start: Double,_ end: Double) -> TimedInterval { TimedInterval(id:id,start:base.addingTimeInterval(start),end:base.addingTimeInterval(end)) }
        let layout = OverlapLayout.columns([interval("a",0,100),interval("b",50,150),interval("c",100,200),interval("d",200,300)])
        check(layout["a"]!.count == 2 && layout["c"]!.count == 2, "Overlap chain uses two columns")
        check(layout["a"]!.column == layout["c"]!.column, "Column reused when previous event ends")
        check(layout["d"]!.count == 1, "Touching event starts new overlap group")
        check(OverlapLayout.columns([interval("a",0,100),interval("b",0,100),interval("c",0,100)])["a"]!.count == 3, "Three simultaneous events")
        check(OverlapLayout.columns([]).isEmpty, "Empty layout")
        // Six truly concurrent events each need a separate lane.
        let stacked = OverlapLayout.columns([
            interval("early1",0,3600), interval("early2",0,3600), interval("early3",0,3600),
            interval("later1",1800,5400), interval("later2",1800,5400), interval("later3",1800,5400)
        ])
        check(stacked.values.allSatisfy { $0.count == 6 }, "All concurrent events receive separate lanes")
        check(stacked["later1"]!.column == 3, "Later events cannot cover active earlier events")
        let adjacent = OverlapLayout.columns([interval("a",0,1800),interval("b",1800,3600)])
        check(adjacent.values.allSatisfy { $0.count == 1 && $0.span == 1 }, "Nonoverlapping events keep full width without inset")
        let mixed = [interval("green1",0,60),interval("teal1",40,100),interval("green2",60,90),interval("green3",90,120)]
        let mixedLayout = OverlapLayout.columns(mixed)
        check(["green1","green2","green3"].allSatisfy { mixedLayout[$0]!.column == 0 }, "Successive events reuse the left edge instead of stair-stepping")
        let expanded = OverlapLayout.columns([interval("long",0,300),interval("a",0,60),interval("b",0,60),interval("later",60,120)])
        check(expanded["later"]!.column == 1 && expanded["later"]!.span == 2, "Events expand into unoccupied neighboring lanes")
        for first in mixed {
            for second in mixed where first.id != second.id && first.start < second.end && first.end > second.start {
                let a = mixedLayout[first.id]!, b = mixedLayout[second.id]!
                check(a.column+a.span <= b.column || b.column+b.span <= a.column, "Simultaneous events never cover one another")
            }
        }
        var swipe = DayScrollGesture()
        check(swipe.consume(x:-10,y:1,time:0,began:true).days == 0, "Small horizontal movement waits for intent")
        check(swipe.consume(x:-24,y:0,time:0.01).days == 1, "Leftward content swipe reveals next day")
        check(swipe.consume(x:-120,y:0,time:0.02).days == 0, "Long gesture advances only one day")
        check(swipe.consume(x:-120,y:0,time:0.03,momentum:true).days == 0, "Momentum does not skip days")
        check(swipe.consume(x:40,y:1,time:0.1,began:true).days == -1, "Reverse swipe reveals previous day")
        check(swipe.consume(x:-40,y:0,time:0.2,began:true).days == 1, "New gesture can advance again immediately")
        var vertical = DayScrollGesture()
        check(!vertical.consume(x:2,y:20,time:0,began:true).horizontal, "Vertical scroll remains native")
        check(!vertical.consume(x:90,y:1,time:0.01).horizontal, "Vertical gesture does not suddenly navigate dates")
        check(vertical.consume(x:-40,y:0,time:0.1,began:true).days == 1, "New horizontal gesture resets vertical lock")
        var wheel = DayScrollGesture()
        check(wheel.consume(x:-10,y:0,time:0,precise:false).days == 1, "Horizontal wheel supports smaller discrete deltas")
        check(wheel.consume(x:-10,y:0,time:0.4,precise:false).days == 1, "Separate wheel bursts each advance one day")
        var jitter = DayScrollGesture()
        check(jitter.consume(x:2,y:1,time:0,began:true).days == 0, "Tiny diagonal jitter does not navigate")
        let initialStart = model.weekStart
        model.navigateDays(1)
        check(Calendar.current.dateComponents([.day],from:initialStart,to:model.weekStart).day == 1, "Visible range advances exactly one day without snapping to a week")
        check(Calendar.current.dateComponents([.day],from:model.weekStart,to:model.weekEnd).day == 7, "View keeps seven days")
        model.navigateDays(-1)
        check(model.weekStart == initialStart, "Opposite swipe restores range")
        let novemberEnd = Calendar.current.date(from:DateComponents(year:2026,month:11,day:30))!
        model.jump(to:novemberEnd); model.navigateDays(1)
        check(Calendar.current.component(.month,from:model.weekStart) == 12 && Calendar.current.component(.day,from:model.weekStart) == 1, "One-day navigation crosses month boundaries")
        let fallBack = Calendar.current.date(from:DateComponents(year:2026,month:11,day:1))!
        model.jump(to:fallBack); model.navigateDays(1)
        check(Calendar.current.component(.day,from:model.weekStart) == 2 && Calendar.current.component(.hour,from:model.weekStart) == 0, "Day navigation stays at midnight across daylight saving time")
        model.navigate(1)
        check(Calendar.current.component(.day,from:model.weekStart) == 9, "Week buttons still navigate seven days from current range")
        let nativeStart = model.weekStart
        let scrollView = FittingScrollView(frame:NSRect(x:0,y:0,width:900,height:600))
        let canvas = CalendarCanvas(model:model)
        canvas.frame = NSRect(x:0,y:0,width:900,height:1800)
        scrollView.documentView = canvas
        scrollView.onDayNavigation = { days in model.navigateDays(days) }
        let wheelEvent = CGEvent(scrollWheelEvent2Source:nil,units:.pixel,wheelCount:2,wheel1:0,wheel2:-80,wheel3:0)!
        let nativeEvent = NSEvent(cgEvent:wheelEvent)!
        canvas.scrollWheel(with:nativeEvent)
        check(Calendar.current.dateComponents([.day],from:nativeStart,to:model.weekStart).day == 1, "Native scroll event travels from canvas through scroll view to day navigation")
        canvas.scrollWheel(with:nativeEvent)
        check(Calendar.current.dateComponents([.day],from:nativeStart,to:model.weekStart).day == 1, "Repeated native events in the same gesture do not skip extra days")
        var pacific = Calendar(identifier:.gregorian)
        pacific.timeZone = TimeZone(identifier:"America/Los_Angeles")!
        let november = pacific.date(from:DateComponents(year:2026,month:11,day:12))!
        let sf = SunCoordinate(latitude:37.7749,longitude:-122.4194)
        let nights = DaylightMath.nightRanges(on:november,coordinate:sf,calendar:pacific)
        check(nights.count == 2 && nights[0].lowerBound == 0 && nights[1].upperBound == 1440, "Night shading covers both ends of a local day")
        check(abs(nights[0].upperBound - 408) < 6 && abs(nights[1].lowerBound - 1018) < 6, "San Francisco November sunrise and sunset fall near 6:48am and 4:58pm")
        let summer = pacific.date(from:DateComponents(year:2026,month:6,day:21))!
        let summerNights = DaylightMath.nightRanges(on:summer,coordinate:sf,calendar:pacific)
        check(summerNights[0].upperBound < nights[0].upperBound && summerNights[1].lowerBound > nights[1].lowerBound, "Daylight expands in summer including daylight saving time")
        var arctic = Calendar(identifier:.gregorian); arctic.timeZone = TimeZone(identifier:"Europe/Oslo")!
        let north = SunCoordinate(latitude:78.22,longitude:15.65)
        let polarSummer = arctic.date(from:DateComponents(year:2026,month:6,day:21))!
        let polarWinter = arctic.date(from:DateComponents(year:2026,month:12,day:21))!
        check(DaylightMath.nightRanges(on:polarSummer,coordinate:north,calendar:arctic).isEmpty, "Midnight sun has no nighttime shading")
        check(DaylightMath.nightRanges(on:polarWinter,coordinate:north,calendar:arctic) == [0.0...1440.0], "Polar night shades the entire day")
        var tokyo = Calendar(identifier:.gregorian); tokyo.timeZone = TimeZone(identifier:"Asia/Tokyo")!
        let tokyoDay = tokyo.date(from:DateComponents(year:2026,month:11,day:12))!
        let shifted = DaylightMath.nightRanges(on:tokyoDay,coordinate:sf,calendar:tokyo)
        check(shifted.count == 1 && shifted[0].lowerBound > 500 && shifted[0].upperBound < 1440, "A different display timezone correctly puts San Francisco night in the middle of the grid")
        for day in [8,9] {
            let march = pacific.date(from:DateComponents(year:2026,month:3,day:day))!
            let ranges = DaylightMath.nightRanges(on:march,coordinate:sf,calendar:pacific)
            check(ranges.count == 2 && ranges.allSatisfy { $0.lowerBound >= 0 && $0.upperBound <= 1440 }, "DST transition uses valid wall-clock daylight ranges")
        }
        check(CalendarMath.creationRange(from:64,to:160) == 60...150, "Forward drag selects a snapped 90-minute span")
        check(CalendarMath.creationRange(from:160,to:64) == 60...150, "Backward drag selects the same time span")
        check(CalendarMath.creationRange(from:0,to:1) == 0...15, "Creation has a 15-minute minimum")
        check(CalendarMath.creationRange(from:1530,to:1700) == 1425...1440, "Creation clamps at midnight")
        let creationModel = CalendarModel(bank:bank,reconnectIfAuthorized:false)
        let creationCanvas = CalendarCanvas(model:creationModel)
        creationCanvas.frame = NSRect(x:0,y:0,width:900,height:1800)
        func mouse(_ type: NSEvent.EventType, _ point: NSPoint) -> NSEvent {
            NSEvent.mouseEvent(with:type,location:creationCanvas.convert(point,to:nil),modifierFlags:[],timestamp:0,windowNumber:0,context:nil,eventNumber:0,clickCount:1,pressure:0)!
        }
        let begin = NSPoint(x:100,y:48+9*64)
        let finish = NSPoint(x:100,y:48+10.5*64)
        creationCanvas.mouseDown(with:mouse(.leftMouseDown,begin))
        creationCanvas.mouseUp(with:mouse(.leftMouseUp,begin))
        check(creationModel.draft == nil, "Single click on empty time does not create an event")
        let originalCount = creationModel.entries.count
        creationCanvas.mouseDown(with:mouse(.leftMouseDown,begin))
        creationCanvas.mouseDragged(with:mouse(.leftMouseDragged,finish))
        creationCanvas.mouseUp(with:mouse(.leftMouseUp,finish))
        check(creationModel.draft?.end.timeIntervalSince(creationModel.draft!.start) == 90*60, "Native empty-slot drag opens an editor with the chosen duration")
        check(creationModel.entries.count == originalCount, "Dragging a new event does not save before editor confirmation")
        creationModel.draft = nil
        creationCanvas.mouseDown(with:mouse(.leftMouseDown,finish))
        creationCanvas.mouseDragged(with:mouse(.leftMouseDragged,begin))
        creationCanvas.mouseUp(with:mouse(.leftMouseUp,begin))
        check(creationModel.draft?.end.timeIntervalSince(creationModel.draft!.start) == 90*60, "Reverse native drag creates the same duration")
        creationModel.newEvent(at:november,durationMinutes:30)
        check(creationModel.draft?.end.timeIntervalSince(november) == 1800, "New Task drop creates a 30-minute editable draft")
        let deletionModel = CalendarModel(bank:bank,reconnectIfAuthorized:false)
        deletionModel.jump(to:Calendar.current.startOfDay(for:Date()).addingTimeInterval(-86400))
        deletionModel.selected = ["one","four"]
        let undeleted = Set(deletionModel.entries.map(\.id))
        check(!deletionModel.deleteSelectedEvents() && Set(deletionModel.entries.map(\.id)) == undeleted, "Read-only member prevents any deletion in a mixed group")
        deletionModel.selected = ["one","two"]
        check(deletionModel.deleteSelectedEvents(), "Selected editable events can be deleted together")
        check(!deletionModel.entries.contains(where:{ ["one","two"].contains($0.id) }) && deletionModel.entries.contains(where:{ $0.id == "three" }), "Deletion removes only selected events")
        check(deletionModel.selected.isEmpty && deletionModel.undoChanges.isEmpty, "Deletion clears stale selection and move history")
        check(!deletionModel.deleteSelectedEvents(), "Empty selection cannot delete anything")
        let deleteCanvas = CalendarCanvas(model:deletionModel)
        deletionModel.selected = ["three"]
        let deleteKey = NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[],timestamp:0,windowNumber:0,context:nil,characters:"\u{7f}",charactersIgnoringModifiers:"\u{7f}",isARepeat:false,keyCode:51)!
        deleteCanvas.keyDown(with:deleteKey)
        check(!deletionModel.entries.contains(where:{ $0.id == "three" }), "Delete key on the calendar removes the selected event")
        let allDayBase = pacific.date(from:DateComponents(year:2026,month:11,day:8))!
        func allDayDate(_ offset: Int) -> Date { pacific.date(byAdding:.day,value:offset,to:allDayBase)! }
        let bars = AllDayLayout.spans([
            TimedInterval(id:"whole-week",start:allDayDate(-2),end:allDayDate(9)),
            TimedInterval(id:"trip",start:allDayDate(1),end:allDayDate(3)),
            TimedInterval(id:"next-trip",start:allDayDate(3),end:allDayDate(6)),
            TimedInterval(id:"outside",start:allDayDate(7),end:allDayDate(8))
        ],weekStart:allDayBase,calendar:pacific)
        check(bars.count == 3, "Multi-day all-day events create one bar each, excluding next week")
        check(bars.first(where:{ $0.id == "whole-week" })!.firstDay == 0 && bars.first(where:{ $0.id == "whole-week" })!.endDay == 7, "Continuous bar clips cleanly to visible week")
        let trip = bars.first(where:{ $0.id == "trip" })!, nextTrip = bars.first(where:{ $0.id == "next-trip" })!
        check(trip.firstDay == 1 && trip.endDay == 3, "All-day exclusive end does not paint an extra day")
        check(trip.row == nextTrip.row && trip.row != bars[0].row, "Touching trips reuse a row while simultaneous bars remain separate")
        do { count += try EventBankTests.run() } catch { fatalError("Event bank checks failed: \(error)") }
        print("Passed \(count) calendar behavior checks.")
    }
}
