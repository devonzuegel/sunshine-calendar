import SwiftUI
import AppKit

@main struct CalendarStudioApp: App {
    @ObservedObject private var textSize = AppTextSize.shared
    init() { AppTextSize.shared.startKeyboardHandling() }
    @StateObject private var model = CalendarModel()
    @AppStorage("sidebarVisible") private var sidebarVisible = true
    @AppStorage("eventBankCollapsed") private var bankCollapsed = false
    var body: some Scene {
        WindowGroup("") {
            CalendarRoot(model:model,sidebarVisible:$sidebarVisible)
                .appFont(size:13)
                .onAppear { model.startViewKeyboardHandling() }
                .frame(minWidth:1000,minHeight:650)
                .background(CalendarUndoWindowBridge(model:model).frame(width:0,height:0))
        }
        .defaultSize(width:1280,height:850)
        .windowToolbarStyle(.unifiedCompact)
        .commands {
            CalendarHistoryCommands(model:model)
            CommandGroup(before:.appTermination) {
                Button("Restart Sunshine Calendar") { AppRestart.restart(model:model) }
                    .keyboardShortcut("r",modifiers:[.command,.shift])
                Divider()
            }
            CommandGroup(replacing:.sidebar) {
                Button(sidebarVisible ? "Hide Calendar List (S)" : "Show Calendar List (S)") { sidebarVisible.toggle() }
                Button(bankCollapsed ? "Show Task Bank (B)" : "Hide Task Bank (B)") { bankCollapsed.toggle() }
            }
            CommandGroup(after:.toolbar) {
                Divider()
                Button("Larger Text") { textSize.adjust(1) }
                    .keyboardShortcut("+",modifiers:.command).disabled(textSize.scale >= AppTextSize.maximum)
                Button("Smaller Text") { textSize.adjust(-1) }
                    .keyboardShortcut("-",modifiers:.command).disabled(textSize.scale <= AppTextSize.minimum)
                Button("Actual Text Size") { textSize.reset() }.keyboardShortcut("0",modifiers:.command)
            }
            CommandGroup(replacing:.newItem) { Button("New Event") { model.newEvent() }.keyboardShortcut("n") }
            CommandMenu("Calendar") {
                Button("Next Calendar View") { model.setView(model.viewMode.cycled(by:1)) }
                    .keyboardShortcut(.tab,modifiers:.control).disabled(model.draft != nil)
                Button("Previous Calendar View") { model.setView(model.viewMode.cycled(by:-1)) }
                    .keyboardShortcut(.tab,modifiers:[.control,.shift]).disabled(model.draft != nil)
                Divider()
                Button(model.weather.enabled ? "Hide Weather Overlay (⇧W)" : "Show Weather Overlay (⇧W)") { model.weather.enabled.toggle() }
                Divider()
                Button("Today (T)") { model.today() }
                Button("Previous Period") { model.navigate(-1) }.keyboardShortcut(.leftArrow,modifiers:.command)
                Button("Next Period") { model.navigate(1) }.keyboardShortcut(.rightArrow,modifiers:.command)
                Button("Refresh") { model.reload() }.keyboardShortcut("r")
            }
        }
    }
}

struct CalendarDateHeadings: View {
    @ObservedObject var model: CalendarModel
    let width: CGFloat
    private var dayWidth: CGFloat { max(1,width/CGFloat(model.visibleDayCount)) }
    var body: some View {
        ZStack(alignment:.leading) {
            if let jump = model.dateJump {
                let offsets = jump.offsets(dayWidth:dayWidth,viewportWidth:width)
                strip(start:jump.from,offset:offsets.before)
                strip(start:jump.to,offset:offsets.after)
            } else { strip(start:model.weekStart,offset:model.horizontalOffset) }
        }.frame(width:width,height:AppTextSize.points(32),alignment:.leading).clipped()
            .transaction { $0.disablesAnimations = true }
    }
    private func strip(start: Date, offset: CGFloat) -> some View {
        HStack(spacing:0) {
            ForEach((-1..<(model.visibleDayCount+1)).map { model.calendar.date(byAdding:.day,value:$0,to:start)! },id:\.self) { date in
                let today = model.calendar.isDateInToday(date)
                HStack(spacing:3) {
                    Text(model.dateLabel(date,template:"EEE"))
                        .foregroundStyle(model.calendar.isDateInWeekend(date) ? .secondary : .primary)
                    Text(model.dateLabel(date,template:"d"))
                        .frame(width:today ? 22 : nil,height:22)
                        .background(today ? Color.red : Color.clear,in:Circle())
                        .foregroundStyle(today ? Color.white : Color.primary)
                }.appFont(size:12).frame(width:dayWidth)
            }
        }.fixedSize(horizontal:true,vertical:false).offset(x:-dayWidth+offset)
            .frame(width:width,alignment:.leading)
    }
}

