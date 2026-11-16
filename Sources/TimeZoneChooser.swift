import SwiftUI
import MapKit

struct ZonePlace: Identifiable {
    let id: String
    let latitude: Double
    let longitude: Double
    var name: String { TimeZoneCatalog.name(id) }
}
enum TimeZoneCatalog {
    static let favorites = ["America/New_York","America/Los_Angeles","America/Argentina/Buenos_Aires","America/Denver","America/Chicago"]
    static func name(_ id: String) -> String {
        switch id {
        case "America/New_York": return "Miami (ET)"
        case "America/Los_Angeles": return "San Francisco (PT)"
        case "America/Argentina/Buenos_Aires": return "Buenos Aires (AT)"
        case "America/Denver": return "Mountain Time (MT)"
        case "America/Chicago": return "Central Time (CT)"
        default: return id.split(separator:"/").last.map(String.init)?.replacingOccurrences(of:"_",with:" ") ?? id
        }
    }
    static func coordinate(_ string: String) -> (Double,Double)? {
        guard let split = string.dropFirst().firstIndex(where:{ $0 == "+" || $0 == "-" }) else { return nil }
        func value(_ part: String, degrees: Int) -> Double? {
            guard let sign = part.first, sign == "+" || sign == "-" else { return nil }
            let digits = String(part.dropFirst())
            guard digits.count == degrees+2 || digits.count == degrees+4,
                  let d = Double(digits.prefix(degrees)), let m = Double(digits.dropFirst(degrees).prefix(2)), m < 60 else { return nil }
            let seconds = digits.count == degrees+4 ? Double(digits.suffix(2)) : 0
            guard let seconds, seconds < 60 else { return nil }
            return (sign == "-" ? -1 : 1)*(d+m/60+seconds/3600)
        }
        guard let lat = value(String(string[..<split]),degrees:2), let lon = value(String(string[split...]),degrees:3), abs(lat) <= 90, abs(lon) <= 180 else { return nil }
        return (lat,lon)
    }
    static let places: [ZonePlace] = {
        guard let url = Bundle.main.url(forResource:"zone",withExtension:"tab"), let source = try? String(contentsOf:url,encoding:.utf8) else { return [] }
        return source.split(separator:"\n").compactMap { line in
            guard !line.hasPrefix("#") else { return nil }
            let fields = line.split(separator:"\t")
            guard fields.count >= 3, let (lat,lon) = coordinate(String(fields[1])) else { return nil }
            let id = String(fields[2])
            guard TimeZone(identifier:id) != nil else { return nil }
            // Our Eastern shortcut is explicitly Miami rather than New York.
            return ZonePlace(id:id,latitude:id == "America/New_York" ? 25.7617 : lat,longitude:id == "America/New_York" ? -80.1918 : lon)
        }
    }()
}

