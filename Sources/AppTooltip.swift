import AppKit
import SwiftUI
import MapKit

enum AppTooltipTiming { static let delay: TimeInterval = 0.75 }

struct WeatherTooltipData {
    let hour: WeatherHour
    let city: String
    let period: String
}

extension View {
    func appHelp(_ text: String) -> some View {
        background(AppTooltipAnchor(text:text)).accessibilityHint(text)
    }
    func weatherHelp(_ hour: WeatherHour, city: String, period: String) -> some View {
        background(AppTooltipAnchor(text:city+" · "+period,weather:WeatherTooltipData(hour:hour,city:city,period:period)))
            .accessibilityHint(city+" · "+period+" · "+hour.detail)
    }
    func timeZoneHelp(_ zone: TimeZone, primary: Bool) -> some View {
        background(AppTooltipAnchor(text:TimeZoneCatalog.name(zone.identifier),zoneID:zone.identifier,primaryZone:primary))
            .accessibilityHint(TimeZoneCatalog.name(zone.identifier)+(primary ? " · Primary timezone" : " · Comparison timezone"))
    }
}

enum AppTooltipPlacement {
    static func frame(size: CGSize, hoverPoint: CGPoint, screen: CGRect, belowEdge: CGFloat? = nil, aboveEdge: CGFloat? = nil) -> CGRect {
        let x = max(screen.minX+8,min(hoverPoint.x+10,screen.maxX-size.width-8))
        let below = (belowEdge ?? hoverPoint.y)-size.height-(belowEdge == nil ? 12 : 0)
        let preferredY = aboveEdge ?? (belowEdge != nil || below >= screen.minY+8 ? below : hoverPoint.y+16)
        let y = max(screen.minY+8,min(preferredY,screen.maxY-size.height-8))
        return CGRect(origin:CGPoint(x:x,y:y),size:size)
    }
}

private struct AppTooltipAnchor: NSViewRepresentable {
    let text: String
    var zoneID: String? = nil
    var primaryZone = false
    var weather: WeatherTooltipData? = nil
    func makeNSView(context: Context) -> AppTooltipTrackingView { AppTooltipTrackingView() }
    func updateNSView(_ view: AppTooltipTrackingView, context: Context) { view.message = text; view.zoneID = zoneID; view.primaryZone = primaryZone; view.weather = weather }
    static func dismantleNSView(_ view: AppTooltipTrackingView, coordinator: ()) { AppTooltipPresenter.shared.hide(owner:view) }
}

private final class AppTooltipTrackingView: NSView {
    var message = ""
    var zoneID: String?
    var primaryZone = false
    var weather: WeatherTooltipData?
    private var area: NSTrackingArea?
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area { removeTrackingArea(area) }
        let area = NSTrackingArea(rect:.zero,options:[.mouseEnteredAndExited,.activeInKeyWindow,.inVisibleRect],owner:self,userInfo:nil)
        addTrackingArea(area); self.area = area
    }
    override func mouseEntered(with event: NSEvent) {
        guard let window else { return }
        AppTooltipPresenter.shared.show(message,from:self,at:window.convertPoint(toScreen:event.locationInWindow))
    }
    override func mouseExited(with event: NSEvent) { AppTooltipPresenter.shared.hide(owner:self) }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { AppTooltipPresenter.shared.hide(owner:self) }
    }
}

private struct AppTooltipBubble: View {
    let text: String
    var body: some View {
        VStack(alignment:.leading,spacing:5) {
            ForEach(Array(text.components(separatedBy:"\n").enumerated()),id:\.offset) { index,line in
                Text(line).appFont(size:index == 0 ? 11 : 10,weight:index == 0 ? .semibold : .regular)
                    .foregroundStyle(index == 0 ? Color.primary : Color.secondary)
                    .fixedSize(horizontal:false,vertical:true)
            }
        }.padding(12).frame(maxWidth:300,alignment:.leading)
            .background(Color(nsColor:.windowBackgroundColor),in:RoundedRectangle(cornerRadius:10))
            .overlay(RoundedRectangle(cornerRadius:10).strokeBorder(Color.primary.opacity(0.10),lineWidth:0.5))
            .padding(1)
    }
}