struct CalendarRoot: View {
    @ObservedObject private var textSize = AppTextSize.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("eventBankCollapsed") private var bankCollapsed = false
    @AppStorage("collapsedCalendarAccountGroups") private var collapsedGroupNames = "[]"
    private var collapsedGroups: Set<String> {
        Set((try? JSONDecoder().decode([String].self,from:Data(collapsedGroupNames.utf8))) ?? [])
    }
    private func toggleGroupExpansion(_ account: String) {
        var groups = collapsedGroups
        if groups.contains(account) { groups.remove(account) } else { groups.insert(account) }
        guard let data = try? JSONEncoder().encode(groups.sorted()), let value = String(data:data,encoding:.utf8) else { return }
        withAnimation(reduceMotion ? nil : .easeInOut(duration:0.18)) { collapsedGroupNames = value }
    }
    @ObservedObject var model: CalendarModel
    @Binding var sidebarVisible: Bool
    @ObservedObject private var weather: WeatherOverlay
    @State private var sidebarOpenAmount: CGFloat
    init(model: CalendarModel, sidebarVisible: Binding<Bool>) {
        self.model = model; self._sidebarVisible = sidebarVisible; self.weather = model.weather
        self._sidebarOpenAmount = State(initialValue:sidebarVisible.wrappedValue ? 1 : 0)
    }
    private var weatherRequestKey: String {
        "\(model.primaryTimeZoneID)-\(weather.enabled)-\(weather.showHorizontalStrip)-\(weather.locationKey)"
    }
    var body: some View {
        HStack(spacing:0) {
            EventBankPanel(model:model,bank:model.bank).zIndex(1)
            VStack(spacing:0) {
                if model.viewMode.isTimeline {
                GeometryReader { geo in
                    HStack(spacing:0) {
                        HStack(spacing:0) {
                            ForEach(Array(model.clockZones.enumerated()),id:\.offset) { index,zone in
                                TimeRibbonHeader(model:model,zone:zone,index:index)
                            }
                        }.frame(width:model.timeGutterWidth,alignment:.leading)
                        CalendarDateHeadings(model:model,width:max(1,geo.size.width-model.timeGutterWidth))
                    }.frame(height:AppTextSize.points(32))
                        .transaction { if model.trackingHorizontalScroll { $0.disablesAnimations = true } }
                        .clipped()
                }.frame(height:AppTextSize.points(32))
                Rectangle().fill(Color.primary.opacity(0.075)).frame(height:0.5)
                WeekCanvas(model:model).id(model.viewMode)
                    .overlay(alignment:.topTrailing) {
                        WeatherAvailabilityNotice(weather:weather,start:model.weekStart,end:model.weekEnd,zoneID:model.primaryTimeZoneID)
                            .padding(8)
                    }
                WeatherWeekStrip(model:model)
                } else { CalendarOverview(model:model) }
            }
            HStack(spacing:0) {
            Rectangle().fill(Color.primary.opacity(0.07)).frame(width:0.5)
            VStack(alignment:.leading,spacing:20) {
                SidebarMiniCalendar(model:model)
                    .padding(.horizontal,-10)
                HStack {
                    Text("CALENDARS").appFont(size:10,weight:.semibold).foregroundStyle(.secondary)
                    Spacer()
                    Button { model.toggleAllCalendarsHidden() } label: {
                        Image(systemName:model.calendarsHidden ? "eye.slash" : "eye")
                            .appFont(size:12).foregroundStyle(.secondary).frame(width:24,height:20)
                    }.buttonStyle(.plain)
                        .appHelp(model.calendarsHidden ? "Restore calendars with your previous selections" : "Hide all calendars temporarily · Your checkbox selections are kept")
                        .accessibilityLabel(model.calendarsHidden ? "Restore selected calendars" : "Temporarily hide all calendars")
                }
                ScrollView {
                    VStack(alignment:.leading,spacing:14) {
                        ForEach(Array(Set(model.sources.map(\.account))).sorted(),id:\.self) { account in
                            VStack(alignment:.leading,spacing:8) {
                                let ids = model.calendarIDs(in:account)
                                let checked = ids.intersection(model.visible).count
                                HStack(spacing:6) {
                                    Button { toggleGroupExpansion(account) } label: {
                                        HStack(spacing:6) {
                                            Text(account.uppercased()).appFont(size:9,weight:.semibold).tracking(0.4).lineLimit(1)
                                            Spacer(minLength:0)
                                            Text("\(checked)/\(ids.count)").appFont(size:9).foregroundStyle(.tertiary)
                                        }.foregroundStyle(.secondary).frame(maxWidth:.infinity,minHeight:24).contentShape(Rectangle())
                                    }.buttonStyle(.plain)
                                        .appHelp((collapsedGroups.contains(account) ? "Expand " : "Collapse ") + account)
                                        .accessibilityLabel((collapsedGroups.contains(account) ? "Expand " : "Collapse ") + account)
                                    Button { model.toggleCalendarGroup(account) } label: {
                                        Image(systemName:checked == 0 ? "square" : (checked == ids.count ? "checkmark.square.fill" : "minus.square.fill"))
                                            .appFont(size:11).foregroundStyle(.secondary).frame(width:18,height:24)
                                    }.buttonStyle(.plain)
                                        .appHelp(checked == ids.count ? "Uncheck all calendars in " + account : "Check all calendars in " + account)
                                        .accessibilityLabel(account+" · \(checked) of \(ids.count) calendars checked")
                                }
                                if !collapsedGroups.contains(account) {
                                ForEach(model.sources.filter { $0.account == account }) { source in
                                    CalendarSourceRow(model:model,source:source)
                                }
                                }
                            }
                        }
                    }.frame(maxWidth:.infinity,alignment:.leading).padding(.horizontal,18)
                }.padding(.horizontal,-18).frame(maxHeight:.infinity)
                if !model.live {
                    Button { model.connect() } label: {
                        HStack { Image(systemName:"link"); Text(model.connecting ? "Connecting…" : "Connect My Calendars") }.frame(maxWidth:.infinity)
                    }.buttonStyle(.borderedProminent).disabled(model.connecting)
                    Text("Uses the calendar accounts already on this Mac. You’ll be asked for access.").appFont(size:10).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                }
            }.padding(.horizontal,18).padding(.top,18).padding(.bottom,6)
                .frame(width:AppTextSize.points(218)).background(.bar)
            }
            .frame(width:AppTextSize.points(218)+0.5)
            // Keep the content at full width, anchored to the reveal's left
            // edge. As the reveal expands leftward from the window edge, the
            // content travels with it instead of canceling its own transition.
            .frame(width:(AppTextSize.points(218)+0.5)*sidebarOpenAmount,alignment:.leading)
            .clipped()
            .allowsHitTesting(sidebarVisible)
            .accessibilityHidden(!sidebarVisible)
        }
        .clipped()
        .onChange(of:sidebarVisible) { _,visible in
            withAnimation(reduceMotion ? nil : .easeInOut(duration:0.25)) {
                sidebarOpenAmount = visible ? 1 : 0
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration:0.25),value:bankCollapsed)
        .background(Color(nsColor:.textBackgroundColor))
        .toolbar {
            ToolbarItem(placement:.navigation) {
                HStack(alignment:.firstTextBaseline,spacing:5) {
                    if model.viewMode != .year {
                        Text(model.dateLabel(model.anchor,template:"MMMM")).appFont(size:18,weight:.bold)
                    }
                    Text(model.dateLabel(model.anchor,template:"yyyy"))
                        .appFont(size:18,weight:model.viewMode == .year ? .semibold : .light)
                }.lineLimit(1).fixedSize(horizontal:true,vertical:false)
            }.withoutSharedToolbarBackground()
            if #available(macOS 26.0, *) {
                ToolbarSpacer(.flexible)
            } else {
                ToolbarItem(placement:.principal) { Spacer() }
            }
            ToolbarItemGroup(placement:.primaryAction) {
                HStack(spacing:10) {
                    ComparisonZoneMenu(model:model)
                    WeatherMenu(weather:model.weather,zoneID:model.primaryTimeZoneID,priorityZones:[model.primaryTimeZoneID]+model.comparisonTimeZones,refreshMac:{ model.daylight.refresh() })
                    DaylightMenu(daylight:model.daylight,displayTimeZone:model.primaryTimeZone)
                    CalendarViewMenu(model:model)
                    Button { model.newEvent() } label: { ToolbarControlLabel(symbol:"plus",title:"New") }
                        .onDrag { NewTaskDrag.provider() }
                        .appHelp("Click to create an event, or drag into the week or Event Bank")
                    HStack(spacing:3) {
                        Button { model.navigate(-1) } label: { ToolbarControlLabel(symbol:"chevron.left") }.appHelp("Previous " + model.viewMode.navigationUnit)
                        Button("Today") { model.today() }
                            .appHelp("Go to today (T)")
                            .appFont(size:12,weight:.medium).fixedSize(horizontal:true,vertical:false)
                            .frame(width:AppTextSize.points(46),height:AppTextSize.points(28))
                        Button { model.navigate(1) } label: { ToolbarControlLabel(symbol:"chevron.right") }.appHelp("Next " + model.viewMode.navigationUnit)
                    }
                    CalendarConnectionStatus(model:model)
                    Button { sidebarVisible.toggle() } label: {
                        ToolbarControlLabel(symbol:"sidebar.right")
                    }
                    .accessibilityLabel(sidebarVisible ? "Hide Sidebar" : "Show Sidebar")
                    .appHelp("\(sidebarVisible ? "Hide" : "Show") sidebar (S)")
                }.fixedSize(horizontal:true,vertical:false)
                    .buttonStyle(.plain).menuStyle(.borderlessButton).controlSize(.small).labelStyle(.titleAndIcon)
                    .padding(.horizontal,4)
            }.withoutSharedToolbarBackground()
        }
        .navigationTitle("")
        .toolbarBackground(.hidden,for:.windowToolbar)
        .onReceive(model.daylight.$coordinate) { weather.updateMacLocation($0) }
        .task(id:weatherRequestKey) {
            if weather.needsData && weather.selectedLocation == nil && weather.macCoordinate == nil { model.daylight.refresh() }
            weather.load(zoneID:model.primaryTimeZoneID)
        }
        .background(EventEditorPopover(model:model))
        .onReceive(NotificationCenter.default.publisher(for:NSApplication.didBecomeActiveNotification)) { _ in if model.live { model.reload() } }
        .alert("Sunshine Calendar",isPresented:Binding(get:{model.message != nil},set:{ if !$0 { model.message = nil } })) { Button("OK") { model.message = nil } } message: { Text(model.message ?? "") }
    }
}

