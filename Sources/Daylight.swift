import Foundation
import CoreLocation
import SwiftUI

struct SunCoordinate: Equatable {
    let latitude: Double
    let longitude: Double
}

enum TwilightMode: String, CaseIterable, Identifiable {
    case civil, astronomical
    var id: String { rawValue }
    var label: String { self == .civil ? "Civil twilight" : "Full astronomical twilight" }
    var darkestElevation: Double { self == .civil ? -6 : -18 }
}

enum DaylightMath {
    // NOAA General Solar Position Calculations, 90.833° apparent sunrise.
    // https://www.gml.noaa.gov/grad/solcalc/solareqns.PDF
    static func solarHeight(at date: Date, coordinate: SunCoordinate) -> Double {
        var utc = Calendar(identifier:.gregorian); utc.timeZone = TimeZone(secondsFromGMT:0)!
        let parts = utc.dateComponents([.hour,.minute,.second],from:date)
        let hour = Double(parts.hour!) + Double(parts.minute!)/60 + Double(parts.second!)/3600
        let ordinal = utc.ordinality(of:.day,in:.year,for:date)!
        let days = utc.range(of:.day,in:.year,for:date)!.count
        let gamma = 2 * Double.pi / Double(days) * (Double(ordinal-1) + (hour-12)/24)
        let equation = 229.18 * (0.000075 + 0.001868*cos(gamma) - 0.032077*sin(gamma) - 0.014615*cos(2*gamma) - 0.040849*sin(2*gamma))
        let declination = 0.006918 - 0.399912*cos(gamma) + 0.070257*sin(gamma) - 0.006758*cos(2*gamma) + 0.000907*sin(2*gamma) - 0.002697*cos(3*gamma) + 0.00148*sin(3*gamma)
        let solarMinutes = hour*60 + equation + 4*coordinate.longitude
        let angle = (solarMinutes/4 - 180) * Double.pi/180
        let latitude = coordinate.latitude * Double.pi/180
        return sin(latitude)*sin(declination) + cos(latitude)*cos(declination)*cos(angle)
    }
    static func solarElevation(at date: Date, coordinate: SunCoordinate) -> Double {
        asin(max(-1,min(1,solarHeight(at:date,coordinate:coordinate)))) * 180 / .pi
    }
    // Civil twilight: darkness follows solar depression below apparent sunset,
    // reaching its maximum at the established -6° civil-twilight boundary.
    // This encodes solar geometry, not a fixed-duration fade or measured lux.
    static func darkness(elevation: Double, mode: TwilightMode) -> Double {
        min(1,max(0,(-0.833-elevation)/(-mode.darkestElevation-0.833)))
    }
    static func civilDarkness(elevation: Double) -> Double { darkness(elevation:elevation,mode:.civil) }
    static func civilTwilightRanges(profile: [Double]) -> [ClosedRange<Double>] { twilightRanges(profile:profile,mode:.civil) }
    static func twilightRanges(profile: [Double], mode: TwilightMode) -> [ClosedRange<Double>] {
        guard profile.count > 1 else { return [] }
        let step = 1440/Double(profile.count-1)
        var ranges: [ClosedRange<Double>] = []
        var beginning: Double?
        for (index,elevation) in profile.enumerated() {
            let twilight = elevation > mode.darkestElevation && elevation < -0.833
            if twilight && beginning == nil { beginning = max(0,Double(index-1)*step) }
            if !twilight, let start = beginning { ranges.append(start...min(1440,Double(index)*step)); beginning = nil }
        }
        if let beginning { ranges.append(beginning...1440) }
        return ranges
    }
    static func sunTransitions(on day: Date, coordinate: SunCoordinate, calendar: Calendar = .current) -> [(minute: Double, sunrise: Bool)] {
        let ranges = nightRanges(on:day,coordinate:coordinate,calendar:calendar)
        var result: [(Double,Bool)] = []
        for range in ranges {
            if range.lowerBound > 0 { result.append((range.lowerBound,false)) }
            if range.upperBound < 1440 { result.append((range.upperBound,true)) }
        }
        return result.sorted { $0.0 < $1.0 }
    }
    static func peakMinute(profile: [Double]) -> Double? {
        guard profile.count > 1, let peak = profile.indices.max(by:{ profile[$0] < profile[$1] }) else { return nil }
        let step = 1440/Double(profile.count-1)
        guard peak > 0, peak < profile.count-1 else { return Double(peak)*step }
        let a = profile[peak-1], b = profile[peak], c = profile[peak+1]
        let denominator = a-2*b+c
        let adjustment = abs(denominator) > 0.0000001 ? max(-0.5,min(0.5,0.5*(a-c)/denominator)) : 0
        return (Double(peak)+adjustment)*step
    }
    static func elevationProfile(on day: Date, coordinate: SunCoordinate, calendar: Calendar = .current) -> [Double] {
        let start = calendar.startOfDay(for:day)
        return stride(from:0,through:1440,by:5).map { minute in
            let instant = minute == 1440 ? calendar.date(byAdding:.day,value:1,to:start)! : calendar.date(bySettingHour:minute/60,minute:minute%60,second:0,of:start)!
            return solarElevation(at:instant,coordinate:coordinate)
        }
    }
    // Ranges in wall-clock minutes match the calendar's 24-hour drawing grid.
    // Sampling absolute instants built in the display timezone also handles DST,
    // polar day/night, and locations whose solar day crosses display midnight.
    static func nightRanges(on day: Date, coordinate: SunCoordinate, calendar: Calendar = .current) -> [ClosedRange<Double>] {
        let start = calendar.startOfDay(for:day)
        let threshold = sin(-0.833 * Double.pi/180)
        func height(_ minute: Int) -> Double {
            let date: Date
            if minute == 1440 { date = calendar.date(byAdding:.day,value:1,to:start)! }
            else { date = calendar.date(bySettingHour:minute/60,minute:minute%60,second:0,of:start)! }
            return solarHeight(at:date,coordinate:coordinate) - threshold
        }
        var ranges: [ClosedRange<Double>] = []
        var previous = height(0)
        var nightStart: Double? = previous < 0 ? 0 : nil
        for minute in stride(from:5,through:1440,by:5) {
            let current = height(minute)
            if (previous < 0) != (current < 0) {
                let crossing = Double(minute-5) + 5 * (-previous)/(current-previous)
                if current < 0 { nightStart = crossing }
                else if let from = nightStart { ranges.append(from...crossing); nightStart = nil }
            }
            previous = current
        }
        if let from = nightStart { ranges.append(from...1440) }
        return ranges
    }
}

