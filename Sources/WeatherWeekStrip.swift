import SwiftUI
import AppKit

enum WeatherStripPalette {
    // Keep the original purple/blue/teal palette, grouping related measures.
    static let actualTemperature = Color(red:0.43,green:0.29,blue:0.71)
    static let feelsLikeTemperature = Color(red:0.56,green:0.43,blue:0.77)
    static let rain = Color(red:0.29,green:0.59,blue:0.83)
    static let wind = Color(red:0.10,green:0.54,blue:0.43)
    static let windGust = Color(red:0.07,green:0.39,blue:0.31)
    static let windDirection = Color(red:0.35,green:0.62,blue:0.52)
}

enum WeatherStripSizing {
    static func clamped(_ height: Double, maximum: Double = 320) -> Double {
        min(max(88,maximum),max(88,height.isFinite ? height : 108))
    }
    static func resized(start: Double, translation: CGFloat, scale: Double, maximum: Double = 320) -> Double {
        clamped(start-Double(translation)/max(0.1,scale),maximum:maximum)
    }
}

enum WeatherStripPresentation: Equatable {
    case hidden, loading, unavailable, forecast
    static func resolve(visible: Bool, loading: Bool, hasForecast: Bool) -> Self {
        if !visible { return .hidden }
        if loading { return .loading }
        return hasForecast ? .forecast : .unavailable
    }
    func height(preferred: CGFloat, scale: Double) -> CGFloat {
        switch self {
        case .hidden: return 0
        case .loading, .unavailable: return CGFloat(30*scale)
        case .forecast: return preferred
        }
    }
}

struct WeatherStripScale {
    let lower: Double
    let upper: Double
    let uvUpper: Double
    let rainUpper: Double
    let windUpper: Double
    init(hours: [WeatherHour]) {
        let temperatures = hours.compactMap(\.temperature)+hours.compactMap(\.apparentTemperature)
        lower = floor((temperatures.min() ?? 45)/5)*5
        upper = max(lower+10,ceil((temperatures.max() ?? 65)/5)*5)
        uvUpper = max(11,ceil(hours.compactMap(\.uvIndex).max() ?? 11))
        rainUpper = max(1,ceil(hours.compactMap(\.precipitation).max() ?? 1))
        let winds = hours.compactMap(\.windSpeed)+hours.compactMap(\.windGusts)
        windUpper = max(10,ceil((winds.max() ?? 10)/5)*5)
    }
    func fraction(_ temperature: Double) -> Double { min(1,max(0,(temperature-lower)/(upper-lower))) }
}

enum WeatherUVStyle {
    static func color(_ index: Double) -> Color {
        switch index { case ..<3: return .green; case ..<6: return Color(red:0.75,green:0.57,blue:0.08); case ..<8: return .orange; case ..<11: return .red; default: return .purple }
    }
}

struct OutdoorWeatherWindow {
    let start: Date
    let end: Date
    static func best(hours: [WeatherHour], now: Date) -> OutdoorWeatherWindow? {
        let upcoming = hours.filter { $0.date >= now && $0.date < now.addingTimeInterval(86400) }.sorted { $0.date < $1.date }
        func score(_ hour: WeatherHour) -> Double? {
            guard hour.isDay, let temp = hour.apparentTemperature ?? hour.temperature,
                  let rain = hour.precipitation, let chance = hour.precipitationProbability,
                  let wind = hour.windSpeed, let code = hour.code,
                  !(95...99).contains(code), !(71...77).contains(code), !(85...86).contains(code),
                  temp >= 45, temp <= 90, rain < 0.2, chance <= 35, wind <= 18,
                  (hour.windGusts ?? wind) <= 28, (hour.uvIndex ?? 0) < 8 else { return nil }
            return abs(temp-68)*0.7+chance*0.3+wind*0.5+(hour.uvIndex ?? 0)*2
        }
        var best: (OutdoorWeatherWindow,Double)?
        for (a,b) in zip(upcoming,upcoming.dropFirst()) {
            guard b.date.timeIntervalSince(a.date) == 3600, let first = score(a), let second = score(b) else { continue }
            let value = first+second
            if best == nil || value < best!.1 {
                best = (OutdoorWeatherWindow(start:a.date,end:b.date.addingTimeInterval(3600)),value)
            }
        }
        return best?.0
    }
}