private struct CalendarSourceRow: View {
    @ObservedObject var model: CalendarModel
    let source: CalendarSource
    var body: some View {
                                    Button { model.toggle(source.id) } label: {
                                        HStack(spacing:8) {
                                            Image(systemName:model.visible.contains(source.id) ? "checkmark.square.fill" : "square").foregroundStyle(Color(nsColor:source.color))
                                            Text(source.title).lineLimit(1).foregroundStyle(.primary)
                                            Spacer(minLength:0)
                                            if !source.writable {
                                                ReadOnlyLockIcon(scale:0.8)
                                                    .padding(4)
                                                    .appHelp(source.readOnlyTooltip)
                                                    .accessibilityLabel(source.readOnlyTooltip)
                                            }
                                        }.contentShape(Rectangle())
                                    }.buttonStyle(.plain)
    }
}

private struct TimeRibbonHeader: View {
    @ObservedObject var model: CalendarModel
    let zone: TimeZone
    let index: Int
    private var primary: Bool { index == model.clockZones.count-1 }
    var body: some View {
        Text(CalendarModel.zoneLabel(zone)).lineLimit(1)
            .appFont(size:9,weight:primary ? .semibold : .regular)
            .foregroundStyle(primary ? Color.primary : Color.secondary)
            .frame(width:CalendarModel.timeColumnWidth-4,alignment:.trailing).padding(.trailing,4)
            .timeZoneHelp(zone,primary:primary)
    }
}

private struct CalendarConnectionStatus: View {
    @ObservedObject var model: CalendarModel
    @State private var showingDetails = false
    private var label: String { model.connecting ? "Connecting calendars" : (model.live ? "Calendars connected" : "Calendars not connected") }
    private static func elapsed(since date: Date, now: Date) -> String {
        let seconds = max(0,Int(now.timeIntervalSince(date)))
        let value: Int
        let unit: String
        switch seconds {
        case ..<60: value = seconds; unit = "second"
        case ..<3600: value = seconds/60; unit = "minute"
        case ..<86400: value = seconds/3600; unit = "hour"
        default: value = seconds/86400; unit = "day"
        }
        return "\(value) \(unit)\(value == 1 ? "" : "s") ago"
    }

