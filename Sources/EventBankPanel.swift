import SwiftUI
import AppKit

struct EventBankPanel: View {
    @ObservedObject var model: CalendarModel
    @ObservedObject var bank: EventBankStore
    @AppStorage("eventBankCollapsed") private var collapsed = false
    @AppStorage("eventBankWidth") private var panelWidth = 280.0
    @State private var resizingFrom: Double?
    @State private var editing: BankTask?
    @State private var receivingEvents = false
    @State private var reorderTarget: UUID?
    @State private var reorderAtEnd = false

    var body: some View {
        HStack(spacing:0) {
            ZStack {
                Rectangle().fill(Color.primary.opacity(0.07)).frame(width:0.5)
                if !collapsed { Capsule().fill(Color.primary.opacity(0.16)).frame(width:3,height:30) }
            }
            .frame(width:collapsed ? 1 : 9).contentShape(Rectangle())
            .help("Drag to resize the event bank")
            .gesture(DragGesture(minimumDistance:1).onChanged { value in
                guard !collapsed else { return }
                if resizingFrom == nil { resizingFrom = panelWidth }
                panelWidth = min(440,max(240,(resizingFrom ?? 280)-Double(value.translation.width)))
            }.onEnded { _ in resizingFrom = nil })
            if collapsed {
                VStack {
                    Button { collapsed = false } label: { Image(systemName:"sidebar.right") }
                        .buttonStyle(.plain).padding(.top,18)
                        .accessibilityLabel("Expand Event Bank").help("Show Event Bank")
                    Text("\(bank.tasks.count)").font(.system(size:10)).foregroundStyle(.secondary)
                    Spacer()
                }.frame(maxWidth:.infinity)
            } else {
                VStack(spacing:0) {
                    HStack(spacing:7) {
                        Image(systemName:"tray.full").font(.system(size:12))
                        Text("Event Bank").font(.system(size:12,weight:.semibold))
                        Spacer(minLength:0)
                        Menu {
                            Button("Choose Google Drive Folder…") { bank.chooseFolder() }
                            if let folder = bank.folder { Button("Show Bank Folder in Finder") { NSWorkspace.shared.open(folder) } }
                            Button("Refresh Bank") { bank.refresh() }
                        } label: { Image(systemName:"ellipsis.circle") }
                            .menuStyle(.borderlessButton).frame(width:20).help("Event bank settings")
                        Button { collapsed = true } label: { Image(systemName:"sidebar.right") }
                            .buttonStyle(.plain).accessibilityLabel("Collapse Event Bank").help("Hide Event Bank")
                    }.padding(.top,17).padding(.bottom,8)
                    HStack {
                        Text("\(bank.tasks.count) task\(bank.tasks.count == 1 ? "" : "s") · ~\(BankTask.durationLabel(bank.totalMinutes))")
                            .font(.system(size:10)).foregroundStyle(.secondary)
                        Spacer(minLength:0)
                        Button { addTask() } label: { Label("New Task",systemImage:"plus") }
                            .onDrag { NewTaskDrag.provider() }
                            .help("Click to add to the bank, or drag into the calendar")
                            .disabled(!model.live || !bank.ready || !model.sources.contains(where:\.writable))
                    }.buttonStyle(QuietCalendarButtonStyle()).padding(.bottom,12)
                    if !model.live {
                        Button("Connect Calendars") { model.connect() }.disabled(model.connecting).padding(.bottom,8)
                    }
                    VStack(alignment:.leading,spacing:7) {
                        Text("Drag tasks to reorder or schedule · Drag below to create").foregroundStyle(.tertiary)
                        Label(bank.syncProblem ?? bank.storageStatus,systemImage:bank.syncProblem == nil ? "folder.badge.gearshape" : "exclamationmark.triangle")
                            .foregroundStyle(bank.syncProblem == nil ? Color.secondary : Color.orange)
                            .lineLimit(2).help(bank.syncProblem ?? bank.storageStatus)
                    }.font(.system(size:9)).frame(maxWidth:.infinity,alignment:.leading).padding(.bottom,10)
                    Rectangle().fill(Color.primary.opacity(0.06)).frame(height:0.5)
                    if bank.tasks.isEmpty {
                        BankCreationArea(empty:true,enabled:model.live && bank.ready) { addTask(minutes:$0) }
                            .frame(maxWidth:.infinity,maxHeight:.infinity)
                        if !bank.ready { Button("Choose a Google Drive Folder…") { bank.chooseFolder() }.font(.system(size:11)) }
                    } else {
                        GeometryReader { space in
                        ScrollView(.vertical) {
                            LazyVStack(spacing:10) {
                                ForEach(bank.tasks) { task in
                                    BankTaskCard(task:task,source:model.calendar(for:task))
                                        .onDrag { BankDrag.provider(for:task.id) }
                                        .overlay(alignment:.top) { if reorderTarget == task.id { Capsule().fill(Color.accentColor).frame(height:3).offset(y:-5) } }
                                        .onDrop(of:[BankDrag.identifier],delegate:BankReorderDelegate(bank:bank,before:task.id,onHover:{ reorderTarget = $0 ? task.id : nil },onError:{ model.message = $0 }))
                                        .onTapGesture(count:2) { editing = task }
                                        .contextMenu {
                                            Button("Edit Task…") { editing = task }
                                            Button("Remove from Bank") {
                                                do { try bank.remove(task.id) }
                                                catch { model.message = error.localizedDescription }
                                            }
                                        }
                                }
                                BankCreationArea(empty:false,enabled:model.live && bank.ready) { addTask(minutes:$0) }
                                    .frame(height:max(200,space.size.height-bank.tasks.reduce(CGFloat(0)) { $0+CGFloat($1.minutes)/60*CalendarMath.hourHeight }-CGFloat(bank.tasks.count)*10-12))
                                    .overlay(alignment:.top) { if reorderAtEnd { Capsule().fill(Color.accentColor).frame(height:3) } }
                                    .onDrop(of:[BankDrag.identifier],delegate:BankReorderDelegate(bank:bank,before:nil,onHover:{ reorderAtEnd = $0 },onError:{ model.message = $0 }))
                            }.padding(.top,12)
                        }
                        }.frame(maxHeight:.infinity)
                    }

                }.padding(.horizontal,12)
            }
        }
        .frame(width:collapsed ? 40 : CGFloat(panelWidth))
        .frame(maxHeight:.infinity)
        .background(Color(nsColor:.controlBackgroundColor).opacity(0.55))
        .overlay { if receivingEvents { RoundedRectangle(cornerRadius:8).stroke(Color.accentColor,lineWidth:2).padding(3).allowsHitTesting(false) } }
        .onDrop(of:[CalendarEventDrag.identifier,NewTaskDrag.identifier],delegate:BankEventDropDelegate(model:model,collapsed:$collapsed,targeted:$receivingEvents,onNew:{ addTask() }))
        .sheet(item:$editing) { task in BankTaskEditor(model:model,bank:bank,task:task) }
        .onReceive(NotificationCenter.default.publisher(for:NSApplication.didBecomeActiveNotification)) { _ in bank.refresh() }
    }
    private func addTask(minutes: Int = 30) {
        guard let source = model.sources.first(where:{ $0.writable && model.visible.contains($0.id) }) ?? model.sources.first(where:\.writable) else { return }
        editing = BankTask(title:"",minutes:minutes,calendarID:source.id,calendarTitle:source.title,account:source.account)
        collapsed = false
    }
}

