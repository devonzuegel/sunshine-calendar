import Foundation
import SwiftUI

// Forecast values stay in Fahrenheit for chart scales and outdoor-window scoring.
// Convert only for display, before rounding either unit.
struct WeatherTemperature {
    let fahrenheit: Double
    var celsius: Double { (fahrenheit-32)*5/9 }
    var celsiusLabel: String { "\(Int(celsius.rounded()))°C" }
    var fahrenheitLabel: String { "\(Int(fahrenheit.rounded()))°F" }
    var pairedLabel: String { celsiusLabel+" / "+fahrenheitLabel }

    static func highLow(high: Double, low: Double) -> (celsius: String, fahrenheit: String) {
        let high = Self(fahrenheit:high), low = Self(fahrenheit:low)
        return ("\(Int(high.celsius.rounded()))°/"+low.celsiusLabel,
                "\(Int(high.fahrenheit.rounded()))°/"+low.fahrenheitLabel)
    }
}

struct WeatherTemperatureText: View {
    let fahrenheit: Double
    var color: Color = .primary
    var referenceSize: CGFloat? = nil
    var body: some View {
        let value = WeatherTemperature(fahrenheit:fahrenheit)
        let reference = Text(" / "+value.fahrenheitLabel).foregroundColor(color.opacity(0.55))
        (Text(value.celsiusLabel).foregroundColor(color)
         + (referenceSize.map { reference.font(.system(size:AppTextSize.points($0))) } ?? reference))
            .lineLimit(1).minimumScaleFactor(0.65)
            .accessibilityLabel(value.pairedLabel)
    }
}

