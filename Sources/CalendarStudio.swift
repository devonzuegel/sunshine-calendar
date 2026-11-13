import SwiftUI
import AppKit

@main struct CalendarStudioApp: App {
    @StateObject private var model = CalendarModel()
    @AppStorage("sidebarVisible") private var sidebarVisible = true
    var body: some Scene {
        WindowGroup {
            CalendarRoot(model:model,sidebarVisible:$sidebarVisible)
                .frame(minWidth:1000,minHeight:650)
        }
        .defaultSize(width:1280,height:850)
        .commands {
            CommandGroup(before:.appTermination) {
                Button("Restart Sunshine Calendar") { AppRestart.restart(model:model) }
                    .keyboardShortcut("r",modifiers:[.command,.shift])
                Divider()
            }
            CommandGroup(replacing:.sidebar) {
                Button(sidebarVisible ? "Hide Sidebar" : "Show Sidebar") { sidebarVisible.toggle() }
                    .keyboardShortcut("s",modifiers:[.command,.option])
            }
            CommandGroup(replacing:.undoRedo) {
                Button("Undo Move") { model.undo() }.keyboardShortcut("z").disabled(model.undoChanges.isEmpty)
                Button("Redo Move") { model.redo() }.keyboardShortcut("z",modifiers:[.command,.shift]).disabled(model.redoChanges.isEmpty)
            }
            CommandGroup(replacing:.newItem) { Button("New Event") { model.newEvent() }.keyboardShortcut("n") }
            CommandMenu("Calendar") {
                Button("Today") { model.today() }.keyboardShortcut("t")
                Button("Previous Week") { model.navigate(-1) }.keyboardShortcut(.leftArrow,modifiers:.command)
                Button("Next Week") { model.navigate(1) }.keyboardShortcut(.rightArrow,modifiers:.command)
                Button("Refresh") { model.reload() }.keyboardShortcut("r")
            }
        }
    }
}

