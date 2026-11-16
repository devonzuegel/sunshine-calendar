import Foundation
import AppKit
import EventKit
import SwiftUI

@main struct CalendarTests {
    @MainActor static func main() async {
        var count = 0
        count += try! PerformanceTests.run()
        func check(_ condition: @autoclosure () -> Bool, _ label: String) {
            precondition(condition(), label); count += 1
        }
        do {
            var calendar = Calendar(identifier:.gregorian)
            calendar.timeZone = TimeZone(identifier:"America/Los_Angeles")!
            func day(_ month: Int, _ day: Int) -> Date { calendar.date(from:DateComponents(year:2026,month:month,day:day))! }
            var event = EventDraft(start:day(12,4),end:day(12,5),allDay:true)
            check(event.displayedEndDate(calendar:calendar) == day(12,4), "An existing one-day all-day event displays its actual last included day")
            let oldEnd = event.end
            event.setDisplayedEndDate(event.displayedEndDate(calendar:calendar),calendar:calendar)
            check(event.end == oldEnd, "Opening and saving all-day dates does not extend existing events")
            event.setDisplayedEndDate(day(12,5),calendar:calendar)
            check(event.end == day(12,6), "Choosing December 5 as the inclusive end stores December 6 for EventKit")
            let span = AllDayLayout.spans([TimedInterval(id:"december",start:event.start,end:event.end)],weekStart:day(12,4),calendar:calendar,dayCount:7)
            check(span.first?.firstDay == 0 && span.first?.endDay == 2, "December 4 through December 5 draws across both calendar columns")
            check(event.displayedEndDate(calendar:calendar) == day(12,5), "A two-day event reloads with the same inclusive end date")
            event.start = day(3,8); event.setDisplayedEndDate(day(3,8),calendar:calendar)
            check(event.end == day(3,9) && event.end.timeIntervalSince(event.start) == 23*3600, "Inclusive all-day ends use calendar days across spring daylight saving")
            event.start = day(11,1); event.setDisplayedEndDate(day(11,1),calendar:calendar)
            check(event.end == day(11,2) && event.end.timeIntervalSince(event.start) == 25*3600, "Inclusive all-day ends use calendar days across autumn daylight saving")
            event.allDay = false
            let timedEnd = day(12,5).addingTimeInterval(17*3600)
            event.setDisplayedEndDate(timedEnd,calendar:calendar)
            check(event.end == timedEnd && event.displayedEndDate(calendar:calendar) == timedEnd, "Timed events retain their exact end time")
        }
        check(CalendarReadOnlyReason.resolve(type:.subscription,subscribed:false,account:"Holidays") == .subscription, "Subscribed calendar types explain their external feed")
        check(CalendarReadOnlyReason.resolve(type:.calDAV,subscribed:true,account:"Google") == .subscription, "CalDAV subscriptions are recognized as feeds rather than shared permissions")
        check(CalendarReadOnlyReason.resolve(type:.birthday,subscribed:false,account:"Contacts") == .birthdays && CalendarReadOnlyReason.birthdays.explanation.contains("Contacts"), "Birthday calendars explain that changes belong in Contacts")
        check(CalendarReadOnlyReason.resolve(type:.calDAV,subscribed:false,account:"Family - SHARED") == .accountAccess("Family - SHARED"), "Calendar titles do not cause guessed sharing or subscription reasons")
        check(CalendarReadOnlyReason.resolve(type:.exchange,subscribed:false,account:"Work") == .accountAccess("Work"), "Exchange calendars retain their account-specific explanation")
        check(CalendarReadOnlyReason.resolve(type:.local,subscribed:false,account:"") == .unspecified && CalendarReadOnlyReason.unspecified.explanation.contains("doesn’t provide"), "Unavailable read-only reasons are explicitly identified as unknown")
        check(CalendarReadOnlyReason.accountAccess("Google").explanation.contains("macOS doesn’t say"), "Account permissions explain the limits of macOS permission metadata")
        do {
            let panel = NSPopover()
            let fixture = PopoverResizeFixture()
            let controller = StablePopoverController(content:PopoverResizeFixtureView(fixture:fixture),popover:panel)
            panel.contentViewController = controller
            let window = NSWindow(contentRect:NSRect(x:0,y:0,width:320,height:200),styleMask:.borderless,backing:.buffered,defer:false)
            window.contentView = controller.view
            controller.view.layoutSubtreeIfNeeded()
            try? await Task.sleep(nanoseconds:30_000_000)
            check(controller.hosting.sizingOptions == [.intrinsicContentSize], "Editor popovers disable automatic hosting-window resizing and use a plain AppKit controller")
            let originalSize = controller.appliedSize
            fixture.height = 240
            controller.requestSize(CGSize(width:320,height:240))
            fixture.height = 280
            controller.requestSize(CGSize(width:320,height:280))
            check(controller.appliedSize == originalSize, "Popover resize requests do not resize synchronously during a layout callback")
            try? await Task.sleep(nanoseconds:20_000_000)
            check(controller.appliedSize == CGSize(width:320,height:280), "Multiple layout changes coalesce to the latest measured editor size")
            for index in 0..<40 {
                fixture.height = CGFloat(200+index%5*20)
                controller.requestSize(CGSize(width:320,height:fixture.height))
                controller.view.layoutSubtreeIfNeeded()
                try? await Task.sleep(nanoseconds:2_000_000)
            }
            check(controller.appliedSize.width == 320 && controller.resizingEnabled, "Repeated editor size changes remain stable without recursive window sizing")
            fixture.height = 340
            controller.hosting.needsLayout = true
            controller.hosting.layoutSubtreeIfNeeded()
            if let bitmap = controller.hosting.bitmapImageRepForCachingDisplay(in:controller.hosting.bounds) { controller.hosting.cacheDisplay(in:controller.hosting.bounds,to:bitmap) }
            try? await Task.sleep(nanoseconds:30_000_000)
            check(controller.appliedSize == CGSize(width:320,height:340), "Natural content growth is measured without automatic hosting-window sizing")
            let beforeClose = controller.appliedSize
            controller.requestSize(CGSize(width:320,height:600))
            controller.stopResizing()
            controller.requestSize(CGSize(width:320,height:700))
            try? await Task.sleep(nanoseconds:20_000_000)
            check(!controller.resizingEnabled && controller.appliedSize == beforeClose, "Closing an editor cancels queued size changes and ignores late focus-layout callbacks")
            check(StablePopoverController.validSize(CGSize(width:CGFloat.infinity,height:200)) == nil && StablePopoverController.validSize(.zero) == nil, "Invalid layout measurements cannot resize a popover window")
        }
        do {
            var calendar = Calendar(identifier:.gregorian); calendar.timeZone = TimeZone(identifier:"America/Los_Angeles")!
            let reference = calendar.date(from:DateComponents(year:2026,month:11,day:15))!
            let december11 = calendar.date(from:DateComponents(year:2026,month:12,day:11))!
            for input in ["12/11","12-11","Dec 11","dec11","DECEMBER11","11 Dec","11dec","Dec 11th","  dec11  ","Dec. 11"] {
                check(DateJumpParser.parse(input,reference:reference,calendar:calendar) == december11, "Flexible date jump parses \(input) as December 11")
            }
            let nextYear = calendar.date(from:DateComponents(year:2027,month:12,day:11))!
            for input in ["12/11/2027","12/11/27","Dec 11, 2027","11 December 2027","2027-12-11"] {
                check(DateJumpParser.parse(input,reference:reference,calendar:calendar) == nextYear, "Date jump respects an explicit year in \(input)")
            }
            for input in ["","whatevs","2/30","13/11","Dec 32","Feb 29, 2026","Dec 11 extra"] {
                check(DateJumpParser.parse(input,reference:reference,calendar:calendar) == nil, "Invalid date jump input is rejected: \(input)")
            }
            check(DateJumpParser.parse("today",reference:reference,calendar:calendar) == reference, "Date jump understands today")
            check(DateJumpParser.parse("tomorrow",reference:reference,calendar:calendar) == calendar.date(byAdding:.day,value:1,to:reference), "Date jump understands tomorrow")
            check(DateJumpParser.parse("yesterday",reference:reference,calendar:calendar) == calendar.date(byAdding:.day,value:-1,to:reference), "Date jump understands yesterday")
            check(DateJumpParser.parse("Feb29 2028",reference:reference,calendar:calendar) == calendar.date(from:DateComponents(year:2028,month:2,day:29)), "Date jump accepts valid leap days")
        }
        do {
            let session = DateJumpSession()
            var calendar = Calendar(identifier:.gregorian); calendar.timeZone = TimeZone(identifier:"America/Los_Angeles")!
            let reference = calendar.date(from:DateComponents(year:2026,month:11,day:15))!
            session.reset(calendar:calendar,reference:reference)
            session.query = "dec11"
            check(session.result == calendar.date(from:DateComponents(year:2026,month:12,day:11)), "Date palette stores the parsed result when input changes")
            session.query = "not a date"
            check(session.result == nil, "Invalid palette input clears a previously valid result")
            let previousGeneration = session.generation
            session.reset(calendar:calendar,reference:reference)
            check(session.query.isEmpty && session.result == nil && session.generation != previousGeneration, "Reopening the cached palette starts a fresh focused input session")
            let presenter = DateJumpPresenter()
            presenter.prepare()
            let firstPanel = presenter.panel
            presenter.prepare()
            check(firstPanel === presenter.panel && presenter.panel?.isVisible == false, "The palette reuses its prepared window without showing or rebuilding it")
            check(DateJumpParser.parse(String(repeating:"a",count:1000),reference:reference,calendar:calendar) == nil, "Oversized pasted input does not perform expensive date parsing")
        }
        let pickerSources = [
            CalendarSource(id:"gmail-health",title:"Health 👟",account:"DevonZuegel@gmail.com",color:.systemPink,writable:true),
            CalendarSource(id:"google-elc",title:"Devon ELC",account:"Google",color:.systemGreen,writable:false),
            CalendarSource(id:"gmail-elc",title:"Devon ELC",account:"DevonZuegel@gmail.com",color:.systemTeal,writable:true),
            CalendarSource(id:"icloud-misc",title:"Misc",account:"iCloud",color:.systemPurple,writable:true),
            CalendarSource(id:"gmail-uber",title:"Über plans",account:"DevonZuegel@gmail.com",color:.systemBlue,writable:true)
        ]
        let pickerAccounts = CalendarPickerAccount.sections(pickerSources)
        check(pickerAccounts.map(\.title) == ["DevonZuegel@gmail.com","Google","iCloud"], "Calendar picker groups calendars under a single heading for each account")
        check(pickerAccounts[0].sources.map(\.id) == ["gmail-elc","gmail-health","gmail-uber"], "Calendar names are sorted within their account")
        check(CalendarPickerAccount.sections(pickerSources,query:"ELC").flatMap(\.sources).map(\.id) == ["gmail-elc","google-elc"], "Duplicate calendar names remain distinct choices across accounts")
        check(CalendarPickerAccount.sections(pickerSources,query:"GMAIL").first?.sources.count == 3, "Calendar search matches account names without case sensitivity")
        check(CalendarPickerAccount.sections(pickerSources,query:"uber").flatMap(\.sources).map(\.id) == ["gmail-uber"], "Calendar search matches names with diacritics")
        check(CalendarPickerAccount.sections(pickerSources,query:"google elc").flatMap(\.sources).map(\.id) == ["google-elc"], "Search terms can combine calendar and account names")
        check(CalendarPickerAccount.sections(pickerSources,query:"  \n ").flatMap(\.sources).count == pickerSources.count, "Whitespace-only search keeps all calendars available")
        check(CalendarPickerAccount.sections(pickerSources,query:"no such calendar").isEmpty && CalendarPickerAccount.sections([]).isEmpty, "Empty and unmatched calendar lists remain empty")
        check(pickerAccounts[1].sources[0].color == pickerSources[1].color && !pickerAccounts[1].sources[0].writable, "Calendar grouping preserves original colors and caller-provided permissions")
        let unnamedAccount = CalendarSource(id:"no-account",title:"Calendar",account:"",color:.gray,writable:true)
        check(CalendarPickerAccount.sections([unnamedAccount],query:"other").first?.title == "Other calendars", "Unnamed accounts have a searchable, readable heading")
        let textPreferenceName = "calendar-text-size-tests-"+UUID().uuidString
        let textPreferences = UserDefaults(suiteName:textPreferenceName)!
        defer { textPreferences.removePersistentDomain(forName:textPreferenceName) }
        let textSize = AppTextSize(preferences:textPreferences)
        func textKey(_ characters: String, _ modifiers: NSEvent.ModifierFlags = .command) -> NSEvent {
            NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:modifiers,timestamp:0,windowNumber:0,context:nil,characters:characters,charactersIgnoringModifiers:characters,isARepeat:false,keyCode:0)!
        }
        check(textSize.handleShortcut(textKey("-")) && textSize.scale == 0.9, "Command-minus reduces app text size")
        check(textSize.handleShortcut(textKey("+",[.command,.shift])) && textSize.scale == 1, "Command-plus increases app text size")
        check(textSize.handleShortcut(textKey("=")) && textSize.scale == 1.1, "Command-equals also increases text without Shift")
        check(!textSize.handleShortcut(textKey("z")) && !textSize.handleShortcut(textKey("-",[])), "Text sizing leaves undo and ordinary typing alone")
        check(!textSize.handleShortcut(textKey("+",[.command,.option])), "Text sizing preserves other modified shortcuts")
        check(AppTextSize(preferences:textPreferences).scale == 1.1, "Text size preference survives reopening")
        for _ in 0..<20 { textSize.adjust(1) }
        check(textSize.scale == AppTextSize.maximum, "Larger text is bounded")
        for _ in 0..<20 { textSize.adjust(-1) }
        check(textSize.scale == AppTextSize.minimum, "Smaller text is bounded")
        check(textSize.handleShortcut(textKey("0")) && textSize.scale == 1, "Command-zero resets text size")
        let graphWeather = WeatherOverlay()
        for layer in WeatherOverlay.GraphLayer.allCases {
            graphWeather.selectGraphLayer(layer,exclusively:true)
            let flags = [graphWeather.showSky,graphWeather.showTemperature,graphWeather.showUV,graphWeather.showRain,graphWeather.showWind]
            check(flags.filter { $0 }.count == 1, "Shift-click leaves exactly one weather layer visible")
            graphWeather.selectGraphLayer(layer,exclusively:false)
            check(![graphWeather.showSky,graphWeather.showTemperature,graphWeather.showUV,graphWeather.showRain,graphWeather.showWind].contains(true), "Normal click toggles the isolated layer off")
            graphWeather.selectGraphLayer(layer,exclusively:true)
            graphWeather.selectGraphLayer(layer,exclusively:true)
            check([graphWeather.showSky,graphWeather.showTemperature,graphWeather.showUV,graphWeather.showRain,graphWeather.showWind].allSatisfy { $0 }, "Shift-clicking the isolated layer restores every layer")
        }
        check(CalendarMath.snappedMinutes(64) == 60, "One hour drag")
        check(CalendarMath.snappedMinutes(-64) == -60, "Negative drag")
        check(CalendarMath.snappedMinutes(9) == 10, "Default grid rounds to the nearest five minutes")
        check(CalendarMath.snappedMinutes(2) == 0, "Tiny drag snaps to zero")
        check(CalendarViewMode.year.cycled(by:1) == .day, "View cycling wraps forward")
        check(CalendarViewMode.day.cycled(by:-1) == .year, "View cycling wraps backward")
        check(CalendarViewMode.week.cycled(by:1) == .month, "View cycling goes directly from week to standard month")
        check(CalendarViewMode.fiveDays.cycled(by:1) == .sixDays && CalendarViewMode.sixDays.cycled(by:1) == .week, "View cycling includes six days between five days and the full week")
        check(DaySwipeMath.jumpDistance(days:1,dayWidth:120,viewportWidth:840) == 120 && DaySwipeMath.jumpDistance(days:-2,dayWidth:120,viewportWidth:840) == -240, "Nearby date jumps slide the correct number of day columns in either direction")
        check(DaySwipeMath.jumpDistance(days:365,dayWidth:120,viewportWidth:840) == 840 && DaySwipeMath.jumpDistance(days:-365,dayWidth:120,viewportWidth:840) == -840, "Distant date jumps slide one viewport without traversing blank months")
        check(DaySwipeMath.jumpDistance(days:0,dayWidth:120,viewportWidth:840) == 0, "Jumping to the current visible date has no horizontal movement")
        let sharedJump = CalendarDateJump(from:Date(timeIntervalSince1970:0),to:Date(timeIntervalSince1970:259200),days:3,progress:0.5)
        check(sharedJump.offsets(dayWidth:120,viewportWidth:840).before == -180 && sharedJump.offsets(dayWidth:120,viewportWidth:840).after == 180, "Date headings and body use the same two-strip offsets at an intermediate jump frame")

