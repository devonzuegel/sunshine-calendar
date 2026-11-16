import SwiftUI
import AppKit
import MapKit

enum LocationDirections {
    static func url(for location: String) -> URL? {
        let destination = location.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !destination.isEmpty else { return nil }
        if let scheme = URL(string:destination)?.scheme?.lowercased(), ["http","https","zoommtg","msteams"].contains(scheme) { return nil }
        var url = URLComponents(string:"https://www.google.com/maps/dir/")!
        // Omitting origin lets Google Maps use the device's current location.
        url.queryItems = [URLQueryItem(name:"api",value:"1"),URLQueryItem(name:"destination",value:destination)]
        return url.url
    }
}

struct LocationSuggestion: Identifiable, Equatable {
    let title: String
    let subtitle: String
    var id: String { title+"\n"+subtitle }
    var location: String {
        let title = title.trimmingCharacters(in:.whitespacesAndNewlines)
        let subtitle = subtitle.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !subtitle.isEmpty, subtitle.caseInsensitiveCompare(title) != .orderedSame else { return title }
        return title.isEmpty ? subtitle : title+", "+subtitle
    }
    static func searchable(_ query: String) -> Bool {
        let value = query.trimmingCharacters(in:.whitespacesAndNewlines)
        return value.count >= 2 && !value.contains("://") && !value.lowercased().hasPrefix("www.") && !value.contains("@")
    }
}

@MainActor final class LocationAutocomplete: NSObject, ObservableObject, @preconcurrency MKLocalSearchCompleterDelegate {
    static weak var active: LocationAutocomplete?
    @Published private(set) var suggestions: [LocationSuggestion] = []
    @Published var highlighted = 0
    @Published private(set) var searching = false
    @Published private(set) var failed = false
    private let completer = MKLocalSearchCompleter()
    private var pending: DispatchWorkItem?
    private var query = ""
    private var activeQuery = ""
    private var focused = false
    private weak var window: NSWindow?
    var choose: ((String) -> Void)?
    override init() {
        super.init(); completer.delegate = self
        completer.resultTypes = [.address,.pointOfInterest]
    }
    func focus(_ focused: Bool, in window: NSWindow?) {
        self.focused = focused; self.window = window
        if focused { Self.active = self }
        else { dismiss(); if Self.active === self { Self.active = nil } }
    }
    func update(_ text: String, near coordinate: SunCoordinate?) {
        pending?.cancel(); pending = nil
        completer.cancel(); activeQuery = ""
        query = text.trimmingCharacters(in:.whitespacesAndNewlines)
        suggestions = []; highlighted = 0; failed = false; searching = false
        guard focused, LocationSuggestion.searchable(query) else { return }
        if let coordinate {
            completer.region = MKCoordinateRegion(center:CLLocationCoordinate2D(latitude:coordinate.latitude,longitude:coordinate.longitude),latitudinalMeters:80_000,longitudinalMeters:80_000)
        }
        let expected = query
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.focused, self.query == expected else { return }
            self.activeQuery = expected; self.searching = true
            self.completer.queryFragment = expected
        }
        pending = work; DispatchQueue.main.asyncAfter(deadline:.now()+0.25,execute:work)
    }
    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        guard focused, !activeQuery.isEmpty, query == activeQuery else { return }
        searching = false; failed = false
        var seen = Set<String>()
        suggestions = Array(completer.results.map { LocationSuggestion(title:$0.title,subtitle:$0.subtitle) }.filter { seen.insert($0.id).inserted }.prefix(5))
        highlighted = 0
    }
    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        guard focused, !activeQuery.isEmpty, query == activeQuery else { return }
        searching = false; failed = true; suggestions = []
    }
    func select(_ index: Int) {
        guard suggestions.indices.contains(index) else { return }
        select(suggestions[index])
    }
    func select(_ suggestion: LocationSuggestion) {
        let location = suggestion.location
        dismiss(); choose?(location)
    }
    func dismiss() {
        pending?.cancel(); pending = nil; completer.cancel()
        query = ""; activeQuery = ""; suggestions = []; searching = false; failed = false
    }
    static func handle(_ event: NSEvent) -> Bool {
        guard let active, active.focused, event.window === active.window,
              event.window?.firstResponder is NSTextView,
              event.modifierFlags.intersection([.command,.control,.option]).isEmpty else { return false }
        if event.keyCode == 53, !active.suggestions.isEmpty || active.searching {
            active.dismiss(); return true
        }
        guard !active.suggestions.isEmpty else { return false }
        switch event.keyCode {
        case 125: active.highlighted = (active.highlighted+1)%active.suggestions.count
        case 126: active.highlighted = (active.highlighted+active.suggestions.count-1)%active.suggestions.count
        case 36,76: active.select(active.highlighted)
        default: return false
        }
        return true
    }
}