struct BankReorderDelegate: DropDelegate {
    let bank: EventBankStore
    let before: UUID?
    var onHover: (Bool) -> Void
    var onError: (String) -> Void
    func validateDrop(info: DropInfo) -> Bool { info.hasItemsConforming(to:[BankDrag.identifier]) }
    func dropEntered(info: DropInfo) { onHover(true) }
    func dropExited(info: DropInfo) { onHover(false) }
    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation:.move) }
    func performDrop(info: DropInfo) -> Bool {
        onHover(false)
        guard let provider = info.itemProviders(for:[BankDrag.identifier]).first else { return false }
        provider.loadDataRepresentation(forTypeIdentifier:BankDrag.identifier) { data,_ in
            guard let data, let string = String(data:data,encoding:.utf8), let id = UUID(uuidString:string) else { return }
            Task { @MainActor in
                do { try bank.reorder(id,before:before) }
                catch { onError(error.localizedDescription) }
            }
        }
        return true
    }
}

struct BankCreationArea: View {
    var empty: Bool
    var enabled: Bool
    var onCreate: (Int) -> Void
    @State private var span: (start: CGFloat, end: CGFloat)?
    private func minutes(_ distance: CGFloat) -> Int {
        max(15,min(1440,CalendarMath.snappedMinutes(abs(distance))))
    }
    var body: some View {
        GeometryReader { geo in
            ZStack {
                RoundedRectangle(cornerRadius:8).fill(Color.primary.opacity(empty ? 0 : 0.025))
                if let span {
                    let length = minutes(span.end-span.start)
                    RoundedRectangle(cornerRadius:6)
                        .fill(Color.accentColor.opacity(0.12))
                        .overlay { RoundedRectangle(cornerRadius:6).strokeBorder(Color.accentColor.opacity(0.5),lineWidth:1) }
                        .frame(height:max(28,abs(span.end-span.start)))
                        .overlay { Text("New Task · ~"+BankTask.durationLabel(length)).font(.system(size:12,weight:.medium)).padding(6) }
                        .position(x:geo.size.width/2,y:(span.start+span.end)/2)
                } else {
                    VStack(spacing:8) {
                        Text(empty ? "Your event bank is empty." : "Drag here to add a task")
                            .font(.system(size:12,weight:.medium))
                        Text(enabled ? "Drag up or down to set an estimated duration." : "Connect your calendars and choose a bank folder to add tasks.")
                            .font(.system(size:11)).foregroundStyle(.secondary)
                    }.multilineTextAlignment(.center).padding(12).allowsHitTesting(false)
                }
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance:4)
                .onChanged { value in
                    guard enabled else { return }
                    span = (max(0,min(geo.size.height,value.startLocation.y)),max(0,min(geo.size.height,value.location.y)))
                }
                .onEnded { _ in
                    guard let current = span else { return }
                    span = nil
                    onCreate(minutes(current.end-current.start))
                })
            .accessibilityLabel("Drag to create a bank task")
            .help("Drag vertically to choose an estimated duration, then enter the task details")
        }
    }
}