enum WeatherVisualMetrics {
    static func rainStrength(_ millimeters: Double?) -> Double {
        guard let millimeters, millimeters > 0, millimeters.isFinite else { return 0 }
        return 1-exp(-millimeters/3)
    }
    static func rainMarks(_ millimeters: Double?) -> Int {
        let strength = rainStrength(millimeters)
        return strength == 0 ? 0 : max(3,Int((strength*65).rounded()))
    }
}

private struct WeatherHourIllustration: View {
    let hour: WeatherHour
    var body: some View {
        Canvas { context,size in
            let strength = WeatherVisualMetrics.rainStrength(hour.precipitation)
            let cloud = max(0,min(1,(hour.cloudCover ?? 0)/100))
            let wind = max(0,hour.windSpeed ?? 0)
            context.fill(Path(CGRect(origin:.zero,size:size)),with:.color(strength > 0 ? Color.blue.opacity(0.025+strength*0.08) : Color.primary.opacity(0.018)))
            if hour.isDay && cloud < 0.8 {
                let disk = CGRect(x:20,y:11,width:23,height:23)
                context.fill(Path(ellipseIn:disk.insetBy(dx:-5,dy:-5)),with:.color(Color.yellow.opacity(0.09*(1-cloud))))
                context.fill(Path(ellipseIn:disk),with:.color(Color.yellow.opacity(0.55*(1-cloud))))
            }
            let count = cloud > 0.05 ? max(1,Int(ceil(cloud*5))) : 0
            for index in 0..<count {
                let x = 15+CGFloat(index)*size.width/5
                var shape = Path(roundedRect:CGRect(x:x,y:18,width:49,height:13),cornerRadius:7)
                shape.addEllipse(in:CGRect(x:x+8,y:8,width:23,height:23))
                shape.addEllipse(in:CGRect(x:x+23,y:13,width:19,height:18))
                context.fill(shape,with:.color(Color.secondary.opacity(0.06+cloud*0.15)))
            }
            let snow = [71,73,75,77,85,86].contains(hour.code ?? -1)
            for index in 0..<WeatherVisualMetrics.rainMarks(hour.precipitation) {
                let x = 9+CGFloat((index*47+13)%239)/252*(size.width-14)
                let y = 30+CGFloat((index*19+7)%31)
                if snow {
                    context.fill(Path(ellipseIn:CGRect(x:x,y:y,width:2,height:2)),with:.color(Color.blue.opacity(0.45)))
                } else {
                    var drop = Path()
                    drop.move(to:CGPoint(x:x,y:y))
                    drop.addLine(to:CGPoint(x:x-min(8,2+wind/7),y:y+3+strength*5))
                    context.stroke(drop,with:.color(Color.blue.opacity(0.3+strength*0.35)),lineWidth:0.75+strength*0.5)
                }
            }
            for index in 0..<min(5,Int(wind/7)) {
                let y = size.height-9-CGFloat(index)*5
                let x = size.width-55+CGFloat(index%2)*12
                var gust = Path(); gust.move(to:CGPoint(x:x,y:y));gust.addLine(to:CGPoint(x:min(size.width-8,x+18+wind/2),y:y))
                context.stroke(gust,with:.color(Color.teal.opacity(0.25)),lineWidth:0.8)
            }
        }.frame(height:72).clipShape(RoundedRectangle(cornerRadius:7))
            .accessibilityLabel("Weather intensity illustration based on precipitation amount, cloud cover, and wind speed")
    }
}

