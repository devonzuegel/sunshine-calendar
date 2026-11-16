import SwiftUI
import CoreLocation

struct WeatherPlace: Codable, Equatable, Identifiable {
    let id: String
    let name: String
    let latitude: Double
    let longitude: Double
    @MainActor static func timezone(_ id: String) -> WeatherPlace? {
        let coordinate = DaylightLocation.ribbonCoordinate(for:id) ?? TimeZoneCatalog.places.first(where:{ $0.id == id }).map { SunCoordinate(latitude:$0.latitude,longitude:$0.longitude) }
        guard let coordinate else { return nil }
        return WeatherPlace(id:id,name:TimeZoneCatalog.name(id),latitude:coordinate.latitude,longitude:coordinate.longitude)
    }
    @MainActor static func prioritized(_ ids: [String]) -> [WeatherPlace] {
        var seen = Set<String>()
        return (ids+TimeZoneCatalog.favorites).filter { seen.insert($0).inserted }.compactMap(timezone)
    }
}

struct WeatherLocationPicker: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var weather: WeatherOverlay
    let priorityZones: [String]
    let refreshMac: () -> Void
    @State private var query = ""
    @State private var results: [WeatherPlace] = []
    @State private var searching = false
    @State private var error: String?
    @State private var geocoder = CLGeocoder()
    private func choose(_ place: WeatherPlace?) {
        weather.chooseLocation(place)
        if place == nil { refreshMac() }
        dismiss()
    }
    private func search() {
        geocoder.cancelGeocode(); searching = true; error = nil
        let query = query.trimmingCharacters(in:.whitespacesAndNewlines)
        Task { @MainActor in
            do {
                let places = try await geocoder.geocodeAddressString(query)
                results = places.compactMap { place in
                    guard let coordinate = place.location?.coordinate else { return nil }
                    let name = [place.locality ?? place.name,place.administrativeArea,place.country].compactMap { $0 }.reduce(into:[String]()) { if !$0.contains($1) { $0.append($1) } }.joined(separator:", ")
                    return WeatherPlace(id:"place:\(coordinate.latitude),\(coordinate.longitude)",name:name,latitude:coordinate.latitude,longitude:coordinate.longitude)
                }
                if results.isEmpty { error = "No matching places found." }
            } catch { self.error = "Couldn’t find that place. Try a city and country." }
            searching = false
        }
    }
    private func row(_ place: WeatherPlace) -> some View {
        Button { choose(place) } label: {
            HStack {
                Image(systemName:"mappin.circle").foregroundStyle(.secondary)
                Text(place.name).lineLimit(1)
                Spacer()
                if weather.selectedLocation?.id == place.id { Image(systemName:"checkmark").foregroundStyle(Color.accentColor) }
            }.padding(.vertical,8).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
    var body: some View {
        VStack(alignment:.leading,spacing:12) {
            HStack { Text("Weather location").appFont(size:16,weight:.semibold); Spacer(); Button("Done") { dismiss() } }
            Text("Forecasts use this location. Calendar times stay in your selected timezone.").appFont(size:11).foregroundStyle(.secondary)
            Button { choose(nil) } label: {
                HStack {
                    Image(systemName:"location").foregroundStyle(Color.accentColor)
                    Text("Use my Mac’s location")
                    Spacer()
                    if weather.selectedLocation == nil { Image(systemName:"checkmark").foregroundStyle(Color.accentColor) }
                }.padding(10).background(Color.primary.opacity(0.035),in:RoundedRectangle(cornerRadius:7))
            }.buttonStyle(.plain)
            if weather.selectedLocation == nil && weather.macCoordinate == nil {
                Text("Allow Location Services, or choose a city below.").appFont(size:10).foregroundStyle(.secondary)
            }
            HStack {
                TextField("Search a city or place",text:$query).textFieldStyle(.roundedBorder).onSubmit { search() }
                Button("Search") { search() }.disabled(query.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || searching)
            }
            if searching { ProgressView().controlSize(.small) }
            if let error { Text(error).appFont(size:10).foregroundStyle(.secondary) }
            ScrollView {
                VStack(alignment:.leading,spacing:0) {
                    if !results.isEmpty {
                        ForEach(results) { row($0) }
                        Divider().padding(.vertical,7)
                    }
                    Text("YOUR TIMEZONES & FAVORITES").appFont(size:9,weight:.semibold).foregroundStyle(.secondary).padding(.vertical,6)
                    ForEach(WeatherPlace.prioritized(priorityZones)) { row($0) }
                }.padding(.horizontal,16)
            }.padding(.horizontal,-16).frame(height:240)
        }.appFont(size:12).padding(16).frame(width:380)
    }
}