    var body: some View {
        Button { showingDetails.toggle() } label: {
            Group {
                if model.connecting { ProgressView().controlSize(.mini) }
                else { Image(systemName:model.live ? "checkmark.circle" : "exclamationmark.circle").appFont(size:12) }
            }.foregroundStyle(model.live ? Color.secondary : Color.orange)
                .frame(width:AppTextSize.points(20),height:AppTextSize.points(28))
        }.buttonStyle(.plain).accessibilityLabel(label+" · Show connection details")
            .appHelp(label+" · Click for details")
            .popover(isPresented:$showingDetails,arrowEdge:.bottom) {
                VStack(alignment:.leading,spacing:14) {
                    HStack(alignment:.top,spacing:8) {
                        Image(systemName:model.live ? "checkmark.circle" : "calendar")
                            .appFont(size:14).foregroundStyle(.secondary)
                        VStack(alignment:.leading,spacing:3) {
                            Text(label).appFont(size:12,weight:.semibold)
                            if model.live {
                                Text("\(model.sources.count) calendars available on this Mac")
                                    .appFont(size:10).foregroundStyle(.secondary)
                            }
                        }
                    }
                    if model.live {
                        HStack(alignment:.center,spacing:12) {
                            VStack(alignment:.leading,spacing:4) {
                                Text("Last successful refresh").appFont(size:10).foregroundStyle(.secondary)
                                if let date = model.lastCalendarRefresh {
                                    TimelineView(.periodic(from:.now,by:1)) { timeline in
                                        Text(Self.elapsed(since:date,now:timeline.date))
                                            .appFont(size:17,weight:.semibold).monospacedDigit()
                                    }
                                    Text(date.formatted(date:.abbreviated,time:.standard))
                                        .appFont(size:9).foregroundStyle(.tertiary)
                                } else { Text("Not yet refreshed").appFont(size:13,weight:.medium) }
                            }
                            Spacer(minLength:0)
                            Button { model.reload() } label: {
                                Label("Refresh",systemImage:"arrow.clockwise").appFont(size:10,weight:.medium)
                            }.buttonStyle(.bordered)
                        }
                        .padding(12).frame(maxWidth:.infinity,alignment:.leading)
                        .background(Color.primary.opacity(0.035),in:RoundedRectangle(cornerRadius:10))
                        if let summary = model.calendarRefreshSummary {
                            Text(summary).appFont(size:9).foregroundStyle(.secondary)
                                .fixedSize(horizontal:false,vertical:true)
                        }
                        Text("Refresh reads calendars from this Mac. Google and iCloud sync in macOS; their server sync times aren’t available here.")
                            .appFont(size:9).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                    } else {
                        Text(model.connecting ? "Waiting for calendar access…" : "You’re viewing sample events. Connect your calendars to view and edit your real events.")
                            .foregroundStyle(.secondary)
                        Button("Connect Calendars") { model.connect() }.disabled(model.connecting)
                    }
                }.appFont(size:11).padding(16).frame(width:280,alignment:.leading)
            }
    }
}

private extension ToolbarContent {
    @ToolbarContentBuilder func withoutSharedToolbarBackground() -> some ToolbarContent {
        if #available(macOS 26.0, *) { self.sharedBackgroundVisibility(.hidden) }
        else { self }
    }
}

struct QuietCalendarButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .appFont(size:12)
            .foregroundStyle(Color.primary.opacity(0.8))
            .padding(.horizontal,9).padding(.vertical,5)
            .background(Color.primary.opacity(configuration.isPressed ? 0.10 : 0.045),in:Capsule())
    }
}

struct EventEditor: View {
    @ObservedObject private var textSize = AppTextSize.shared
    @ObservedObject var model: CalendarModel
    @Binding var draft: EventDraft
    var onClose: () -> Void
    @FocusState private var titleFocused: Bool
    private var editorTimeZone: TimeZone { TimeZone(identifier:draft.timeZoneID) ?? .current }
    private var editorCalendar: Calendar { var calendar = Calendar.current; calendar.timeZone = editorTimeZone; return calendar }
    private var displayedEndDate: Binding<Date> {
        Binding(get:{ draft.displayedEndDate(calendar:editorCalendar) },
                set:{ draft.setDisplayedEndDate($0,calendar:editorCalendar) })
    }
    private var readOnly: Bool { draft.original?.writable == false }
    private var hairline: Color { Color.primary.opacity(0.09) }