private struct WeatherTooltipCard: View {
    let data: WeatherTooltipData
    private var rows: [(String,String)] {
        let h = data.hour
        return [
            ("Feels like",h.apparentTemperature.map { WeatherTemperature(fahrenheit:$0).pairedLabel } ?? "—"),
            ("Rain chance",h.precipitationProbability.map { "\(Int($0.rounded()))%" } ?? "—"),
            ("Precipitation",h.precipitation.map { String(format:"%.1f mm",$0) } ?? "—"),
            ("UV index",h.uvIndex.map { String(format:"%.1f",$0) } ?? "—"),
            ("Cloud cover",h.cloudCover.map { "\(Int($0.rounded()))%" } ?? "—"),
            ("Wind",h.windSpeed.map { "\(Int($0.rounded())) mph" } ?? "—"),
            ("From",h.windDirection.map { WeatherHour.compass($0) } ?? "—"),
            ("Gusts",h.windGusts.map { "\(Int($0.rounded())) mph" } ?? "—")
        ]
    }
    var body: some View {
        VStack(alignment:.leading,spacing:9) {
            Text(data.city).appFont(size:11,weight:.semibold)
            Text(data.period).appFont(size:10).foregroundStyle(.secondary)
            HStack(spacing:10) {
                Image(systemName:data.hour.symbol).symbolRenderingMode(.hierarchical)
                    .appFont(size:24).foregroundStyle(Color.secondary)
                if let temperature = data.hour.temperature {
                    WeatherTemperatureText(fahrenheit:temperature,referenceSize:14).appFont(size:24,weight:.semibold)
                } else { Text("—").appFont(size:24,weight:.semibold) }
                Spacer(minLength:0)
                Text(data.hour.condition).appFont(size:11).foregroundStyle(.secondary)
            }.padding(.vertical,3)
            WeatherHourIllustration(hour:data.hour)
            Grid(horizontalSpacing:12,verticalSpacing:7) {
                ForEach(Array(rows.enumerated()),id:\.offset) { _,row in
                    GridRow {
                        Text(row.0).foregroundStyle(.secondary).frame(maxWidth:.infinity,alignment:.leading)
                        HStack(spacing:7) {
                            if let amount = row.0 == "Rain chance" ? data.hour.precipitationProbability : (row.0 == "Cloud cover" ? data.hour.cloudCover : nil) {
                                GeometryReader { geometry in
                                    Capsule().fill(Color.primary.opacity(0.06))
                                    Capsule().fill(row.0 == "Rain chance" ? Color.blue.opacity(0.5) : Color.secondary.opacity(0.3))
                                        .frame(width:geometry.size.width*max(0,min(1,amount/100)))
                                }.frame(width:37,height:4)
                            }
                            Text(row.1).fontWeight(.medium)
                                .foregroundStyle(row.0 == "UV index" ? data.hour.uvIndex.map(WeatherUVStyle.color) ?? Color.secondary : Color.primary)
                        }.frame(maxWidth:.infinity,alignment:.trailing)
                    }
                }
            }.appFont(size:10)
            Text("Hourly forecast · Open-Meteo").appFont(size:9).foregroundStyle(.tertiary)
        }.padding(14).frame(width:280,alignment:.leading)
            .background(Color(nsColor:.windowBackgroundColor),in:RoundedRectangle(cornerRadius:10))
            .overlay(RoundedRectangle(cornerRadius:10).strokeBorder(Color.primary.opacity(0.10),lineWidth:0.5)).padding(1)
    }
}

enum TimezoneMapGeometry {
    static func polygons(from data: Data) -> [[[[Double]]]] {
        guard let root = try? JSONSerialization.jsonObject(with:data) as? [String:Any],
              let features = root["features"] as? [[String:Any]] else { return [] }
        return features.flatMap { feature -> [[[[Double]]]] in
            guard let geometry = feature["geometry"] as? [String:Any] else { return [] }
            if geometry["type"] as? String == "Polygon", let polygon = geometry["coordinates"] as? [[[Double]]] { return [polygon] }
            return geometry["coordinates"] as? [[[[Double]]]] ?? []
        }
    }
    static func point(latitude: Double, longitude: Double, size: CGSize) -> CGPoint {
        CGPoint(x:(longitude+180)/360*size.width,y:(80-latitude)/160*size.height)
    }
    static let land: [[[[Double]]]] = {
        guard let url = Bundle.main.url(forResource:"TimezoneLand",withExtension:"geojson"), let data = try? Data(contentsOf:url) else { return [] }
        return polygons(from:data)
    }()
}