struct EventLocationField: View {
    @Binding var location: String
    let coordinate: SunCoordinate?
    @StateObject private var autocomplete = LocationAutocomplete()
    @FocusState private var focused: Bool
    @State private var window: NSWindow?
    @State private var chosen: String?
    var body: some View {
        TextField("Add a location or video call",text:$location).appFont(size:13)
            .focused($focused)
            .background(LocationWindowAnchor { window = $0 })
            .onAppear { autocomplete.choose = { value in chosen = value; location = value } }
            .onChange(of:focused) { _,value in
                autocomplete.focus(value,in:window)
                if value { autocomplete.update(location,near:coordinate) }
            }
            .onChange(of:location) { _,value in
                if chosen == value { chosen = nil; return }
                chosen = nil
                if focused { autocomplete.update(value,near:coordinate) }
            }
            .onChange(of:window) { _,value in if focused { autocomplete.focus(true,in:value) } }
            .onDisappear { autocomplete.focus(false,in:nil); autocomplete.choose = nil }
            .overlay(alignment:.topLeading) {
                if focused && (!autocomplete.suggestions.isEmpty || autocomplete.failed) {
                    VStack(alignment:.leading,spacing:1) {
                        if autocomplete.failed {
                            Text("Address suggestions unavailable · You can still enter a location")
                                .appFont(size:10).foregroundStyle(.secondary).padding(9)
                        }
                        ForEach(Array(autocomplete.suggestions.enumerated()),id:\.element.id) { index,item in
                            Button { autocomplete.select(item) } label: {
                                HStack(alignment:.top,spacing:8) {
                                    Image(systemName:"mappin.and.ellipse").appFont(size:12).frame(width:16).padding(.top,2)
                                    VStack(alignment:.leading,spacing:2) {
                                        Text(item.title).appFont(size:12,weight:.medium).lineLimit(1)
                                        if !item.subtitle.isEmpty { Text(item.subtitle).appFont(size:10).opacity(0.75).lineLimit(1) }
                                    }.frame(maxWidth:.infinity,alignment:.leading)
                                }.padding(.horizontal,9).padding(.vertical,7)
                                    .foregroundStyle(index == autocomplete.highlighted ? Color.white : Color.primary)
                                    .background(index == autocomplete.highlighted ? Color.accentColor : .clear,in:RoundedRectangle(cornerRadius:5))
                                    .contentShape(Rectangle())
                            }.buttonStyle(.plain).onHover { if $0 { autocomplete.highlighted = index } }
                        }
                    }.padding(4).frame(maxWidth:.infinity,alignment:.leading)
                        .background(Color(nsColor:.windowBackgroundColor),in:RoundedRectangle(cornerRadius:8))
                        .overlay { RoundedRectangle(cornerRadius:8).strokeBorder(Color.primary.opacity(0.12),lineWidth:0.5) }
                        .shadow(color:Color.black.opacity(0.13),radius:10,y:4)
                        .offset(y:AppTextSize.points(23))
                }
            }
    }
}

private struct LocationWindowAnchor: NSViewRepresentable {
    var attached: (NSWindow?) -> Void
    func makeNSView(context: Context) -> WindowView { let view = WindowView(); view.attached = attached; return view }
    func updateNSView(_ view: WindowView, context: Context) { view.attached = attached }
    final class WindowView: NSView {
        var attached: ((NSWindow?) -> Void)?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            DispatchQueue.main.async { [weak self] in self?.attached?(self?.window) }
        }
    }
}
