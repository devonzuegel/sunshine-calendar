import Foundation
import AppKit
import Combine

@main struct AuditBenchmark {
    @MainActor static func main() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("sunshine-perf-"+UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:folder) }
        let bank = EventBankStore(folder:folder,watch:false)
        let model = CalendarModel(bank:bank,reconnectIfAuthorized:false)
        var checksum = 0
        func measure(_ name: String, _ block: () -> Void) {
            let start = ProcessInfo.processInfo.systemUptime
            block()
            print("\(name): \(String(format:"%.2f",(ProcessInfo.processInfo.systemUptime-start)*1000)) ms")
        }
        let start = Date(timeIntervalSince1970:1_794_700_000)
        var calendar = Calendar(identifier:.gregorian); calendar.timeZone = TimeZone(identifier:"America/Los_Angeles")!
        measure("event_labels_3000") {
            for i in 0..<3000 {
                let date = start.addingTimeInterval(Double(i%120)*600)
                checksum += EventTimeLabel.string(start:date,end:date.addingTimeInterval(5400),calendar:calendar).count
            }
        }
        measure("localized_date_labels_3000") {
            for i in 0..<3000 { checksum += model.dateLabel(start.addingTimeInterval(Double(i%24)*3600),template:i%2 == 0 ? "ha" : "EEE MMM d").count }
        }
        let weather = (0..<552).map { i in WeatherHour(date:start.addingTimeInterval(Double(i)*3600),temperature:60,precipitation:0,cloudCover:40,code:2,windSpeed:5,windDirection:90,isDay:true) }
        #if PERF_AFTER
        let index = WeatherHourIndex(weather)
        #endif
        measure("weather_day_lookups_10000") {
            for i in 0..<10000 {
                let from = start.addingTimeInterval(Double(i%20)*86400), to = from.addingTimeInterval(86400)
                #if PERF_AFTER
                checksum += index.hours(from:from,to:to).count
                #else
                checksum += weather.filter { $0.date >= from && $0.date < to }.count
                #endif
            }
        }
        for i in 0..<150 { try bank.save(BankTask(title:"Synthetic task \(i)",minutes:30,calendarID:"work",calendarTitle:"Work",account:"Sample",position:Double(150-i))) }
        measure("bank_ordered_reads_1000") { for _ in 0..<1000 { checksum += bank.tasks.count+bank.totalMinutes } }
        var publications = 0
        let subscription = bank.objectWillChange.sink { publications += 1 }
        measure("unchanged_bank_refreshes_5") { for _ in 0..<5 { bank.refresh() } }
        print("unchanged_bank_publications: \(publications)")
        withExtendedLifetime(subscription) {}
        print("checksum: \(checksum)")
    }
}
