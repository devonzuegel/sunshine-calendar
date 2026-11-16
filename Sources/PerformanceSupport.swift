import Foundation

// Main-thread formatters are shared only for identical locale/calendar/zone/format
// settings. The bounded cache avoids repeatedly rebuilding Foundation's formatter
// machinery during drawing while still following locale and timezone changes.
@MainActor enum CalendarDateFormatting {
    private static let formatters: NSCache<NSString,DateFormatter> = {
        let cache = NSCache<NSString,DateFormatter>(); cache.countLimit = 64; return cache
    }()
    private static let localeObserver = NotificationCenter.default.addObserver(forName:NSLocale.currentLocaleDidChangeNotification,object:nil,queue:.main) { _ in
        Task { @MainActor in formatters.removeAllObjects() }
    }
    static func string(_ date: Date, timeZone: TimeZone, format: String, locale: Locale = .current, localized: Bool = false) -> String {
        _ = localeObserver
        let key = "\(locale.identifier)\u{0}\(Calendar.current.identifier)\u{0}\(timeZone.identifier)\u{0}\(localized)\u{0}\(format)" as NSString
        let formatter: DateFormatter
        if let existing = formatters.object(forKey:key) { formatter = existing }
        else {
            formatter = DateFormatter(); formatter.locale = locale; formatter.timeZone = timeZone
            if localized { formatter.setLocalizedDateFormatFromTemplate(format) } else { formatter.dateFormat = format }
            formatters.setObject(formatter,forKey:key)
        }
        return formatter.string(from:date)
    }
}

// Immutable forecast data gets one index per response. Queries retain the same
// inclusive-start/exclusive-end semantics and original order as Array.filter.
// The fallback also keeps malformed/out-of-order responses behaving as before.
@MainActor final class WeatherHourIndex {
    private struct RangeKey: Hashable { let start: Date; let end: Date }
    private let values: [WeatherHour]
    private let sorted: Bool
    private var ranges: [RangeKey:[WeatherHour]] = [:]
    init(_ values: [WeatherHour]) {
        self.values = values
        sorted = zip(values,values.dropFirst()).allSatisfy { $0.date <= $1.date }
    }
    private func lowerBound(_ date: Date) -> Int {
        var low = 0, high = values.count
        while low < high {
            let middle = low+(high-low)/2
            if values[middle].date < date { low = middle+1 } else { high = middle }
        }
        return low
    }
    func hours(from start: Date, to end: Date) -> [WeatherHour] {
        guard start < end else { return [] }
        let key = RangeKey(start:start,end:end)
        if let cached = ranges[key] { return cached }
        let result = sorted ? Array(values[lowerBound(start)..<lowerBound(end)]) : values.filter { $0.date >= start && $0.date < end }
        if ranges.count >= 128 { ranges.removeAll(keepingCapacity:true) }
        ranges[key] = result
        return result
    }
    func hour(at date: Date) -> WeatherHour? {
        guard sorted else { return values.first { $0.date == date } }
        let index = lowerBound(date)
        return index < values.count && values[index].date == date ? values[index] : nil
    }
}