private struct CleanTimezoneMap: View {
    let coordinate: CLLocationCoordinate2D
    var body: some View {
        Canvas { context,size in
            context.clip(to:Path(CGRect(origin:.zero,size:size)))
            context.fill(Path(CGRect(origin:.zero,size:size)),with:.color(Color.primary.opacity(0.018)))
            for polygon in TimezoneMapGeometry.land {
                var coast = Path()
                for ring in polygon {
                    for (index,position) in ring.enumerated() where position.count >= 2 {
                        let p = TimezoneMapGeometry.point(latitude:position[1],longitude:position[0],size:size)
                        if index == 0 { coast.move(to:p) } else { coast.addLine(to:p) }
                    }
                    coast.closeSubpath()
                }
                context.fill(coast,with:.color(Color.secondary.opacity(0.17)),style:FillStyle(eoFill:true))
            }
            let left = TimezoneMapGeometry.point(latitude:0,longitude:coordinate.longitude-7.5,size:size).x
            let right = TimezoneMapGeometry.point(latitude:0,longitude:coordinate.longitude+7.5,size:size).x
            context.fill(Path(CGRect(x:left,y:0,width:right-left,height:size.height)),with:.color(Color.accentColor.opacity(0.10)))
            var edges = Path()
            for x in [left,right] { edges.move(to:CGPoint(x:x,y:0)); edges.addLine(to:CGPoint(x:x,y:size.height)) }
            context.stroke(edges,with:.color(Color.accentColor.opacity(0.23)),lineWidth:0.6)
            let dot = TimezoneMapGeometry.point(latitude:coordinate.latitude,longitude:coordinate.longitude,size:size)
            context.fill(Path(ellipseIn:CGRect(x:dot.x-7,y:dot.y-7,width:14,height:14)),with:.color(Color.accentColor.opacity(0.12)))
            let marker = Path(ellipseIn:CGRect(x:dot.x-3.5,y:dot.y-3.5,width:7,height:7))
            context.fill(marker,with:.color(Color.accentColor))
            context.stroke(marker,with:.color(Color(nsColor:.windowBackgroundColor)),lineWidth:1.5)
        }.accessibilityLabel("Map showing "+String(format:"%.1f°, %.1f°",coordinate.latitude,coordinate.longitude))
    }
}

private struct TimeZoneMapTooltip: View {
    let zoneID: String
    let primary: Bool
    private var coordinate: CLLocationCoordinate2D? {
        if let location = DaylightLocation.ribbonCoordinate(for:zoneID) {
            return CLLocationCoordinate2D(latitude:location.latitude,longitude:location.longitude)
        }
        return TimeZoneCatalog.places.first(where:{ $0.id == zoneID }).map { CLLocationCoordinate2D(latitude:$0.latitude,longitude:$0.longitude) }
    }
    private var offset: String {
        let minutes = (TimeZone(identifier:zoneID)?.secondsFromGMT(for:Date()) ?? 0)/60
        return String(format:"UTC%@%02d:%02d",minutes < 0 ? "−" : "+",abs(minutes)/60,abs(minutes)%60)
    }
    var body: some View {
        VStack(alignment:.leading,spacing:9) {
            HStack {
                Text(TimeZoneCatalog.name(zoneID)).appFont(size:12,weight:.semibold)
                Spacer()
                Text(offset).appFont(size:10,weight:.medium).foregroundStyle(.secondary)
            }
            if let coordinate {
                CleanTimezoneMap(coordinate:coordinate)
                    .frame(width:300,height:150).clipShape(RoundedRectangle(cornerRadius:7))
                Text("Approximate band · actual timezone borders vary")
                    .appFont(size:9).foregroundStyle(.secondary)
            } else {
                Text("Map location unavailable").appFont(size:11).foregroundStyle(.secondary)
            }
            Text(primary ? "Primary · calendar times use this zone" : "Comparison · today’s local time and daylight")
                .appFont(size:10).foregroundStyle(.secondary)
        }.padding(12).frame(width:324)
            .background(Color(nsColor:.windowBackgroundColor),in:RoundedRectangle(cornerRadius:10))
            .overlay(RoundedRectangle(cornerRadius:10).strokeBorder(Color.primary.opacity(0.1),lineWidth:0.5)).padding(1)
    }
}