struct BankEventDropDelegate: DropDelegate {
    let model: CalendarModel
    @Binding var collapsed: Bool
    @Binding var targeted: Bool
    var onNew: () -> Void
    func validateDrop(info: DropInfo) -> Bool { info.hasItemsConforming(to:[CalendarEventDrag.identifier,NewTaskDrag.identifier]) }
    func dropEntered(info: DropInfo) { targeted = true }
    func dropExited(info: DropInfo) { targeted = false }
    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation:info.hasItemsConforming(to:[NewTaskDrag.identifier]) ? .copy : .move) }
    func performDrop(info: DropInfo) -> Bool {
        targeted = false
        if info.hasItemsConforming(to:[NewTaskDrag.identifier]) { collapsed = false; onNew(); return true }
        guard let provider = info.itemProviders(for:[CalendarEventDrag.identifier]).first else { return false }
        provider.loadDataRepresentation(forTypeIdentifier:CalendarEventDrag.identifier) { data,_ in
            guard let data, let ids = try? JSONDecoder().decode([String].self,from:data) else { return }
            Task { @MainActor in
                collapsed = false
                _ = model.moveEventsToBank(ids)
            }
        }
        return true
    }
}

struct BankTaskCard: View {
    let task: BankTask
    let source: CalendarSource?
    private var height: CGFloat { CGFloat(task.minutes)/60*CalendarMath.hourHeight }
    @Environment(\.colorScheme) private var scheme
    private var ink: Color {
        source.map { Color(nsColor:$0.color.blended(withFraction:scheme == .dark ? 0.35 : 0.45,of:scheme == .dark ? .white : .black) ?? $0.color) } ?? .secondary
    }
    private var color: Color { source.map { Color(nsColor:$0.color) } ?? .gray }
    var body: some View {
        VStack(alignment:.leading,spacing:height < 85 ? 3 : 7) {
            if height < 45 {
                HStack(spacing:5) {
                    Text(task.title).font(.system(size:11,weight:.medium)).lineLimit(1)
                    Spacer(minLength:0)
                    Text("~"+BankTask.durationLabel(task.minutes)).font(.system(size:10)).foregroundStyle(ink)
                }
            } else {
                if height >= 85 {
                    HStack(spacing:5) {
                        Circle().fill(color).frame(width:6,height:6)
                        Text(source?.title ?? "Choose a calendar").font(.system(size:9)).foregroundStyle(.secondary).lineLimit(1)
                        Spacer(minLength:0)
                        if !task.notes.isEmpty { Image(systemName:"text.alignleft").font(.system(size:9)).foregroundStyle(.tertiary) }
                    }
                }
                Text(task.title).font(.system(size:12,weight:.medium)).lineLimit(height >= 85 ? 2 : 1)
                    .frame(maxWidth:.infinity,alignment:.leading)
                if height > 145 && !task.notes.isEmpty { Text(task.notes).font(.system(size:11)).foregroundStyle(.secondary).lineLimit(3) }
                Spacer(minLength:0)
                HStack(spacing:4) {
                    Image(systemName:"clock").font(.system(size:10))
                    Text("~"+BankTask.durationLabel(task.minutes)).font(.system(size:11,weight:.medium))
                    Spacer()
                    Image(systemName:"hand.draw").font(.system(size:10)).foregroundStyle(.tertiary)
                }.foregroundStyle(ink)
            }
        }
        .padding(.horizontal,11).padding(.vertical,height < 45 ? 3 : 8)
        .frame(maxWidth:.infinity).frame(height:height).clipped()
        .background(color.opacity(0.075),in:RoundedRectangle(cornerRadius:8))
        .overlay(alignment:.leading) { RoundedRectangle(cornerRadius:1.5).fill(color).frame(width:3).padding(.vertical,min(9,height/5)).padding(.leading,3) }
        .overlay { RoundedRectangle(cornerRadius:8).strokeBorder(Color.primary.opacity(0.045),lineWidth:0.5) }
        .contentShape(RoundedRectangle(cornerRadius:8))
        .accessibilityElement(children:.combine)
        .accessibilityLabel("\(task.title), approximately \(task.minutes) minutes, \(source?.title ?? "calendar unavailable")")
        .help(source == nil ? "Edit this task to choose an available calendar." : "Drag onto the calendar to schedule \(task.minutes) minutes.")
    }
}