private struct WeatherStripCorner: View {
    let height: CGFloat
    @ObservedObject var model: CalendarModel
    @ObservedObject var weather: WeatherOverlay
    var body: some View {
        TimelineView(.periodic(from:.now,by:60)) { timeline in
            let current = weather.hours.first { $0.date <= timeline.date && timeline.date < $0.date.addingTimeInterval(3600) }
            let outdoor = OutdoorWeatherWindow.best(hours:weather.hours,now:timeline.date)
            VStack(spacing:3) {
                Text("NOW").appFont(size:6,weight:.medium).foregroundStyle(.secondary)
                if let current, let temperature = current.temperature {
                    if model.comparisonTimeZones.isEmpty {
                        let value = WeatherTemperature(fahrenheit:temperature)
                        VStack(spacing:1) {
                            HStack(spacing:2) {
                                Image(systemName:current.symbol).appFont(size:8).foregroundStyle(.secondary)
                                Text(value.celsiusLabel).appFont(size:11,weight:.semibold)
                                    .lineLimit(1).minimumScaleFactor(0.65)
                            }
                            Text(value.fahrenheitLabel).appFont(size:7).foregroundStyle(.secondary)
                        }.accessibilityElement(children:.ignore).accessibilityLabel(value.pairedLabel)
                    } else {
                        HStack(spacing:3) {
                            Image(systemName:current.symbol).foregroundStyle(.secondary)
                            WeatherTemperatureText(fahrenheit:temperature,referenceSize:8).fontWeight(.semibold)
                        }.appFont(size:12).lineLimit(1).minimumScaleFactor(0.65)
                    }
                    if height >= AppTextSize.points(100), let feels = current.apparentTemperature {
                        let pair = WeatherTemperature(fahrenheit:feels).pairedLabel
                        if model.comparisonTimeZones.isEmpty {
                            VStack(spacing:0) {
                                Text("Feels").appFont(size:5.5)
                                Text(pair.replacingOccurrences(of:" / ",with:"/")).appFont(size:6)
                            }.foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.65)
                        } else {
                            Text("Feels "+pair).appFont(size:7).foregroundStyle(.secondary)
                                .lineLimit(1).minimumScaleFactor(0.65)
                        }
                    }
                } else { Text("—").appFont(size:12).foregroundStyle(.tertiary) }
                Rectangle().fill(Color.primary.opacity(0.08)).frame(width:20,height:0.5).padding(.vertical,2)
                if height >= AppTextSize.points(108) { Image(systemName:"figure.walk").appFont(size:10).foregroundStyle(.green.opacity(0.8)) }
                if let outdoor {
                    Text("Outside").appFont(size:7,weight:.medium)
                    Text(windowLabel(outdoor)).appFont(size:8,weight:.medium)
                        .lineLimit(1).minimumScaleFactor(0.65)
                } else {
                    Text("No window").appFont(size:7).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.7)
                }
            }.padding(.horizontal,3).frame(width:model.timeGutterWidth,height:height)
                .appHelp(help(current:current,outdoor:outdoor))
        }
    }
    private func windowLabel(_ window: OutdoorWeatherWindow) -> String {
        let start = model.dateLabel(window.start,template:"ha").lowercased()
        let end = model.dateLabel(window.end,template:"ha").lowercased()
        let same = start.hasSuffix("am") == end.hasSuffix("am")
        return (same ? String(start.dropLast(2)) : start)+"–"+end
    }
    private func help(current: WeatherHour?, outdoor: OutdoorWeatherWindow?) -> String {
        var lines = [weather.city]
        lines.append(current.map { "Now · "+$0.detail } ?? "Current conditions unavailable")
        if let outdoor {
            lines.append("Suggested outdoor window · "+model.dateLabel(outdoor.start,template:"EEE MMM d")+" · "+windowLabel(outdoor)+" · "+CalendarModel.zoneLabel(model.calendar.timeZone))
            lines.append("Best two-hour daylight stretch in the next 24 hours: dry, mild, and less windy, with lower UV. Times follow the calendar’s primary timezone.")
        } else { lines.append("No suitable two-hour outdoor window in the next 24 hours, or forecast data is unavailable.") }
        return lines.joined(separator:"\n")
    }
}