struct WeatherHour: Identifiable {
    var id: Date { date }
    let date: Date
    let temperature: Double?
    let precipitation: Double?
    let cloudCover: Double?
    let code: Int?
    let windSpeed: Double?
    let windDirection: Double?
    let isDay: Bool
    var apparentTemperature: Double? = nil
    var humidity: Double? = nil
    var precipitationProbability: Double? = nil
    var windGusts: Double? = nil
    var uvIndex: Double? = nil
    var precipitationInches: Double? { precipitation.map { $0/25.4 } }
    var symbol: String {
        switch code ?? -1 {
        case 0: return isDay ? "sun.max.fill" : "moon.stars.fill"
        case 1,2: return isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        case 3: return "cloud.fill"
        case 45,48: return "cloud.fog.fill"
        case 71...77,85,86: return "cloud.snow.fill"
        case 95...99: return "cloud.bolt.rain.fill"
        case 51...67,80...82: return "cloud.rain.fill"
        default: return "questionmark.circle"
        }
    }
    var condition: String {
        switch code ?? -1 {
        case 0: return isDay ? "Clear sky" : "Clear night"
        case 1,2: return "Partly cloudy"
        case 3: return "Overcast"
        case 45,48: return "Fog"
        case 51...57: return "Drizzle"
        case 61...67,80...82: return "Rain"
        case 71...77,85,86: return "Snow"
        case 95...99: return "Thunderstorms"
        default: return "Conditions unavailable"
        }
    }
    static func compass(_ degrees: Double) -> String {
        let names = ["N","NE","E","SE","S","SW","W","NW"]
        return names[Int(((degrees.truncatingRemainder(dividingBy:360)+360)/45).rounded()) % 8]
    }
    var cloudDescription: String {
        guard let cover = cloudCover else { return "Unavailable" }
        switch cover { case ..<10: return "Clear"; case ..<50: return "Partly cloudy"; case ..<85: return "Mostly cloudy"; default: return "Overcast" }
    }
    var windFlowVector: CGPoint? {
        guard let direction = windDirection else { return nil }
        let angle = (direction+180)*Double.pi/180
        return CGPoint(x:sin(angle),y:-cos(angle))
    }
    var detail: String {
        var lines = [condition]
        if let temperature { lines[0] += " · "+WeatherTemperature(fahrenheit:temperature).pairedLabel }
        if let precipitation { lines.append(String(format:"Precipitation: %.1f mm",precipitation)) }
        if let cloudCover { lines.append("Cloud cover: \(Int(cloudCover))%") }
        if let windSpeed { lines.append("Wind: \(Int(windSpeed.rounded())) mph" + (windDirection.map { " from " + Self.compass($0) } ?? "")) }
        if let uvIndex { lines.append(String(format:"UV index: %.1f",uvIndex)) }
        return lines.joined(separator:"\n")
    }
}
struct WeatherResponse: Decodable {
    struct Hourly: Decodable {
        let time: [Double]
        let temperature_2m: [Double?]
        let precipitation: [Double?]
        let cloud_cover: [Double?]
        let weather_code: [Int?]
        let wind_speed_10m: [Double?]
        let wind_direction_10m: [Double?]
        let is_day: [Int?]
        let apparent_temperature: [Double?]?
        let relative_humidity_2m: [Double?]?
        let precipitation_probability: [Double?]?
        let wind_gusts_10m: [Double?]?
        let uv_index: [Double?]?
    }
    let hourly: Hourly
    func hours() -> [WeatherHour] {
        let h = hourly
        return h.time.indices.map { index in
            func value<T>(_ items: [T?]) -> T? { items.indices.contains(index) ? items[index] : nil }
            return WeatherHour(date:Date(timeIntervalSince1970:h.time[index]),temperature:value(h.temperature_2m),precipitation:value(h.precipitation),cloudCover:value(h.cloud_cover),code:value(h.weather_code),windSpeed:value(h.wind_speed_10m),windDirection:value(h.wind_direction_10m),isDay:value(h.is_day) == 1,apparentTemperature:value(h.apparent_temperature ?? []),humidity:value(h.relative_humidity_2m ?? []),precipitationProbability:value(h.precipitation_probability ?? []),windGusts:value(h.wind_gusts_10m ?? []),uvIndex:value(h.uv_index ?? []))
        }
    }
}
@MainActor final class WeatherOverlay: ObservableObject {
    @Published var enabled = UserDefaults.standard.bool(forKey:"weatherOverlayEnabled") {
        didSet { UserDefaults.standard.set(enabled,forKey:"weatherOverlayEnabled") }
    }
    @Published var showHorizontalStrip = UserDefaults.standard.object(forKey:"weatherHorizontalStrip") as? Bool ?? true {
        didSet { UserDefaults.standard.set(showHorizontalStrip,forKey:"weatherHorizontalStrip") }
    }
    var needsData: Bool { enabled || showHorizontalStrip }
    @Published var showSky = true
    @Published var showTemperature = true
    @Published var showUV = true
    @Published var showRain = true
    @Published var showWind = true
    enum GraphLayer: CaseIterable { case sky, temperature, uv, rain, wind }
    func selectGraphLayer(_ layer: GraphLayer, exclusively: Bool) {
        if exclusively {
            let alreadyIsolated = showSky == (layer == .sky)
                && showTemperature == (layer == .temperature)
                && showUV == (layer == .uv)
                && showRain == (layer == .rain)
                && showWind == (layer == .wind)
            showSky = alreadyIsolated || layer == .sky
            showTemperature = alreadyIsolated || layer == .temperature
            showUV = alreadyIsolated || layer == .uv
            showRain = alreadyIsolated || layer == .rain
            showWind = alreadyIsolated || layer == .wind
        } else {
            switch layer {
            case .sky: showSky.toggle()
            case .temperature: showTemperature.toggle()
            case .uv: showUV.toggle()
            case .rain: showRain.toggle()
            case .wind: showWind.toggle()
            }
        }
    }