struct BankTaskEditor: View {
    @ObservedObject var model: CalendarModel
    @ObservedObject var bank: EventBankStore
    @State private var task: BankTask
    @State private var preset: Int
    @State private var error: String?
    @FocusState private var titleFocused: Bool
    @Environment(\.dismiss) private var dismiss
    private let expectedRevision: UUID?
    private let presets = [15,30,45,60,90,120,180,240]

    init(model: CalendarModel, bank: EventBankStore, task: BankTask) {
        self.model = model; self.bank = bank
        var resolved = task
        resolved.calendarID = model.calendar(for:task)?.id ?? ""
        _task = State(initialValue:resolved)
        _preset = State(initialValue:[15,30,45,60,90,120,180,240].contains(task.minutes) ? task.minutes : 0)
        expectedRevision = bank.records[task.id]?.revision
    }
    var body: some View {
        VStack(alignment:.leading,spacing:16) {
            Text(expectedRevision == nil ? "Add to Event Bank" : "Edit Bank Task").font(.title2.bold())
            Text("Choose a duration now. Pick a time later.").font(.system(size:12)).foregroundStyle(.secondary)
            Form {
                TextField("Task",text:$task.title).focused($titleFocused)
                Picker("Estimated time",selection:$preset) {
                    ForEach(presets,id:\.self) { value in Text(BankTask.durationLabel(value)).tag(value) }
                    Text("Custom…").tag(0)
                }.onChange(of:preset) { _,value in if value > 0 { task.minutes = value } }
                if preset == 0 {
                    HStack { Text("Minutes"); Spacer(); TextField("Minutes",value:$task.minutes,format:.number).frame(width:85); Stepper("",value:$task.minutes,in:1...10080).labelsHidden() }
                }
                Picker("Calendar",selection:$task.calendarID) {
                    Text("Choose a calendar").tag("")
                    ForEach(model.sources.filter(\.writable)) { source in Text("\(source.title) · \(source.account)").tag(source.id) }
                }
                TextField("Notes (optional)",text:$task.notes,axis:.vertical).lineLimit(3...6)
            }.formStyle(.grouped)
            if let error { Text(error).font(.system(size:11)).foregroundStyle(.red).fixedSize(horizontal:false,vertical:true) }
            HStack {
                Label("Saved in your Google Drive folder",systemImage:"folder").font(.system(size:10)).foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save Task") { save() }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
                    .disabled(task.title.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || task.calendarID.isEmpty || !(1...10080).contains(task.minutes))
            }
        }.padding(24).frame(width:500).onAppear { titleFocused = true }
    }
    private func save() {
        guard let source = model.sources.first(where:{ $0.id == task.calendarID && $0.writable && !$0.title.hasPrefix("- ") }) else { error = "Choose an editable calendar."; return }
        task.title = task.title.trimmingCharacters(in:.whitespacesAndNewlines)
        task.calendarTitle = source.title; task.account = source.account
        do { try bank.save(task,expectedRevision:expectedRevision); dismiss() }
        catch { self.error = error.localizedDescription }
    }
}