struct WeatherWeekStrip: View {
    @ObservedObject private var textSize = AppTextSize.shared
    @ObservedObject var model: CalendarModel
    @ObservedObject var weather: WeatherOverlay
    init(model: CalendarModel) { self.model = model; self.weather = model.weather }
    @AppStorage("weatherStripHeight") private var savedHeight = 108.0
    @State private var resizeStart: Double?
    @State private var liveHeight: Double?
    @State private var hoveringResize = false
    private var maximumHeight: Double { min(320,Double((NSScreen.main?.visibleFrame.height ?? 900)*0.45)/textSize.scale) }
    private var stripHeight: CGFloat { AppTextSize.points(CGFloat(WeatherStripSizing.clamped(liveHeight ?? savedHeight,maximum:maximumHeight))) }
    private var active: Bool { weather.showHorizontalStrip }
    private var hasForecast: Bool { !weather.hours(from:model.weekStart,to:model.weekEnd).isEmpty }
    private var presentation: WeatherStripPresentation { .resolve(visible:active,loading:weather.isLoading,hasForecast:hasForecast) }
    var body: some View {
        Group {
            if presentation == .loading || presentation == .unavailable { compactStatus }
            else { forecast }
        }
        .frame(height:presentation.height(preferred:stripHeight,scale:textSize.scale))
        .clipped().allowsHitTesting(active).accessibilityHidden(!active)
        .animation(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? nil : .easeInOut(duration:0.22),value:presentation)
    }
    private var compactStatus: some View {
        HStack(spacing:8) {
            Image(systemName:"cloud.sun").foregroundStyle(.secondary)
            Text("Weather").foregroundStyle(.secondary)
            Text(weather.locationName).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.tail)
                .layoutPriority(-1)
            if presentation == .loading {
                ProgressView().controlSize(.mini).accessibilityLabel("Loading weather")
                Text("Loading forecast…").foregroundStyle(.secondary).lineLimit(1)
            } else {
                Text(weather.hours.isEmpty ? weather.status : "No forecast for these dates")
                    .foregroundStyle(.secondary).lineLimit(1).truncationMode(.tail)
                    .appHelp(weather.hours.isEmpty ? weather.status : "No weather for these dates · forecasts cover the next 16 days")
                Button("Retry") { weather.load(zoneID:model.primaryTimeZoneID,force:true) }.buttonStyle(.borderless)
            }
            Spacer(minLength:0)
        }.appFont(size:10).padding(.horizontal,12)
            .frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.leading)
            .background(Color(nsColor:.textBackgroundColor))
    }
    private var forecast: some View {
        GeometryReader { geometry in
            let width = max(1,(geometry.size.width-model.timeGutterWidth)/CGFloat(model.visibleDayCount))
            let visibleHours = weather.hours(from:model.weekStart,to:model.weekEnd)
            let scale = WeatherStripScale(hours:visibleHours)
            HStack(spacing:0) {
                WeatherStripCorner(height:stripHeight,model:model,weather:weather)
                HStack(spacing:0) {
                    ForEach(-1..<(model.visibleDayCount+1),id:\.self) { index in
                        let day = model.calendar.date(byAdding:.day,value:index,to:model.weekStart)!
                        WeatherStripDay(model:model,weather:weather,day:day,scale:scale)
                            .frame(width:width)
                    }
                }
                .offset(x:-width+model.horizontalOffset)
                .frame(width:max(1,geometry.size.width-model.timeGutterWidth),alignment:.leading).clipped()
            }
            .transaction { if model.trackingHorizontalScroll { $0.disablesAnimations = true } }
        }
        .overlay(alignment:.top) {
            if presentation == .forecast {
                ZStack(alignment:.top) {
                    Color(nsColor:.textBackgroundColor)
                    Capsule().fill(Color.primary.opacity(hoveringResize || resizeStart != nil ? 0.30 : 0.12))
                        .frame(width:28,height:2).padding(.top,1)
                }.frame(maxWidth:.infinity).frame(height:7).contentShape(Rectangle())
                    .onHover { hovering in
                        hoveringResize = hovering
                        if hovering { NSCursor.resizeUpDown.push() } else { NSCursor.pop() }
                    }
                    .highPriorityGesture(DragGesture(minimumDistance:1,coordinateSpace:.global)
                        .onChanged { value in
                            if resizeStart == nil { resizeStart = WeatherStripSizing.clamped(savedHeight,maximum:maximumHeight) }
                            liveHeight = WeatherStripSizing.resized(start:resizeStart ?? savedHeight,translation:value.translation.height,scale:textSize.scale,maximum:maximumHeight)
                        }
                        .onEnded { _ in
                            if let liveHeight { savedHeight = liveHeight }
                            liveHeight = nil; resizeStart = nil
                        })
                    .onTapGesture(count:2) { savedHeight = 108 }
                    .accessibilityLabel("Weather strip height")
                    .accessibilityValue("\(Int(stripHeight)) points")
                    .accessibilityAdjustableAction { direction in
                        savedHeight = WeatherStripSizing.clamped(savedHeight+(direction == .increment ? 16 : -16),maximum:maximumHeight)
                    }
                    .appHelp("Drag to resize the weather strip · Double-click to reset")
            }
        }
    }
}