    @Published private(set) var hours: [WeatherHour] = [] {
        didSet { hourIndex = WeatherHourIndex(hours) }
    }
    private var hourIndex = WeatherHourIndex([])
    @Published private(set) var status = "Weather is off"
    @Published private(set) var city = ""
    @Published private(set) var revision = 0
    @Published private(set) var isLoading = false
    @Published private(set) var selectedLocation: WeatherPlace?
    @Published private(set) var macCoordinate: SunCoordinate?
    var locationName: String { selectedLocation?.name ?? "My Mac’s location" }
    var locationKey: String {
        if let place = selectedLocation { return "\(place.id):\(place.latitude),\(place.longitude)" }
        return macCoordinate.map { "mac:\($0.latitude),\($0.longitude)" } ?? "mac:waiting"
    }
    func chooseLocation(_ place: WeatherPlace?) {
        selectedLocation = place
        if let place, let data = try? JSONEncoder().encode(place) { UserDefaults.standard.set(data,forKey:"weatherSelectedPlace") }
        else { UserDefaults.standard.removeObject(forKey:"weatherSelectedPlace") }
    }
    func updateMacLocation(_ coordinate: SunCoordinate?) {
        guard macCoordinate != coordinate else { return }
        macCoordinate = coordinate
    }
    private var loadedID: String?
    private var loadedAt: Date?
    private var request: Task<Void,Never>?
    private var deadline: DispatchWorkItem?
    private var requestID = UUID()
    private var loadingID: String?
    private let session: URLSession
    private let timeout: TimeInterval
    init(session: URLSession? = nil, timeout: TimeInterval = 12) {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        configuration.waitsForConnectivity = false
        self.session = session ?? URLSession(configuration:configuration)
        self.timeout = timeout
        if let data = UserDefaults.standard.data(forKey:"weatherSelectedPlace") { selectedLocation = try? JSONDecoder().decode(WeatherPlace.self,from:data) }
    }
    private func cancelRequest() {
        requestID = UUID()
        deadline?.cancel(); deadline = nil
        request?.cancel(); request = nil
        loadingID = nil; isLoading = false
    }
    static func url(latitude: Double, longitude: Double) -> URL {
        var parts = URLComponents(string:"https://api.open-meteo.com/v1/forecast")!
        parts.queryItems = [
            URLQueryItem(name:"latitude",value:String(latitude)), URLQueryItem(name:"longitude",value:String(longitude)),
            URLQueryItem(name:"hourly",value:"temperature_2m,precipitation,cloud_cover,weather_code,wind_speed_10m,wind_direction_10m,is_day,apparent_temperature,relative_humidity_2m,precipitation_probability,wind_gusts_10m,uv_index"),
            URLQueryItem(name:"temperature_unit",value:"fahrenheit"), URLQueryItem(name:"wind_speed_unit",value:"mph"),
            URLQueryItem(name:"precipitation_unit",value:"mm"),URLQueryItem(name:"timezone",value:"GMT"),URLQueryItem(name:"timeformat",value:"unixtime"),
            URLQueryItem(name:"past_days",value:"7"),URLQueryItem(name:"forecast_days",value:"16")
        ]
        return parts.url!
    }
    func load(zoneID: String, force: Bool = false) {
        guard needsData else { cancelRequest(); return }
        let locationID = locationKey
        if !force, loadedID == locationID, let loadedAt, Date().timeIntervalSince(loadedAt) < 1200 { return }
        if !force, isLoading, loadingID == locationID { return }
        cancelRequest()
        let coordinate = selectedLocation.map { SunCoordinate(latitude:$0.latitude,longitude:$0.longitude) } ?? macCoordinate
        guard let coordinate else {
            hours = []; city = "My Mac’s location"; status = "Choose a weather location or allow Mac location access"; revision += 1; return
        }
        if loadedID != locationID { hours = []; revision += 1 }
        isLoading = true
        city = locationName; status = "Loading weather for \(city)…"
        let token = UUID(); requestID = token; loadingID = locationID
        let deadline = DispatchWorkItem { [weak self] in
            guard let self, self.requestID == token, self.isLoading else { return }
            self.cancelRequest()
            self.status = "Weather service isn’t responding. Try again."
            self.revision += 1
        }
        self.deadline = deadline
        DispatchQueue.main.asyncAfter(deadline:.now()+timeout,execute:deadline)
        request = Task {
            defer {
                if requestID == token {
                    self.deadline?.cancel(); self.deadline = nil
                    loadingID = nil; isLoading = false
                }
            }
            do {
                var request = URLRequest(url:Self.url(latitude:coordinate.latitude,longitude:coordinate.longitude))
                request.timeoutInterval = timeout
                let (data,response) = try await session.data(for:request)
                guard !Task.isCancelled, requestID == token else { return }
                guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
                let values = try JSONDecoder().decode(WeatherResponse.self,from:data).hours()
                guard !values.isEmpty else { throw URLError(.zeroByteResource) }
                guard !Task.isCancelled, requestID == token else { return }
                isLoading = false
                hours = values; loadedID = locationID; loadedAt = Date(); revision += 1
                status = "Hourly weather · \(city)"
            } catch {
                guard !Task.isCancelled, requestID == token else { return }
                isLoading = false
                status = "Weather unavailable: " + error.localizedDescription; revision += 1
            }
        }
    }
    func hours(on day: Date, calendar: Calendar) -> [WeatherHour] {
        guard needsData else { return [] }
        let start = calendar.startOfDay(for:day), end = calendar.date(byAdding:.day,value:1,to:start)!
        return hours(from:start,to:end)
    }
    func hours(from start: Date, to end: Date) -> [WeatherHour] { hourIndex.hours(from:start,to:end) }
    func hour(at date: Date) -> WeatherHour? { hourIndex.hour(at:date) }
}
struct WeatherMenu: View {
    @ObservedObject var weather: WeatherOverlay
    let zoneID: String
    var priorityZones: [String] = []
    var refreshMac: () -> Void = {}
    @State private var choosingLocation = false
    var body: some View {
        Menu {
            Button("Location: " + weather.locationName + "…") { choosingLocation = true }
            Divider()
            Toggle("Calendar weather overlay",isOn:$weather.enabled)
            Toggle("Horizontal weather strip",isOn:$weather.showHorizontalStrip)
            Divider()
            Toggle("Sun & clouds",isOn:$weather.showSky)
            Toggle("Temperature",isOn:$weather.showTemperature)
            Toggle("UV",isOn:$weather.showUV)
            Toggle("Rain & snow",isOn:$weather.showRain)
            Toggle("Wind",isOn:$weather.showWind)
            Divider()
            Text(weather.status)
            Text("Celsius first · Fahrenheit alongside · mph")
            Text("Blue: precipitation · teal strip: wind")
            Text("Available: past 7 days and up to 16 forecast days")
            Button("Refresh Weather") { weather.load(zoneID:zoneID,force:true) }.disabled(!weather.needsData)
            Link("Weather data: Open-Meteo",destination:URL(string:"https://open-meteo.com/")!)
        } label: { ToolbarControlLabel(symbol:"cloud.sun",title:"Weather",dropdown:true) }
        .menuIndicator(.hidden)
        .popover(isPresented:$choosingLocation,arrowEdge:.bottom) {
            WeatherLocationPicker(weather:weather,priorityZones:priorityZones,refreshMac:refreshMac)
        }
        .appHelp("Toggle hourly weather (⇧W) · sun, rain and wind")
    }
}

struct WeatherAvailabilityNotice: View {
    @ObservedObject var weather: WeatherOverlay
    let start: Date
    let end: Date
    let zoneID: String
    private var missing: Bool { !weather.hours.contains { $0.date >= start && $0.date < end } }
    var body: some View {
        if weather.enabled && !weather.showHorizontalStrip && missing {
            HStack(spacing:8) {
                if weather.isLoading { ProgressView().controlSize(.mini) }
                else { Image(systemName:"cloud") }
                Text(weather.isLoading || weather.hours.isEmpty ? weather.status : "No weather for these dates · forecasts cover the next 16 days")
                    .appFont(size:10).lineLimit(2)
                Button(weather.isLoading ? "Restart" : "Retry") { weather.load(zoneID:zoneID,force:true) }.buttonStyle(.borderless)
            }.padding(9).frame(maxWidth:330)
                .background(.regularMaterial,in:RoundedRectangle(cornerRadius:8))
                .overlay(RoundedRectangle(cornerRadius:8).strokeBorder(Color.primary.opacity(0.1),lineWidth:0.5))
        }
    }
}
