import SwiftUI
import AppKit

enum CalendarViewMode: String, CaseIterable, Identifiable {
    case day, twoDays, threeDays, fourDays, fiveDays, sixDays, week, month, monthDetailed, year
    var id: String { rawValue }
    var dayCount: Int {
        switch self { case .day: return 1; case .twoDays: return 2; case .threeDays: return 3; case .fourDays: return 4; case .fiveDays: return 5; case .sixDays: return 6; default: return 7 }
    }
    var isTimeline: Bool { [.day,.twoDays,.threeDays,.fourDays,.fiveDays,.sixDays,.week].contains(self) }
    var label: String {
        switch self {
        case .day: return "Day"
        case .twoDays: return "2 Days"
        case .threeDays: return "3 Days"
        case .fourDays: return "4 Days"
        case .fiveDays: return "5 Days"
        case .sixDays: return "6 Days"
        case .week: return "7 Days (Week)"
        case .month: return "Month · Standard"
        case .monthDetailed: return "Month · Detailed"
        case .year: return "Year"
        }
    }
    func cycled(by step: Int) -> CalendarViewMode {
        let modes = Self.allCases
        let index = modes.firstIndex(of:self)!
        return modes[((index + step) % modes.count + modes.count) % modes.count]
    }
    var navigationUnit: String { isTimeline ? (dayCount == 1 ? "day" : "\(dayCount) days") : (self == .year ? "year" : "month") }
}
enum CalendarViewDates {
    static func monthStart(_ date: Date, calendar: Calendar) -> Date { calendar.dateInterval(of:.month,for:date)!.start }
    static func monthGridStart(_ date: Date, calendar: Calendar) -> Date {
        calendar.dateInterval(of:.weekOfYear,for:monthStart(date,calendar:calendar))!.start
    }
    static func isMultiDay(_ event: CalendarEntry, calendar: Calendar) -> Bool {
        event.end > event.start && !calendar.isDate(event.start,inSameDayAs:event.end.addingTimeInterval(-0.001))
    }
    static func monthSpans(_ entries: [CalendarEntry], week: Date, calendar: Calendar) -> [AllDaySpan] {
        let intervals = entries.filter { isMultiDay($0,calendar:calendar) }.map { event in
            let last = calendar.startOfDay(for:event.end.addingTimeInterval(-0.001))
            return TimedInterval(id:event.id,start:calendar.startOfDay(for:event.start),end:calendar.date(byAdding:.day,value:1,to:last)!)
        }
        return AllDayLayout.spans(intervals,weekStart:week,calendar:calendar)
    }
    static func events(_ entries: [CalendarEntry], on date: Date, calendar: Calendar) -> [CalendarEntry] {
        let start = calendar.startOfDay(for:date), end = calendar.date(byAdding:.day,value:1,to:start)!
        return entries.filter { $0.start < end && $0.end > start }.sorted {
            if $0.allDay != $1.allDay { return $0.allDay }
            return $0.start == $1.start ? $0.title < $1.title : $0.start < $1.start
        }
    }
}
struct CalendarViewMenu: View {
    @ObservedObject var model: CalendarModel
    var body: some View {
        Menu {
            Picker("Calendar view",selection:Binding(get:{ model.viewMode },set:{ model.setView($0) })) {
                Section("Time grid") { ForEach(CalendarViewMode.allCases.filter(\.isTimeline)) { Text($0.label).tag($0) } }
                Section("Month detail") { ForEach([CalendarViewMode.month,.monthDetailed]) { Text($0.label).tag($0) } }
                Text("Year").tag(CalendarViewMode.year)
            }.pickerStyle(.inline).labelsHidden()
        } label: {
            HStack(spacing:5) {
                Text(model.viewMode.label).appFont(size:12,weight:.medium)
                Image(systemName:"chevron.down").appFont(size:8,weight:.semibold)
            }.padding(.horizontal,8).frame(height:AppTextSize.points(28)).fixedSize()
        }.menuIndicator(.hidden)
        .appHelp("Choose view · Control-Tab: next · Control-Shift-Tab: previous")
    }
}
struct CalendarOverview: View {
    @ObservedObject var model: CalendarModel
    var body: some View {
        if model.viewMode == .year { CalendarYearOverview(model:model) }
        else { CalendarMonthOverview(model:model) }
    }
}
struct CalendarMonthOverview: View {
    @ObservedObject private var textSize = AppTextSize.shared
    @ObservedObject var model: CalendarModel
    @State private var weeks: [Date] = []
    @State private var scrollWeek: Date?
    private func week(containing date: Date) -> Date { model.calendar.dateInterval(of:.weekOfYear,for:date)!.start }
    private func resetScroll() {
        let target = CalendarViewDates.monthGridStart(model.anchor,calendar:model.calendar)
        weeks = (-26...30).map { model.calendar.date(byAdding:.weekOfYear,value:$0,to:target)! }
        loadEvents()
        scrollWeek = target
    }
    private func loadEvents() {
        guard let first = weeks.first, let last = weeks.last else { return }
        model.loadMonthScrollRange(start:first,end:model.calendar.date(byAdding:.day,value:7,to:last)!)
    }
    private func scrolled(to date: Date?) {
        guard let date, let index = weeks.firstIndex(of:date) else { return }
        // The middle of the top week determines the toolbar's month.
        let middle = model.calendar.date(byAdding:.day,value:3,to:date)!
        if !model.calendar.isDate(middle,equalTo:model.anchor,toGranularity:.month) { model.anchor = middle }
        if index < 5 {
            let first = weeks[0]
            weeks.insert(contentsOf:(-26 ... -1).map { model.calendar.date(byAdding:.weekOfYear,value:$0,to:first)! },at:0)
            if weeks.count > 109 { weeks.removeLast(26) }
            loadEvents()
        } else if index > weeks.count-6 {
            let last = weeks.last!
            weeks.append(contentsOf:(1...26).map { model.calendar.date(byAdding:.weekOfYear,value:$0,to:last)! })
            if weeks.count > 109 { weeks.removeFirst(26) }
            loadEvents()
        }
    }
    private var rowHeight: CGFloat {
        switch model.viewMode { case .monthDetailed: return 252*textSize.scale; default: return 125*textSize.scale }
    }
    var body: some View {
        VStack(spacing:0) {
            HStack(spacing:0) {
                ForEach(0..<7,id:\.self) { offset in
                    let day = model.calendar.date(byAdding:.day,value:offset,to:week(containing:model.anchor))!
                    Text(model.dateLabel(day,template:"EEE")).appFont(size:10,weight:.medium).foregroundStyle(.secondary).frame(maxWidth:.infinity)
                }
            }.padding(.vertical,9)
            ScrollView {
                LazyVStack(spacing:0) {
                    ForEach(weeks,id:\.self) { start in
                        MonthWeekRow(model:model,start:start,baseHeight:rowHeight).id(start)
                    }
                }.scrollTargetLayout()
            }.scrollPosition(id:$scrollWeek,anchor:.top)
                .onChange(of:scrollWeek) { _,date in scrolled(to:date) }
        }
        .onAppear { resetScroll() }
        .onChange(of:model.firstVisibleDay) { _,_ in resetScroll() }
        .onChange(of:model.primaryTimeZoneID) { _,_ in resetScroll() }
    }

}
private struct MonthWeekRow: View {
    @ObservedObject private var textSize = AppTextSize.shared
    @ObservedObject var model: CalendarModel
    let start: Date
    let baseHeight: CGFloat
    private var spans: [AllDaySpan] { CalendarViewDates.monthSpans(model.shown,week:start,calendar:model.calendar) }
    var body: some View {
        let ribbons = spans
        let laneHeight = AppTextSize.points(21)
        let ribbonHeight = CGFloat((ribbons.map(\.row).max() ?? -1)+1)*laneHeight
        HStack(spacing:0) {
            ForEach(0..<7,id:\.self) { offset in
                let date = model.calendar.date(byAdding:.day,value:offset,to:start)!
                MonthDayCell(model:model,date:date,events:CalendarViewDates.events(model.shown,on:date,calendar:model.calendar),ribbonHeight:ribbonHeight)
                    .frame(maxWidth:.infinity).frame(height:baseHeight+ribbonHeight)
            }
        }
        .overlay(alignment:.topLeading) {
            GeometryReader { geometry in
                ForEach(ribbons,id:\.id) { span in
                    if let event = model.shown.first(where:{ $0.id == span.id }) {
                        let end = model.calendar.date(byAdding:.day,value:7,to:start)!
                        HStack(spacing:3) {
                            if event.start < start { Image(systemName:"chevron.left").appFont(size:8).foregroundStyle(.secondary) }
                            MonthEventRow(model:model,event:event,detailed:false)
                            if event.end > end { Image(systemName:"chevron.right").appFont(size:8).foregroundStyle(.secondary) }
                        }
                        .frame(width:max(1,geometry.size.width/7*CGFloat(span.endDay-span.firstDay)-4),height:laneHeight-2)
                        .offset(x:geometry.size.width/7*CGFloat(span.firstDay)+2,y:AppTextSize.points(33)+CGFloat(span.row)*laneHeight)
                    }
                }
            }
        }
    }
}
private struct MonthDayCell: View {
    @ObservedObject var model: CalendarModel
    let date: Date
    let events: [CalendarEntry]
    var ribbonHeight: CGFloat = 0
    private var singleDayEvents: [CalendarEntry] { events.filter { !CalendarViewDates.isMultiDay($0,calendar:model.calendar) } }
    @State private var agenda = false
    private var currentMonth: Bool { model.calendar.component(.month,from:date) % 2 == 0 }
    private var limit: Int { model.viewMode == .monthDetailed ? 6 : 3 }
    var body: some View {
        VStack(alignment:.leading,spacing:4) {
            HStack {
                Button(model.dateLabel(date,template:model.calendar.component(.day,from:date) == 1 ? "MMM d" : "d")) { model.jump(to:date); model.setView(.day) }
                    .buttonStyle(.plain).appFont(size:11,weight:.medium)
                    .foregroundStyle(model.calendar.isDateInToday(date) ? Color.white : Color.primary)
                    .frame(minWidth:23,minHeight:23).background(model.calendar.isDateInToday(date) ? Color.red : .clear,in:Circle())
                Spacer(minLength:0)
                if model.weather.enabled, let hour = model.weather.hours(on:date,calendar:model.calendar).first(where:{ model.calendar.component(.hour,from:$0.date) == 12 }) {
                    Image(systemName:hour.symbol).appFont(size:9).foregroundStyle(.secondary).appHelp(hour.detail)
                }
            }
                if ribbonHeight > 0 { Color.clear.frame(height:ribbonHeight) }
                ForEach(singleDayEvents.prefix(limit)) { event in
                    MonthEventRow(model:model,event:event,detailed:model.viewMode == .monthDetailed)
                }
                if singleDayEvents.count > limit { Button("+\(singleDayEvents.count-limit) more") { agenda = true }.buttonStyle(.plain).appFont(size:9).foregroundStyle(.secondary) }
            Spacer(minLength:0)
        }.padding(6).frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading)
            .background(currentMonth ? Color.clear : Color.primary.opacity(0.025))
            .overlay(Rectangle().strokeBorder(Color.primary.opacity(0.11),lineWidth:0.5))
            .contentShape(Rectangle())
            .onTapGesture(count:2) { model.newEvent(at:model.dateAtMinute(13*60,on:date)) }
            .popover(isPresented:$agenda) {
                VStack(alignment:.leading,spacing:10) {
                    Text(model.dateLabel(date,template:"EEEE MMM d")).appFont(size:14,weight:.semibold)
                    ScrollView { VStack(spacing:6) { ForEach(events) { event in MonthEventRow(model:model,event:event,detailed:true) } }.padding(.horizontal,14) }.padding(.horizontal,-14)
                    Button("Open Day") { agenda = false; model.jump(to:date); model.setView(.day) }
                }.padding(14).frame(width:320,height:320)
            }
    }
}
private struct MonthEventRow: View {
    @ObservedObject var model: CalendarModel
    let event: CalendarEntry
    var detailed: Bool
    var body: some View {
        VStack(alignment:.leading,spacing:1) {
            HStack(spacing:4) {
                Text(event.displayTitle).appFont(size:10,weight:.medium).lineLimit(1).frame(maxWidth:.infinity,alignment:.leading)
                if !event.writable { ReadOnlyLockIcon(color:Color(nsColor:event.color)) }
            }
            if detailed {
                Text(event.allDay ? "All day" : EventTimeLabel.string(start:event.start,end:event.end,calendar:model.calendar))
                    .appFont(size:8).lineLimit(1).foregroundStyle(.secondary)
            }
        }.padding(.vertical,3).padding(.leading,6).padding(.trailing,3).frame(maxWidth:.infinity,alignment:.leading)
            .background(Color(nsColor:event.color).opacity(model.selected.contains(event.id) ? 0.26 : 0.11),in:RoundedRectangle(cornerRadius:3))
            .overlay(alignment:.leading) { RoundedRectangle(cornerRadius:1).fill(Color(nsColor:event.color)).frame(width:2) }
            .contentShape(Rectangle())
            .onTapGesture(count:2) { model.edit(event) }
            .onTapGesture { model.select(event.id,extending:NSEvent.modifierFlags.contains(.command)) }
            .appHelp(event.title + (event.allDay ? " · All day" : " · "+model.dateLabel(event.start,template:"jm").lowercased()))
    }
}
struct CalendarYearOverview: View {
    @ObservedObject var model: CalendarModel
    private var months: [Date] {
        let start = model.calendar.dateInterval(of:.year,for:model.anchor)!.start
        return (0..<12).map { model.calendar.date(byAdding:.month,value:$0,to:start)! }
    }
    var body: some View {
        ScrollView {
            LazyVGrid(columns:[GridItem(.adaptive(minimum:210),spacing:22)],spacing:24) {
                ForEach(months,id:\.self) { month in
                    VStack(alignment:.leading,spacing:8) {
                        Button(model.dateLabel(month,template:"MMMM")) { model.jump(to:month); model.setView(.month) }
                            .buttonStyle(.plain).appFont(size:14,weight:.semibold)
                        let start = CalendarViewDates.monthGridStart(month,calendar:model.calendar)
                        LazyVGrid(columns:Array(repeating:GridItem(.flexible(),spacing:1),count:7),spacing:4) {
                            ForEach(0..<7) { index in
                                Text(model.dateLabel(model.calendar.date(byAdding:.day,value:index,to:start)!,template:"EEEEE")).appFont(size:8).foregroundStyle(.tertiary)
                            }
                            ForEach(0..<42) { offset in
                                let date = model.calendar.date(byAdding:.day,value:offset,to:start)!
                                let inMonth = model.calendar.isDate(date,equalTo:month,toGranularity:.month)
                                let items = inMonth ? CalendarViewDates.events(model.shown,on:date,calendar:model.calendar) : []
                                Button { model.jump(to:date); model.setView(.day) } label: {
                                    VStack(spacing:2) {
                                        Text(inMonth ? model.dateLabel(date,template:"d") : " ").appFont(size:10)
                                            .foregroundStyle(model.calendar.isDateInToday(date) ? Color.red : Color.primary)
                                        Circle().fill(items.first.map { Color(nsColor:$0.color) } ?? .clear).frame(width:3,height:3)
                                    }.frame(maxWidth:.infinity).padding(.vertical,1)
                                }.buttonStyle(.plain).disabled(!inMonth)
                                    .appHelp(items.isEmpty ? "" : "\(items.count) events · double-click an event in Day view to edit")
                            }
                        }
                    }.padding(12).background(Color.primary.opacity(0.025),in:RoundedRectangle(cornerRadius:10))
                }
            }.padding(16)
        }
    }
}