private struct WeatherStripDay: View {
    @ObservedObject var model: CalendarModel
    @ObservedObject var weather: WeatherOverlay
    let day: Date
    let scale: WeatherStripScale
    @State private var hoverX: CGFloat?
    private var hours: [WeatherHour] { weather.hours(on:day,calendar:model.calendar).sorted { $0.date < $1.date } }
    private let purple = WeatherStripPalette.actualTemperature
    private let blue = WeatherStripPalette.rain
    private func x(_ date: Date, width: CGFloat) -> CGFloat { CGFloat(model.minuteOfDay(date)/1440)*width }
    private func drawMetricLine(context: GraphicsContext, size: CGSize, baseline: CGFloat,
                                value: (WeatherHour) -> Double?, upper: Double,
                                color: Color, dash: [CGFloat] = [], circular: Bool = false) {
        func point(_ hour: WeatherHour, _ value: Double) -> CGPoint {
            CGPoint(x:x(hour.date,width:size.width),y:baseline-3-CGFloat(max(0,min(1,value/upper)))*max(1,baseline-14))
        }
        var path = Path()
        var previous: (Date,Double)?
        for hour in hours {
            guard let value = value(hour) else { previous = nil; continue }
            let p = point(hour,value)
            if let previous, hour.date.timeIntervalSince(previous.0) <= 5400,
               !circular || abs(value-previous.1) <= 180 { path.addLine(to:p) }
            else { path.move(to:p) }
            previous = (hour.date,value)
        }
        let midnight = model.calendar.date(byAdding:.day,value:1,to:model.calendar.startOfDay(for:day))!
        if let previous, midnight.timeIntervalSince(previous.0) <= 5400,
           let next = weather.hour(at:midnight), let value = value(next),
           !circular || abs(value-previous.1) <= 180 {
            path.addLine(to:CGPoint(x:size.width,y:point(next,value).y))
        }
        context.stroke(path,with:.color(color.opacity(0.8)),style:StrokeStyle(lineWidth:0.9,lineCap:.round,dash:dash))
    }
    private func drawHoverLabels(context: GraphicsContext, plotSize: CGSize) {
        guard let hoverX, !model.trackingHorizontalScroll else { return }
        let guideX = min(plotSize.width,max(0,hoverX))
        let baseline = max(1,plotSize.height-18)
                            let minute = Double(guideX/max(1,plotSize.width))*1440
                            if let hour = hours.first(where:{ model.minuteOfDay($0.date) <= minute && minute < model.minuteOfDay($0.date)+60 }) {
                                // Sort by the rendered curve at the cursor, interpolating between
                                // hourly samples so crossings reorder at their visual position.
                                func interpolated(_ key: (WeatherHour) -> Double?) -> Double? {
                                    guard let current = key(hour) else { return nil }
                                    let elapsed = (minute-model.minuteOfDay(hour.date))/60
                                    guard let next = weather.hour(at:hour.date.addingTimeInterval(3600)),
                                          let following = key(next) else { return current }
                                    return current+(following-current)*max(0,min(1,elapsed))
                                }
                                func metricY(_ value: Double, upper: Double) -> CGFloat {
                                    baseline-3-CGFloat(max(0,min(1,value/upper)))*max(1,baseline-14)
                                }
                                func temperatureY(_ value: Double) -> CGFloat {
                                    8+(1-scale.fraction(value))*max(1,baseline-16)
                                }
                                var values: [(String,Color,CGFloat)] = []
                                if weather.showTemperature, let value = hour.temperature { values.append(("Air \(WeatherTemperature(fahrenheit:value).pairedLabel) - Actual",purple,temperatureY(interpolated { $0.temperature } ?? value))) }
                                if weather.showTemperature, let value = hour.apparentTemperature { values.append(("Air \(WeatherTemperature(fahrenheit:value).pairedLabel) - Feels Like",WeatherStripPalette.feelsLikeTemperature,temperatureY(interpolated { $0.apparentTemperature } ?? value))) }
                                if weather.showUV, let value = hour.uvIndex { values.append((String(format:"UV %.1f",value),.orange,metricY(interpolated { $0.uvIndex } ?? value,upper:scale.uvUpper))) }
                                if weather.showRain && (hour.precipitationProbability != nil || hour.precipitationInches != nil) {
                                    let chance = hour.precipitationProbability.map { "\(Int($0.rounded()))%" } ?? "—"
                                    let amount = hour.precipitationInches.map { String(format:"%.1f inches",$0) } ?? "—"
                                    values.append(("Rain \(chance) - \(amount)",blue,metricY(interpolated { $0.precipitationProbability } ?? 0,upper:100)))
                                }
                                if weather.showSky, let value = hour.cloudCover { values.append(("Cloud cover \(Int(value.rounded()))% - \(hour.cloudDescription)",.secondary,8+CGFloat(max(0,min(100,interpolated { $0.cloudCover } ?? value))/100)*baseline*0.35)) }
                                if weather.showWind, let value = hour.windSpeed {
                                    let gust = hour.windGusts.map { " - Gust \(Int($0.rounded())) mph" } ?? ""
                                    let direction = hour.windDirection.map { " - From \(WeatherHour.compass($0))" } ?? ""
                                    values.append(("Wind \(Int(value.rounded())) mph"+gust+direction,WeatherStripPalette.wind,metricY(interpolated { $0.windSpeed } ?? value,upper:scale.windUpper)))
                                }
                                values = values.enumerated().sorted {
                                    $0.element.2 == $1.element.2 ? $0.offset < $1.offset : $0.element.2 < $1.element.2
                                }.map(\.element)
                                let rowHeight = min(AppTextSize.points(11),max(1,(baseline-4)/CGFloat(max(1,values.count))))
                                for (index,value) in values.enumerated() {
                                    let label = context.resolve(Text(value.0).font(.system(size:AppTextSize.points(8),weight:.medium)).foregroundColor(value.1))
                                    let measured = label.measure(in:CGSize(width:300,height:rowHeight))
                                    let arrow = value.0.hasPrefix("Wind ") ? hour.windFlowVector : nil
                                    let width = measured.width+6+(arrow == nil ? 0 : 12)
                                    let left = guideX+5
                                    let top = 2+CGFloat(index)*rowHeight
                                    let badge = CGRect(x:left,y:top,width:width,height:rowHeight-0.5)
                                    context.fill(Path(roundedRect:badge,cornerRadius:2),with:.color(Color(nsColor:.windowBackgroundColor).opacity(0.94)))
                                    context.draw(label,at:CGPoint(x:left+3,y:top+(rowHeight-measured.height)/2),anchor:.topLeading)
                                    if let arrow {
                                        let center = CGPoint(x:left+measured.width+9,y:top+rowHeight/2)
                                        let tip = CGPoint(x:center.x+arrow.x*3,y:center.y+arrow.y*3)
                                        var direction = Path()
                                        direction.move(to:CGPoint(x:center.x-arrow.x*3,y:center.y-arrow.y*3)); direction.addLine(to:tip)
                                        direction.move(to:CGPoint(x:tip.x-arrow.x*2-arrow.y*1.6,y:tip.y-arrow.y*2+arrow.x*1.6))
                                        direction.addLine(to:tip)
                                        direction.addLine(to:CGPoint(x:tip.x-arrow.x*2+arrow.y*1.6,y:tip.y-arrow.y*2-arrow.x*1.6))
                                        context.stroke(direction,with:.color(WeatherStripPalette.wind),style:StrokeStyle(lineWidth:0.9,lineCap:.round,lineJoin:.round))
                                    }
                                }
                            }
    }
    var body: some View {
        VStack(spacing:2) {
            if !hours.isEmpty {
                let temperatures = hours.compactMap(\.temperature)
                GeometryReader { geometry in
                    Canvas { context,size in
                        let baseline = max(1,size.height-18)
                        let hourWidth = size.width/24
                        func temperatureY(_ value: Double) -> CGFloat { 8+(1-scale.fraction(value))*max(1,baseline-16) }
                        for hour in hours {
                            let left = x(hour.date,width:size.width)
                            if weather.showSky {
                                let cloud = max(0,min(1,(hour.cloudCover ?? 0)/100))
                                if hour.isDay {
                                    context.fill(Path(CGRect(x:left,y:0,width:hourWidth+0.5,height:baseline)),with:.color(.yellow.opacity(0.09)))
                                }
                                if hour.cloudCover != nil {
                                    context.fill(Path(CGRect(x:left,y:0,width:hourWidth+0.5,height:8+CGFloat(cloud)*baseline*0.35)),with:.color(.gray.opacity(0.15)))
                                }
                            }
                            if weather.showRain, let chance = hour.precipitationProbability {
                                let height = CGFloat(max(0,min(100,chance))/100)*baseline*0.55
                                context.fill(Path(CGRect(x:left,y:baseline-height,width:hourWidth+0.5,height:height)),with:.color(blue.opacity(0.18)))
                            }
                            if weather.showRain, let rain = hour.precipitation, rain > 0 {
                                let height = min(baseline*0.32,CGFloat(rain)*5+1)
                                context.fill(Path(CGRect(x:left+1,y:baseline-height,width:max(1,hourWidth-2),height:height)),with:.color(blue.opacity(0.48)))
                            }
                        }
                        // A dedicated UV ribbon sits below the plot, separate
                        // from rainfall, and uses the same hourly time axis.
                        for hour in hours {
                            if weather.showUV, let uv = hour.uvIndex {
                                context.fill(Path(CGRect(x:x(hour.date,width:size.width),y:baseline+1,width:hourWidth+0.5,height:3)),with:.color(WeatherUVStyle.color(uv).opacity(uv > 0 ? 0.65 : 0.12)))
                            }
                        }
                        var line = Path()
                        var previous: Date?
                        for hour in hours {
                            guard let temperature = hour.temperature else { previous = nil; continue }
                            let point = CGPoint(x:x(hour.date,width:size.width),y:temperatureY(temperature))
                            if let previous, hour.date.timeIntervalSince(previous) <= 5400 { line.addLine(to:point) }
                            else { line.move(to:point) }
                            previous = hour.date
                        }
                        let midnight = model.calendar.date(byAdding:.day,value:1,to:model.calendar.startOfDay(for:day))!
                        if let previous, midnight.timeIntervalSince(previous) <= 5400,
                           let next = weather.hour(at:midnight), let value = next.temperature {
                            line.addLine(to:CGPoint(x:size.width,y:temperatureY(value)))
                        }
                        if weather.showTemperature { context.stroke(line,with:.color(purple.opacity(0.85)),lineWidth:1.2) }
                        var feelsLine = Path()
                        var previousFeels: Date?
                        for hour in hours {
                            guard let feels = hour.apparentTemperature else { previousFeels = nil; continue }
                            let point = CGPoint(x:x(hour.date,width:size.width),y:temperatureY(feels))
                            if let previousFeels, hour.date.timeIntervalSince(previousFeels) <= 5400 { feelsLine.addLine(to:point) }
                            else { feelsLine.move(to:point) }
                            previousFeels = hour.date
                        }
                        if let previousFeels, midnight.timeIntervalSince(previousFeels) <= 5400,
                           let next = weather.hour(at:midnight), let value = next.apparentTemperature {
                            feelsLine.addLine(to:CGPoint(x:size.width,y:temperatureY(value)))
                        }
                        if weather.showTemperature { context.stroke(feelsLine,with:.color(WeatherStripPalette.feelsLikeTemperature.opacity(0.8)),style:StrokeStyle(lineWidth:1.1,dash:[4,2])) }
                        if weather.showWind {
                            drawMetricLine(context:context,size:size,baseline:baseline,value:{ $0.windSpeed },upper:scale.windUpper,color:WeatherStripPalette.wind)
                            drawMetricLine(context:context,size:size,baseline:baseline,value:{ $0.windGusts },upper:scale.windUpper,color:WeatherStripPalette.windGust,dash:[4,2])
                        }
                        if let hoverX, !model.trackingHorizontalScroll {
                            let guideX = min(size.width,max(0,hoverX))
                            var guide = Path()
                            guide.move(to:CGPoint(x:guideX,y:0)); guide.addLine(to:CGPoint(x:guideX,y:baseline))
                            context.stroke(guide,with:.color(Color.accentColor.opacity(0.7)),lineWidth:1)
                        }
                        for hour in [0,6,12,18,24] {
                            let label = [0:"12a",6:"6a",12:"12p",18:"6p",24:"12a"][hour]!
                            context.draw(Text(label).font(.system(size:AppTextSize.points(7))).foregroundColor(.secondary),at:CGPoint(x:min(size.width-8,max(8,size.width*CGFloat(hour)/24)),y:size.height-7))
                        }
                    }
                    TimelineView(.periodic(from:.now,by:30)) { timeline in
                        if model.calendar.isDate(day,inSameDayAs:timeline.date) {
                            let nowX = x(timeline.date,width:geometry.size.width)
                            Path { path in
                                path.move(to:CGPoint(x:nowX,y:0))
                                path.addLine(to:CGPoint(x:nowX,y:max(0,geometry.size.height-18)))
                            }.stroke(Color.red.opacity(0.8),lineWidth:1)
                                .allowsHitTesting(false)
                                .accessibilityLabel("Current time")
                        }
                    }.allowsHitTesting(false)
                    Canvas { context,_ in
                        drawHoverLabels(context:context,plotSize:geometry.size)
                    }.frame(width:geometry.size.width+300,height:geometry.size.height)
                        .allowsHitTesting(false)
                }.contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let point): hoverX = point.x
                        case .ended: hoverX = nil
                        }
                    }
                HStack(spacing:4) {
                    if let middle = hours.min(by:{ abs(model.minuteOfDay($0.date)-720) < abs(model.minuteOfDay($1.date)-720) }) {
                        Button { weather.selectGraphLayer(.sky,exclusively:NSApp.currentEvent?.modifierFlags.contains(.shift) == true) } label: {
                            Image(systemName:middle.symbol).symbolRenderingMode(.hierarchical).foregroundStyle(blue)
                        }.buttonStyle(.plain).opacity(weather.showSky ? 1 : 0.35)
                            .accessibilityLabel("Sky shading").accessibilityValue(weather.showSky ? "Shown" : "Hidden")
                            .appHelp("Toggle sky and cloud shading · Shift-click to show only sky")
                    }
                    if let high = temperatures.max(), let low = temperatures.min() {
                        let range = WeatherTemperature.highLow(high:high,low:low)
                        Button { weather.selectGraphLayer(.temperature,exclusively:NSApp.currentEvent?.modifierFlags.contains(.shift) == true) } label: {
                            (Text(range.celsius).foregroundColor(purple)
                             + Text(" · "+range.fahrenheit).foregroundColor(purple.opacity(0.55)))
                                .minimumScaleFactor(0.65)
                        }.buttonStyle(.plain).opacity(weather.showTemperature ? 1 : 0.35)
                            .accessibilityLabel("Temperature lines").accessibilityValue(weather.showTemperature ? "Shown" : "Hidden")
                            .appHelp("High: \(WeatherTemperature(fahrenheit:high).pairedLabel)\nLow: \(WeatherTemperature(fahrenheit:low).pairedLabel)\nShift-click to show only temperature")
                    }
                    if let peakUV = hours.compactMap(\.uvIndex).max() {
                        Button { weather.selectGraphLayer(.uv,exclusively:NSApp.currentEvent?.modifierFlags.contains(.shift) == true) } label: {
                            Text("UV \(Int(peakUV.rounded()))").foregroundStyle(WeatherUVStyle.color(peakUV))
                        }.buttonStyle(.plain).opacity(weather.showUV ? 1 : 0.35)
                            .accessibilityLabel("UV ribbon").accessibilityValue(weather.showUV ? "Shown" : "Hidden")
                            .appHelp(String(format:"Peak hourly UV index: %.1f\nColored ribbon: hourly UV index\nShift-click to show only UV",peakUV))
                    }
                    if let rain = hours.compactMap(\.precipitationProbability).max() {
                        Button { weather.selectGraphLayer(.rain,exclusively:NSApp.currentEvent?.modifierFlags.contains(.shift) == true) } label: {
                            HStack(spacing:2) { Image(systemName:"drop"); Text("\(Int(rain.rounded()))%") }.foregroundStyle(blue)
                        }.buttonStyle(.plain).opacity(weather.showRain ? 1 : 0.35)
                            .accessibilityLabel("Rain graph").accessibilityValue(weather.showRain ? "Shown" : "Hidden")
                            .appHelp("Toggle rain probability and precipitation · Shift-click to show only rain")
                    }
                    if let wind = hours.compactMap(\.windSpeed).max() {
                        Button { weather.selectGraphLayer(.wind,exclusively:NSApp.currentEvent?.modifierFlags.contains(.shift) == true) } label: {
                            Text("\(Int(wind.rounded()))mph").foregroundStyle(WeatherStripPalette.wind)
                        }.buttonStyle(.plain).opacity(weather.showWind ? 1 : 0.35)
                            .accessibilityLabel("Wind lines").accessibilityValue(weather.showWind ? "Shown" : "Hidden")
                            .appHelp("Toggle wind speed and gusts · Shift-click to show only wind")
                    }
                }.appFont(size:8).lineLimit(1).minimumScaleFactor(0.65).padding(.horizontal,5).frame(maxWidth:.infinity,alignment:.center).frame(height:16)
                    .background(Color(nsColor:.textBackgroundColor))
            } else {
                Spacer()
                Text(weather.isLoading ? "Loading…" : "No forecast").appFont(size:9).foregroundStyle(.tertiary)
                Spacer()
            }
        }.onChange(of:day) { _,_ in hoverX = nil }
            .padding(.top,4)
            .background(Color(nsColor:.textBackgroundColor))
            .zIndex(hoverX == nil ? 0 : 1)
    }
}