    var body: some View {
        VStack(alignment:.leading,spacing:16) {
            if readOnly {
                Label("Read-only event · Details cannot be edited",systemImage:"lock")
                    .appFont(size:11,weight:.medium).foregroundStyle(.secondary)
                    .frame(maxWidth:.infinity,alignment:.leading).padding(10)
                    .background(Color.primary.opacity(0.045),in:RoundedRectangle(cornerRadius:8))
            }
            if let item = draft.original, item.invitationStatus != .none {
                HStack(spacing:8) {
                    Label(item.invitationStatus.label,systemImage:item.invitationStatus == .accepted ? "checkmark.circle" : "questionmark.circle")
                        .appFont(size:12,weight:.medium)
                    Spacer()
                    Button("Respond in Apple Calendar…") { model.respondInAppleCalendar(item) }.controlSize(.small)
                }.padding(10).background(Color.primary.opacity(0.035),in:RoundedRectangle(cornerRadius:8))
            }

            VStack(alignment:.leading,spacing:12) {
                HStack(alignment:.top,spacing:12) {
                    TextField("Event title",text:$draft.title,axis:.vertical)
                        .appFont(size:20,weight:.semibold).lineLimit(nil)
                        .fixedSize(horizontal:false,vertical:true).layoutPriority(1)
                        .focused($titleFocused)
                    CalendarColorPicker(sources:readOnly ? model.sources : model.sources.filter(\.writable),selection:$draft.calendarID,compact:true)
                        .frame(width:AppTextSize.points(66),height:AppTextSize.points(34)).appHelp("Choose calendar")
                }.disabled(readOnly)
                HStack(spacing:8) {
                    if let directions = LocationDirections.url(for:draft.location) {
                        Button { NSWorkspace.shared.open(directions) } label: { EventFieldIcon(name:"map-pin") }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Directions to "+draft.location+" in Google Maps")
                            .appHelp("Directions in Google Maps from your current location")
                    } else { EventFieldIcon(name:"map-pin") }
                    EventLocationField(location:$draft.location,coordinate:model.daylight.coordinate).disabled(readOnly)
                }
            }.textFieldStyle(.plain).zIndex(10)

            Divider().overlay(hairline)

            Grid(alignment:.leading,horizontalSpacing:14,verticalSpacing:10) {
                GridRow {
                    Text("All day").foregroundStyle(.secondary).frame(width:AppTextSize.points(66),alignment:.leading)
                    Toggle("All day",isOn:$draft.allDay).labelsHidden().toggleStyle(.switch).controlSize(.small)
                        .onChange(of:draft.allDay) { _,value in
                            if value { draft.start = editorCalendar.startOfDay(for:draft.start); draft.end = editorCalendar.date(byAdding:.day,value:1,to:draft.start)! }
                        }
                }
                GridRow {
                    Text("Starts").foregroundStyle(.secondary)
                    EventDateControl(date:$draft.start,allDay:draft.allDay,label:"Starts",timeZone:editorTimeZone)
                }
                GridRow {
                    Text("Ends").foregroundStyle(.secondary)
                    EventDateControl(date:displayedEndDate,allDay:draft.allDay,label:"Ends",timeZone:editorTimeZone)
                }
                GridRow {
                    Text("Time zone").foregroundStyle(.secondary)
                    EventTimeZoneButton(selection:$draft.timeZoneID).disabled(draft.allDay)
                }
                GridRow {
                    Text("Repeat").foregroundStyle(.secondary)
                    Picker("Repeat",selection:$draft.repeatSchedule) {
                        ForEach(EventRepeat.allCases.filter { $0 != .unchanged || draft.original?.recurring == true }) { schedule in
                            Text(schedule.label).tag(schedule)
                        }
                    }.labelsHidden().frame(width:AppTextSize.points(210),alignment:.leading).controlSize(.regular)
                }
            }.appFont(size:13).frame(maxWidth:.infinity,alignment:.leading).disabled(readOnly)

            VStack(spacing:0) {
                HStack(alignment:.top,spacing:8) {
                    EventFieldIcon(name:"link-2")
                    TextField("Add a link",text:$draft.url)
                }.padding(10)
                Divider().padding(.leading,34)
                HStack(alignment:.top,spacing:8) {
                    EventFieldIcon(name:"sticky-note")
                    RichNotesEditor(notes:$draft.notes)
                }.padding(10)
            }.appFont(size:13).textFieldStyle(.plain)
                .background(Color.primary.opacity(0.025),in:RoundedRectangle(cornerRadius:9))
                .overlay(RoundedRectangle(cornerRadius:9).strokeBorder(hairline,lineWidth:0.5))
                .disabled(readOnly)

            if draft.original != nil {
                EventAttendeeSection(attendees:model.eventAttendees(for:draft.original?.id))
            }

            if !readOnly && draft.original?.recurring == true {
                Text(draft.repeatSchedule == .unchanged ? "Changes apply to this occurrence only." : "Repeat changes apply to this and future events.")
                    .appFont(size:10).foregroundStyle(.secondary)
            }
            if draft.allDay { Text("Includes both the start and end dates.").appFont(size:10).foregroundStyle(.secondary) }
            HStack(spacing:10) {
                if !model.live { Text("Preview only").appFont(size:10).foregroundStyle(.secondary) }
                Spacer()
                Button(readOnly ? "Done" : "Cancel") { onClose() }.keyboardShortcut(.cancelAction)
                if !readOnly {
                Button("Save") { if model.save(draft) { onClose() } }
                    .keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
                    .tint(model.sources.first(where:{ $0.id == draft.calendarID }).map { Color(nsColor:$0.color) })
                    .disabled(draft.original?.writable == false || draft.title.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || draft.end <= draft.start)
                }
            }.controlSize(.regular)
        }.padding(20).appFont(size:13).frame(width:AppTextSize.points(400)).fixedSize(horizontal:false,vertical:true)
            .background(Color(nsColor:.windowBackgroundColor))
            .onAppear { titleFocused = !readOnly }
            .onExitCommand { onClose() }
    }
}

private enum AttendeeStyle {
    static func color(_ status: InvitationStatus, organizer: Bool = false) -> Color {
        if organizer { return .blue }
        switch status {
        case .accepted: return .green
        case .maybe: return .orange
        case .declined: return .red
        default: return .secondary
        }
    }
    static func label(_ status: InvitationStatus) -> String {
        switch status {
        case .accepted: return "Going"
        case .unanswered: return "No reply"
        default: return status.label.isEmpty ? "Unknown" : status.label
        }
    }
    static func rank(_ person: EventAttendee) -> Int {
        if person.isOrganizer { return 0 }
        switch person.response {
        case .accepted: return 1
        case .maybe: return 2
        case .unanswered, .none, .delegated: return 3
        case .declined: return 4
        }
    }
}
struct EventAttendeeSection: View {
    let attendees: [EventAttendee]
    @State private var filter: InvitationStatus?
    private var visible: [EventAttendee] {
        attendees.filter { person in filter == nil || (!person.isOrganizer && person.response == filter) }
            .sorted {
                let a = AttendeeStyle.rank($0), b = AttendeeStyle.rank($1)
                return a == b ? $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending : a < b
            }
    }
    var body: some View {
        VStack(alignment:.leading,spacing:8) {
            HStack {
                Label("Attendees · \(attendees.count)",systemImage:"person.2")
                    .appFont(size:11,weight:.semibold).foregroundStyle(.secondary)
                Spacer()
                if filter != nil { Button("Show all") { filter = nil }.buttonStyle(.plain).appFont(size:10).foregroundStyle(Color.accentColor) }
            }
            if attendees.isEmpty {
                Text("No attendees listed").appFont(size:12).foregroundStyle(.secondary)
            } else {
                HStack(spacing:5) {
                    ForEach([InvitationStatus.accepted,.maybe,.unanswered,.declined],id:\.rawValue) { status in
                        let count = attendees.filter { !$0.isOrganizer && $0.response == status }.count
                        if count > 0 {
                            Button { filter = filter == status ? nil : status } label: {
                                Text("\(count) " + AttendeeStyle.label(status)).appFont(size:9,weight:.medium)
                                    .padding(.horizontal,6).padding(.vertical,4)
                                    .foregroundStyle(AttendeeStyle.color(status))
                                    .background(AttendeeStyle.color(status).opacity(filter == status ? 0.2 : 0.09),in:Capsule())
                            }.buttonStyle(.plain).appHelp("Filter to " + AttendeeStyle.label(status).lowercased())
                        }
                    }
                }
                ScrollView {
                    LazyVStack(spacing:0) {
                        ForEach(visible) { person in
                            EventAttendeeRow(person:person)
                            if person.id != visible.last?.id { Divider().opacity(0.45) }
                        }
                    }.padding(.horizontal,12)
                }.padding(.horizontal,-12).scrollIndicators(.visible)
                    .frame(height:CGFloat(min(max(1,visible.count),5))*AppTextSize.points(44))
                if visible.count > 5 { Text("Scroll to see all \(visible.count) people").appFont(size:9).foregroundStyle(.tertiary) }
            }
        }.padding(12).frame(maxWidth:.infinity,alignment:.leading)
            .background(Color.primary.opacity(0.025),in:RoundedRectangle(cornerRadius:9))
            .overlay(RoundedRectangle(cornerRadius:9).strokeBorder(Color.primary.opacity(0.08),lineWidth:0.5))
    }
}