// A non-interactive child panel avoids clipping at toolbar/popover boundaries
// and never takes focus away from a button, editor, or calendar gesture.
@MainActor private final class AppTooltipPresenter {
    static let shared = AppTooltipPresenter()
    private weak var owner: AppTooltipTrackingView?
    private var panel: NSPanel?
    private var pending: DispatchWorkItem?
    private var monitor: Any?
    private var resignObserver: Any?
    private init() {
        monitor = NSEvent.addLocalMonitorForEvents(matching:[.leftMouseDown,.rightMouseDown,.otherMouseDown,.keyDown,.scrollWheel]) { [weak self] event in
            self?.hide(); return event
        }
        resignObserver = NotificationCenter.default.addObserver(forName:NSWindow.didResignKeyNotification,object:nil,queue:.main) { [weak self] _ in
            MainActor.assumeIsolated { self?.hide() }
        }
    }
    func show(_ text: String, from view: AppTooltipTrackingView, at hoverPoint: NSPoint) {
        hide()
        guard !text.isEmpty, let window = view.window, window.isKeyWindow else { return }
        owner = view
        let work = DispatchWorkItem { [weak self, weak view] in
            guard let self, let view, self.owner === view, let parent = view.window, parent.isKeyWindow else { return }
            let bubble: AnyView
            if let weather = view.weather { bubble = AnyView(WeatherTooltipCard(data:weather)) }
            else if let zoneID = view.zoneID { bubble = AnyView(TimeZoneMapTooltip(zoneID:zoneID,primary:view.primaryZone)) }
            else { bubble = AnyView(AppTooltipBubble(text:text)) }
            let content = NSHostingView(rootView:bubble)
            let size = content.fittingSize
            guard size.width > 0, size.height > 0 else { return }
            let screen = parent.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
            // The strip is at the bottom of the calendar. Keep its detail
            // card above the entire strip so the graph remains unobscured.
            let stripTop: CGFloat? = view.weather == nil ? nil : parent.convertToScreen(view.convert(view.bounds,to:nil)).maxY+4
            let frame = AppTooltipPlacement.frame(size:size,hoverPoint:hoverPoint,screen:screen,aboveEdge:stripTop)
            let panel = NSPanel(contentRect:frame,styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
            panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true
            panel.ignoresMouseEvents = true; panel.hidesOnDeactivate = true
            // Hosting-view automatic resizing can recenter the panel after its
            // initial frame is assigned. Fix its measured size, then position it
            // after attachment using the original hover event's screen point.
            content.sizingOptions = []
            content.setFrameSize(size)
            panel.contentView = content
            parent.addChildWindow(panel,ordered:.above)
            panel.setFrame(frame,display:false)
            panel.orderFront(nil)
            panel.setFrame(frame,display:true)
            self.panel = panel
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline:.now()+(view.weather == nil ? AppTooltipTiming.delay : 0.1),execute:work)
    }
    func hide(owner view: AppTooltipTrackingView? = nil) {
        if let view, owner !== view { return }
        pending?.cancel(); pending = nil
        if let panel { panel.parent?.removeChildWindow(panel); panel.orderOut(nil) }
        panel = nil; owner = nil
    }
}