        check(DaySwipeMath.jumpDuration(days:1) == DaySwipeMath.navigationDuration && DaySwipeMath.jumpDuration(days:365) <= 0.36 && DaySwipeMath.jumpDuration(days:-365) == DaySwipeMath.jumpDuration(days:365), "Date jumps stay quick and have symmetric bounded animation duration")
        check(DaySwipeMath.snapOffset(from:30,to:0,progress:0) == 30, "Snap begins at the finger release position")
        check(DaySwipeMath.snapOffset(from:-90,to:-120,progress:1) == -120, "Snap ends exactly on the day boundary")
        let snapPositions = (0...20).map { DaySwipeMath.snapOffset(from:30,to:0,progress:Double($0)/20) }
        check(zip(snapPositions,snapPositions.dropFirst()).allSatisfy { $0 >= $1 && $1 >= 0 }, "Snap moves monotonically without overshoot")
        var precisePan = TrackpadDayGesture()
        let firstPan = precisePan.consume(x:-1,y:0,phase:.began)
        check(firstPan.handled && firstPan.delta == -1.6 && precisePan.isTracking, "Horizontal trackpad input responds immediately with the faster gain")
        check(precisePan.consume(x:2,y:0,phase:.changed).delta == 3.2, "Gesture reversal preserves direction and the same gain")
        let releasePan = precisePan.consume(x:0,y:0,phase:.ended)
        check(releasePan.finished && !releasePan.cancelled && !precisePan.isTracking, "A release finishes one horizontal pan")
        let coastPan = precisePan.consume(x:-80,y:6,phase:[],momentum:.changed)
        check(coastPan.handled && coastPan.delta == 0 && !coastPan.finished, "Momentum after a horizontal release is consumed without moving additional days or scrolling vertically")
        check(precisePan.consume(x:0,y:0,phase:[],momentum:.ended).handled && !precisePan.swallowingMomentum, "The horizontal momentum guard ends with the momentum sequence")
        check(!precisePan.consume(x:0,y:8,phase:.began).handled, "A new vertical gesture remains normal vertical scrolling")
        check(!precisePan.consume(x:1,y:30,phase:.changed).handled, "Vertical gestures stay vertical despite horizontal jitter")
        var cancelledPan = TrackpadDayGesture()
        _ = cancelledPan.consume(x:4,y:0,phase:.began)
        check(cancelledPan.consume(x:0,y:0,phase:.cancelled).cancelled && !cancelledPan.isTracking && !cancelledPan.swallowingMomentum, "Cancelling a horizontal gesture clears tracking and momentum state")
        var ambiguousPan = TrackpadDayGesture()
        check(!ambiguousPan.consume(x:1,y:1,phase:.began).handled && ambiguousPan.consume(x:3,y:0,phase:.changed).handled, "Ambiguous diagonal movement can resolve into a horizontal gesture without locking vertically")
        check(DaySwipeMath.imageShifts(toward:-20) == [0,1] && DaySwipeMath.imageShifts(toward:20) == [-1,0], "Panning captures only the current view and the neighboring view being revealed")
        let imageDays = (-1...2).map { Date(timeIntervalSince1970:Double($0)*86400) }
        var snapshotCache = DaySwipeSnapshotCache<Int>()
        var snapshotRenders = 0
        func makeImage() -> Int? { snapshotRenders += 1; return snapshotRenders }
        _ = snapshotCache.image(for:imageDays[1],render:makeImage)
        _ = snapshotCache.image(for:imageDays[2],render:makeImage)
        check(snapshotRenders == 2, "A pan starts with two snapshots instead of three")
        snapshotCache.retain(Set([imageDays[1],imageDays[2],imageDays[3]]))
        _ = snapshotCache.image(for:imageDays[2],render:makeImage)
        _ = snapshotCache.image(for:imageDays[3],render:makeImage)
        check(snapshotRenders == 3, "Crossing the next day reuses the neighboring snapshot and renders only one new view")
        _ = snapshotCache.image(for:imageDays[1],render:makeImage)
        check(snapshotRenders == 3, "Reversing into the previous cached day does not render it again")
        snapshotCache.retain(Set([imageDays[2],imageDays[3]]))
        _ = snapshotCache.image(for:imageDays[1],render:makeImage)
        check(snapshotRenders == 4, "Snapshots outside the retained neighborhood are evicted")
        snapshotCache.clear()
        _ = snapshotCache.image(for:imageDays[1],render:makeImage)
        check(snapshotRenders == 5, "Finishing or resizing a pan clears old snapshot images")
        let missingImage: Int? = snapshotCache.image(for:imageDays[0],render:{ nil })
        _ = snapshotCache.image(for:imageDays[0],render:makeImage)
        check(missingImage == nil && snapshotRenders == 6, "A failed snapshot can be retried rather than caching an empty view")
        let tooltipScreen = CGRect(x:0,y:0,width:1440,height:900)
        let toolbarTip = AppTooltipPlacement.frame(size:CGSize(width:260,height:55),hoverPoint:CGPoint(x:800,y:870),screen:tooltipScreen)
        check(toolbarTip.minX == 810 && toolbarTip.maxY == 858, "Toolbar tooltip stays beside the original hover point")
        let bottomTip = AppTooltipPlacement.frame(size:CGSize(width:260,height:55),hoverPoint:CGPoint(x:800,y:20),screen:tooltipScreen)
        check(bottomTip.minY == 36, "Tooltip flips above a hover near the screen bottom")
        let secondScreen = CGRect(x:-1440,y:200,width:1440,height:900)
        let secondTip = AppTooltipPlacement.frame(size:CGSize(width:260,height:55),hoverPoint:CGPoint(x:-50,y:1050),screen:secondScreen)
        check(secondScreen.contains(secondTip) && secondTip.maxX == -8, "Tooltip positioning respects secondary screen coordinates")
        let outdoorNow = Date(timeIntervalSince1970:0)
        func outdoorHour(_ hour: Double, rain: Double = 0, day: Bool = true, temperature: Double = 68) -> WeatherHour {
            WeatherHour(date:outdoorNow.addingTimeInterval(hour*3600),temperature:temperature,precipitation:rain,cloudCover:20,code:0,windSpeed:5,windDirection:0,isDay:day,precipitationProbability:10)
        }
        let outdoor = OutdoorWeatherWindow.best(hours:[outdoorHour(1,temperature:50),outdoorHour(2),outdoorHour(3)],now:outdoorNow)
        check(outdoor?.start == outdoorNow.addingTimeInterval(7200) && outdoor?.end == outdoorNow.addingTimeInterval(14400), "Outdoor window chooses the more comfortable contiguous two-hour stretch")
        check(OutdoorWeatherWindow.best(hours:[outdoorHour(1,rain:2),outdoorHour(2,rain:2)],now:outdoorNow) == nil, "Outdoor window excludes rainy stretches")
        check(OutdoorWeatherWindow.best(hours:[outdoorHour(1,day:false),outdoorHour(2,day:false)],now:outdoorNow) == nil, "Outdoor window excludes nighttime")
        check(OutdoorWeatherWindow.best(hours:[outdoorHour(1),outdoorHour(3)],now:outdoorNow) == nil, "Outdoor window cannot bridge missing forecast hours")
        check(OutdoorWeatherWindow.best(hours:[],now:outdoorNow) == nil, "Missing forecast does not invent an outdoor window")
        let temperatureExamples: [(Double,String)] = [(32,"0°C / 32°F"),(212,"100°C / 212°F"),(-40,"-40°C / -40°F"),(0,"-18°C / 0°F"),(55,"13°C / 55°F"),(53,"12°C / 53°F")]
        check(temperatureExamples.allSatisfy { WeatherTemperature(fahrenheit:$0.0).pairedLabel == $0.1 }, "Weather temperatures lead with Celsius and include equivalent Fahrenheit, including freezing and negative values")
        check(WeatherTemperature(fahrenheit:59.8).pairedLabel == "15°C / 60°F", "Celsius converts from the original forecast value before either unit is rounded")
        let temperatureRange = WeatherTemperature.highLow(high:64,low:53)
        check(temperatureRange.celsius == "18°/12°C" && temperatureRange.fahrenheit == "64°/53°F", "Daily highs and lows retain their order in both temperature units")
        check(outdoorHour(1,temperature:55).detail.contains("13°C / 55°F"), "Current-condition help includes both units in Celsius-first order")
        check(CalendarNotePreview.plainText("<p>Hello &amp; welcome.</p><p>Next<br>line &#x2600;</p>") == "Hello & welcome.\nNext\nline ☀", "Notes preview removes HTML while preserving paragraph and line breaks and decoding entities")
        check(CalendarNotePreview.plainText("Meet <alex@example.com> at 2 < 3") == "Meet <alex@example.com> at 2 < 3", "Notes preview preserves ordinary angle-bracket text")
        check(CalendarNotePreview.plainText("<script>alert(1)</script><b>Notes</b>") == "Notes", "Notes preview excludes script content")
        check(BankTaskResize.minutes(original:60,translation:CalendarMath.hourHeight/2,top:false,fine:false) == 90, "Bank bottom resize grows by the calendar time scale")
        check(BankTaskResize.minutes(original:60,translation:CalendarMath.hourHeight/2,top:true,fine:false) == 30, "Bank top resize shrinks when dragged downward")
        check(BankTaskResize.minutes(original:60,translation:CalendarMath.hourHeight*7/60,top:false,fine:true) == 67, "Shift bank resize uses minute precision")
        check(BankTaskResize.minutes(original:10,translation: -CalendarMath.hourHeight,top:false,fine:false) == 1, "Bank resize keeps a positive duration")
        let rich = RichNotesHTML.decode("<p>Hello <b>bold</b> <i>italic</i> <a href=\"https://example.com\">link</a></p><ul><li>One</li><li>Two</li></ul>",fontSize:13)
        let richString = rich.string as NSString
        check(!rich.string.contains("<p>") && rich.string.contains("One") && rich.string.contains("Two"), "Rich notes display HTML paragraphs and list contents without tags")
        let boldFont = rich.attribute(.font,at:richString.range(of:"bold").location,effectiveRange:nil) as! NSFont
        check(NSFontManager.shared.traits(of:boldFont).contains(.boldFontMask), "Rich notes preserve bold formatting")
        let italicFont = rich.attribute(.font,at:richString.range(of:"italic").location,effectiveRange:nil) as! NSFont
        check(NSFontManager.shared.traits(of:italicFont).contains(.italicFontMask), "Rich notes preserve italic formatting")
        check(rich.attribute(.link,at:richString.range(of:"link").location,effectiveRange:nil) != nil, "Rich notes preserve clickable links")
        let htmlDocument = #"<!DOCTYPE html PUBLIC "-//W3C//DTD HTML 4.01//EN" "http://www.w3.org/TR/html4/strict.dtd"><html><head><meta charset="utf-8"><title>Hidden metadata</title><style>p { font: 13px Helvetica; }</style></head><body><p>Arrival &amp; pickup</p><p>Second line</p></body></html>"#
        check(CalendarNotePreview.plainText(htmlDocument) == "Arrival & pickup\nSecond line", "Full HTML note previews exclude doctype, metadata, and CSS")
        check(CalendarNotePreview.plainText("<!-- hidden --><!DOCTYPE html [<!ENTITY test 'unused'>]><p>Visible</p>") == "Visible", "HTML previews remove comments and internal document declarations")
        let exportedPreview = CalendarNotePreview.plainText(RichNotesHTML.encode(rich))
        check(exportedPreview.contains("Hello bold italic link") && !exportedPreview.contains("DOCTYPE") && !exportedPreview.contains("font-family") && !exportedPreview.contains("<html"), "HTML saved by the rich editor has a readable event-card preview")
        let richAgain = RichNotesHTML.decode(RichNotesHTML.encode(rich),fontSize:13)
        check(richAgain.string.contains("bold") && richAgain.attribute(.link,at:(richAgain.string as NSString).range(of:"link").location,effectiveRange:nil) != nil, "Rich notes formatting survives HTML save and reload")
        check(RichNotesHTML.decode("First\nSecond",fontSize:13).string == "First\nSecond", "Plain multiline notes remain readable in the rich editor")
        let plainNotes = "A:\n- Kipply\n- Roon\n\nB:\n- Robert\n"
        check(RichNotesHTML.encode(RichNotesHTML.decode(plainNotes,fontSize:13)) == plainNotes, "Ordinary multiline notes stay exact plain text with no extra blank lines or HTML")
        check(RichNotesHTML.encode(NSAttributedString(string:"")) == "", "Empty notes stay empty rather than becoming an HTML document")
        let boldOnly = NSMutableAttributedString(string:"Hello bold",attributes:[.font:NSFont.systemFont(ofSize:13)])
        boldOnly.addAttribute(.font,value:NSFont.boldSystemFont(ofSize:13),range:NSRange(location:6,length:4))
        check(RichNotesHTML.encode(boldOnly) == "Hello **bold**", "Bold notes save as portable Markdown rather than HTML")
        let markdownNote = "Hello **bold** and *italic*\n- [link](https://example.com)"
        let markdownRich = RichNotesHTML.decode(markdownNote,fontSize:13)
        check(markdownRich.string == "Hello bold and italic\n- link", "Markdown notes render formatting while retaining plain list lines")
        check(NSFontManager.shared.traits(of:markdownRich.attribute(.font,at:6,effectiveRange:nil) as! NSFont).contains(.boldFontMask), "Markdown bold renders as bold in the editor")
        check(RichNotesHTML.encode(markdownRich) == markdownNote, "Basic Markdown formatting survives save and reload without HTML")
        check(CalendarNotePreview.plainText(markdownNote) == "Hello bold and italic\n- link", "Calendar card previews hide Markdown formatting markers")
        check(!RichNotesHTML.encode(RichNotesHTML.decode("<p>Simple imported notes</p>",fontSize:13)).contains("<"), "Simple imported HTML can simplify to plain text when edited")
        let underlined = NSAttributedString(string:"Special formatting",attributes:[.underlineStyle:NSUnderlineStyle.single.rawValue])
        check(RichNotesHTML.encode(underlined).contains("<html"), "Formatting outside portable Markdown retains HTML instead of being lost")
        boldOnly.setAttributes([.font:NSFont.systemFont(ofSize:13)],range:NSRange(location:0,length:boldOnly.length))
        check(RichNotesHTML.encode(boldOnly) == "Hello bold", "Removing formatting returns notes to plain text")
        let multiBold = NSAttributedString(string:"One\nTwo",attributes:[.font:NSFont.boldSystemFont(ofSize:13)])
        check(RichNotesHTML.encode(multiBold) == "**One**\n**Two**", "Bold spanning paragraphs preserves line breaks as Markdown")
        let detectedURL = NSAttributedString(string:"https://example.com",attributes:[.link:URL(string:"https://example.com")!])
        check(RichNotesHTML.encode(detectedURL) == "https://example.com", "Automatic URL detection does not promote plain notes to Markdown or HTML")
        let codeNote = RichNotesHTML.decode("Use `code` here",fontSize:13)
        check(!RichNotesHTML.encode(codeNote).contains("<html") && RichNotesHTML.decode(RichNotesHTML.encode(codeNote),fontSize:13).string == codeNote.string, "Inline code remains portable Markdown")
        let listEditor = NSTextView()
        listEditor.string = "One\nTwo"
        listEditor.setSelectedRange(NSRange(location:0,length:(listEditor.string as NSString).length))
        let noteActions = RichNotesActions(); noteActions.editor = listEditor
        noteActions.bulletList()
        check(listEditor.string == "- One\n- Two" && RichNotesHTML.encode(listEditor.attributedString()) == "- One\n- Two", "The list toolbar creates plain Markdown bullets")
        listEditor.string = "• One\n• Two"
        listEditor.setSelectedRange(NSRange(location:0,length:(listEditor.string as NSString).length))
        noteActions.bulletList()
        check(listEditor.string == "One\nTwo", "The list toolbar can still remove existing Unicode bullets")