@MainActor final class DaylightLocation: NSObject, ObservableObject, @preconcurrency CLLocationManagerDelegate {
    @Published var twilightMode = TwilightMode(rawValue:UserDefaults.standard.string(forKey:"twilightMode") ?? "") ?? .astronomical {
        didSet { UserDefaults.standard.set(twilightMode.rawValue,forKey:"twilightMode") }
    }
    @Published private(set) var coordinate: SunCoordinate?
    @Published private(set) var status = "Daylight uses your Mac’s location"
    @Published var enabled = UserDefaults.standard.object(forKey:"daylightShading") as? Bool ?? true {
        didSet { UserDefaults.standard.set(enabled,forKey:"daylightShading") }
    }
    private let manager = CLLocationManager()
    private var started = false
    private var requesting = false
    private var cache: [String: [ClosedRange<Double>]] = [:]
    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        manager.distanceFilter = 5000
    }
    func start() {
        guard !started, enabled else { return }
        started = true; refresh()
    }
    func refresh() {
        started = true
        guard CLLocationManager.locationServicesEnabled() else { coordinate = nil; cache = [:]; status = "Enable Location Services to show daylight"; return }
        switch manager.authorizationStatus {
        case .notDetermined:
            status = "Allow location access to show daylight"
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            guard !requesting else { return }
            requesting = true; status = "Finding your location…"
            manager.requestLocation()
        case .denied, .restricted:
            coordinate = nil; cache = [:]
            status = "Location access is off · enable it in System Settings"
        @unknown default: status = "Location unavailable"
        }
    }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard started else { return }
        refresh()
    }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        requesting = false
        guard let location = locations.last, location.horizontalAccuracy >= 0,
              abs(location.timestamp.timeIntervalSinceNow) < 600 else { status = "Location unavailable · try refreshing"; return }
        coordinate = SunCoordinate(latitude:location.coordinate.latitude,longitude:location.coordinate.longitude)
        cache = [:]; status = "Daylight for your Mac’s location"
    }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        requesting = false; status = coordinate == nil ? "Location unavailable · try refreshing" : "Using last location · refresh unavailable"
    }
    static func ribbonCoordinate(for identifier: String) -> SunCoordinate? {
        // These timezone shortcuts intentionally represent the labeled city.
        switch identifier {
        case "America/New_York": return SunCoordinate(latitude:25.7617,longitude:-80.1918) // Miami
        case "America/Los_Angeles": return SunCoordinate(latitude:37.7749,longitude:-122.4194)
        case "America/Argentina/Buenos_Aires", "America/Buenos_Aires": return SunCoordinate(latitude:-34.6037,longitude:-58.3816)
        case "America/Denver": return SunCoordinate(latitude:39.7392,longitude:-104.9903)
        case "America/Chicago": return SunCoordinate(latitude:41.8781,longitude:-87.6298)
        default: return nil
        }
    }
    @Published private var ribbonCoordinates: [String: SunCoordinate] = [:]
    private var requestedRibbonLocations: Set<String> = []
    func prepareRibbonLocations(_ zones: [TimeZone]) {
        for zone in zones where Self.ribbonCoordinate(for:zone.identifier) == nil && !requestedRibbonLocations.contains(zone.identifier) {
            requestedRibbonLocations.insert(zone.identifier)
            let city = zone.identifier.split(separator:"/").last.map(String.init)?.replacingOccurrences(of:"_",with:" ") ?? zone.identifier
            Task {
                let geocoder = CLGeocoder()
                do {
                    if let location = try await geocoder.geocodeAddressString(city).first?.location {
                        ribbonCoordinates[zone.identifier] = SunCoordinate(latitude:location.coordinate.latitude,longitude:location.coordinate.longitude)
                    }
                } catch { requestedRibbonLocations.remove(zone.identifier) }
            }
        }
    }
    func hasRibbonLocation(_ zone: TimeZone) -> Bool {
        Self.ribbonCoordinate(for:zone.identifier) != nil || ribbonCoordinates[zone.identifier] != nil
    }
    func ribbonNightRanges(zone: TimeZone, primaryCalendar: Calendar, today: Date = Date()) -> [ClosedRange<Double>] {
        guard enabled, let coordinate = Self.ribbonCoordinate(for:zone.identifier) ?? ribbonCoordinates[zone.identifier] else { return [] }
        let day = primaryCalendar.startOfDay(for:today)
        let key = "ribbon-\(zone.identifier)-\(primaryCalendar.timeZone.identifier)-\(day.timeIntervalSince1970)"
        if let cached = cache[key] { return cached }
        let ranges = DaylightMath.nightRanges(on:day,coordinate:coordinate,calendar:primaryCalendar)
        if cache.count > 100 { cache = [:] }
        cache[key] = ranges
        return ranges
    }
    func sunTransitions(on day: Date, calendar: Calendar, ribbonZone: TimeZone? = nil) -> [(minute: Double, sunrise: Bool)] {
        guard enabled else { return [] }
        let location = ribbonZone.map { Self.ribbonCoordinate(for:$0.identifier) ?? ribbonCoordinates[$0.identifier] } ?? coordinate
        guard let location else { return [] }
        return DaylightMath.sunTransitions(on:day,coordinate:location,calendar:calendar)
    }
    private var elevationCache: [String: [Double]] = [:]
    func elevationProfile(on day: Date, calendar: Calendar, ribbonZone: TimeZone? = nil) -> [Double]? {
        guard enabled else { return nil }
        let location: SunCoordinate?
        if let ribbonZone { location = Self.ribbonCoordinate(for:ribbonZone.identifier) ?? ribbonCoordinates[ribbonZone.identifier] }
        else { location = coordinate }
        guard let location else { return nil }
        let key = "\(calendar.startOfDay(for:day).timeIntervalSince1970)-\(calendar.timeZone.identifier)-\(location.latitude)-\(location.longitude)"
        if let cached = elevationCache[key] { return cached }
        let values = DaylightMath.elevationProfile(on:day,coordinate:location,calendar:calendar)
        if elevationCache.count > 80 { elevationCache = [:] }
        elevationCache[key] = values
        return values
    }
    func ranges(on day: Date, calendar: Calendar = .current) -> [ClosedRange<Double>] {
        guard enabled, let coordinate else { return [] }
        let key = "\(calendar.startOfDay(for:day).timeIntervalSince1970)-\(calendar.timeZone.identifier)"
        if let cached = cache[key] { return cached }
        let result = DaylightMath.nightRanges(on:day,coordinate:coordinate,calendar:calendar)
        if cache.count > 60 { cache = [:] }
        cache[key] = result
        return result
    }
}

struct DaylightMenu: View {
    @ObservedObject var daylight: DaylightLocation
    var displayTimeZone: TimeZone = .current
    var body: some View {
        Menu {
            Toggle("Shade nighttime hours",isOn:$daylight.enabled)
                .onChange(of:daylight.enabled) { _,enabled in if enabled { daylight.refresh() } }
            Picker("Twilight gradient",selection:$daylight.twilightMode) {
                ForEach(TwilightMode.allCases) { mode in Text(mode.label).tag(mode) }
            }
            Text(daylight.status)
            Text("Timezone: \(displayTimeZone.identifier)")
            Button("Refresh Mac Location") { daylight.refresh() }
        } label: { ToolbarControlLabel(symbol:"sun.max",title:"Daylight",dropdown:true) }
        .menuIndicator(.hidden)
        .appHelp(daylight.status + " · " + displayTimeZone.identifier)
        .onAppear { daylight.start() }
    }
}