private struct EventAttendeeRow: View {
    let person: EventAttendee
    private var displayName: String { person.name + (person.isCurrentUser ? " (you)" : "") }
    private var tooltip: String { person.name + " · " + person.responseLabel + (person.email.map { " · " + $0 } ?? "") }
    private var color: Color { AttendeeStyle.color(person.response,organizer:person.isOrganizer) }
    var body: some View {
        HStack(alignment:.center,spacing:8) {
            VStack(alignment:.leading,spacing:2) {
                Text(displayName).appFont(size:12,weight:person.isCurrentUser ? .semibold : .medium).lineLimit(1)
                if let email = person.email, email.localizedCaseInsensitiveCompare(person.name) != .orderedSame {
                    Text(email).appFont(size:10).foregroundStyle(.secondary).lineLimit(1).textSelection(.enabled)
                }
            }.frame(maxWidth:.infinity,alignment:.leading)
            Label(person.isOrganizer ? "Organizer" : AttendeeStyle.label(person.response),systemImage:person.responseIcon)
                .appFont(size:10,weight:.medium).foregroundStyle(color)
                .lineLimit(1).fixedSize(horizontal:true,vertical:false)
                .padding(.horizontal,7).padding(.vertical,4)
                .background(color.opacity(0.10),in:Capsule())
                .layoutPriority(1)
        }.frame(minHeight:AppTextSize.points(43)).appHelp(tooltip)
    }
}

struct EventTimeZoneButton: View {
    @ObservedObject private var textSize = AppTextSize.shared
    @Binding var selection: String
    @State private var showing = false
    var body: some View {
        Button { showing = true } label: {
            HStack {
                Text(selection.isEmpty ? "Floating (local time)" : TimeZoneCatalog.name(selection)).lineLimit(1)
                Image(systemName:"chevron.down").appFont(size:9)
            }
        }.buttonStyle(.plain).popover(isPresented:$showing) {
            TimeZoneChooser(current:selection,allowsFloating:true) { selection = $0 }
        }
    }
}

struct EventDateControl: View {
    @ObservedObject private var textSize = AppTextSize.shared
    @Binding var date: Date
    var allDay: Bool
    var label: String
    var timeZone: TimeZone
    private var formatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier:"en_US_POSIX")
        formatter.calendar = Calendar(identifier:.gregorian)
        formatter.dateFormat = "MMM d, yyyy"
        formatter.isLenient = false
        formatter.timeZone = timeZone
        return formatter
    }
    private var dateOnly: Binding<Date> {
        Binding(get:{ date },set:{ newDate in
            var calendar = Calendar.current; calendar.timeZone = timeZone
            let time = calendar.dateComponents([.hour,.minute,.second],from:date)
            date = calendar.date(bySettingHour:time.hour ?? 0,minute:time.minute ?? 0,second:time.second ?? 0,of:newDate) ?? newDate
        })
    }
    var body: some View {
        HStack(spacing:8) {
            TextField("Nov 15, 2026",value:dateOnly,formatter:formatter)
                .textFieldStyle(.roundedBorder).frame(width:AppTextSize.points(122))
                .accessibilityLabel(label+" date").appHelp("Date: Nov 15, 2026")
            if !allDay {
                DatePicker(label+" time",selection:$date,displayedComponents:.hourAndMinute)
                    .labelsHidden().datePickerStyle(.field).environment(\.timeZone,timeZone)
            }
        }
    }
}