struct TimeZoneChooser: View {
    @ObservedObject private var textSize = AppTextSize.shared
    let current: String?
    var excluded: String? = nil
    var allowsFloating = false
    var onChoose: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var mode = 0
    @State private var search = ""
    @State private var candidate: String?
    private var results: [String] {
        TimeZone.knownTimeZoneIdentifiers.sorted().filter {
            search.isEmpty || TimeZoneCatalog.name($0).localizedCaseInsensitiveContains(search) || $0.localizedCaseInsensitiveContains(search)
        }
    }
    var body: some View {
        VStack(alignment:.leading,spacing:12) {
            HStack {
                Text("Choose a time zone").appFont(size:13,weight:.semibold)
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            Picker("Browse",selection:$mode) {
                Text("Map").tag(0); Text("List").tag(1)
            }.pickerStyle(.segmented).labelsHidden()
            if mode == 0 {
                ZoneMap(places:TimeZoneCatalog.places,selection:$candidate,excluded:excluded)
                    .frame(height:290).clipShape(RoundedRectangle(cornerRadius:8))
                Text("Select a city dot. Pinch to zoom or drag to pan. The highlighted band is approximate.")
                    .appFont(size:10).foregroundStyle(.secondary)
            } else {
                TextField("Search cities or timezones",text:$search).textFieldStyle(.roundedBorder)
                ScrollView {
                    LazyVStack(spacing:0) {
                        if search.isEmpty {
                            if allowsFloating { option("",name:"Floating (local time)") }
                            ForEach(TimeZoneCatalog.favorites,id:\.self) { option($0) }
                            Divider().padding(.vertical,6)
                        }
                        ForEach(results,id:\.self) { option($0) }
                    }.padding(.horizontal,16)
                }.padding(.horizontal,-16).frame(height:290)
            }
            Divider()
            HStack {
                VStack(alignment:.leading,spacing:3) {
                    Text(candidate.map { $0.isEmpty ? "Floating (local time)" : TimeZoneCatalog.name($0) } ?? "Select a timezone")
                        .appFont(size:13,weight:.semibold)
                    if let candidate, !candidate.isEmpty {
                        Text(candidate.replacingOccurrences(of:"_",with:" ")).appFont(size:10).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button("Use time zone") {
                    if let candidate { onChoose(candidate); dismiss() }
                }.buttonStyle(.borderedProminent).disabled(candidate == nil || candidate == excluded)
            }
        }.padding(16).frame(width:520)
            .onAppear { candidate = current }
    }
    private func option(_ id: String, name: String? = nil) -> some View {
        Button { candidate = id } label: {
            HStack {
                VStack(alignment:.leading,spacing:2) {
                    Text(name ?? TimeZoneCatalog.name(id)).appFont(size:12)
                    if !id.isEmpty { Text(id.replacingOccurrences(of:"_",with:" ")).appFont(size:10).foregroundStyle(.secondary) }
                }
                Spacer()
                if candidate == id { Image(systemName:"checkmark").foregroundStyle(Color.accentColor) }
            }.padding(8).frame(maxWidth:.infinity,alignment:.leading)
                .background(candidate == id ? Color.accentColor.opacity(0.1) : .clear,in:RoundedRectangle(cornerRadius:5))
                .contentShape(Rectangle())
        }.buttonStyle(.plain).disabled(id == excluded)
    }
}

struct ZoneMap: View {
    let places: [ZonePlace]
    @Binding var selection: String?
    var excluded: String? = nil
    @State private var zoom: CGFloat = 1
    @State private var pan: CGSize = .zero
    @GestureState private var dragging: CGSize = .zero
    @GestureState private var pinching: CGFloat = 1
    @State private var hovered: String?
    private func effectiveZoom() -> CGFloat { min(12,max(1,zoom*pinching)) }
    private func offset(_ size: CGSize) -> CGSize {
        let scale = effectiveZoom()
        return CGSize(width:max(-size.width*(scale-1)/2,min(size.width*(scale-1)/2,pan.width+dragging.width)),
                      height:max(-size.height*(scale-1)/2,min(size.height*(scale-1)/2,pan.height+dragging.height)))
    }
    private func project(latitude: Double, longitude: Double, size: CGSize) -> CGPoint {
        let base = TimezoneMapGeometry.point(latitude:latitude,longitude:longitude,size:size)
        let delta = offset(size), scale = effectiveZoom()
        return CGPoint(x:(base.x-size.width/2)*scale+size.width/2+delta.width,y:(base.y-size.height/2)*scale+size.height/2+delta.height)
    }
    private func nearest(_ point: CGPoint, size: CGSize) -> ZonePlace? {
        let candidates = places.filter { $0.id != excluded }
        return candidates.min { a,b in
            let x = project(latitude:a.latitude,longitude:a.longitude,size:size)
            let y = project(latitude:b.latitude,longitude:b.longitude,size:size)
            return hypot(x.x-point.x,x.y-point.y) < hypot(y.x-point.x,y.y-point.y)
        }.flatMap { place in
            let p = project(latitude:place.latitude,longitude:place.longitude,size:size)
            return hypot(p.x-point.x,p.y-point.y) <= 14 ? place : nil
        }
    }
    var body: some View {
        GeometryReader { geometry in
            Canvas { context,size in
                context.clip(to:Path(CGRect(origin:.zero,size:size)))
                context.fill(Path(CGRect(origin:.zero,size:size)),with:.color(Color.primary.opacity(0.018)))
                for polygon in TimezoneMapGeometry.land {
                    var path = Path()
                    for ring in polygon {
                        for (index,p) in ring.enumerated() where p.count >= 2 {
                            let point = project(latitude:p[1],longitude:p[0],size:size)
                            if index == 0 { path.move(to:point) } else { path.addLine(to:point) }
                        }
                        path.closeSubpath()
                    }
                    context.fill(path,with:.color(Color.secondary.opacity(0.17)),style:FillStyle(eoFill:true))
                }
                if let selected = places.first(where:{ $0.id == selection }) {
                    let left = project(latitude:0,longitude:selected.longitude-7.5,size:size).x
                    let right = project(latitude:0,longitude:selected.longitude+7.5,size:size).x
                    context.fill(Path(CGRect(x:left,y:0,width:right-left,height:size.height)),with:.color(Color.accentColor.opacity(0.10)))
                    var edges = Path()
                    for x in [left,right] { edges.move(to:CGPoint(x:x,y:0)); edges.addLine(to:CGPoint(x:x,y:size.height)) }
                    context.stroke(edges,with:.color(Color.accentColor.opacity(0.23)),lineWidth:0.6)
                }
                for place in places {
                    let point = project(latitude:place.latitude,longitude:place.longitude,size:size)
                    guard CGRect(origin:.zero,size:size).insetBy(dx:-5,dy:-5).contains(point) else { continue }
                    let selected = place.id == selection
                    let radius: CGFloat = selected ? 3.5 : (place.id == hovered ? 3 : 1.6)
                    let path = Path(ellipseIn:CGRect(x:point.x-radius,y:point.y-radius,width:radius*2,height:radius*2))
                    context.fill(path,with:.color(selected ? Color.accentColor : Color.secondary.opacity(place.id == excluded ? 0.15 : 0.5)))
                    if selected { context.stroke(path,with:.color(Color(nsColor:.windowBackgroundColor)),lineWidth:1.3) }
                }
                if let place = places.first(where:{ $0.id == hovered }) {
                    let point = project(latitude:place.latitude,longitude:place.longitude,size:size)
                    let label = context.resolve(Text(place.name).font(.system(size:11,weight:.medium)).foregroundColor(.primary))
                    let measured = label.measure(in:CGSize(width:250,height:30))
                    let rect = CGRect(x:max(3,min(size.width-measured.width-15,point.x+8)),y:max(3,min(size.height-25,point.y-22)),width:measured.width+12,height:22)
                    context.fill(Path(roundedRect:rect,cornerRadius:5),with:.color(Color(nsColor:.windowBackgroundColor).opacity(0.96)))
                    context.draw(label,at:CGPoint(x:rect.minX+6,y:rect.minY+4),anchor:.topLeading)
                }
            }.contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance:0)
                    .updating($dragging) { value,state,_ in state = value.translation }
                    .onEnded { value in
                        if hypot(value.translation.width,value.translation.height) < 4 {
                            if let place = nearest(value.location,size:geometry.size) { selection = place.id }
                        } else {
                            let limitX = geometry.size.width*(zoom-1)/2, limitY = geometry.size.height*(zoom-1)/2
                            pan = CGSize(width:max(-limitX,min(limitX,pan.width+value.translation.width)),height:max(-limitY,min(limitY,pan.height+value.translation.height)))
                        }
                    })
                .simultaneousGesture(MagnificationGesture().updating($pinching) { value,state,_ in state = value }
                    .onEnded { value in zoom = min(12,max(1,zoom*value)); if zoom == 1 { pan = .zero } })
                .onContinuousHover { phase in
                    switch phase { case .active(let point): hovered = nearest(point,size:geometry.size)?.id; case .ended: hovered = nil }
                }
                .overlay(alignment:.topTrailing) {
                    HStack(spacing:8) {
                        Button { zoom = max(1,zoom/1.6); if zoom == 1 { pan = .zero } } label: { Image(systemName:"minus") }
                        Button { zoom = min(12,zoom*1.6) } label: { Image(systemName:"plus") }
                        Button { zoom = 1; pan = .zero } label: { Image(systemName:"arrow.up.left.and.arrow.down.right") }
                    }.appFont(size:11).buttonStyle(.plain).padding(9)
                        .background(Color(nsColor:.windowBackgroundColor).opacity(0.94),in:RoundedRectangle(cornerRadius:7)).padding(8)
                }
        }.accessibilityLabel("Timezone city map. Select a city dot, or use the List tab to search by name.")
    }
}