        check(WeatherStripSizing.resized(start:108,translation:-40,scale:1) == 148, "Dragging the strip top upward increases its height")
        check(WeatherStripSizing.resized(start:108,translation:40,scale:1) == 88, "Weather strip has a usable minimum height")
        check(WeatherStripSizing.resized(start:108,translation:-40,scale:2) == 128, "Weather strip resize accounts for text scaling")
        check(WeatherStripSizing.clamped(900,maximum:240) == 240 && WeatherStripSizing.clamped(.nan) == 108, "Weather strip bounds handle small screens and invalid stored heights")
        check(WeatherStripPresentation.resolve(visible:false,loading:true,hasForecast:true) == .hidden, "Disabled weather strip remains hidden while loading")
        check(WeatherStripPresentation.resolve(visible:true,loading:true,hasForecast:false) == .loading, "First weather load uses a single compact status row")
        check(WeatherStripPresentation.resolve(visible:true,loading:true,hasForecast:true) == .loading, "Weather refresh uses the chosen compact loading design")
        check(WeatherStripPresentation.resolve(visible:true,loading:false,hasForecast:true) == .forecast, "Loaded weather expands to the forecast")
        check(WeatherStripPresentation.resolve(visible:true,loading:false,hasForecast:false) == .unavailable, "Missing forecast stays compact with status and retry")
        check(WeatherStripPresentation.loading.height(preferred:220,scale:1) == 30 && WeatherStripPresentation.forecast.height(preferred:220,scale:1) == 220, "Compact loading preserves the user's chosen expanded height")
        check(WeatherStripPresentation.loading.height(preferred:220,scale:1.5) == 45 && WeatherStripPresentation.hidden.height(preferred:220,scale:1) == 0, "Compact weather layout respects text scaling and hidden state")
        check(LocationSuggestion(title:"Castro Fitness",subtitle:"3122 22nd St, San Francisco, CA").location == "Castro Fitness, 3122 22nd St, San Francisco, CA", "Location suggestions include the place and its actual address")
        check(LocationSuggestion(title:"San Francisco",subtitle:"San Francisco").location == "San Francisco", "Location selection avoids repeating identical place names")
        check(LocationSuggestion.searchable("Castro Fitness, SF") && !LocationSuggestion.searchable("C") && !LocationSuggestion.searchable("https://meet.google.com/test"), "Address lookup waits for meaningful text and leaves video links alone")
        let locationAutocomplete = LocationAutocomplete()
        var chosenLocation: String?
        locationAutocomplete.choose = { chosenLocation = $0 }
        locationAutocomplete.focus(false,in:nil)
        locationAutocomplete.select(LocationSuggestion(title:"Castro Fitness",subtitle:"San Francisco, CA"))
        check(chosenLocation == "Castro Fitness, San Francisco, CA", "Clicking a suggestion still selects its address when the field loses focus")

        check(CalendarMath.snappedMinutes(CalendarMath.hourHeight*6/60) == 5 && CalendarMath.snappedMinutes(-CalendarMath.hourHeight*6/60) == -5, "Default dragging snaps forward and backward to five-minute intervals")
        check(CalendarMath.snappedMinutes(CalendarMath.hourHeight*6/60,fine:true) == 6, "Shift retains one-minute dragging precision")
        check(BankTaskResize.minutes(original:60,translation:CalendarMath.hourHeight*6/60,top:false,fine:false) == 65, "Bank duration resize shares the five-minute grid")
        let destination = "Castro Fitness, 2275 Market St, San Francisco, CA"
        let directions = URLComponents(url:LocationDirections.url(for:destination)!,resolvingAgainstBaseURL:false)!
        check(directions.host == "www.google.com" && directions.path == "/maps/dir/" && directions.queryItems?.first(where:{ $0.name == "api" })?.value == "1", "Location pin builds a Google Maps directions URL")
        check(directions.queryItems?.first(where:{ $0.name == "destination" })?.value == destination && directions.queryItems?.contains(where:{ $0.name == "origin" }) == false, "Directions use the event address and let Maps determine the current origin")
        let specialAddress = "Café A&B + Main #2 &origin=Elsewhere"
        let specialURL = URLComponents(url:LocationDirections.url(for:specialAddress)!,resolvingAgainstBaseURL:false)!
        check(specialURL.queryItems?.count == 2 && specialURL.queryItems?.first(where:{ $0.name == "destination" })?.value == specialAddress, "Directions safely encode punctuation and non-ASCII address text")
        check(LocationDirections.url(for:"  ") == nil && LocationDirections.url(for:"https://meet.google.com/example") == nil, "Empty locations and video links do not offer street directions")
        let emptyWeatherScale = WeatherStripScale(hours:[])
        check(emptyWeatherScale.upper > emptyWeatherScale.lower, "Empty forecast strip has a valid temperature scale")
        check(emptyWeatherScale.fraction(emptyWeatherScale.lower) == 0 && emptyWeatherScale.fraction(emptyWeatherScale.upper) == 1, "Weather strip maps temperature endpoints consistently")
        let worldCenter = TimezoneMapGeometry.point(latitude:0,longitude:0,size:CGSize(width:300,height:150))
        check(worldCenter == CGPoint(x:150,y:75), "Timezone world map projects coordinates consistently")
        let landData = try! Data(contentsOf:URL(fileURLWithPath:"Resources/TimezoneLand.geojson"))
        check(TimezoneMapGeometry.polygons(from:landData).count > 100, "Offline timezone map includes simplified world coastlines")
        check(WeatherVisualMetrics.rainMarks(0) == 0 && WeatherVisualMetrics.rainMarks(nil) == 0, "Dry or missing precipitation produces no rain marks")
        check(WeatherVisualMetrics.rainMarks(8) > WeatherVisualMetrics.rainMarks(1) && WeatherVisualMetrics.rainMarks(1) > WeatherVisualMetrics.rainMarks(0.1), "Weather illustration density increases with rainfall amount")
        check(WeatherVisualMetrics.rainMarks(1000) <= 65, "Weather rain illustration has bounded density")
        let stripTip = AppTooltipPlacement.frame(size:CGSize(width:280,height:350),hoverPoint:CGPoint(x:400,y:800),screen:tooltipScreen,belowEdge:700)
        let stripTipLowerHover = AppTooltipPlacement.frame(size:CGSize(width:280,height:350),hoverPoint:CGPoint(x:400,y:740),screen:tooltipScreen,belowEdge:700)
        check(stripTip.maxY == 700 && stripTip == stripTipLowerHover, "Weather tooltip stays below the strip regardless of cursor height")
        let weatherShortcuts = WeatherPlace.prioritized(["America/Argentina/Buenos_Aires","America/Los_Angeles","America/Argentina/Buenos_Aires"])
        check(weatherShortcuts.first?.name == "Buenos Aires (AT)" && Set(weatherShortcuts.map(\.id)).count == weatherShortcuts.count, "Weather places prioritize selected timezones without duplicates")
        check(abs((WeatherPlace.timezone("America/New_York")?.latitude ?? 0)-25.7617) < 0.001, "Miami weather shortcut uses Miami rather than New York")
        let bottomStripTip = AppTooltipPlacement.frame(size:CGSize(width:280,height:350),hoverPoint:CGPoint(x:400,y:100),screen:tooltipScreen,aboveEdge:180)
        check(bottomStripTip.minY == 180, "Bottom weather-strip tooltip touches the strip’s upper edge")
        do {
            let zones = CalendarModel(reconnectIfAuthorized:false)
            let previousPrimary = UserDefaults.standard.object(forKey:"primaryTimeZone")
            let previousComparisons = UserDefaults.standard.object(forKey:"comparisonTimeZones")
            defer {
                UserDefaults.standard.set(previousPrimary,forKey:"primaryTimeZone")
                UserDefaults.standard.set(previousComparisons,forKey:"comparisonTimeZones")
            }
            zones.setPrimaryTimeZone("America/Los_Angeles")
            zones.comparisonTimeZones = ["America/Argentina/Buenos_Aires","America/New_York"]
            check(zones.moveTimeZone("America/Argentina/Buenos_Aires",toSlot:0) && zones.primaryTimeZoneID == "America/Argentina/Buenos_Aires" && zones.comparisonTimeZones[0] == "America/Los_Angeles", "Dropping comparison on primary swaps roles")
            check(zones.moveTimeZone("America/Argentina/Buenos_Aires",toSlot:2) && zones.primaryTimeZoneID == "America/New_York" && zones.comparisonTimeZones[1] == "America/Argentina/Buenos_Aires", "Primary can be dragged into a comparison slot")
            check(zones.moveTimeZone("America/Los_Angeles",toSlot:2) && zones.comparisonTimeZones == ["America/Argentina/Buenos_Aires","America/Los_Angeles"], "Dragging comparisons swaps their order")
            check(!zones.moveTimeZone("invalid",toSlot:0) && !zones.moveTimeZone("America/Los_Angeles",toSlot:3), "Timezone drops reject invalid payloads and slots")
        }
        let noonProfile = (0...288).map { 60-pow((Double($0)*5-735.2)/100,2) }
        check(abs((DaylightMath.peakMinute(profile:noonProfile) ?? 0)-735.2) < 0.01, "Solar noon marker interpolates the real elevation peak between samples")
        check(DaylightMath.peakMinute(profile:[]) == nil, "Missing daylight data does not fabricate a solar noon marker")
        var eventLabelCalendar = Calendar(identifier:.gregorian)
        eventLabelCalendar.timeZone = TimeZone(identifier:"America/Los_Angeles")!
        func labelDate(_ hour: Int, _ minute: Int = 0) -> Date {
            eventLabelCalendar.date(from:DateComponents(year:2026,month:11,day:14,hour:hour,minute:minute))!
        }
        check(EventTimeLabel.string(start:labelDate(14,40),end:labelDate(15,40),calendar:eventLabelCalendar) == "2:40–3:40pm · 1h", "Event time suppresses duplicate meridiem and includes duration")
        check(EventTimeLabel.string(start:labelDate(11,30),end:labelDate(12,30),calendar:eventLabelCalendar) == "11:30am–12:30pm · 1h", "Event time retains both meridiems when crossing noon")
        check(EventTimeLabel.string(start:labelDate(9),end:labelDate(10,30),calendar:eventLabelCalendar) == "9–10:30am · 1h 30m", "Event time includes mixed hour/minute duration")
        check(EventTimeLabel.string(start:labelDate(14,40),end:labelDate(15,40),calendar:eventLabelCalendar,includeDuration:false) == "2:40–3:40pm", "Inline event time omits duration while retaining the compact time range")
        check(EventTimeLabel.string(start:labelDate(11,30),end:labelDate(12,30),calendar:eventLabelCalendar,includeDuration:false) == "11:30am–12:30pm", "Inline time retains both meridiems when crossing noon")
        let emojiQuery = EmojiCatalog.query(in:"foobar :ki",caret:NSRange(location:10,length:0))
        check(emojiQuery?.query == "ki" && emojiQuery?.range == NSRange(location:7,length:3), "Emoji autocomplete preserves typed query and replacement range")
        check(EmojiCatalog.query(in:"https://",caret:NSRange(location:8,length:0)) == nil, "Emoji autocomplete leaves URLs alone")
        check(EmojiCatalog.query(in:":",caret:NSRange(location:1,length:0)) == nil, "Emoji suggestions wait until a search character is typed")
        let emojiEntries = EmojiCatalog.decode(try! Data(contentsOf:URL(fileURLWithPath:"Resources/EmojiCatalog.json")))
        let kissMatches = EmojiCatalog.matches("ki",in:emojiEntries)
        check(kissMatches.contains { $0.name.lowercased().contains("kiss") } && kissMatches.contains { $0.name.lowercased().contains("kiribati") }, "Emoji autocomplete finds emoji names and flags matching the typed prefix")
        let testRoot = FileManager.default.temporaryDirectory.appendingPathComponent("calendar-studio-tests-"+UUID().uuidString,isDirectory:true)
        defer { try? FileManager.default.removeItem(at:testRoot) }
        let bank = EventBankStore(folder:testRoot,watch:false)
        let model = CalendarModel(bank:bank,reconnectIfAuthorized:false)
        do {
            let clipboardBank = EventBankStore(folder:testRoot.appendingPathComponent("clipboard-bank"),watch:false)
            let clipboardModel = CalendarModel(bank:clipboardBank,reconnectIfAuthorized:false)
            let first = BankTask(title:"First task",minutes:90,calendarID:"work",calendarTitle:"Work",account:"Preview",notes:"Keep these notes")
            let second = BankTask(title:"Second task",minutes:20,calendarID:"personal",calendarTitle:"Personal",account:"Preview")
            try clipboardBank.save(first); try clipboardBank.save(second)
            clipboardModel.selectedBankTasks = [first.id,second.id]
            let pasteboard = NSPasteboard(name:NSPasteboard.Name("sunshine-tests-"+UUID().uuidString))
            defer { pasteboard.releaseGlobally() }
            clipboardModel.copyBankTasks(pasteboard:pasteboard)
            clipboardModel.pasteBankTasks(pasteboard:pasteboard)
            check(clipboardBank.tasks.count == 4 && clipboardModel.selectedBankTasks.count == 2, "Pasting bank tasks creates and selects distinct copies")
            let copied = clipboardBank.tasks.first { clipboardModel.selectedBankTasks.contains($0.id) && $0.title == first.title }!
            check(copied.minutes == 90 && copied.notes == first.notes && copied.calendarID == first.calendarID, "Bank clipboard preserves duration, notes, and calendar")
            clipboardModel.undo()
            check(clipboardBank.tasks.count == 2, "One undo removes a multi-task paste")
            clipboardModel.redo()
            check(clipboardBank.tasks.count == 4, "Redo restores a multi-task paste")
            clipboardModel.selectedBankTasks = Set(clipboardBank.tasks.map(\.id))
            clipboardModel.deleteBankTasks()
            check(clipboardBank.tasks.isEmpty, "Delete removes all selected bank tasks")
            clipboardModel.undo()
            check(clipboardBank.tasks.count == 4, "One undo restores all deleted bank tasks")
            let order = clipboardBank.tasks.map(\.id)
            clipboardModel.bankDragIDs = [order[0],order[1]]
            try clipboardModel.reorderBankTasks(order[0],before:nil)
            check(Array(clipboardBank.tasks.map(\.id).suffix(2)) == [order[0],order[1]], "Dragging a bank selection reorders the whole group in order")
            clipboardModel.undo()
            check(clipboardBank.tasks.map(\.id) == order, "One undo restores the original order after a group reorder")
            clipboardModel.bankDragIDs = [order[0],order[1]]
            try clipboardModel.reorderBankTasks(order[0],before:order[1])
            check(clipboardBank.tasks.map(\.id) == order, "Dropping within a selected group leaves its order unchanged")
            let editingTask = clipboardBank.tasks[0]
            let editorSession = BankEditorSession(model:clipboardModel,bank:clipboardBank,task:editingTask)
            editorSession.task.title = "Edited in popover"
            editorSession.task.notes = "First line\nSecond line"
            check(editorSession.commit(), "Bank popover commits changed fields on dismissal")
            check(clipboardBank.records[editingTask.id]?.notes == "First line\nSecond line", "Bank editor preserves multiline notes")
            clipboardModel.undo()
            check(clipboardBank.records[editingTask.id]?.title == editingTask.title, "Click-away bank edits are undoable")
            let invalidSession = BankEditorSession(model:clipboardModel,bank:clipboardBank,task:clipboardBank.records[editingTask.id]!)
            invalidSession.task.title = " "
            check(!invalidSession.commit() && invalidSession.error != nil, "Invalid bank edit keeps the popover open with an error")
            let unchanged = BankEditorSession(model:clipboardModel,bank:clipboardBank,task:clipboardBank.records[editingTask.id]!)
            let historyCount = clipboardModel.undoHistory.count
            check(unchanged.commit() && clipboardModel.undoHistory.count == historyCount, "Closing an unchanged bank task does not add an undo entry")


        } catch { fatalError("Bank clipboard test: \(error)") }

        do {
            let crossBank = EventBankStore(folder:testRoot.appendingPathComponent("cross-bank"),watch:false)
            let cross = CalendarModel(bank:crossBank,reconnectIfAuthorized:false)
            let task = BankTask(title:"Cross-area task",minutes:90,calendarID:"work",calendarTitle:"Work",account:"Preview",notes:"Keep me")
            try crossBank.save(task)
            cross.selectedBankTasks = [task.id]
            check(cross.copyBankTasks(), "Bank copy confirms clipboard success")
            cross.pasteTarget = cross.entries[0].start
            cross.pasteEvents()
            let event = cross.selection.first!
            check(event.title == task.title && event.notes == task.notes && event.end.timeIntervalSince(event.start) == 5400, "Bank-to-calendar paste preserves title, notes, and estimated duration")
            check(crossBank.tasks.count == 1, "Copying a bank task onto the calendar leaves the original in the bank")
            cross.copySelectedEvents(); cross.pasteBankTasks()
            check(crossBank.tasks.count == 2 && crossBank.tasks.allSatisfy { $0.notes == task.notes && $0.minutes == 90 }, "Calendar-to-bank paste preserves notes and duration")
            cross.undo()
            check(crossBank.tasks.count == 1, "Calendar-to-bank paste is undoable")
            cross.selectedBankTasks = [task.id]; cross.deleteBankTasks(cut:true)
            check(crossBank.tasks.isEmpty, "Cut removes selected bank tasks after copying")
            cross.undo()
            check(crossBank.tasks.count == 1, "Undo cut restores bank tasks")
        } catch { fatalError("Cross-area clipboard test: \(error)") }
        check(model.lastCalendarRefresh == nil, "Sample calendar reloads do not claim a successful real-calendar refresh")
        for (key,mode) in [("1",CalendarViewMode.day),("2",.twoDays),("3",.threeDays),("4",.fourDays),("5",.fiveDays),("6",.sixDays),("7",.week)] {
            check(model.handleViewLetter(key) && model.viewMode == mode, "Number key selects the corresponding day-count view")
        }
        model.draft = EventDraft(start:Date(),end:Date().addingTimeInterval(3600),calendarID:"work")
        check(["1","6","7"].allSatisfy { !model.handleViewLetter($0) } && model.viewMode == .week, "Day-count shortcuts leave open event editors alone")
        model.draft = nil
        check(!model.handleViewLetter("2",shift:true), "Shift-number input does not trigger day-count shortcuts")
        model.setView(.week)