struct CalendarRoot: View {
    @ObservedObject var model: CalendarModel
    @Binding var sidebarVisible: Bool
    var body: some View {
        HStack(spacing:0) {
            if sidebarVisible {
            VStack(alignment:.leading,spacing:20) {
                HStack { Image(systemName:"calendar").font(.title2).foregroundStyle(.red); Text("Sunshine Calendar").font(.headline) }.padding(.top,14)
                DatePicker("Jump to date",selection:$model.anchor,displayedComponents:.date)
                    .datePickerStyle(.graphical).labelsHidden().onChange(of:model.anchor) { _,date in
                        if model.weekStart != Calendar.current.startOfDay(for:date) { model.jump(to:date) }
                    }
                Text("CALENDARS").font(.system(size:10,weight:.semibold)).foregroundStyle(.secondary)
                ScrollView {
                    VStack(alignment:.leading,spacing:14) {
                        ForEach(Array(Set(model.sources.map(\.account))).sorted(),id:\.self) { account in
                            VStack(alignment:.leading,spacing:8) {
                                Text(account).font(.caption).foregroundStyle(.secondary)
                                ForEach(model.sources.filter { $0.account == account }) { source in
                                    Button { model.toggle(source.id) } label: {
                                        HStack(spacing:8) {
                                            Image(systemName:model.visible.contains(source.id) ? "checkmark.square.fill" : "square").foregroundStyle(Color(nsColor:source.color))
                                            Text(source.title).lineLimit(1).foregroundStyle(.primary)
                                            Spacer(minLength:0)
                                            if !source.writable { Image(systemName:"lock.fill").font(.system(size:9)).foregroundStyle(.secondary) }
                                        }.contentShape(Rectangle())
                                    }.buttonStyle(.plain)
                                }
                            }
                        }
                    }.frame(maxWidth:.infinity,alignment:.leading)
                }
                Spacer(minLength:0)
                VStack(alignment:.leading,spacing:7) {
                    Text("MOVE TOGETHER").font(.system(size:10,weight:.semibold)).foregroundStyle(.secondary)
                    Text("⌘-click events to select a group. Drag any selected event to move them together.").font(.system(size:12)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                    Text("Snaps to 15 minutes · ⌘Z to undo").font(.system(size:10)).foregroundStyle(.tertiary)
                }
                if !model.live {
                    Button { model.connect() } label: {
                        HStack { Image(systemName:"link"); Text(model.connecting ? "Connecting…" : "Connect My Calendars") }.frame(maxWidth:.infinity)
                    }.buttonStyle(.borderedProminent).disabled(model.connecting)
                    Text("Uses the calendar accounts already on this Mac. You’ll be asked for access.").font(.system(size:10)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                } else {
                    Label("Your calendars are connected",systemImage:"checkmark.circle.fill").font(.system(size:11)).foregroundStyle(.secondary)
                }
            }.padding(18).frame(width:218).background(.bar)
            Rectangle().fill(Color.primary.opacity(0.07)).frame(width:0.5)
            }
            VStack(spacing:0) {
                HStack(spacing:12) {
                    Button { sidebarVisible.toggle() } label: {
                        Image(systemName:"sidebar.left")
                    }
                    .accessibilityLabel(sidebarVisible ? "Hide Sidebar" : "Show Sidebar")
                    .help("\(sidebarVisible ? "Hide" : "Show") sidebar (⌥⌘S)")
                    HStack(alignment:.firstTextBaseline,spacing:5) {
                        Text(model.anchor.formatted(.dateTime.month(.wide))).font(.system(size:24,weight:.semibold))
                        Text(model.anchor.formatted(.dateTime.year())).font(.system(size:24,weight:.light))
                    }
                    Spacer()
                    DaylightMenu(daylight:model.daylight)
                    Text("Week").font(.system(size:11,weight:.medium))
                        .padding(.horizontal,13).padding(.vertical,5)
                        .background(Color.primary.opacity(0.055),in:Capsule())
                    Button { model.newEvent() } label: { Label("New Task",systemImage:"plus") }
                        .onDrag { NewTaskDrag.provider() }
                        .help("Click to create an event, or drag into the week or Event Bank")
                    HStack(spacing:4) {
                        Button { model.navigate(-1) } label: { Image(systemName:"chevron.left") }.help("Previous week")
                        Button("Today") { model.today() }
                        Button { model.navigate(1) } label: { Image(systemName:"chevron.right") }.help("Next week")
                    }
                }.buttonStyle(QuietCalendarButtonStyle()).padding(.horizontal,16).padding(.top,12).padding(.bottom,13)
                GeometryReader { geo in
                    HStack(spacing:0) {
                        Text("W\(Calendar.current.component(.weekOfYear,from:model.anchor))")
                            .font(.system(size:9)).foregroundStyle(.tertiary).frame(width:58)
                        ForEach((0..<7).map { Calendar.current.date(byAdding:.day,value:$0,to:model.weekStart)! },id:\.self) { date in
                            let today = Calendar.current.isDateInToday(date)
                            HStack(spacing:3) {
                                Text(date.formatted(.dateTime.weekday(.abbreviated)))
                                    .foregroundStyle(Calendar.current.isDateInWeekend(date) ? .secondary : .primary)
                                Text(date.formatted(.dateTime.day()))
                                    .frame(width:today ? 22 : nil,height:22)
                                    .background(today ? Color.red : Color.clear,in:Circle())
                                    .foregroundStyle(today ? Color.white : Color.primary)
                            }.font(.system(size:12)).frame(width:max(1,(geo.size.width-58)/7)).transition(.opacity)
                        }
                    }.frame(height:32)
                        .animation(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? nil : .easeInOut(duration:0.26),value:model.weekStart)
                        .clipped()
                }.frame(height:32)
                Rectangle().fill(Color.primary.opacity(0.075)).frame(height:0.5)
                WeekCanvas(model:model)
                Rectangle().fill(Color.primary.opacity(0.06)).frame(height:0.5)
                HStack {
                    Text(model.status).lineLimit(1)
                    Spacer()
                    if !model.selected.isEmpty { Text("\(model.selected.count) selected").foregroundStyle(.primary) }
                    Button { model.undo() } label: { Image(systemName:"arrow.uturn.backward") }.disabled(model.undoChanges.isEmpty).help("Undo move (⌘Z)")
                }.font(.system(size:10)).foregroundStyle(.tertiary).buttonStyle(.borderless).padding(.horizontal,12).frame(height:24)
            }
            EventBankPanel(model:model,bank:model.bank)
        }
        .background(Color(nsColor:.textBackgroundColor))
        .sheet(item:$model.draft) { draft in EventEditor(model:model,draft:draft) }
        .alert("Sunshine Calendar",isPresented:Binding(get:{model.message != nil},set:{ if !$0 { model.message = nil } })) { Button("OK") { model.message = nil } } message: { Text(model.message ?? "") }
    }
}

struct QuietCalendarButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size:12))
            .foregroundStyle(Color.primary.opacity(0.8))
            .padding(.horizontal,9).padding(.vertical,5)
            .background(Color.primary.opacity(configuration.isPressed ? 0.10 : 0.045),in:Capsule())
    }
}

struct EventEditor: View {
    @ObservedObject var model: CalendarModel
    @State var draft: EventDraft
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment:.leading,spacing:18) {
            Text(draft.original == nil ? "New Event" : "Edit Event").font(.title2.bold())
            Form {
                TextField("Title",text:$draft.title)
                Picker("Calendar",selection:$draft.calendarID) {
                    ForEach(model.sources.filter(\.writable)) { source in Text("\(source.title) · \(source.account)").tag(source.id) }
                }
                Toggle("All-day",isOn:$draft.allDay).onChange(of:draft.allDay) { _,value in
                    if value { draft.start = Calendar.current.startOfDay(for:draft.start); draft.end = Calendar.current.date(byAdding:.day,value:1,to:draft.start)! }
                }
                DatePicker("Starts",selection:$draft.start,displayedComponents:draft.allDay ? [.date] : [.date,.hourAndMinute])
                DatePicker(draft.allDay ? "Ends (exclusive)" : "Ends",selection:$draft.end,displayedComponents:draft.allDay ? [.date] : [.date,.hourAndMinute])
                TextField("Location",text:$draft.location)
                TextField("Notes",text:$draft.notes,axis:.vertical).lineLimit(3...6)
            }.formStyle(.grouped)
            if draft.original?.recurring == true { Text("Changes apply to this occurrence only.").font(.caption).foregroundStyle(.secondary) }
            if draft.allDay { Text("For a one-day event, set the end date to the following day.").font(.caption).foregroundStyle(.secondary) }
            HStack {
                if !model.live { Text("Sample event · preview only").font(.caption).foregroundStyle(.secondary) }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") { if model.save(draft) { dismiss() } }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
                    .disabled(draft.title.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || draft.end <= draft.start)
            }
        }.padding(24).frame(width:480)
    }
}