struct SidebarMiniCalendar: View {
    @ObservedObject private var textSize = AppTextSize.shared
    @ObservedObject var model: CalendarModel
    @State private var month: Date
    init(model: CalendarModel) {
        self.model = model
        self._month = State(initialValue:CalendarViewDates.monthStart(model.anchor,calendar:model.calendar))
    }
    private var dates: [Date] {
        let start = CalendarViewDates.monthGridStart(month,calendar:model.calendar)
        return (0..<42).map { model.calendar.date(byAdding:.day,value:$0,to:start)! }
    }
    private var weekdayLabels: [String] {
        let labels = model.calendar.veryShortStandaloneWeekdaySymbols
        return (0..<7).map { labels[(model.calendar.firstWeekday-1+$0)%7] }
    }
    private func browse(_ amount: Int) { month = model.calendar.date(byAdding:.month,value:amount,to:month)! }
    var body: some View {
        VStack(spacing:9) {
            HStack(spacing:4) {
                Text(model.dateLabel(month,template:"MMMM yyyy")).appFont(size:12,weight:.semibold).lineLimit(1)
                Spacer(minLength:2)
                Button { browse(-1) } label: { Image(systemName:"chevron.left") }
                    .appHelp("Previous month").accessibilityLabel("Previous month")
                Button { month = CalendarViewDates.monthStart(Date(),calendar:model.calendar); model.today() } label: {
                    Circle().fill(Color.secondary).frame(width:5,height:5).frame(width:18,height:20)
                }.appHelp("Jump to today").accessibilityLabel("Jump to today")
                Button { browse(1) } label: { Image(systemName:"chevron.right") }
                    .appHelp("Next month").accessibilityLabel("Next month")
            }.appFont(size:10,weight:.medium).buttonStyle(.plain).padding(.horizontal,5)
            LazyVGrid(columns:Array(repeating:GridItem(.flexible(minimum:0),spacing:1),count:7),spacing:3) {
                ForEach(0..<7,id:\.self) { index in
                    Text(weekdayLabels[index]).appFont(size:9,weight:.medium).foregroundStyle(.tertiary)
                        .frame(maxWidth:.infinity).frame(height:16)
                }
                ForEach(dates,id:\.self) { date in
                    let today = model.calendar.isDateInToday(date)
                    let selected = model.calendar.isDate(date,inSameDayAs:model.anchor)
                    let inMonth = model.calendar.isDate(date,equalTo:month,toGranularity:.month)
                    Button { model.jump(to:date) } label: {
                        Text(model.dateLabel(date,template:"d"))
                            .appFont(size:11,weight:today || selected ? .semibold : .regular)
                            .foregroundStyle(today ? Color.white : (inMonth ? Color.primary.opacity(0.8) : Color.secondary.opacity(0.45)))
                            .frame(maxWidth:.infinity).frame(height:AppTextSize.points(24))
                            .background {
                                if today { Circle().fill(Color.red).frame(width:AppTextSize.points(23),height:AppTextSize.points(23)) }
                                else if selected { RoundedRectangle(cornerRadius:6).fill(Color.primary.opacity(0.075)) }
                            }
                            .contentShape(Rectangle())
                    }.buttonStyle(.plain)
                        .accessibilityLabel(model.dateLabel(date,template:"EEEE MMMM d yyyy"))
                        .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
        }
        .background(MiniCalendarMonthScroll { browse($0) })
        .onChange(of:model.anchor) { _,date in month = CalendarViewDates.monthStart(date,calendar:model.calendar) }
        .onChange(of:model.primaryTimeZoneID) { _,_ in month = CalendarViewDates.monthStart(model.anchor,calendar:model.calendar) }
    }
}

private struct MiniCalendarMonthScroll: NSViewRepresentable {
    var browse: (Int) -> Void
    func makeNSView(context: Context) -> MiniCalendarScrollView { MiniCalendarScrollView() }
    func updateNSView(_ view: MiniCalendarScrollView, context: Context) { view.browse = browse }
    static func dismantleNSView(_ view: MiniCalendarScrollView, coordinator: ()) { view.detach() }
}
private final class MiniCalendarScrollView: NSView {
    var browse: ((Int) -> Void)?
    private var gesture = DayScrollGesture()
    private var monitor: Any?
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        detach()
        guard window != nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching:.scrollWheel) { [weak self] event in
            guard let self, event.window === self.window, !self.isHiddenOrHasHiddenAncestor,
                  self.visibleRect.contains(self.convert(event.locationInWindow,from:nil)) else { return event }
            let shifted = event.modifierFlags.contains(.shift) && event.scrollingDeltaX == 0
            let result = self.gesture.consume(x:shifted ? event.scrollingDeltaY : event.scrollingDeltaX,
                y:shifted ? 0 : event.scrollingDeltaY,time:event.timestamp,
                began:event.phase.contains(.began),momentum:!event.momentumPhase.isEmpty,
                precise:event.hasPreciseScrollingDeltas)
            if result.days != 0 { self.browse?(result.days) }
            return result.horizontal ? nil : event
        }
    }
    func detach() {
        if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
    }
    deinit { if let monitor { NSEvent.removeMonitor(monitor) } }
}