        do {
            let copies = CalendarModel(bank:bank,reconnectIfAuthorized:false)
            copies.selected = ["one", "two"]
            let originals = copies.selection.sorted { $0.start < $1.start }
            copies.copySelectedEvents()
            copies.setView(.twoDays); copies.jump(to:originals[0].start)
            let destination = copies.calendar.date(byAdding:.day,value:1,to:originals[0].start)!
            let expectedShift = destination.timeIntervalSince(originals[0].start)
            copies.pasteTarget = destination.addingTimeInterval(600)
            copies.pasteEvents()
            let pasted = copies.selection.sorted { $0.start < $1.start }
            check(pasted.count == 2, "Paste duplicates a selected group")
            check(zip(pasted,originals).allSatisfy { $0.id != $1.id && $0.start == $1.start.addingTimeInterval(expectedShift) && $0.end == $1.end.addingTimeInterval(expectedShift) }, "Paste uses the clicked day but preserves original times and group spacing")
            let ids = Set(pasted.map(\.id))
            copies.undo()
            check(copies.entries.allSatisfy { !ids.contains($0.id) }, "One undo removes the pasted group")
            copies.redo()
            check(copies.selection.count == 2, "Redo restores the pasted group")
        }
        do {
            let continuous = CalendarModel(bank:bank,reconnectIfAuthorized:false)
            let sample = continuous.entries.first!
            continuous.setView(.month)
            continuous.jump(to:continuous.calendar.date(byAdding:.month,value:2,to:sample.start)!)
            check(!continuous.entries.contains(where:{ $0.id == sample.id }), "Month initially excludes distant events")
            continuous.loadMonthScrollRange(start:continuous.calendar.date(byAdding:.month,value:-1,to:sample.start)!,end:continuous.calendar.date(byAdding:.month,value:4,to:sample.end)!)
            check(continuous.entries.contains(where:{ $0.id == sample.id }), "Continuous month scroll loads neighboring month events")
            continuous.setView(.day)
            check(!continuous.entries.contains(where:{ $0.id == sample.id }), "Timeline ignores the month scroll loading range")
        }
        do {
            let cal = model.calendar
            let week = cal.dateInterval(of:.weekOfYear,for:Date())!.start
            var event = model.entries.first!
            event.start = cal.date(byAdding:.day,value:2,to:week)!
            event.end = cal.date(byAdding:.day,value:5,to:week)!
            let spans = CalendarViewDates.monthSpans([event],week:week,calendar:cal)
            check(spans.count == 1 && spans[0].firstDay == 2 && spans[0].endDay == 5, "Month ribbon covers multiple days with exclusive midnight end")
            event.end = cal.date(byAdding:.hour,value:12,to:event.end)!
            check(CalendarViewDates.monthSpans([event],week:week,calendar:cal)[0].endDay == 6, "Timed multi-day ribbon includes its final partial day")
            event.end = cal.date(byAdding:.day,value:9,to:week)!
            let nextWeek = cal.date(byAdding:.day,value:7,to:week)!
            let continuation = CalendarViewDates.monthSpans([event],week:nextWeek,calendar:cal)
            check(continuation.count == 1 && continuation[0].firstDay == 0 && continuation[0].endDay == 2, "Month ribbon continues across week boundaries")
            event.end = cal.date(byAdding:.hour,value:1,to:event.start)!
            check(CalendarViewDates.monthSpans([event],week:week,calendar:cal).isEmpty, "Single-day events remain inside their day cells")
        }
        do {
            let shortcuts = CalendarModel(bank:bank,reconnectIfAuthorized:false)
            check(shortcuts.handleViewLetter("m") && shortcuts.viewMode == .month, "M opens standard month")
            check(shortcuts.handleViewLetter("m") && shortcuts.viewMode == .monthDetailed, "M cycles to detailed month")
            check(shortcuts.handleViewLetter("m") && shortcuts.viewMode == .month, "M wraps month detail levels")
            check(shortcuts.handleViewLetter("w") && shortcuts.viewMode == .week, "W opens week")
            let previousSidebar = UserDefaults.standard.object(forKey:"sidebarVisible")
            let previousBank = UserDefaults.standard.object(forKey:"eventBankCollapsed")
            let previousWeather = shortcuts.weather.enabled
            defer {
                UserDefaults.standard.set(previousSidebar,forKey:"sidebarVisible")
                UserDefaults.standard.set(previousBank,forKey:"eventBankCollapsed")
                shortcuts.weather.enabled = previousWeather
            }
            UserDefaults.standard.set(true,forKey:"sidebarVisible")
            UserDefaults.standard.set(false,forKey:"eventBankCollapsed")
            check(shortcuts.handleViewLetter("s") && !UserDefaults.standard.bool(forKey:"sidebarVisible"), "S toggles calendar list")
            check(shortcuts.handleViewLetter("b") && UserDefaults.standard.bool(forKey:"eventBankCollapsed"), "B toggles bank")
            check(shortcuts.handleViewLetter("W",shift:true) && shortcuts.weather.enabled != previousWeather && shortcuts.viewMode == .week, "Shift W toggles weather without changing the view")
            check(!shortcuts.handleViewLetter("b",shift:true), "Shift B does not toggle bank")
            shortcuts.jump(to:shortcuts.calendar.date(byAdding:.day,value:10,to:Date())!)
            check(shortcuts.handleViewLetter("t") && shortcuts.calendar.isDateInToday(shortcuts.anchor), "T returns the calendar to today")
            shortcuts.selected = ["one"]
            check(!shortcuts.handleViewLetter("m") && shortcuts.viewMode == .week, "View letters do nothing with an event selected")
            shortcuts.selected = []
            shortcuts.newEvent()
            check(!shortcuts.handleViewLetter("m"), "View letters do nothing while editing")
        }
        do {
            let cut = CalendarModel(bank:bank,reconnectIfAuthorized:false)
            cut.selected = ["one","two"]
            let originals = cut.selection.sorted { $0.start < $1.start }
            check(cut.cutSelectedEvents(), "Cut removes an editable group")
            check(cut.entries.allSatisfy { !["one","two"].contains($0.id) } && cut.undoTitle.contains("Cut"), "Cut has its own undo action")
            cut.undo()
            check(cut.selection.count == 2, "Undo restores cut events")
            cut.redo()
            check(cut.entries.allSatisfy { !["one","two"].contains($0.id) }, "Redo removes cut events again")
            cut.setView(.twoDays); cut.jump(to:originals[0].start)
            let destination = cut.calendar.date(byAdding:.day,value:1,to:originals[0].start)!
            let expectedShift = destination.timeIntervalSince(originals[0].start)
            cut.pasteTarget = destination.addingTimeInterval(600)
            cut.pasteEvents()
            let pasted = cut.selection.sorted { $0.start < $1.start }
            check(pasted.count == 2 && zip(pasted,originals).allSatisfy { $0.start == $1.start.addingTimeInterval(expectedShift) && $0.end == $1.end.addingTimeInterval(expectedShift) }, "Cut clipboard pastes the group preserving durations and spacing")
            cut.undo(); cut.undo()
            check(cut.entries.contains { $0.id == "one" }, "Undo paste then cut restores original locations")
            var readonly = originals[0]; readonly.id = "readonly-cut"; readonly.writable = false
            cut.entries.append(readonly); cut.selected = [readonly.id,"one"]
            let clipboardChange = NSPasteboard.general.changeCount
            check(!cut.cutSelectedEvents() && cut.entries.contains { $0.id == "one" } && NSPasteboard.general.changeCount == clipboardChange, "Mixed read-only cuts change neither events nor clipboard")
        }
        do {
            let groups = CalendarModel(bank:bank,reconnectIfAuthorized:false)
            groups.visible = ["work"]
            let remembered = groups.visible
            groups.toggleAllCalendarsHidden()
            check(groups.shown.isEmpty && groups.visible == remembered, "Master calendar hide preserves individual checks")
            check(groups.scrollPreviewEntries(start:groups.weekStart).isEmpty, "Hidden calendars stay hidden while swiping")
            groups.toggleAllCalendarsHidden()
            check(groups.visible == remembered && !groups.shown.isEmpty, "Master restore preserves the exact previous selection")
            groups.toggleCalendarGroup("Preview")
            check(groups.calendarIDs(in:"Preview").isSubset(of:groups.visible), "Partially selected group checks every member")
            groups.toggleCalendarGroup("Preview")
            check(groups.visible.isDisjoint(with:groups.calendarIDs(in:"Preview")), "Checked group unchecks every member")
            groups.visible = ["work"]
            groups.toggleCalendarGroup("Unknown")
            check(groups.visible == ["work"], "Group toggle does not change unrelated calendars")
        }
        // Keep the one-day move inside the visible range even on Saturdays.
        model.jump(to:Calendar.current.date(byAdding:.day,value:-1,to:Date())!)
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
        check(layout["a"]!.count == 1 && layout["c"]!.count == 1, "Staggered starts retain full readable width")
        check(layout["a"]!.column == layout["c"]!.column, "Column reused when previous event ends")
        check(layout["d"]!.count == 1, "Touching event starts new overlap group")
        check(OverlapLayout.columns([interval("a",0,100),interval("b",0,100),interval("c",0,100)])["a"]!.count == 3, "Three simultaneous events")
        check(OverlapLayout.columns([]).isEmpty, "Empty layout")
        // Six truly concurrent events each need a separate lane.
        let stacked = OverlapLayout.columns([
            interval("early1",0,3600), interval("early2",0,3600), interval("early3",0,3600),
            interval("later1",1800,5400), interval("later2",1800,5400), interval("later3",1800,5400)
        ])
        check(stacked.values.allSatisfy { $0.count == 3 }, "Equal starts share columns within each staggered row")
        check(stacked["later1"]!.depth == 1, "Later rows overlap with a small inset")
        let adjacent = OverlapLayout.columns([interval("a",0,1800),interval("b",1800,3600)])
        check(adjacent.values.allSatisfy { $0.count == 1 && $0.span == 1 }, "Nonoverlapping events keep full width without inset")
        let mixed = [interval("green1",0,60),interval("teal1",40,100),interval("green2",60,90),interval("green3",90,120)]
        let mixedLayout = OverlapLayout.columns(mixed)
        check(["green1","green2","green3"].allSatisfy { mixedLayout[$0]!.column == 0 }, "Successive events reuse the left edge instead of stair-stepping")
        let expanded = OverlapLayout.columns([interval("long",0,300),interval("a",0,60),interval("b",0,60),interval("later",60,120)])
        check(expanded["later"]!.column == 0 && expanded["later"]!.count == 1 && expanded["later"]!.depth == 1, "Later single events use nearly full width")
        check(mixedLayout["green1"]!.depth == 0 && mixedLayout["green2"]!.depth == 0 && mixedLayout["green3"]!.depth == 0, "Successive events reuse the leftmost inset while another event continues")
        check(mixedLayout["teal1"]!.depth == 1, "Nested task overlaps its earlier event with a small inset")
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
        let panStart = model.weekStart
        canvas.trackHorizontal(delta:-canvas.dayWidth*0.65)
        check(model.trackingHorizontalScroll && model.horizontalOffset < 0, "Native panning updates the shared header and weather-strip position")
        canvas.finishHorizontal()
        let releasedOffset = model.horizontalOffset
        check(releasedOffset > 0 && model.calendar.dateComponents([.day],from:panStart,to:model.weekStart).day == 1, "Native release rebases the date range while snapshots finish the remaining distance")
        canvas.trackHorizontal(delta:-3)
        check(abs(model.horizontalOffset-(releasedOffset-3)) < 0.001, "Grabbing an unfinished snap continues from its visible position without jumping to zero")
        canvas.finishHorizontal(cancelled:true)
        try? await Task.sleep(nanoseconds:250_000_000)
        check(!model.trackingHorizontalScroll && abs(model.horizontalOffset) < 0.001, "Interrupted and cancelled pans finish with the calendar and header aligned")
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
        check(CalendarMath.creationRange(from:0,to:1) == 0...5, "Creation has a five-minute minimum on the default grid")
        check(CalendarMath.creationRange(from:1530,to:1700) == 1435...1440, "Creation clamps at midnight")
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
        creationModel.draft = nil
        // Sticky-bar coordinates require a real clip view; detached NSViews
        // may report a null visibleRect after AppKit processes pending layout.
        let creationScroll = NSScrollView(frame:NSRect(x:0,y:0,width:900,height:800))
        creationScroll.documentView = creationCanvas
        creationScroll.layoutSubtreeIfNeeded()
        let allDayFirst = NSPoint(x:creationCanvas.gutter+creationCanvas.dayWidth*0.5,y:creationCanvas.stickyTop+10)
        let allDayLast = NSPoint(x:creationCanvas.gutter+creationCanvas.dayWidth*2.5,y:creationCanvas.stickyTop+10)
        let allDayOriginalCount = creationModel.entries.count
        creationCanvas.mouseDown(with:mouse(.leftMouseDown,allDayFirst))
        creationCanvas.mouseUp(with:mouse(.leftMouseUp,allDayFirst))
        check(creationModel.draft == nil, "A single click in the empty all-day bar does not create an event")
        creationCanvas.mouseDown(with:mouse(.leftMouseDown,allDayFirst))
        creationCanvas.mouseDragged(with:mouse(.leftMouseDragged,allDayLast))
        creationCanvas.mouseUp(with:mouse(.leftMouseUp,allDayLast))
        let allDayForward = creationModel.draft!
        check(allDayForward.allDay && Calendar.current.dateComponents([.day],from:allDayForward.start,to:allDayForward.end).day == 3, "Dragging across three all-day columns opens a three-day all-day draft")
        check(creationModel.entries.count == allDayOriginalCount, "An all-day drag does not save before editor confirmation")
        creationModel.draft = nil
        creationCanvas.mouseDown(with:mouse(.leftMouseDown,allDayLast))
        creationCanvas.mouseDragged(with:mouse(.leftMouseDragged,allDayFirst))
        creationCanvas.mouseUp(with:mouse(.leftMouseUp,allDayFirst))
        check(creationModel.draft?.start == allDayForward.start && creationModel.draft?.end == allDayForward.end, "Reverse all-day dragging selects the same inclusive date range")
        creationModel.draft = nil
        creationCanvas.mouseDown(with:mouse(.leftMouseDown,allDayFirst))
        let sameColumn = NSPoint(x:allDayFirst.x+8,y:allDayFirst.y)
        creationCanvas.mouseDragged(with:mouse(.leftMouseDragged,sameColumn))
        creationCanvas.mouseUp(with:mouse(.leftMouseUp,sameColumn))
        check(creationModel.draft?.allDay == true && Calendar.current.dateComponents([.day],from:creationModel.draft!.start,to:creationModel.draft!.end).day == 1, "A drag within one all-day column creates a single-day event")
        creationModel.draft = nil
        creationCanvas.mouseDown(with:mouse(.leftMouseDown,allDayFirst))
        creationCanvas.mouseDragged(with:mouse(.leftMouseDragged,allDayLast))
        let escapeCreation = NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[],timestamp:0,windowNumber:0,context:nil,characters:"\u{1b}",charactersIgnoringModifiers:"\u{1b}",isARepeat:false,keyCode:53)!
        creationCanvas.keyDown(with:escapeCreation)
        creationCanvas.mouseUp(with:mouse(.leftMouseUp,allDayLast))
        check(creationModel.draft == nil, "Escape cancels an all-day drag without opening an event")
        do {
        let savedPrimaryForCreation = UserDefaults.standard.object(forKey:"primaryTimeZone")
        defer { UserDefaults.standard.set(savedPrimaryForCreation,forKey:"primaryTimeZone") }
        let foreignZoneModel = CalendarModel(bank:bank,reconnectIfAuthorized:false)
        foreignZoneModel.setPrimaryTimeZone("America/Argentina/Buenos_Aires")
        let selectedDay = foreignZoneModel.calendar.date(from:DateComponents(year:2026,month:12,day:4))!
        foreignZoneModel.newAllDayEvent(from:selectedDay,through:foreignZoneModel.calendar.date(byAdding:.day,value:1,to:selectedDay)!)
        check(Calendar.current.component(.day,from:foreignZoneModel.draft!.start) == 4 && Calendar.current.component(.day,from:foreignZoneModel.draft!.end) == 6 && foreignZoneModel.draft?.timeZoneID == "", "All-day creation preserves column dates as local floating dates with a foreign primary time zone")
        }
        do {
            let details = CalendarModel(bank:bank,reconnectIfAuthorized:false)
            check(!details.handleViewLetter(" ") && details.draft == nil, "Space without a selected event does nothing")
            details.select("one",extending:false)
            check(!details.handleViewLetter(" ",shift:true) && details.draft == nil, "Modified Space does not open event details")
            check(details.handleViewLetter(" ") && details.draft?.original?.id == "one", "Space opens the selected calendar event with the normal editor")
            let opened = details.draft!.id
            check(!details.handleViewLetter(" ") && details.draft?.id == opened, "Space does not replace an already-open editor")
            details.draft = nil; details.bankHasFocus = true
            check(!details.handleViewLetter(" "), "Bank focus does not open a stale calendar selection")
            details.bankHasFocus = false
            let canvas = CalendarCanvas(model:details)
            canvas.frame = NSRect(x:0,y:0,width:900,height:1800)
            let space = NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[],timestamp:0,windowNumber:0,context:nil,characters:" ",charactersIgnoringModifiers:" ",isARepeat:false,keyCode:49)!
            canvas.keyDown(with:space)
            check(details.draft?.original?.id == "one" && details.editorAnchorInWindow != nil, "Native canvas Space opens details anchored to the selected event")
        }
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            let jumpModel = CalendarModel(bank:bank,reconnectIfAuthorized:false)
            let jumpCanvas = CalendarCanvas(model:jumpModel)
            jumpCanvas.frame = NSRect(x:0,y:0,width:900,height:1800)
            let jumpScroll = NSScrollView(frame:NSRect(x:0,y:0,width:900,height:600)); jumpScroll.documentView = jumpCanvas
            let jumpWindow = NSWindow(contentRect:jumpScroll.frame,styleMask:.borderless,backing:.buffered,defer:false); jumpWindow.contentView = jumpScroll
            jumpCanvas.synchronize()
            let destination = jumpModel.calendar.date(byAdding:.day,value:20,to:jumpModel.weekStart)!
            jumpModel.jump(to:destination); jumpCanvas.synchronize()
            let jumpOverlay = jumpCanvas.subviews.first
            check(jumpOverlay?.subviews.filter { $0 is NSImageView }.count == 2, "A mini-calendar-style multi-day jump creates an animated current/destination pair")
            jumpCanvas.synchronize()
            check(jumpCanvas.subviews.first === jumpOverlay, "Same-date refreshes preserve an in-flight date jump animation")
            jumpModel.today(); jumpCanvas.synchronize()
            check(jumpModel.calendar.isDateInToday(jumpModel.firstVisibleDay) && jumpCanvas.subviews.first?.subviews.filter { $0 is NSImageView }.count == 2, "Today navigation also animates a jump back to the current date")
            check(jumpModel.dateJump?.to == jumpModel.weekStart && jumpModel.dateJump?.progress == 0, "Date headings retain the source range when the body starts a Today jump")
            for _ in 0..<10 {
                if (jumpModel.dateJump?.progress ?? 0) > 0 { break }
                try? await Task.sleep(nanoseconds:10_000_000)
            }
            if let frame = jumpModel.dateJump {
                let offsets = frame.offsets(dayWidth:jumpCanvas.dayWidth,viewportWidth:jumpCanvas.bounds.width-jumpCanvas.gutter)
                let tiles = jumpCanvas.subviews.first!.subviews
                check(frame.progress > 0 && frame.progress < 1 && abs(tiles[0].frame.minX-offsets.before) < 0.001 && abs(tiles[1].frame.minX-offsets.after) < 0.001, "Native body positions exactly match the published header positions during motion")
            } else { check(false, "Date jump supplies a shared intermediate animation frame") }
            let inFlightFrame = jumpModel.dateJump
            jumpModel.today(); jumpCanvas.synchronize()
            check(jumpModel.dateJump?.from == inFlightFrame?.from && jumpModel.dateJump?.progress == inFlightFrame?.progress, "Pressing Today again preserves the shared in-flight heading and body animation")
            try? await Task.sleep(nanoseconds:450_000_000)
            check(jumpModel.dateJump == nil && jumpCanvas.subviews.isEmpty, "Header and body finish on the same destination without a second header animation")

        }
        let deletionModel = CalendarModel(bank:bank,reconnectIfAuthorized:false)
        deletionModel.jump(to:Calendar.current.startOfDay(for:Date()).addingTimeInterval(-86400))
        deletionModel.selected = ["one","four"]
        let undeleted = Set(deletionModel.entries.map(\.id))
        check(!deletionModel.deleteSelectedEvents() && Set(deletionModel.entries.map(\.id)) == undeleted, "Read-only member prevents any deletion in a mixed group")
        deletionModel.selected = ["one","two"]
        check(deletionModel.deleteSelectedEvents(), "Selected editable events can be deleted together")
        check(!deletionModel.entries.contains(where:{ ["one","two"].contains($0.id) }) && deletionModel.entries.contains(where:{ $0.id == "three" }), "Deletion removes only selected events")
        check(deletionModel.selected.isEmpty && deletionModel.canUndo, "Deletion clears selection and registers undo")
        check(!deletionModel.deleteSelectedEvents(), "Empty selection cannot delete anything")
        deletionModel.undo()
        check(deletionModel.entries.contains(where:{ $0.id == "one" }) && deletionModel.entries.contains(where:{ $0.id == "two" }), "Undo restores a deleted group")
        deletionModel.redo()
        check(!deletionModel.entries.contains(where:{ $0.id == "one" }), "Redo deletes the restored group")
        let history = CalendarModel(bank:bank,reconnectIfAuthorized:false)
        var added = EventDraft(title:"Undo test", start:history.anchor, end:history.anchor.addingTimeInterval(3600), calendarID:"work", location:"Studio", notes:"Original notes", url:"https://example.com")
        check(history.save(added), "Create an undoable event")
        let addedID = history.entries.first(where:{ $0.title == "Undo test" })!.id
        history.edit(history.entries.first(where:{ $0.id == addedID })!)
        check(history.draft?.notes == "Original notes", "Preview retains full event details")
        added = history.draft!; added.title = "Edited event"; added.notes = "Updated notes"; added.allDay = true
        check(history.save(added), "Edit an undoable event")
        history.draft = nil
        history.undo()
        check(history.entries.first(where:{ $0.id == addedID })?.title == "Undo test", "Undo restores edited title")
        history.edit(history.entries.first(where:{ $0.id == addedID })!)
        check(history.draft?.notes == "Original notes" && history.draft?.allDay == false && history.draft?.location == "Studio", "Undo restores notes, location and all-day state")
        check(history.entries.first(where:{ $0.id == history.draft?.original?.id })?.location == "Studio", "Restored event cards retain the location shown in the editor")
        history.draft = nil
        history.undo()
        check(!history.entries.contains(where:{ $0.id == addedID }), "Second undo removes the created event")
        history.redo(); history.redo()
        check(history.entries.first(where:{ $0.id == addedID })?.title == "Edited event", "Redo replays create then edit")
        history.selected = ["one"]
        let startBeforeMoves = history.selection.first!.start
        history.move(minutes:10); history.move(minutes:20)
        history.selected = ["one"]
        check(history.deleteSelectedEvents(), "Delete after consecutive moves")
        history.undo(); history.undo(); history.undo()
        check(history.entries.first(where:{ $0.id == "one" })?.start == startBeforeMoves, "Undo delete and both prior moves in order")
        history.redo(); history.redo(); history.redo()
        check(!history.entries.contains(where:{ $0.id == "one" }), "Redo moves and deletion in order")
        history.undo()
        history.selected = ["one"]
        history.move(minutes:5)
        check(!history.canRedo, "A new action discards redo history")
        history.jump(to:history.anchor.addingTimeInterval(86400))
        check(history.canUndo, "Navigation preserves event history")
        history.undo()
        check(history.canRedo, "Undo remains available after navigation")
        let historyBank = EventBankStore(folder:testRoot.appendingPathComponent("undo-bank"),watch:false)
        let bankModel = CalendarModel(bank:historyBank,reconnectIfAuthorized:false)
        do {
            var task = BankTask(title:"Bank undo",minutes:30,calendarID:"work",calendarTitle:"Work",account:"Preview")
            try historyBank.save(task)
            task = historyBank.tasks[0]; task.title = "Edited bank task"
            try historyBank.save(task)
            try historyBank.remove(task.id)
            bankModel.undo()
            check(historyBank.tasks.first?.title == "Edited bank task", "Undo bank deletion restores task")
            bankModel.undo()
            check(historyBank.tasks.first?.title == "Bank undo", "Earlier bank edit follows restored task identity")
            bankModel.undo()
            check(historyBank.tasks.isEmpty, "Undo original bank creation follows restored identity")
            bankModel.redo(); bankModel.redo(); bankModel.redo()
            check(historyBank.tasks.isEmpty, "Redo replays bank creation, edit and deletion")
            bankModel.selected = ["one"]
            check(bankModel.moveEventsToBank(["one"]), "Move event into bank")
            check(historyBank.tasks.count == 1, "Moving to bank creates one pending task")
            bankModel.undo()
            check(historyBank.tasks.isEmpty && bankModel.entries.contains(where:{ $0.id == "one" }), "Undo transfer restores calendar event and removes bank copy together")
            bankModel.redo()
            check(historyBank.tasks.count == 1 && !bankModel.entries.contains(where:{ $0.id == "one" }), "Redo transfer avoids duplicate tasks")
            bankModel.undo()
            let otherMac = EventBankStore(folder:historyBank.folder,watch:false)
            let pending = BankTask(title:"Concurrent task",minutes:10,calendarID:"work",calendarTitle:"Work",account:"Preview")
            try historyBank.save(pending)
            otherMac.refresh()
            var changed = otherMac.tasks.first(where:{ $0.id == pending.id })!
            changed.title = "Changed on another Mac"; try otherMac.save(changed)
            bankModel.undo()
            check(bankModel.canUndo && historyBank.tasks.contains(where:{ $0.title == "Changed on another Mac" }), "Sync conflict preserves newer task and retryable history")
        } catch { preconditionFailure("Unexpected bank undo error: \(error)") }
        let nativeModel = CalendarModel(bank:EventBankStore(folder:nil,watch:false),reconnectIfAuthorized:false)
        nativeModel.selected = ["one"]; nativeModel.move(minutes:10)
        check(nativeModel.eventUndoManager.canUndo && nativeModel.eventUndoManager.undoMenuItemTitle == "Undo Move Event", "Native undo manager supplies action label and availability")
        nativeModel.eventUndoManager.undo()
        check(nativeModel.eventUndoManager.canRedo && nativeModel.eventUndoManager.redoMenuItemTitle == "Redo Move Event", "Native manager exposes redo after undo")
        nativeModel.eventUndoManager.redo()
        check(nativeModel.canUndo, "Native redo restores event action")
        nativeModel.newEvent()
        check(!nativeModel.eventUndoManager.canUndo, "Unsaved editor cannot undo underlying calendar events")
        nativeModel.draft = nil
        // Exercise the same routing used by the explicit Edit menu commands.
        // These windows remain offscreen and all event changes use preview data.
        let undoWindow = NSWindow(contentRect:NSRect(x:0,y:0,width:300,height:150),styleMask:.borderless,backing:.buffered,defer:false)
        let undoDelegate = CalendarUndoWindowDelegate(previous:nil,model:nativeModel)
        undoWindow.delegate = undoDelegate
        let routing = CalendarHistoryRouting(model:nativeModel)
        check(routing.manager(in:undoWindow) === nativeModel.eventUndoManager, "Calendar and bank focus route menu commands to event history")
        let movedStart = nativeModel.entries.first(where:{ $0.id == "one" })!.start
        routing.undo(in:undoWindow)
        check(nativeModel.entries.first(where:{ $0.id == "one" })!.start == movedStart.addingTimeInterval(-600), "Undo menu routing reverses an event move")
        routing.redo(in:undoWindow)
        check(nativeModel.entries.first(where:{ $0.id == "one" })!.start == movedStart, "Redo menu routing reapplies an event move")
        let typing = NSTextView(frame:undoWindow.contentView!.bounds)
        typing.allowsUndo = true
        undoWindow.contentView = typing
        undoWindow.makeFirstResponder(typing)
        typing.insertText("New notes",replacementRange:NSRange(location:0,length:0))
        check(routing.manager(in:undoWindow) === typing.undoManager && typing.undoManager?.canUndo == true, "Typing focus routes Undo to the editor's actual text history")
        routing.undo(in:undoWindow)
        check(typing.string.isEmpty && nativeModel.entries.first(where:{ $0.id == "one" })!.start == movedStart, "Typing Undo removes text without changing a calendar event")
        routing.redo(in:undoWindow)
        check(typing.string == "New notes", "Typing Redo restores text")
        undoWindow.makeFirstResponder(nil)
        nativeModel.newEvent()
        check(routing.manager(in:undoWindow) == nil, "Open event editor blocks Undo of underlying saved events")
        nativeModel.draft = nil
        check(routing.manager(in:nil) == nil, "No active window cannot undo an unrelated event")
        let memoryStore = EKEventStore()
        let memoryCalendar = EKCalendar(for:.event,eventStore:memoryStore)
        memoryCalendar.title = "In-memory test"
        let memoryEvent = EKEvent(eventStore:memoryStore)
        memoryEvent.calendar = memoryCalendar; memoryEvent.title = "Snapshot"
        memoryEvent.startDate = Date(); memoryEvent.endDate = memoryEvent.startDate.addingTimeInterval(3600)
        memoryEvent.notes = "Notes"; memoryEvent.location = "Studio"; memoryEvent.url = URL(string:"https://example.com")
        memoryEvent.timeZone = TimeZone(identifier:"America/New_York")
        memoryEvent.alarms = [EKAlarm(relativeOffset:-600)]
        memoryEvent.recurrenceRules = [EKRecurrenceRule(recurrenceWith:.weekly,interval:2,end:nil)]
        let memoryEntry = CalendarEntry(id:"snapshot",title:memoryEvent.title,start:memoryEvent.startDate,end:memoryEvent.endDate,calendarID:memoryCalendar.calendarIdentifier,color:.blue)
        let captured = EventSnapshot(memoryEvent,entry:memoryEntry)
        memoryEvent.notes = "Changed"; memoryEvent.alarms = nil; memoryEvent.recurrenceRules = nil
        captured.apply(to:memoryEvent,calendar:memoryCalendar)
        check(memoryEvent.notes == "Notes" && memoryEvent.alarms?.first?.relativeOffset == -600 && memoryEvent.recurrenceRules?.first?.interval == 2, "Event snapshots restore notes, alarms and recurrence rules")
        check(captured.matches(memoryEvent), "Copied recurrence and alarms compare by value for conflict checks")
        memoryEvent.notes = "Changed elsewhere"
        check(!captured.matches(memoryEvent), "Conflict check notices changes to event details")
        let singleOccurrence = EventSnapshot(memoryEvent,entry:memoryEntry,occurrenceOnly:true)
        let restoredOccurrence = EKEvent(eventStore:memoryStore)
        singleOccurrence.apply(to:restoredOccurrence,calendar:memoryCalendar)
        check(restoredOccurrence.recurrenceRules?.isEmpty != false, "Restoring one deleted occurrence never recreates the full recurring series")
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
        let protectedCards = [NSRect(x:0,y:0,width:200,height:43),NSRect(x:7,y:10,width:193,height:48),NSRect(x:0,y:30,width:200,height:50)]
        let protectedLabels = ProtectedTitleLayout.frames(protectedCards)
        check(!protectedLabels[0].intersects(protectedLabels[1]) && !protectedLabels[1].intersects(protectedLabels[2]), "Overlapping event titles shift within their cards to stay readable")
        check(zip(protectedCards,protectedLabels).allSatisfy { $0.contains($1) }, "Protected titles stay within actual event duration bounds")
        let separatedLabels = ProtectedTitleLayout.frames([NSRect(x:0,y:0,width:100,height:40),NSRect(x:100,y:0,width:100,height:40)])
        check(separatedLabels[0].minY == separatedLabels[1].minY, "Side-by-side event titles keep their natural top alignment")
        let compactTitleFont = NSFont.systemFont(ofSize:10,weight:.semibold)
        let compactTime = EventCardLabelLayout.time("6:15–6:45pm · 30m",font:NSFont.systemFont(ofSize:9),color:.systemTeal,durationFirst:true)
        let compactFrame = NSRect(x:6,y:2,width:300,height:20)
        let compactLine = EventCardLabelLayout.inline(title:"fundraising tasks",time:compactTime,titleFont:compactTitleFont,color:.systemTeal,in:compactFrame)
        check(compactLine?.title.string == "fundraising tasks" && compactLine?.time.string == "30m · 6:15–6:45pm", "A short event with horizontal room shows duration before the right-aligned time range")
        check((compactTime.attribute(.foregroundColor,at:0,effectiveRange:nil) as! NSColor).alphaComponent < (compactTime.attribute(.foregroundColor,at:6,effectiveRange:nil) as! NSColor).alphaComponent, "Leading inline duration remains more faded than the time range")
        check(compactLine?.titleFrame.minX == compactFrame.minX && compactLine?.timeFrame.maxX == compactFrame.maxX && compactLine!.titleFrame.maxX+8 <= compactLine!.timeFrame.minX, "Inline event time is aligned to the right edge with space separating it from the left-aligned title")
        check(EventCardLabelLayout.inline(title:"A much longer title that needs all the available width",time:compactTime,titleFont:compactTitleFont,color:.systemTeal,in:NSRect(x:6,y:2,width:200,height:20)) == nil, "Inline time never displaces or truncates a longer event title")
        check(EventCardLabelLayout.inline(title:"Bike",time:compactTime,titleFont:compactTitleFont,color:.systemTeal,in:NSRect(x:6,y:2,width:300,height:7)) == nil, "Extremely short event rectangles do not draw time text beyond their vertical bounds")
        check(EventCardLabelLayout.inline(title:"Two\nlines",time:compactTime,titleFont:compactTitleFont,color:.systemTeal,in:NSRect(x:6,y:2,width:300,height:20)) == nil, "Multiline titles retain their existing layout instead of forcing inline times")
        let largeTime = EventCardLabelLayout.time("6:15–6:45pm",font:NSFont.systemFont(ofSize:18),color:.systemTeal)
        check(EventCardLabelLayout.inline(title:"fundraising tasks",time:largeTime,titleFont:NSFont.systemFont(ofSize:20,weight:.semibold),color:.systemTeal,in:NSRect(x:6,y:2,width:220,height:30)) == nil, "Inline labels account for larger text before deciding whether both labels fit")
        let secondLineTime = EventCardLabelLayout.time("6:15–6:45pm · 30m",font:NSFont.systemFont(ofSize:9),color:.systemTeal)
        let secondLineString = secondLineTime.string as NSString
        let timeColor = secondLineTime.attribute(.foregroundColor,at:0,effectiveRange:nil) as! NSColor
        let durationColor = secondLineTime.attribute(.foregroundColor,at:secondLineString.range(of:"30m").location,effectiveRange:nil) as! NSColor
        check(durationColor.alphaComponent < timeColor.alphaComponent, "Second-line event durations retain their faded styling")
        let remembered = CalendarModel(bank:bank,reconnectIfAuthorized:false)
        remembered.jump(to:Calendar.current.startOfDay(for:Date()).addingTimeInterval(-86400))
        remembered.select("three",extending:false)
        remembered.selected = [] // Starting an empty-slot drag clears selection.
        remembered.newEvent(durationMinutes:30)
        check(remembered.draft?.calendarID == "personal", "New event uses the last selected event calendar even after clearing selection")
        remembered.select("one",extending:false)
        remembered.newEvent()
        check(remembered.draft?.calendarID == "work", "Selecting an event in another calendar changes creation calendar")
        remembered.select("three",extending:true)
        check(remembered.creationCalendar?.id == "personal", "Most recently selected event wins during multiselection")
        remembered.select("three",extending:true)
        check(remembered.creationCalendar?.id == "personal", "Deselecting an event does not change the remembered creation calendar")
        remembered.select("four",extending:false)
        check(remembered.creationCalendar?.id == "personal", "Read-only calendars cannot become the creation destination")
        remembered.sources.removeAll { $0.id == "personal" }
        check(remembered.creationCalendar?.id == "work", "Unavailable remembered calendar falls back to an editable calendar")
        remembered.newEvent(at:november,durationMinutes:45)
        check(remembered.creationPreview?.start == november && remembered.creationPreview?.end == november.addingTimeInterval(2700), "Open new-event editor retains a preview with the chosen time span")
        let countBeforeDraft = remembered.entries.count
        remembered.draft!.title = "Draft title"
        remembered.draft!.end = november.addingTimeInterval(3600)
        check(remembered.creationPreview?.title == "Draft title" && remembered.creationPreview?.end == november.addingTimeInterval(3600), "Preview follows title and duration edits")
        check(remembered.entries.count == countBeforeDraft, "Draft rectangle does not create a real event before saving")
        remembered.draft = nil
        check(remembered.creationPreview == nil, "Closing the editor removes the draft rectangle")
        check(EventRepeat.never.rule == nil && EventRepeat.unchanged.rule == nil, "Never creates no recurrence; existing schedules can remain untouched")
        check(EventRepeat.daily.rule?.frequency == .daily && EventRepeat.daily.rule?.interval == 1, "Daily repeat saves a daily rule")
        check(EventRepeat.biweekly.rule?.frequency == .weekly && EventRepeat.biweekly.rule?.interval == 2, "Every two weeks saves a two-week interval")
        check(EventRepeat.weekdays.rule?.daysOfTheWeek?.count == 5, "Weekday repeat includes exactly five weekdays")
        check(EventRepeat.monthly.rule?.frequency == .monthly && EventRepeat.yearly.rule?.frequency == .yearly, "Monthly and yearly repeat use the correct frequencies")
        check(EventDraft().timeZoneID == TimeZone.current.identifier, "New events default to the current timezone")
        var urlDraft = EventDraft()
        urlDraft.url = "example.com/meeting"
        urlDraft.notes = "Keep these notes separate."
        check(urlDraft.eventURL?.absoluteString == "https://example.com/meeting" && urlDraft.notes == "Keep these notes separate.", "URL field normalizes bare web addresses without changing notes")
        urlDraft.url = "https://example.com/meeting"
        check(urlDraft.eventURL?.absoluteString == urlDraft.url, "Full event URL is preserved")
        urlDraft.url = "not a url"
        check(urlDraft.eventURL == nil, "Malformed URL is rejected")
        urlDraft.url = ""
        check(urlDraft.eventURL == nil, "Clearing URL removes the event URL")
        let storedZones = UserDefaults.standard.object(forKey:"comparisonTimeZones")
        let zoneModel = CalendarModel(bank:bank,reconnectIfAuthorized:false)
        let choices = ["America/New_York","America/Los_Angeles","America/Argentina/Buenos_Aires","America/Denver"].filter { $0 != TimeZone.current.identifier }
        zoneModel.toggleComparisonZone(choices[0]); zoneModel.toggleComparisonZone(choices[1]); zoneModel.toggleComparisonZone(choices[2])
        check(zoneModel.clockZones.count == 3 && zoneModel.timeGutterWidth == 102+CalendarModel.timeRibbonGap, "Comparison columns allow two extra zones and align the header gutter")
        check(zoneModel.clockZones.last!.identifier == TimeZone.current.identifier, "Primary timezone remains closest to the calendar")
        zoneModel.toggleComparisonZone(choices[0])
        check(zoneModel.clockZones.count == 2 && zoneModel.timeGutterWidth == 68+CalendarModel.timeRibbonGap, "Removing a comparison reclaims its column width")
        zoneModel.toggleComparisonZone(TimeZone.current.identifier)
        check(zoneModel.clockZones.count == 2, "Primary timezone cannot be duplicated as a comparison")
        if let storedZones { UserDefaults.standard.set(storedZones,forKey:"comparisonTimeZones") }
        else { UserDefaults.standard.removeObject(forKey:"comparisonTimeZones") }
        let immediate = DaySwipeMath.advance(offset:0,delta:-1,width:120)
        check(immediate.days == 0 && immediate.offset == -1, "Trackpad movement starts with the first pixel rather than a threshold")
        let continuous = DaySwipeMath.advance(offset:immediate.offset,delta:-260,width:120)
        check(continuous.days == 2 && continuous.offset == -21, "Continuous movement crosses multiple days without losing partial distance")
        let reversal = DaySwipeMath.advance(offset:continuous.offset,delta:81,width:120)
        check(reversal.days == 0 && reversal.offset == 60, "Reversing the gesture remains continuous")
        check(DaySwipeMath.settle(offset:-59,width:120) == 0 && DaySwipeMath.settle(offset:-61,width:120) == 1 && DaySwipeMath.settle(offset:61,width:120) == -1, "Release settles to the nearest day in either direction")
        check(InvitationStatus(participant:.pending) == .unanswered, "Unanswered invitation maps from current-user pending status")
        check(InvitationStatus(participant:.tentative) == .maybe, "Tentative RSVP is labeled Maybe")
        check(InvitationStatus(participant:.accepted) == .accepted && InvitationStatus(participant:.declined) == .declined, "Accepted and declined responses remain distinct")
        var invited = CalendarEntry(id:"invite",title:"Team call",start:Date(),end:Date().addingTimeInterval(3600),calendarID:"work",color:.systemBlue,invitationStatus:.unanswered)
        check(invited.displayTitle == "Team call", "Unanswered events keep a clean title while their accent indicates status")
        invited.invitationStatus = .maybe
        check(invited.displayTitle == "Maybe · Team call", "Maybe remains explicit on protected overlapping titles")
        invited.invitationStatus = .accepted
        check(invited.displayTitle == "Team call", "Accepted events retain ordinary card titles")
        let savedPrimary = UserDefaults.standard.object(forKey:"primaryTimeZone")
        let savedComparisons = UserDefaults.standard.object(forKey:"comparisonTimeZones")
        let primaryModel = CalendarModel(bank:bank,reconnectIfAuthorized:false)
        primaryModel.setPrimaryTimeZone("America/Los_Angeles")
        primaryModel.setComparisonZone("America/New_York",at:0)
        primaryModel.setComparisonZone("America/Argentina/Buenos_Aires",at:1)
        let originalInstant = primaryModel.entries.first(where:{ $0.id == "one" })!.start
        let dateBefore = primaryModel.calendar.dateComponents([.year,.month,.day],from:primaryModel.weekStart)
        primaryModel.setPrimaryTimeZone("America/New_York")
        check(primaryModel.primaryTimeZoneID == "America/New_York" && primaryModel.comparisonTimeZones[0] == "America/Los_Angeles", "Choosing a comparison as primary swaps zones")
        check(primaryModel.calendar.dateComponents([.year,.month,.day],from:primaryModel.weekStart) == dateBefore, "Changing primary keeps the displayed date range")
        check(primaryModel.entries.first(where:{ $0.id == "one" })!.start == originalInstant, "Changing timezone never moves actual calendar events")
        check(primaryModel.calendar.component(.hour,from:primaryModel.dateAtMinute(9*60,on:primaryModel.weekStart)) == 9, "Dragging uses wall-clock time in the selected primary timezone")
        primaryModel.newEvent()
        check(primaryModel.draft?.timeZoneID == "America/New_York", "New event editor defaults to the selected primary timezone")
        primaryModel.setComparisonZone("America/Chicago",at:0)
        check(primaryModel.comparisonTimeZones[0] == "America/Chicago", "A comparison slot can be replaced directly")
        if let savedPrimary { UserDefaults.standard.set(savedPrimary,forKey:"primaryTimeZone") } else { UserDefaults.standard.removeObject(forKey:"primaryTimeZone") }
        if let savedComparisons { UserDefaults.standard.set(savedComparisons,forKey:"comparisonTimeZones") } else { UserDefaults.standard.removeObject(forKey:"comparisonTimeZones") }
        let sfRibbon = DaylightLocation.ribbonCoordinate(for:"America/Los_Angeles")!
        let baRibbon = DaylightLocation.ribbonCoordinate(for:"America/Argentina/Buenos_Aires")!
        let ribbonDate = pacific.date(from:DateComponents(year:2026,month:11,day:13))!
        let sfNight = DaylightMath.nightRanges(on:ribbonDate,coordinate:sfRibbon,calendar:pacific)
        let baNight = DaylightMath.nightRanges(on:ribbonDate,coordinate:baRibbon,calendar:pacific)
        check(sfNight != baNight, "Each ribbon uses its own city rather than the Mac location")
        check(baNight.reduce(0) { $0+$1.upperBound-$1.lowerBound } < sfNight.reduce(0) { $0+$1.upperBound-$1.lowerBound }, "Buenos Aires has longer November daylight than San Francisco")
        check(DaylightLocation.ribbonCoordinate(for:"America/New_York")!.latitude < 26, "Miami timezone shortcut uses Miami sunrise, not New York sunrise")
        check(DaylightLocation.ribbonCoordinate(for:"America/Buenos_Aires") == baRibbon, "Buenos Aires timezone aliases use the same location")
        let initialEdit = EventDraft(title:"Meeting",calendarID:"work")
        var changedEdit = initialEdit
        check(changedEdit.hasSameContent(as:initialEdit), "Unchanged editor can close without a redundant calendar save")
        changedEdit.notes = "Updated notes"
        check(!changedEdit.hasSameContent(as:initialEdit), "Click-away saving detects note edits")
        changedEdit = initialEdit; changedEdit.location = "New location"
        check(!changedEdit.hasSameContent(as:initialEdit), "Click-away saving detects location edits")
        changedEdit = initialEdit; changedEdit.url = "https://example.com"
        check(!changedEdit.hasSameContent(as:initialEdit), "Click-away saving detects URL edits")
        let sfMap = TimeZoneCatalog.coordinate("+3746-12225")!
        check(abs(sfMap.0-37.7667) < 0.001 && abs(sfMap.1+122.4167) < 0.001, "Map pins parse timezone coordinates with minutes and signed longitude")
        let baMap = TimeZoneCatalog.coordinate("-3436-05827")!
        check(baMap.0 < 0 && baMap.1 < 0, "Southern and western timezone pins retain their hemisphere")
        let detailedMap = TimeZoneCatalog.coordinate("+251146+0551847")!
        check(detailedMap.0 > 25 && detailedMap.1 > 55, "Timezone map supports second-resolution locations")
        check(TimeZoneCatalog.coordinate("invalid") == nil && TimeZoneCatalog.coordinate("+9900+18100") == nil, "Invalid map coordinates are rejected")
        check(TimeZoneCatalog.name("America/New_York") == "Miami (ET)", "Map and list use the same favorite city labels")
        let overflowModel = CalendarModel(bank:bank,reconnectIfAuthorized:false)
        for index in 0..<6 {
            overflowModel.entries.append(CalendarEntry(id:"all-day-\(index)",title:"All day \(index)",start:overflowModel.weekStart,end:overflowModel.calendar.date(byAdding:.day,value:1,to:overflowModel.weekStart)!,calendarID:"work",color:.systemBlue,allDay:true))
        }
        check(overflowModel.allDayHeight == 68 && overflowModel.allDayRowCount == 6, "Collapsed all-day view leaves a miniature ribbon for each overflow row")
        overflowModel.allDayExpanded = true
        check(overflowModel.allDayHeight == 112, "Expanded all-day view has room for every event row")
        overflowModel.allDayExpanded = false
        check(overflowModel.allDayHeight == 68, "All-day section can return to its compact line stack")
        do {
            let hoverCanvas = CalendarCanvas(model:overflowModel)
            hoverCanvas.frame = NSRect(x:0,y:0,width:900,height:1800)
            let hoverScroll = NSScrollView(frame:NSRect(x:0,y:0,width:900,height:600)); hoverScroll.documentView = hoverCanvas
            hoverCanvas.synchronize()
            func hover(_ point: NSPoint) -> NSEvent {
                NSEvent.mouseEvent(with:.mouseMoved,location:hoverCanvas.convert(point,to:nil),modifierFlags:[],timestamp:0,windowNumber:0,context:nil,eventNumber:0,clickCount:0,pressure:0)!
            }
            let trayPoint = NSPoint(x:hoverCanvas.gutter+20,y:hoverCanvas.stickyTop+10)
            hoverCanvas.mouseMoved(with:hover(trayPoint))
            check(!overflowModel.allDayExpanded, "Hover entry waits before expanding the tray")
            hoverCanvas.mouseMoved(with:hover(NSPoint(x:trayPoint.x,y:hoverCanvas.stickyBottom+50)))
            try? await Task.sleep(nanoseconds:350_000_000)
            check(!overflowModel.allDayExpanded, "A brief pass through the all-day tray does not expand it")
            hoverCanvas.mouseMoved(with:hover(trayPoint))
            try? await Task.sleep(nanoseconds:350_000_000)
            check(overflowModel.allDayExpanded, "Sustained hover expands the collapsed tray after its entry delay")
            hoverCanvas.mouseMoved(with:hover(NSPoint(x:trayPoint.x,y:hoverCanvas.stickyBottom+50)))
            check(overflowModel.allDayExpanded, "Hover exit waits before collapsing the tray")
            hoverCanvas.mouseMoved(with:hover(trayPoint))
            try? await Task.sleep(nanoseconds:500_000_000)
            check(overflowModel.allDayExpanded, "Re-entering during the exit delay cancels automatic collapse")
            hoverCanvas.mouseMoved(with:hover(NSPoint(x:trayPoint.x,y:hoverCanvas.stickyBottom+50)))
            try? await Task.sleep(nanoseconds:500_000_000)
            check(!overflowModel.allDayExpanded, "A tray opened by hover collapses after sustained exit")
            overflowModel.allDayExpanded = true; hoverCanvas.synchronize()
            hoverCanvas.mouseMoved(with:hover(trayPoint))
            hoverCanvas.mouseMoved(with:hover(NSPoint(x:trayPoint.x,y:hoverCanvas.stickyBottom+50)))
            try? await Task.sleep(nanoseconds:500_000_000)
            check(overflowModel.allDayExpanded, "A manually opened tray stays expanded after hover exit")
            overflowModel.allDayExpanded = false
        }

        do {
            let allDayModel = CalendarModel(bank:bank,reconnectIfAuthorized:false)
            let firstDay = allDayModel.weekStart
            let secondEnd = allDayModel.calendar.date(byAdding:.day,value:2,to:firstDay)!
            let draft = EventDraft(title:"Resizable all-day fixture",start:firstDay,end:secondEnd,calendarID:"work",allDay:true)
            check(allDayModel.save(draft), "All-day resize fixture saves through normal event creation")
            let id = allDayModel.entries.first(where:{ $0.title == draft.title })!.id
            let canvas = CalendarCanvas(model:allDayModel)
            canvas.frame = NSRect(x:0,y:0,width:900,height:1800)
            let scroll = NSScrollView(frame:NSRect(x:0,y:0,width:900,height:600)); scroll.documentView = canvas
            let window = NSWindow(contentRect:scroll.frame,styleMask:.borderless,backing:.buffered,defer:false); window.contentView = scroll
            func render() {
                canvas.synchronize()
                let area = NSRect(x:0,y:canvas.stickyTop,width:900,height:150)
                let bitmap = canvas.bitmapImageRepForCachingDisplay(in:area)!
                canvas.cacheDisplay(in:area,to:bitmap)
            }
            func dragEvent(_ type: NSEvent.EventType, _ point: NSPoint) -> NSEvent {
                NSEvent.mouseEvent(with:type,location:canvas.convert(point,to:nil),modifierFlags:[],timestamp:0,windowNumber:window.windowNumber,context:nil,eventNumber:0,clickCount:1,pressure:0)!
            }
            render()
            let right = NSPoint(x:canvas.gutter+2*canvas.dayWidth-5,y:canvas.stickyTop+10)
            let extend = NSPoint(x:right.x+canvas.dayWidth,y:right.y+60)
            canvas.mouseDown(with:dragEvent(.leftMouseDown,right))
            canvas.mouseDragged(with:dragEvent(.leftMouseDragged,extend))
            canvas.mouseUp(with:dragEvent(.leftMouseUp,extend))
            let extendedEnd = allDayModel.calendar.date(byAdding:.day,value:3,to:firstDay)!
            check(allDayModel.entries.first(where:{ $0.id == id })?.end == extendedEnd, "Dragging an all-day right edge extends by one day and ignores vertical movement")
            allDayModel.undo()
            check(allDayModel.entries.first(where:{ $0.id == id })?.end == secondEnd, "All-day side resizing can be undone")
            allDayModel.redo()
            check(allDayModel.entries.first(where:{ $0.id == id })?.end == extendedEnd, "All-day side resizing can be redone")
            render()
            let left = NSPoint(x:canvas.gutter+5,y:canvas.stickyTop+10)
            let shrink = NSPoint(x:left.x+canvas.dayWidth,y:left.y)
            canvas.mouseDown(with:dragEvent(.leftMouseDown,left))
            canvas.mouseDragged(with:dragEvent(.leftMouseDragged,shrink))
            canvas.mouseUp(with:dragEvent(.leftMouseUp,shrink))
            check(allDayModel.entries.first(where:{ $0.id == id })?.start == allDayModel.calendar.date(byAdding:.day,value:1,to:firstDay), "Dragging an all-day left edge inward shrinks its date range")
            check(allDayModel.resizeEvent(id,startEdge:false,minutes:-20*1440), "An oversized all-day shrink clamps rather than inverting dates")
            let single = allDayModel.entries.first(where:{ $0.id == id })!
            check(allDayModel.calendar.dateComponents([.day],from:single.start,to:single.end).day == 1 && single.allDay, "All-day resizing preserves a one-calendar-day minimum and all-day status")
            var readOnly = single; readOnly.id = "readonly-all-day-resize"; readOnly.writable = false
            allDayModel.entries.append(readOnly)
            check(!allDayModel.resizeEvent(readOnly.id,startEdge:false,minutes:1440), "Read-only all-day events cannot be resized")
            var local = Calendar(identifier:.gregorian); local.timeZone = TimeZone(identifier:"America/Los_Angeles")!
            let march = local.date(from:DateComponents(year:2026,month:3,day:7))!
            let event = CalendarEntry(id:"dst-resize",title:"DST",start:march,end:local.date(byAdding:.day,value:1,to:march)!,calendarID:"work",color:.systemBlue,allDay:true)
            let resized = CalendarMath.resized(event,startEdge:false,minutes:1440,calendar:local)
            check(resized.end == local.date(from:DateComponents(year:2026,month:3,day:9))! && resized.end.timeIntervalSince(event.end) == 23*3600, "All-day resize follows calendar dates instead of adding fixed 24-hour periods across daylight saving")
        }
        let resizeModel = CalendarModel(bank:bank,reconnectIfAuthorized:false)
        let beforeResize = resizeModel.entries.first(where:{ $0.id == "one" })!
        check(resizeModel.resizeEvent("one",startEdge:false,minutes:30), "Dragging bottom edge saves a longer event")
        let afterResize = resizeModel.entries.first(where:{ $0.id == "one" })!
        check(afterResize.start == beforeResize.start && afterResize.end == beforeResize.end.addingTimeInterval(1800), "Bottom-edge resize preserves start")
        resizeModel.undo()
        check(resizeModel.entries.first(where:{ $0.id == "one" })!.end == beforeResize.end, "Resize can be undone")
        check(resizeModel.resizeEvent("one",startEdge:true,minutes:-15), "Dragging top edge can extend the start")
        let earlier = resizeModel.entries.first(where:{ $0.id == "one" })!
        check(earlier.end == beforeResize.end && earlier.start == beforeResize.start.addingTimeInterval(-900), "Top-edge resize preserves end")
        let clamped = CalendarMath.resized(beforeResize,startEdge:true,minutes:300)
        check(clamped.end.timeIntervalSince(clamped.start) == 60, "Resize cannot invert the event or shorten below one minute")
        resizeModel.jump(to:resizeModel.calendar.startOfDay(for:Date()).addingTimeInterval(-86400))
        check(!resizeModel.resizeEvent("four",startEdge:false,minutes:30), "Read-only events cannot be resized")
        check(CalendarMath.snappedMinutes(9,fine:true) == 8, "Shift snaps drag movement to single minutes")
        check(CalendarMath.snappedMinutes(-9,fine:true) == -8 && CalendarMath.snappedMinutes(-9) == -10, "Both snap precisions work for earlier times")
        check(CalendarMath.creationRange(from:0,to:1,fine:true) == 0...1, "Shift allows a one-minute new event")
        check(CalendarMath.creationRange(from:1700,to:1800,fine:true) == 1439...1440, "Fine creation remains within the day boundary")
        check(EventAttendee.email(from:URL(string:"mailto:person%2Bcalendar@example.com")!) == "person+calendar@example.com", "Attendee email decodes calendar participant addresses")
        check(EventAttendee.email(from:URL(string:"https://example.com/person")!) == nil, "Non-email attendee identifiers are not shown as fake email addresses")
        let attendee = EventAttendee(id:"guest",name:"Guest",email:"guest@example.com",response:.maybe,isOrganizer:false,isCurrentUser:false)
        check(attendee.responseLabel == "Maybe", "Attendee section clearly identifies tentative responses")
        let organizer = EventAttendee(id:"host",name:"Host",email:nil,response:.none,isOrganizer:true,isCurrentUser:false)
        check(organizer.responseLabel == "Organizer", "Organizer is identified independently of RSVP status")
        let insetCard = NSRect(x:20,y:0,width:200,height:20)
        let insetTitle = ProtectedTitleLayout.frames([insetCard])[0]
        check(insetTitle.minX == insetCard.minX+EventCardInsets.textLeading && insetTitle.width == insetCard.width-EventCardInsets.textLeading-EventCardInsets.textTrailing, "Overlapping and ordinary events share identical horizontal text insets")
        check(EventCardInsets.textLeading > EventCardInsets.accentWidth, "Every event title leaves a visible gap after its accent bar")
        let transferUndoBank = EventBankStore(folder:testRoot.appendingPathComponent("schedule-undo"),watch:false)
        let transferUndoModel = CalendarModel(bank:transferUndoBank,reconnectIfAuthorized:false)
        do {
            let scheduledEntry = transferUndoModel.entries.first(where:{ $0.id == "one" })!
            var pending = BankTask(title:scheduledEntry.title,minutes:60,calendarID:scheduledEntry.calendarID,calendarTitle:"Work",account:"Preview",notes:"Retain these notes")
            try transferUndoBank.save(pending)
            pending = transferUndoBank.records[pending.id]!
            try transferUndoBank.didSchedule(pending.id,at:scheduledEntry.start,eventID:scheduledEntry.id)
            transferUndoModel.recordScheduledBankTask(previousTask:pending,event:EventSnapshot(entry:scheduledEntry),taskID:pending.id)
            check(transferUndoModel.undoTitle == "Undo Schedule Bank Task", "Bank-to-calendar drop records a single combined undo action")
            transferUndoModel.eventUndoManager.undo()
            check(!transferUndoModel.entries.contains(where:{ $0.id == scheduledEntry.id }), "Command undo removes the event created by a bank drop")
            check(transferUndoBank.tasks.count == 1 && transferUndoBank.tasks[0].notes == pending.notes && transferUndoBank.tasks[0].minutes == 60, "Command undo restores task details to the bank")
            transferUndoModel.eventUndoManager.redo()
            check(transferUndoModel.entries.contains(where:{ $0.id == scheduledEntry.id }) && transferUndoBank.tasks.isEmpty, "Redo reschedules the event and removes its bank task together")
            transferUndoModel.eventUndoManager.undo()
            check(transferUndoBank.tasks.count == 1, "Repeated undo/redo does not duplicate bank tasks")
            check(CalendarCanvas(model:transferUndoModel).undoManager === transferUndoModel.eventUndoManager, "Drop destination routes keyboard undo to the combined event history")
        } catch { fatalError("Bank scheduling undo regression failed: \(error)") }
        check(DaylightMath.civilDarkness(elevation:-6) == 1 && DaylightMath.civilDarkness(elevation:-18) == 1, "Civil twilight reaches maximum darkness at six degrees below the horizon")
        check(DaylightMath.civilDarkness(elevation:-0.833) == 0 && DaylightMath.civilDarkness(elevation:20) == 0, "Daytime remains unshaded at and above apparent sunrise")
        check(DaylightMath.civilDarkness(elevation:-4) > DaylightMath.civilDarkness(elevation:-2), "Twilight shade follows solar depression continuously")
        let sfProfile = DaylightMath.elevationProfile(on:ribbonDate,coordinate:sfRibbon,calendar:pacific)
        let northernProfile = DaylightMath.elevationProfile(on:ribbonDate,coordinate:SunCoordinate(latitude:60,longitude:-122.4),calendar:pacific)
        let sfTwilight = DaylightMath.civilTwilightRanges(profile:sfProfile)
        let northernTwilight = DaylightMath.civilTwilightRanges(profile:northernProfile)
        check(sfProfile.count == 289 && sfTwilight.count == 2, "Daylight gradient samples the full solar trajectory and finds dawn and dusk")
        check(northernTwilight.reduce(0) { $0+$1.upperBound-$1.lowerBound } > sfTwilight.reduce(0) { $0+$1.upperBound-$1.lowerBound }, "Higher-latitude civil twilight naturally takes longer rather than using a fixed fade duration")
        let officialTransitions = DaylightMath.sunTransitions(on:ribbonDate,coordinate:sfRibbon,calendar:pacific)
        check(officialTransitions.count == 2 && officialTransitions[0].sunrise && !officialTransitions[1].sunrise, "Hover labels retain official sunrise and sunset independently of gradient endpoints")
        let quickDelete = CalendarModel(bank:bank,reconnectIfAuthorized:false)
        let quickCanvas = CalendarCanvas(model:quickDelete)
        quickDelete.selected = ["one"]
        let beforeQuickDelete = quickDelete.entries.first(where:{ $0.id == "one" })!
        quickCanvas.keyDown(with:deleteKey)
        check(!quickDelete.entries.contains(where:{ $0.id == "one" }) && quickDelete.message == nil, "Delete key immediately removes a selected editable event")
        quickCanvas.undoManager?.undo()
        let restoredQuickDelete = quickDelete.entries.first(where:{ $0.id == "one" })
        check(restoredQuickDelete?.title == beforeQuickDelete.title && restoredQuickDelete?.start == beforeQuickDelete.start && restoredQuickDelete?.end == beforeQuickDelete.end, "Keyboard undo restores the immediately deleted event and its original times")
        quickCanvas.undoManager?.redo()
        check(!quickDelete.entries.contains(where:{ $0.id == "one" }), "Keyboard redo deletes the restored event again")
        let sidebarPreference = UserDefaults.standard.object(forKey:"sidebarVisible")
        let bankPreference = UserDefaults.standard.object(forKey:"eventBankCollapsed")
        UserDefaults.standard.set(true,forKey:"sidebarVisible")
        UserDefaults.standard.set(false,forKey:"eventBankCollapsed")
        func panelKey(_ character: String) -> NSEvent {
            NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:.command,timestamp:0,windowNumber:0,context:nil,characters:character,charactersIgnoringModifiers:character,isARepeat:false,keyCode:0)!
        }
        _ = quickCanvas.performKeyEquivalent(with:panelKey("c"))
        _ = quickCanvas.performKeyEquivalent(with:panelKey("b"))
        check(UserDefaults.standard.bool(forKey:"sidebarVisible") && !UserDefaults.standard.bool(forKey:"eventBankCollapsed"), "Old command shortcuts no longer toggle panes")
        check(quickDelete.handleViewLetter("s") && !UserDefaults.standard.bool(forKey:"sidebarVisible"), "S hides the calendar sidebar")
        check(quickDelete.handleViewLetter("b") && UserDefaults.standard.bool(forKey:"eventBankCollapsed"), "B collapses the task bank")
        _ = quickDelete.handleViewLetter("s"); _ = quickDelete.handleViewLetter("b")
        check(UserDefaults.standard.bool(forKey:"sidebarVisible") && !UserDefaults.standard.bool(forKey:"eventBankCollapsed"), "Single-letter shortcuts toggle both panes back open")
        if let sidebarPreference { UserDefaults.standard.set(sidebarPreference,forKey:"sidebarVisible") } else { UserDefaults.standard.removeObject(forKey:"sidebarVisible") }
        if let bankPreference { UserDefaults.standard.set(bankPreference,forKey:"eventBankCollapsed") } else { UserDefaults.standard.removeObject(forKey:"eventBankCollapsed") }
        let gradientBitmap = NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:80,pixelsHigh:80,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep:gradientBitmap)
        NSColor.white.setFill(); NSRect(x:0,y:0,width:80,height:80).fill()
        DaylightGradientRenderer.draw([-18,-18],in:NSRect(x:0,y:0,width:20,height:80),nightColor:.black,maximumAlpha:0.5)
        NSGraphicsContext.restoreGraphicsState()
        let shadedPixel = gradientBitmap.colorAt(x:10,y:40)!.usingColorSpace(.deviceRGB)!
        let daylightPixel = gradientBitmap.colorAt(x:50,y:40)!.usingColorSpace(.deviceRGB)!
        check(shadedPixel.redComponent < 0.8, "Nighttime ribbon gradient shades its own column")
        check(daylightPixel.redComponent > 0.99 && daylightPixel.greenComponent > 0.99 && daylightPixel.blueComponent > 0.99, "A nighttime ribbon cannot tint daytime in neighboring calendar columns")
        let daylightPreference = UserDefaults.standard.object(forKey:"daylightShading")
        let ribbonService = DaylightLocation(); ribbonService.enabled = true
        let sfZone = TimeZone(identifier:"America/Los_Angeles")!
        let baZone = TimeZone(identifier:"America/Argentina/Buenos_Aires")!
        let independentSF = ribbonService.elevationProfile(on:ribbonDate,calendar:pacific,ribbonZone:sfZone)!
        let independentBA = ribbonService.elevationProfile(on:ribbonDate,calendar:pacific,ribbonZone:baZone)!
        let afternoonIndex = (15*60+30)/5
        check(DaylightMath.civilDarkness(elevation:independentSF[afternoonIndex]) == 0 && DaylightMath.civilDarkness(elevation:independentBA[afternoonIndex]) == 1, "Comparison ribbon uses Buenos Aires night while San Francisco remains in daylight at the same instant")
        let distinctBitmap = NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:68,pixelsHigh:1440,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep:distinctBitmap)
        NSColor.white.setFill(); NSRect(x:0,y:0,width:68,height:1440).fill()
        DaylightGradientRenderer.draw(independentBA,in:NSRect(x:0,y:0,width:34,height:1440),nightColor:.black,maximumAlpha:0.4)
        DaylightGradientRenderer.draw(independentSF,in:NSRect(x:34,y:0,width:34,height:1440),nightColor:.black,maximumAlpha:0.4)
        NSGraphicsContext.restoreGraphicsState()
        // Bitmap y is top-down; this context's drawing coordinates are bottom-up.
        let baEvening = distinctBitmap.colorAt(x:17,y:1440-930)!.usingColorSpace(.deviceRGB)!.redComponent
        let sfAfternoon = distinctBitmap.colorAt(x:51,y:1440-930)!.usingColorSpace(.deviceRGB)!.redComponent
        check(baEvening < sfAfternoon-0.2, "Rendered comparison ribbon stays dark beside the primary ribbon's clear afternoon")
        var baPrimaryCalendar = pacific; baPrimaryCalendar.timeZone = baZone
        let baPrimaryDate = baPrimaryCalendar.date(from:DateComponents(year:2026,month:11,day:13))!
        let sfAsComparison = ribbonService.elevationProfile(on:baPrimaryDate,calendar:baPrimaryCalendar,ribbonZone:sfZone)!
        let baAsPrimary = ribbonService.elevationProfile(on:baPrimaryDate,calendar:baPrimaryCalendar,ribbonZone:baZone)!
        check(sfAsComparison != baAsPrimary, "Swapping primary timezone preserves distinct per-city daylight calculations")
        if let daylightPreference { UserDefaults.standard.set(daylightPreference,forKey:"daylightShading") } else { UserDefaults.standard.removeObject(forKey:"daylightShading") }
        check(DaylightMath.darkness(elevation:-18,mode:.astronomical) == 1 && DaylightMath.darkness(elevation:-0.833,mode:.astronomical) == 0, "Full twilight fades from the horizon to eighteen degrees below it")
        check(DaylightMath.darkness(elevation:-6,mode:.astronomical) > 0 && DaylightMath.darkness(elevation:-6,mode:.astronomical) < 1, "Full twilight is still partially light at the civil-twilight boundary")
        check(DaylightMath.darkness(elevation:-12,mode:.astronomical) > DaylightMath.darkness(elevation:-6,mode:.astronomical), "Full twilight continues darkening through nautical twilight")
        let fullTwilight = DaylightMath.twilightRanges(profile:sfProfile,mode:.astronomical)
        check(fullTwilight.reduce(0) { $0+$1.upperBound-$1.lowerBound } > sfTwilight.reduce(0) { $0+$1.upperBound-$1.lowerBound }, "Full twilight has a longer natural transition than civil twilight")
        let weatherFixture = Data(#"{"hourly":{"time":[0,3600],"temperature_2m":[64,null],"precipitation":[0,2.5],"cloud_cover":[10,95],"weather_code":[0,63],"wind_speed_10m":[4,22],"wind_direction_10m":[0,225],"is_day":[1,0]}}"#.utf8)
        let weatherHours = try! JSONDecoder().decode(WeatherResponse.self,from:weatherFixture).hours()
        check(weatherHours.count == 2 && weatherHours[1].date.timeIntervalSince(weatherHours[0].date) == 3600, "Weather timestamps decode as absolute instants without timezone ambiguity")
        check(weatherHours[0].symbol == "sun.max.fill" && weatherHours[1].symbol == "cloud.rain.fill", "Weather overlay distinguishes clear sky and rain")
        check(weatherHours[1].temperature == nil && weatherHours[1].precipitation == 2.5, "Missing weather values remain missing rather than becoming false zero readings")
        check(weatherHours[1].detail.contains("22 mph") && WeatherHour.compass(225) == "SW", "Weather hover details include wind speed and direction")
        let weatherURL = URLComponents(url:WeatherOverlay.url(latitude:37.7749,longitude:-122.4194),resolvingAgainstBaseURL:false)!
        check(weatherURL.host == "api.open-meteo.com" && weatherURL.queryItems?.contains(where:{ $0.name == "timeformat" && $0.value == "unixtime" }) == true, "Weather request uses HTTPS forecast service and unambiguous timestamps")
        check(weatherURL.queryItems?.contains(where:{ $0.name == "temperature_unit" && $0.value == "fahrenheit" }) == true && weatherHours[0].temperature == 64, "Display conversion leaves forecast storage and chart and outdoor-window calculations in Fahrenheit")
        let detailedWeatherFixture = Data(#"{"hourly":{"time":[0],"temperature_2m":[64],"precipitation":[1.2],"cloud_cover":[80],"weather_code":[63],"wind_speed_10m":[12],"wind_direction_10m":[225],"is_day":[1],"apparent_temperature":[61],"relative_humidity_2m":[75],"precipitation_probability":[85],"wind_gusts_10m":[22],"uv_index":[5.2]}}"#.utf8)
        let detailedWeather = try! JSONDecoder().decode(WeatherResponse.self,from:detailedWeatherFixture).hours()[0]
        check(abs((detailedWeather.precipitationInches ?? 0)-1.2/25.4) < 0.000001, "Weather hover converts rainfall from millimeters to inches")
        var coldFeelsLike = detailedWeather
        coldFeelsLike.apparentTemperature = -20
        let combinedScale = WeatherStripScale(hours:[coldFeelsLike])
        check(combinedScale.lower <= -20 && combinedScale.upper >= 64, "Weather strip scale includes both actual and feels-like temperatures")
        check(detailedWeather.windFlowVector!.x > 0 && detailedWeather.windFlowVector!.y < 0, "Wind from SW arrow points toward NE")
        check(detailedWeather.cloudDescription == "Mostly cloudy", "Cloud cover label describes sky coverage separately from rain")
        let allWeatherScales = WeatherStripScale(hours:[detailedWeather])
        check(allWeatherScales.rainUpper >= 1.2 && allWeatherScales.windUpper >= 22, "Rain and shared wind/gust scales cover the forecast values")
        check(detailedWeather.uvIndex == 5.2, "Weather decodes hourly UV index")
        check(weatherHours[0].uvIndex == nil, "Missing UV data stays unavailable rather than becoming zero")
        check(weatherURL.queryItems?.first(where:{ $0.name == "hourly" })?.value?.components(separatedBy:",").contains("uv_index") == true, "Weather request includes hourly UV")
        check(detailedWeather.apparentTemperature == 61 && detailedWeather.humidity == 75, "Large weather card receives feels-like temperature and humidity")
        check(detailedWeather.precipitationProbability == 85 && detailedWeather.windGusts == 22, "Large weather card receives precipitation probability and wind gusts")
        let modes = CalendarModel(bank:bank,reconnectIfAuthorized:false)
        modes.jump(to:modes.calendar.date(from:DateComponents(year:2026,month:11,day:14))!)
        for (mode,count) in [(CalendarViewMode.day,1),(.twoDays,2),(.threeDays,3),(.fourDays,4),(.fiveDays,5),(.sixDays,6),(.week,7)] {
            modes.setView(mode)
            check(modes.visibleDayCount == count && modes.calendar.dateComponents([.day],from:modes.weekStart,to:modes.weekEnd).day == count, "Timeline view loads exactly its requested number of days")
            let origin = modes.weekStart
            modes.navigate(1)
            check(modes.calendar.dateComponents([.day],from:origin,to:modes.weekStart).day == count, "Timeline navigation advances one visible period")
        }
        modes.jump(to:modes.calendar.date(from:DateComponents(year:2026,month:11,day:14))!)
        modes.setView(.month)
        check(modes.calendar.dateComponents([.day],from:modes.weekStart,to:modes.weekEnd).day == 42, "Month data includes all six displayed weeks including neighboring dates")
        modes.navigate(1)
        check(modes.calendar.component(.month,from:modes.anchor) == 12, "Month navigation advances a calendar month")
        modes.setView(.year)
        check(modes.calendar.component(.month,from:modes.weekStart) == 1 && modes.calendar.component(.year,from:modes.weekEnd) == 2027, "Year view loads one complete calendar year")
        modes.navigate(1)
        check(modes.calendar.component(.year,from:modes.anchor) == 2027, "Year navigation advances one year")
        let partialAllDay = AllDayLayout.spans([
            TimedInterval(id:"same-date",start:allDayDate(2).addingTimeInterval(3600),end:allDayDate(2).addingTimeInterval(7200)),
            TimedInterval(id:"clipped",start:allDayDate(-1),end:allDayDate(0).addingTimeInterval(3600)),
            TimedInterval(id:"invalid",start:allDayDate(3),end:allDayDate(3))
        ],weekStart:allDayBase,calendar:pacific)
        check(partialAllDay.count == 2 && partialAllDay.allSatisfy { $0.endDay > $0.firstDay }, "Rounded or clipped all-day spans cannot collapse to accent-only slivers")
        check(partialAllDay.first(where:{ $0.id == "same-date" })?.endDay == 3, "Same-date all-day interval gets exactly one day")
        check(partialAllDay.first(where:{ $0.id == "clipped" })?.endDay == 1, "All-day interval clipped at the visible boundary occupies the first day")
        let shortSpan = AllDayLayout.spans([TimedInterval(id:"long",start:allDayDate(-1),end:allDayDate(5))],weekStart:allDayBase,calendar:pacific,dayCount:2)
        check(shortSpan[0].firstDay == 0 && shortSpan[0].endDay == 2, "All-day bars clip correctly in a two-day view")
        do {
            var display = Calendar(identifier:.gregorian)
            display.timeZone = TimeZone(identifier:"America/Los_Angeles")!
            var editor = display; editor.timeZone = TimeZone(secondsFromGMT:0)!
            func date(_ day: Int, _ calendar: Calendar) -> Date { calendar.date(from:DateComponents(year:2026,month:12,day:day))! }
            let first = date(4,display)
            var draft = EventDraft(title:"Inclusive all-day rendering",start:first,end:date(5,display),calendarID:"work",allDay:true,timeZoneID:"GMT")
            draft.setDisplayedEndDate(date(5,editor),calendar:editor)
            check(draft.displayedEndDate(calendar:editor) == date(5,editor), "Regression: editor retains December 5 as the chosen last day")
            let projected = AllDayLayout.spans([TimedInterval(id:"regression",start:draft.start,end:draft.end)],weekStart:first,calendar:display)
            check(projected.first?.firstDay == 0 && projected.first?.endDay == 2, "A timezone-shifted all-day end after midnight includes both December 4 and December 5")
            let savedModel = CalendarModel(bank:bank,reconnectIfAuthorized:false)
            savedModel.jump(to:first)
            check(savedModel.save(draft), "The timezone regression fixture saves through the normal event path")
            let reloaded = savedModel.entries.first(where:{ $0.title == draft.title })!
            let savedSpan = AllDayLayout.spans([TimedInterval(id:reloaded.id,start:reloaded.start,end:reloaded.end)],weekStart:first,calendar:display)
            check(savedSpan.first?.endDay == 2, "Saving and reloading the event preserves both displayed days")
            for last in [date(5,display),date(5,display).addingTimeInterval(1),date(5,display).addingTimeInterval(16*3600)] {
                let span = AllDayLayout.spans([TimedInterval(id:"edge",start:first,end:last)],weekStart:first,calendar:display)
                let expected = last == date(5,display) ? 1 : 2
                check(span.first?.endDay == expected, "Only an exact display-midnight end excludes that date")
            }
            let monthEntry = CalendarEntry(id:"month-match",title:"Trip",start:first,end:draft.end,calendarID:"work",color:.systemBlue,allDay:true)
            check(CalendarViewDates.events([monthEntry],on:date(5,display),calendar:display).count == 1, "Timeline all-day bars agree with month and year day-overlap rules")
        }
        check(AllDayTrayLayout.collapsedHeight(rows:2) == 40 && AllDayTrayLayout.collapsedHeight(rows:6) == 68, "Collapsed all-day ribbons reserve six pixels plus a one-pixel gap")
        let thinRow = AllDayTrayLayout.rowFrame(row:4,expansion:0)
        let middleRow = AllDayTrayLayout.rowFrame(row:4,expansion:0.5)
        let fullRow = AllDayTrayLayout.rowFrame(row:4,expansion:1)
        check(thinRow.y == 52 && thinRow.height == 6 && fullRow.y == 74 && fullRow.height == 16, "A hidden calendar-colored line expands into the same event's full row")
        check(middleRow.y == 63 && middleRow.height == 11, "All-day row position and height interpolate smoothly in both directions")
        check(AllDayTrayLayout.expansion(height:68,rows:6) == 0 && AllDayTrayLayout.expansion(height:90,rows:6) == 0.5 && AllDayTrayLayout.expansion(height:112,rows:6) == 1, "Tray height drives matching line-to-card expansion and collapse progress")
        let boundaryEvents = [CalendarEntry(id:"ends-midnight",title:"Trip",start:allDayDate(0),end:allDayDate(1),calendarID:"work",color:.systemBlue,allDay:true)]
        check(CalendarViewDates.events(boundaryEvents,on:allDayDate(1),calendar:pacific).isEmpty, "Month and year summaries respect exclusive all-day end dates")
        do { count += try EventBankTests.run() } catch { fatalError("Event bank checks failed: \(error)") }
        do {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [StalledWeatherProtocol.self]
            let weather = WeatherOverlay(session:URLSession(configuration:configuration),timeout:0.06)
            let previous = weather.enabled
            let previousPlace = weather.selectedLocation
            weather.chooseLocation(WeatherPlace.timezone("America/Los_Angeles"))
            defer { weather.chooseLocation(previousPlace) }
            let previousStrip = weather.showHorizontalStrip
            defer { weather.enabled = previous; weather.showHorizontalStrip = previousStrip }
            weather.showHorizontalStrip = false
            weather.enabled = true
            weather.load(zoneID:"America/Los_Angeles")
            check(weather.isLoading, "Weather starts loading")
            try? await Task.sleep(nanoseconds:180_000_000)
            check(!weather.isLoading && weather.status.contains("isn’t responding"), "Stalled weather stops at its hard deadline")
            weather.load(zoneID:"America/Los_Angeles",force:true)
            check(weather.isLoading, "Weather can retry after timing out")
            weather.enabled = false; weather.showHorizontalStrip = true
            weather.load(zoneID:"America/Los_Angeles")
            check(weather.needsData && weather.isLoading, "Horizontal strip loads independently with overlay off")
            weather.showHorizontalStrip = false
            weather.load(zoneID:"America/Los_Angeles")
            check(!weather.isLoading, "Turning both weather views off clears loading immediately")
            try? await Task.sleep(nanoseconds:100_000_000)
            check(!weather.isLoading, "An old weather request cannot restore stale loading state")
        }
        do {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [SuccessfulWeatherProtocol.self]
            let weather = WeatherOverlay(session:URLSession(configuration:configuration),timeout:2)
            let oldPlace = weather.selectedLocation, oldOverlay = weather.enabled, oldStrip = weather.showHorizontalStrip
            defer { weather.chooseLocation(oldPlace); weather.enabled = oldOverlay; weather.showHorizontalStrip = oldStrip }
            weather.chooseLocation(WeatherPlace.timezone("America/Los_Angeles"))
            weather.enabled = false; weather.showHorizontalStrip = true
            weather.load(zoneID:"America/Los_Angeles",force:true)
            check(weather.isLoading, "Successful weather request initially shows loading")
            for _ in 0..<100 where weather.isLoading { try? await Task.sleep(nanoseconds:10_000_000) }
            check(!weather.isLoading && weather.hours.count == 2, "Successful forecast response exits loading and publishes hours")
            let start = Date(timeIntervalSince1970:1_794_700_000)
            let visible = weather.hours(from:start,to:start.addingTimeInterval(7200))
            check(visible.count == 2, "Successful forecast populates the indexed data used by the weather strip")
            check(WeatherStripPresentation.resolve(visible:true,loading:weather.isLoading,hasForecast:!visible.isEmpty) == .forecast, "Weather strip expands after a successful forecast")
        }
        print("Passed \(count) calendar behavior checks.")
    }
}

private final class StalledWeatherProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { }
    override func stopLoading() { }
}

private final class SuccessfulWeatherProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let body = #"{"hourly":{"time":[1794700000,1794703600],"temperature_2m":[61,62],"precipitation":[0,0],"cloud_cover":[30,40],"weather_code":[2,2],"wind_speed_10m":[5,6],"wind_direction_10m":[90,90],"is_day":[1,1]}}"#
        client?.urlProtocol(self,didReceive:HTTPURLResponse(url:request.url!,statusCode:200,httpVersion:nil,headerFields:["Content-Type":"application/json"])!,cacheStoragePolicy:.notAllowed)
        client?.urlProtocol(self,didLoad:Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() { }
}

@MainActor private final class PopoverResizeFixture: ObservableObject {
    @Published var height: CGFloat = 200
}
private struct PopoverResizeFixtureView: View {
    @ObservedObject var fixture: PopoverResizeFixture
    var body: some View { Text("Editor sizing regression").frame(width:320,height:fixture.height).fixedSize() }
}