// Native menu images retain their exact calendar colors in light and dark mode.
struct EventEditorPopover: NSViewRepresentable {
    @ObservedObject var model: CalendarModel
    func makeCoordinator() -> Coordinator { Coordinator(model:model) }
    func makeNSView(context: Context) -> NSView { NSView() }
    func updateNSView(_ view: NSView, context: Context) {
        // Wait until the background anchor has joined its window and laid out.
        DispatchQueue.main.async { context.coordinator.present(in:view) }
    }
    static func dismantleNSView(_ view: NSView, coordinator: Coordinator) { coordinator.popover?.close() }
    @MainActor final class Coordinator: NSObject, NSPopoverDelegate {
        let model: CalendarModel
        var popover: NSPopover?
        var presentedID: UUID?
        private var initialDraft: EventDraft?
        private var savingOnDismiss = false
        private var escapeMonitor: Any?
        deinit { if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor) } }
        init(model: CalendarModel) { self.model = model }
        func present(in view: NSView) {
            guard let draft = model.draft else {
                popover?.close(); popover = nil; presentedID = nil; return
            }
            guard presentedID != draft.id, view.window != nil else { return }
            if popover != nil { return }
            let panel = NSPopover()
            panel.behavior = .semitransient
            panel.animates = true
            panel.delegate = self
            initialDraft = draft
            let editingDraft = Binding<EventDraft>(get:{ [weak self] in self?.model.draft ?? draft },set:{ [weak self] value in
                if self?.model.draft != nil { self?.model.draft = value }
            })
            let hosting = NSHostingController(rootView:EventEditor(model:model,draft:editingDraft,onClose:{ [weak self] in
                self?.model.draft = nil
                self?.popover?.close()
            }))
            hosting.sizingOptions = [.preferredContentSize]
            panel.contentViewController = hosting
            var anchor = model.editorAnchorInWindow.map { view.convert($0,from:nil) }
                ?? NSRect(x:view.bounds.midX,y:view.bounds.midY,width:1,height:1)
            anchor = anchor.intersection(view.bounds)
            if anchor.isNull || anchor.isEmpty { anchor = NSRect(x:view.bounds.midX,y:view.bounds.midY,width:1,height:1) }
            popover = panel; presentedID = draft.id
            panel.show(relativeTo:anchor,of:view,preferredEdge:.maxX)
            // A native popover can leave focus in the calendar or its text-field
            // editor, so handle Escape for these two windows while it is open.
            escapeMonitor = NSEvent.addLocalMonitorForEvents(matching:.keyDown) { [weak self, weak view, weak panel] event in
                if LocationAutocomplete.handle(event) { return nil }
                guard let self, let panel, panel.isShown, event.keyCode == 53,
                      event.modifierFlags.intersection([.command,.control,.option]).isEmpty,
                      event.window != nil,
                      event.window === view?.window || event.window === panel.contentViewController?.view.window,
                      NSApp.modalWindow == nil else { return event }
                if let editor = event.window?.firstResponder as? NSTextView, editor.hasMarkedText() { return event }
                self.model.draft = nil
                panel.close()
                return nil
            }
        }
        func popoverShouldClose(_ popover: NSPopover) -> Bool {
            guard !savingOnDismiss else { return false }
            guard model.draft != nil else { return true }
            // Commit an active date/text field before reading its bound value.
            guard popover.contentViewController?.view.window?.makeFirstResponder(nil) != false else { return false }
            guard let edited = model.draft else { return true }
            if edited.original?.writable == false || (edited.original != nil && initialDraft.map { edited.hasSameContent(as:$0) } == true) {
                model.draft = nil; return true
            }
            if edited.original == nil && edited.title.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty {
                model.draft = nil; return true
            }
            savingOnDismiss = true
            defer { savingOnDismiss = false }
            guard model.save(edited) else { return false }
            model.draft = nil
            return true
        }
        func popoverDidClose(_ notification: Notification) {
            if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor); self.escapeMonitor = nil }
            if model.draft?.id == presentedID { model.draft = nil }
            popover = nil; presentedID = nil; initialDraft = nil
        }
    }
}

private struct TimeZoneCardFrames: PreferenceKey {
    static var defaultValue: [Int:CGRect] = [:]
    static func reduce(value: inout [Int:CGRect], nextValue: () -> [Int:CGRect]) { value.merge(nextValue(),uniquingKeysWith:{ _,new in new }) }
}

