import Foundation
import CoreLocation
import SwiftUI

struct SunCoordinate: Equatable {
    let latitude: Double
    let longitude: Double
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
    var body: some View {
        Menu {
            Toggle("Shade nighttime hours",isOn:$daylight.enabled)
                .onChange(of:daylight.enabled) { _,enabled in if enabled { daylight.refresh() } }
            Text(daylight.status)
            Text("Timezone: \(TimeZone.current.identifier)")
            Button("Refresh Mac Location") { daylight.refresh() }
        } label: { Image(systemName:"sun.max") }
        .help(daylight.status + " · " + TimeZone.current.identifier)
        .onAppear { daylight.start() }
    }
}
