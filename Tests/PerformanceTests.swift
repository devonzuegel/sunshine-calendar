import Foundation
import Combine

@MainActor enum PerformanceTests {
    static func run() throws -> Int {
        var count = 0
        func check(_ value: @autoclosure () -> Bool, _ label: String) { precondition(value(),label); count += 1 }
        // Compare the cache against newly constructed formatters, including
        // DST transitions, fractional-hour zones, locales, and alternating keys.
        let dates = [1_794_700_000.0,1_794_700_000+100*86400,1_794_700_000-240*86400].map(Date.init(timeIntervalSince1970:))
        for zoneID in ["America/Los_Angeles","America/Argentina/Buenos_Aires","Asia/Kathmandu","UTC"] {
            let zone = TimeZone(identifier:zoneID)!
            for locale in [Locale(identifier:"en_US_POSIX"),Locale(identifier:"es_AR"),Locale.current] {
                for localized in [false,true] {
                    for format in localized ? ["ha","EEE MMM d"] : ["ha","h:mma","h:mm"] {
                        let reference = DateFormatter(); reference.locale = locale; reference.timeZone = zone
                        if localized { reference.setLocalizedDateFormatFromTemplate(format) } else { reference.dateFormat = format }
                        for date in dates {
                            check(CalendarDateFormatting.string(date,timeZone:zone,format:format,locale:locale,localized:localized) == reference.string(from:date),"Cached date formatting retains timezone, locale, and format semantics")
                        }
                    }
                }
            }
        }
        let origin = Date(timeIntervalSince1970:0)
        func hour(_ seconds: Double, _ temperature: Double = 60) -> WeatherHour {
            WeatherHour(date:origin.addingTimeInterval(seconds),temperature:temperature,precipitation:0,cloudCover:40,code:2,windSpeed:5,windDirection:90,isDay:true)
        }
        for values in [[],[hour(0)],[hour(0),hour(3600),hour(3600,70),hour(7200)],[hour(7200),hour(0),hour(3600)]] {
            let index = WeatherHourIndex(values)
            for (start,end) in [(-3600.0,0.0),(0,3600),(3600,7200),(0,10800),(7200,7200),(7200,3600)] {
                let a = origin.addingTimeInterval(start), b = origin.addingTimeInterval(end)
                let reference = values.filter { $0.date >= a && $0.date < b }
                for _ in 0..<2 {
                    let actual = index.hours(from:a,to:b)
                    check(actual.map(\.date) == reference.map(\.date) && actual.map(\.temperature) == reference.map(\.temperature),"Indexed weather ranges preserve boundaries, duplicates, and source order")
                }
            }
            check(index.hour(at:origin.addingTimeInterval(3600))?.temperature == values.first(where:{ $0.date == origin.addingTimeInterval(3600) })?.temperature,"Exact-hour lookup retains first-match behavior")
        }
        // Calendar boundaries are actual local midnights, including 23/25-hour
        // DST days. A fresh index after a response must never return old values.
        var calendar = Calendar(identifier:.gregorian); calendar.timeZone = TimeZone(identifier:"America/Los_Angeles")!
        for parts in [DateComponents(year:2026,month:3,day:8),DateComponents(year:2026,month:11,day:1)] {
            let day = calendar.date(from:parts)!, next = calendar.date(byAdding:.day,value:1,to:day)!
            let values = (-2...28).map { offset in hour(day.timeIntervalSince1970+Double(offset)*3600) }
            let index = WeatherHourIndex(values)
            check(index.hours(from:day,to:next).map(\.date) == values.filter { $0.date >= day && $0.date < next }.map(\.date),"Weather lookup respects DST midnight boundaries")
        }
        check(WeatherHourIndex([hour(0,45)]).hour(at:origin)?.temperature == 45 && WeatherHourIndex([hour(0,80)]).hour(at:origin)?.temperature == 80,"New weather indices cannot reuse stale forecast values")
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("bank-performance-tests-"+UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:folder) }
        let first = EventBankStore(folder:folder,watch:false), second = EventBankStore(folder:folder,watch:false)
        let original = BankTask(title:"A",minutes:30,calendarID:"work",calendarTitle:"Work",account:"Sample",position:2)
        try first.save(original)
        check(first.tasks.map(\.title) == ["A"],"Bank task cache reflects additions")
        first.refresh() // Normalize the initial storage-status label before measuring an unchanged poll.
        var publications = 0
        let subscription = first.objectWillChange.sink { publications += 1 }
        first.refresh(); first.refresh()
        check(publications == 0,"Unchanged bank refreshes do not invalidate UI")
        var update = second.records[original.id] ?? original
        second.refresh(); update = second.records[original.id]!
        update.title = "Updated"; update.minutes = 80
        try second.save(update,expectedRevision:update.revision)
        first.refresh()
        check(first.tasks.first?.title == "Updated" && first.totalMinutes == 80 && publications > 0,"Synced edits invalidate cached tasks and publish real changes")
        let new = BankTask(title:"B",minutes:15,calendarID:"work",calendarTitle:"Work",account:"Sample",position:1)
        try first.save(new)
        check(first.tasks.map(\.title) == ["B","Updated"],"Cached bank order follows explicit positions")
        try first.reorder(original.id,before:new.id)
        check(first.tasks.map(\.title) == ["Updated","B"],"Reorder invalidates cached bank order")
        try first.remove(new.id)
        check(first.tasks.map(\.title) == ["Updated"] && first.totalMinutes == 80,"Deletion invalidates cached bank contents and duration")
        try first.schedule(original.id,at:origin) { _ in "synthetic-event" }
        check(first.tasks.isEmpty,"Scheduled tasks disappear from cached bank immediately")
        withExtendedLifetime(subscription) {}
        return count
    }
}