struct ComparisonZoneMenu: View {
    @ObservedObject private var textSize = AppTextSize.shared
    @ObservedObject var model: CalendarModel
    @State private var showing = false
    @State private var browsingSlot: Int?
    @State private var dropSlot: Int?
    @State private var slotFrames: [Int:CGRect] = [:]
    @State private var dragFrames: [Int:CGRect] = [:]
    @State private var draggingZone: String?
    @State private var dragOffset: CGFloat = 0
    private let favorites = ["America/New_York","America/Los_Angeles","America/Argentina/Buenos_Aires","America/Denver","America/Chicago"]
    private func name(_ id: String) -> String {
        switch id {
        case "America/New_York": return "Miami (ET)"
        case "America/Los_Angeles": return "San Francisco (PT)"
        case "America/Argentina/Buenos_Aires": return "Buenos Aires (AT)"
        case "America/Denver": return "Mountain Time (MT)"
        case "America/Chicago": return "Central Time (CT)"
        default: return id.split(separator:"/").last.map(String.init)?.replacingOccurrences(of:"_",with:" ") ?? id
        }
    }
    private func cardDrag(_ selection: String?) -> some Gesture {
        DragGesture(minimumDistance:4,coordinateSpace:.named("timezoneCards"))
            .onChanged { value in
                guard let selection else { return }
                if draggingZone == nil { draggingZone = selection; dragFrames = slotFrames }
                dragOffset = value.translation.height
                dropSlot = dragFrames.keys.sorted().first { slot in
                    slot <= model.comparisonTimeZones.count && dragFrames[slot]!.contains(value.location)
                }
            }
            .onEnded { _ in
                withAnimation(.easeInOut(duration:0.18)) {
                    if let identifier = draggingZone, let target = dropSlot { _ = model.moveTimeZone(identifier,toSlot:target) }
                    draggingZone = nil; dragOffset = 0; dropSlot = nil; dragFrames = [:]
                }
            }
    }
    private func slot(_ title: String, selection: String?, primary: Bool, index: Int = 0) -> some View {
        let slotID = primary ? 0 : index+1
        return HStack(spacing:10) {
            HStack(spacing:8) {
                VStack(alignment:.leading,spacing:6) {
                    Text(title).appFont(size:10).foregroundStyle(.secondary)
                    HStack(spacing:5) {
                        if selection == nil { Image(systemName:"plus.circle").foregroundStyle(.secondary) }
                        Text(selection.map(name) ?? "Add a timezone")
                            .appFont(size:14,weight:selection == nil ? .regular : .medium)
                            .foregroundStyle(selection == nil ? Color.secondary : Color.primary)
                    }
                }.frame(maxWidth:.infinity,alignment:.leading)
                if selection != nil {
                    Image(systemName:"line.3.horizontal").appFont(size:10).foregroundStyle(.tertiary)
                }
            }.contentShape(Rectangle()).gesture(cardDrag(selection))
                .appHelp(selection == nil ? "Choose a timezone using the arrow" : "Drag to swap timezone positions")
            Menu {
                if !primary { Button("None") { model.setComparisonZone(nil,at:index) }; Divider() }
                ForEach(favorites,id:\.self) { id in choice(id,primary:primary,index:index,selected:selection) }
                Button("All Time Zones… · Map / List") { browsingSlot = primary ? -1 : index }
            } label: {
                Image(systemName:"chevron.down").appFont(size:10,weight:.medium).frame(width:20,height:32)
            }.menuStyle(.borderlessButton).menuIndicator(.hidden)
                .accessibilityLabel("Choose " + title.lowercased() + " timezone")
        }.frame(maxWidth:.infinity,minHeight:45,alignment:.leading)
            .padding(12)
            .background(Color.primary.opacity(selection == nil ? 0.018 : 0.045),in:RoundedRectangle(cornerRadius:9))
            .overlay {
                if dropSlot == slotID && draggingZone != nil && draggingZone != selection {
                    RoundedRectangle(cornerRadius:9).strokeBorder(Color.accentColor.opacity(0.65),lineWidth:1.5).allowsHitTesting(false)
                } else if selection == nil {
                    RoundedRectangle(cornerRadius:9).strokeBorder(Color.secondary.opacity(0.3),style:StrokeStyle(lineWidth:1,dash:[4,3])).allowsHitTesting(false)
                }
            }
            .background(GeometryReader { geometry in
                Color.clear.preference(key:TimeZoneCardFrames.self,value:[slotID:geometry.frame(in:.named("timezoneCards"))])
            })
            .offset(y:draggingZone != nil && draggingZone == selection ? dragOffset : 0)
            .zIndex(draggingZone != nil && draggingZone == selection ? 1 : 0)
    }
    private func choice(_ id: String, primary: Bool, index: Int, selected: String?) -> some View {
        Button {
            if primary { model.setPrimaryTimeZone(id) }
            else { model.setComparisonZone(id,at:index) }
        } label: {
            HStack { Text(name(id)); if selected == id { Image(systemName:"checkmark") } }
        }.disabled(!primary && id == model.primaryTimeZoneID)
    }
    var body: some View {
        Button { showing.toggle() } label: { ToolbarControlLabel(symbol:"globe",title:"Zones") }
            .appHelp("Choose the primary calendar timezone and two comparisons")
            .popover(isPresented:$showing,arrowEdge:.bottom) {
                VStack(alignment:.leading,spacing:10) {
                    Text("Time Zones").appFont(size:15,weight:.semibold)
                    slot("Primary · calendar view",selection:model.primaryTimeZoneID,primary:true)
                    ForEach(0..<2,id:\.self) { index in
                        slot("Comparison \(index+1)",selection:index < model.comparisonTimeZones.count ? model.comparisonTimeZones[index] : nil,primary:false,index:index)
                    }
                    Text("Drag cards to swap their roles. The primary zone controls the calendar’s times.")
                        .appFont(size:10).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                }.padding(14).frame(width:AppTextSize.points(310))
                    .coordinateSpace(name:"timezoneCards")
                    .onPreferenceChange(TimeZoneCardFrames.self) { slotFrames = $0 }
                    .popover(isPresented:Binding(get:{ browsingSlot != nil },set:{ if !$0 { browsingSlot = nil } })) {
                        if let target = browsingSlot {
                            TimeZoneChooser(current:target == -1 ? model.primaryTimeZoneID : (target < model.comparisonTimeZones.count ? model.comparisonTimeZones[target] : nil),excluded:target == -1 ? nil : model.primaryTimeZoneID) { id in
                                if target == -1 { model.setPrimaryTimeZone(id) }
                                else { model.setComparisonZone(id,at:target) }
                            }
                        }
                    }
            }
    }
}

// Preserve SwiftUI's existing window delegate while providing a native undo manager.
struct CalendarUndoWindowBridge: NSViewRepresentable {
    let model: CalendarModel
    func makeNSView(context: Context) -> CalendarUndoAttachment { CalendarUndoAttachment(model:model) }
    func updateNSView(_ view: CalendarUndoAttachment, context: Context) { view.attach() }
    static func dismantleNSView(_ view: CalendarUndoAttachment, coordinator: ()) { view.detach() }
}
final class CalendarUndoAttachment: NSView {
    let model: CalendarModel
    private var delegateProxy: CalendarUndoWindowDelegate?
    private weak var attachedWindow: NSWindow?
    init(model: CalendarModel) { self.model = model; super.init(frame:.zero) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); attach() }
    func attach() {
        guard let window else { detach(); return }
        window.title = ""
        window.titleVisibility = .hidden
        window.toolbarStyle = .unifiedCompact
        window.titlebarSeparatorStyle = .none
        // SwiftUI installs toolbar appearance after the attachment's update.
        // Reapply after that pass so its default separator cannot return.
        DispatchQueue.main.async { [weak window] in
            window?.title = ""; window?.titleVisibility = .hidden
            window?.titlebarSeparatorStyle = .none
        }
        if attachedWindow === window, window.delegate === delegateProxy { return }
        detach()
        let proxy = CalendarUndoWindowDelegate(previous:window.delegate,model:model)
        delegateProxy = proxy; attachedWindow = window; window.delegate = proxy
    }
    func detach() {
        if let attachedWindow, attachedWindow.delegate === delegateProxy { attachedWindow.delegate = delegateProxy?.previous }
        attachedWindow = nil; delegateProxy = nil
    }
}

@MainActor private enum EventFieldImages {
    private static let cache: NSCache<NSString,NSImage> = {
        let cache = NSCache<NSString,NSImage>(); cache.countLimit = 32; return cache
    }()
    static func image(_ name: String) -> NSImage? {
        if let image = cache.object(forKey:name as NSString) { return image }
        guard let url = Bundle.main.url(forResource:name,withExtension:"pdf",subdirectory:"FieldIcons"), let image = NSImage(contentsOf:url) else { return nil }
        cache.setObject(image,forKey:name as NSString)
        return image
    }
}

struct EventFieldIcon: View {
    @ObservedObject private var textSize = AppTextSize.shared
    let name: String
    var body: some View {
        Group {
            if let image = EventFieldImages.image(name) {
                Image(nsImage:image).renderingMode(.template).resizable().scaledToFit()
            }
        }
        .frame(width:18,height:18)
        .foregroundStyle(.secondary)
        .accessibilityHidden(true)
    }
}
