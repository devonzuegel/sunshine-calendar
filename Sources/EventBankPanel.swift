import SwiftUI
import AppKit

private struct BankTaskFrames: PreferenceKey {
    static let defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(),uniquingKeysWith:{ _,new in new })
    }
}
private struct BankSectionFrames: PreferenceKey {
    static let defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(),uniquingKeysWith:{ _,new in new })
    }
}

struct EventBankPanel: View {
    @ObservedObject private var textSize = AppTextSize.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var model: CalendarModel
    @ObservedObject var bank: EventBankStore
    @AppStorage("eventBankCollapsed") private var collapsed = false
    @AppStorage("eventBankWidth") private var panelWidth = 280.0
    @State private var showingInfo = false
    @State private var resizingFrom: Double?
    @State private var hoveringGrabber = false
    @State private var editing: BankTask?
    @State private var receivingEvents = false
    @State private var reorderTarget: UUID?
    @State private var reorderAtEnd = false
    @State private var taskFrames: [UUID: CGRect] = [:]
    @State private var sectionFrames: [UUID: CGRect] = [:]
    @State private var categoryTarget: UUID?
    @State private var dropCategory: UUID?
    @State private var receivingCategory = false
    @State private var categoryEditing: BankCategory?
    @State private var scrollToCategory: UUID?
    @AppStorage("collapsedBankCategories") private var collapsedCategoryJSON = "[]"
    private var collapsedCategories: Set<UUID> { Set((try? JSONDecoder().decode([UUID].self,from:Data(collapsedCategoryJSON.utf8))) ?? []) }
    @State private var hoveredThumbnail: UUID?
    @State private var thumbnailY: CGFloat = 0
    @State private var resizingTask: BankTask?
    @State private var resizeDuration: Int?
    @Namespace private var taskGeometry

    var body: some View {
        HStack(spacing:0) {
            if collapsed {
                VStack {
                    Button { collapsed = false } label: { Image(systemName:"sidebar.left") }
                        .buttonStyle(.plain).padding(.top,18)
                        .accessibilityLabel("Expand Event Bank").appHelp("Show Event Bank (B)")
                    Text("\(bank.tasks.count)").appFont(size:10).foregroundStyle(.secondary)
                    ScrollView(.vertical) {
                        VStack(spacing:6) {
                            ForEach(bank.tasks) { task in
                                GeometryReader { itemGeometry in
                                    BankTaskThumbnail(task:task,source:model.calendar(for:task))
                                        .matchedGeometryEffect(id:task.id,in:taskGeometry,anchor:.topLeading)
                                        .overlay(alignment:.top) { if reorderTarget == task.id { Capsule().fill(Color.accentColor).frame(height:3).offset(y:-3) } }
                                        .onHover { hovering in
                                            if hovering {
                                                thumbnailY = itemGeometry.frame(in:.named("bankRibbon")).minY
                                                hoveredThumbnail = task.id
                                            } else if hoveredThumbnail == task.id { hoveredThumbnail = nil }
                                        }
                                        .onDrag { hoveredThumbnail = nil; return model.beginBankDrag(task.id) }
                                        .onTapGesture { hoveredThumbnail = nil; collapsed = false }
                                        .contextMenu { taskActions(task) }
                                        .background(BankEditorPopover(model:model,bank:bank,editing:$editing,anchorID:task.id))
                                        .preference(key:BankTaskFrames.self,value:collapsed ? [task.id:itemGeometry.frame(in:.named("bankRibbon"))] : [:])
                                }.frame(width:26,height:min(66,max(16,CGFloat(task.minutes)/60*CalendarMath.hourHeight)))
                            }
                        }.padding(.vertical,8)
                    }.scrollIndicators(.hidden)
                }.frame(width:39).contentShape(Rectangle())
                    .simultaneousGesture(TapGesture().onEnded {
                        hoveredThumbnail = nil; collapsed = false
                    })
                    .transition(.opacity)
            } else {
                VStack(spacing:0) {
                    HStack(spacing:4) {
                        if panelWidth*0.8 >= 220 { Image(systemName:"tray.full").appFont(size:12,weight:.regular).foregroundStyle(.secondary) }
                        Text("Event Bank").appFont(size:12,weight:.semibold).lineLimit(1).minimumScaleFactor(0.7)
                        Spacer(minLength:0)
                        Button { showingInfo.toggle() } label: {
                            headerIcon(bank.syncProblem == nil ? "info.circle" : "exclamationmark.circle")
                                .foregroundStyle(bank.syncProblem == nil ? Color.secondary : Color.orange)
                        }.buttonStyle(.plain).accessibilityLabel("Event bank information")
                            .popover(isPresented:$showingInfo,arrowEdge:.top) {
                                VStack(alignment:.leading,spacing:10) {
                                    Text("Event Bank").appFont(size:12,weight:.semibold)
                                    Text("Drag tasks to reorder or schedule. Drag below the tasks to create one.")
                                    Label(bank.syncProblem ?? bank.storageStatus,systemImage:bank.syncProblem == nil ? "folder.badge.gearshape" : "exclamationmark.triangle")
                                        .foregroundStyle(bank.syncProblem == nil ? Color.secondary : Color.orange)
                                }.appFont(size:11).padding(14).frame(width:260,alignment:.leading)
                            }
                        Menu {
                            Button("New Category…") { categoryEditing = BankCategory(title:"") }.disabled(!bank.ready)
                            Divider()
                            Button("Choose Google Drive Folder…") { bank.chooseFolder() }
                            if let folder = bank.folder { Button("Show Bank Folder in Finder") { NSWorkspace.shared.open(folder) } }
                            Button("Refresh Bank") { bank.refresh() }
                        } label: { headerIcon("ellipsis.circle").foregroundStyle(.secondary) }
                            .menuStyle(.borderlessButton).menuIndicator(.hidden)
                            .fixedSize().accessibilityLabel("Event bank settings").appHelp("Event bank settings")
                        Button { collapsed = true } label: { headerIcon("sidebar.left").foregroundStyle(.secondary) }
                            .buttonStyle(.plain).accessibilityLabel("Collapse Event Bank").appHelp("Hide Event Bank (B)")
                    }.padding(.top,17).padding(.bottom,8)
                    Text("\(bank.tasks.count) task\(bank.tasks.count == 1 ? "" : "s") · ~\(BankTask.durationLabel(bank.totalMinutes))")
                        .appFont(size:10).foregroundStyle(.secondary)
                        .frame(maxWidth:.infinity,alignment:.leading).padding(.bottom,12)
                    if !model.live {
                        Button("Connect Calendars") { model.connect() }.disabled(model.connecting).padding(.bottom,8)
                    }
                    Rectangle().fill(Color.primary.opacity(0.06)).frame(height:0.5)
                    if !bank.ready {
                        BankCreationArea(empty:true,enabled:model.live && bank.ready) { addTask(minutes:$0) }
                            .simultaneousGesture(TapGesture().onEnded { model.selectedBankTasks = [] })
                            .frame(maxWidth:.infinity,maxHeight:.infinity)
                        if !bank.ready { Button("Choose a Google Drive Folder…") { bank.chooseFolder() }.appFont(size:11) }
                    } else { categoryList }

                }.padding(.horizontal,12)
                    .frame(width:CGFloat(panelWidth)*0.8-12)
                    .transition(.opacity)
            }
            ZStack {
                Rectangle().fill(Color.primary.opacity(0.07)).frame(width:0.5)
                if !collapsed { Capsule().fill(Color.primary.opacity(hoveringGrabber || resizingFrom != nil ? 0.35 : 0.16)).frame(width:3,height:30) }
            }
            .frame(width:collapsed ? 1 : 12).contentShape(Rectangle())
            .onTapGesture { if collapsed { hoveredThumbnail = nil; collapsed = false } }
            .appHelp("Drag to resize the event bank · Double-click to reset")
            .onHover { hovering in
                hoveringGrabber = hovering
                if hovering && !collapsed { NSCursor.resizeLeftRight.push() }
                else if !hovering && !collapsed { NSCursor.pop() }
            }
            .onTapGesture(count:2) { if !collapsed { panelWidth = 280 } }
            .highPriorityGesture(DragGesture(minimumDistance:1,coordinateSpace:.global).onChanged { value in
                guard !collapsed else { return }
                if resizingFrom == nil { resizingFrom = panelWidth }
                panelWidth = min(800,max(200,(resizingFrom ?? 280)+Double(value.translation.width)/0.8))
            }.onEnded { _ in resizingFrom = nil })
        }
        .frame(width:collapsed ? 40 : CGFloat(panelWidth)*0.8)
        .frame(maxHeight:.infinity)
        .clipped()
        .contentShape(Rectangle())
        .animation(reduceMotion ? nil : .easeInOut(duration:0.25),value:collapsed)
        .background(Color(nsColor:.controlBackgroundColor).opacity(0.55))
        .coordinateSpace(name:"bankRibbon")
        .onPreferenceChange(BankTaskFrames.self) { taskFrames = $0 }
        .onPreferenceChange(BankSectionFrames.self) { sectionFrames = $0 }
        .overlay {
            GeometryReader { geometry in
                if collapsed, let id = hoveredThumbnail, let task = bank.tasks.first(where:{ $0.id == id }) {
                    BankThumbnailDetails(task:task,source:model.calendar(for:task))
                        .frame(width:240)
                        .position(x:geometry.size.width+128,y:min(max(90,thumbnailY+50),max(90,geometry.size.height-100)))
                        .transition(.opacity.combined(with:.scale(scale:0.96,anchor:.leading)))
                }
            }.allowsHitTesting(false)
        }
        .animation(reduceMotion ? nil : .easeOut(duration:0.16),value:hoveredThumbnail)
        .animation(reduceMotion ? nil : .easeOut(duration:0.12),value:bank.tasks.map(\.id))
        .animation(reduceMotion ? nil : .easeInOut(duration:0.2),value:bank.categories.map(\.id))
        .onChange(of:collapsed) { _,_ in hoveredThumbnail = nil }
        .simultaneousGesture(TapGesture().onEnded {
            model.bankHasFocus = true
            if model.draft == nil { model.selected = [] }
        })

        .overlay { if receivingEvents { RoundedRectangle(cornerRadius:8).stroke(Color.accentColor,lineWidth:2).padding(3).allowsHitTesting(false) } }
        .onDrop(of:[CalendarEventDrag.identifier,BankDrag.identifier,NewTaskDrag.identifier,BankCategoryDrag.identifier],delegate:BankDropDelegate(model:model,frames:taskFrames,sectionFrames:sectionFrames,collapsed:$collapsed,targeted:$receivingEvents,before:$reorderTarget,atEnd:$reorderAtEnd,categoryBefore:$categoryTarget,receivingCategory:$receivingCategory,taskCategory:$dropCategory,onNew:{ addTask(categoryID:$0) }))
        .sheet(item:$categoryEditing) { category in
            BankCategoryEditor(bank:bank,category:category) {
                categoryEditing = nil
                if bank.categoryRecords[category.id] != nil { scrollToCategory = category.id }
            }
        }
        .background(BankEditorPopover(model:model,bank:bank,editing:$editing,anchorID:nil))
        .onReceive(NotificationCenter.default.publisher(for:NSApplication.didBecomeActiveNotification)) { _ in bank.refresh() }
    }
    private func headerIcon(_ name: String) -> some View {
        Image(systemName:name).appFont(size:12,weight:.regular).frame(width:20,height:20)
    }
    private var categoryList: some View {
        GeometryReader { space in
            ScrollViewReader { proxy in
            ScrollView(.vertical) {
                LazyVStack(spacing:10) {
                    ForEach(bank.sections) { section in categorySection(section).id(section.id) }
                    BankCreationArea(empty:bank.tasks.isEmpty,enabled:model.live && bank.ready) {
                        addTask(minutes:$0,categoryID:bank.categories.last?.id)
                    }
                    .simultaneousGesture(TapGesture().onEnded { model.selectedBankTasks = [] })
                    .frame(height:max(160,space.size.height-visibleTaskHeight-CGFloat(bank.categories.count)*34-24))
                }.padding(.top,8).padding(.horizontal,12)
            }.padding(.horizontal,-12)
                .onChange(of:scrollToCategory) { _,id in
                    guard let id else { return }
                    withAnimation(reduceMotion ? nil : .easeInOut(duration:0.2)) { proxy.scrollTo(id,anchor:.top) }
                }
            }
        }.frame(maxHeight:.infinity)
    }
    private var visibleTaskHeight: CGFloat {
        bank.sections.filter { !collapsedCategories.contains($0.id) }.reduce(0) { total,section in
            total+section.tasks.reduce(CGFloat(0)) { $0+CGFloat($1.minutes)/60*CalendarMath.hourHeight+10 }
        }
    }
    private func toggleCategory(_ id: UUID) {
        var values = collapsedCategories
        if values.contains(id) { values.remove(id) } else { values.insert(id) }
        let update = { collapsedCategoryJSON = String(data:(try? JSONEncoder().encode(Array(values))) ?? Data("[]".utf8),encoding:.utf8) ?? "[]" }
        withAnimation(reduceMotion ? nil : .easeInOut(duration:0.18),update)
    }
    private func moveCategory(_ id: UUID, by step: Int) {
        let ids = bank.categories.map(\.id)
        guard let index = ids.firstIndex(of:id), ids.indices.contains(index+step) else { return }
        let target = step < 0 ? ids[index-1] : (index+2 < ids.count ? ids[index+2] : nil)
        do { try bank.reorderCategory(id,before:target) } catch { model.message = error.localizedDescription }
    }
    private func categorySection(_ section: BankSection) -> some View {
        let closed = collapsedCategories.contains(section.id)
        return VStack(spacing:8) {
            Button { toggleCategory(section.id) } label: {
                HStack(spacing:6) {
                    Image(systemName:"chevron.right").appFont(size:7,weight:.semibold)
                        .rotationEffect(.degrees(closed ? 0 : 90)).foregroundStyle(.secondary)
                    Text(section.category.title).appFont(size:10,weight:.semibold).lineLimit(1)
                    Spacer(minLength:0)
                    Text("\(section.tasks.count)").appFont(size:9).foregroundStyle(.secondary)
                }.frame(maxWidth:.infinity).frame(height:25).contentShape(Rectangle())
            }.buttonStyle(.plain)
                .accessibilityLabel(section.category.title+", \(section.tasks.count) tasks, "+(closed ? "collapsed" : "expanded"))
                .appHelp("Click to expand or collapse · Drag the section to reorder · ~"+BankTask.durationLabel(section.totalMinutes))
            if !closed {
                ForEach(section.tasks) { task in taskRow(task) }
                if section.tasks.isEmpty {
                    Text("Drop tasks here").appFont(size:9).foregroundStyle(.tertiary)
                        .frame(maxWidth:.infinity).frame(height:26)
                }
            }
        }.contentShape(Rectangle())
            .onDrag { BankCategoryDrag.provider(section.id) }
            .accessibilityAction(named:Text("Move Category Up")) { moveCategory(section.id,by:-1) }
            .accessibilityAction(named:Text("Move Category Down")) { moveCategory(section.id,by:1) }
            .contextMenu {
                Button("New Task in Category…") { addTask(categoryID:section.id) }
                Button("New Category…") { categoryEditing = BankCategory(title:"") }
                if section.id != BankCategory.uncategorizedID {
                    Button("Rename Category…") { categoryEditing = section.category }
                    Button("Remove Category, Keep Tasks") {
                        do { try bank.removeCategory(section.id) } catch { model.message = error.localizedDescription }
                    }
                }
            }
            .overlay(alignment:.top) { if receivingCategory && categoryTarget == section.id { Capsule().fill(Color.accentColor).frame(height:3).offset(y:-4) } }
            .overlay(alignment:.bottom) { if receivingCategory && categoryTarget == nil && bank.categories.last?.id == section.id { Capsule().fill(Color.accentColor).frame(height:3).offset(y:4) } }
            .overlay(alignment:.bottom) { if receivingEvents && !receivingCategory && dropCategory == section.id && reorderTarget == nil && !closed && !section.tasks.isEmpty { Capsule().fill(Color.accentColor).frame(height:3).offset(y:4) } }
            .overlay { if receivingEvents && !receivingCategory && dropCategory == section.id && (closed || section.tasks.isEmpty) { RoundedRectangle(cornerRadius:4).stroke(Color.accentColor.opacity(0.5),lineWidth:1) } }
            .background(GeometryReader { geometry in
                Color.clear.preference(key:BankSectionFrames.self,value:collapsed ? [:] : [section.id:geometry.frame(in:.named("bankRibbon"))])
            })
    }
    private func taskRow(_ task: BankTask) -> some View {
        BankTaskCard(task:resizePreview(task),source:model.calendar(for:task),selected:model.selectedBankTasks.contains(task.id))
            .matchedGeometryEffect(id:task.id,in:taskGeometry,anchor:.topLeading)
            .onDrag { model.beginBankDrag(task.id) }
            .overlay(alignment:.top) { if reorderTarget == task.id { Capsule().fill(Color.accentColor).frame(height:3).offset(y:-4) } }
            .background(GeometryReader { geometry in
                Color.clear.preference(key:BankTaskFrames.self,value:collapsed ? [:] : [task.id:geometry.frame(in:.named("bankRibbon"))])
            })
            .overlay { if model.selectedBankTasks.contains(task.id) { RoundedRectangle(cornerRadius:7).stroke(Color(nsColor:model.calendar(for:task)?.color ?? .secondaryLabelColor),lineWidth:1.5).allowsHitTesting(false) } }
            .overlay(alignment:.top) { resizeHandle(task,top:true) }
            .overlay(alignment:.bottom) { resizeHandle(task,top:false) }
            .onTapGesture(count:2) { editing = task }
            .onTapGesture { model.selectBankTask(task.id,extending:NSEvent.modifierFlags.contains(.command)) }
            .contextMenu { taskActions(task) }
            .background(BankEditorPopover(model:model,bank:bank,editing:$editing,anchorID:task.id))
    }
    @ViewBuilder private func taskActions(_ task: BankTask) -> some View {
        Button("Edit Task…") { model.selectBankTask(task.id,extending:false); editing = task }
        Divider()
        Button("Copy") { selectForAction(task); model.copyBankTasks() }
        Button("Cut") { selectForAction(task); model.deleteBankTasks(cut:true) }
        Button("Paste") { model.bankHasFocus = true; model.pasteBankTasks() }.disabled(!bank.ready)
        Menu("Move to Category") {
            ForEach(bank.categories) { category in
                Button(category.title) {
                    selectForAction(task)
                    do { try model.moveSelectedBankTasks(to:category.id) } catch { model.message = error.localizedDescription }
                }
            }
        }
        Divider()
        Button(model.selectedBankTasks.count > 1 && model.selectedBankTasks.contains(task.id) ? "Delete Selected Tasks" : "Delete Task") {
            selectForAction(task); model.deleteBankTasks()
        }
    }
    private func selectForAction(_ task: BankTask) {
        if !model.selectedBankTasks.contains(task.id) { model.selectBankTask(task.id,extending:false) }
    }
    private func resizePreview(_ task: BankTask) -> BankTask {
        guard resizingTask?.id == task.id, let resizeDuration else { return task }
        var preview = task; preview.minutes = resizeDuration; return preview
    }
    private func resizeHandle(_ task: BankTask, top: Bool) -> some View {
        Capsule().fill(Color(nsColor:model.calendar(for:task)?.color ?? .secondaryLabelColor).opacity(model.selectedBankTasks.contains(task.id) ? 0.65 : 0.18))
            .frame(width:16,height:1.5)
            .frame(maxWidth:.infinity).frame(height:min(7,max(2,CGFloat(task.minutes)/60*CalendarMath.hourHeight/3)))
            .contentShape(Rectangle())
            .highPriorityGesture(DragGesture(minimumDistance:1,coordinateSpace:.global)
                .onChanged { value in
                    if resizingTask == nil {
                        resizingTask = task
                        model.selectBankTask(task.id,extending:false)
                    }
                    guard let original = resizingTask, original.id == task.id else { return }
                    resizeDuration = BankTaskResize.minutes(original:original.minutes,translation:value.translation.height,top:top,fine:NSEvent.modifierFlags.contains(.shift))
                }
                .onEnded { _ in
                    defer { resizingTask = nil; resizeDuration = nil }
                    guard var original = resizingTask, let minutes = resizeDuration, original.minutes != minutes else { return }
                    let revision = original.revision
                    original.minutes = minutes
                    do { try bank.save(original,expectedRevision:revision) }
                    catch { model.message = error.localizedDescription }
                })
            .onHover { hovering in if hovering { NSCursor.resizeUpDown.push() } else { NSCursor.pop() } }
            .appHelp("Drag to resize · 5-minute steps · Shift for 1 minute")
    }
    private func addTask(minutes: Int = 30, categoryID: UUID? = nil) {
        guard let source = model.creationCalendar else { return }
        editing = BankTask(title:"",minutes:minutes,calendarID:source.id,calendarTitle:source.title,account:source.account)
        editing?.categoryID = categoryID == BankCategory.uncategorizedID ? nil : categoryID
        collapsed = false
    }
}

private struct BankTaskThumbnail: View {
    let task: BankTask
    let source: CalendarSource?
    private var color: Color { source.map { Color(nsColor:$0.color) } ?? .gray }
    var body: some View {
        RoundedRectangle(cornerRadius:4).fill(color.opacity(0.23))
            .overlay(alignment:.leading) { RoundedRectangle(cornerRadius:1).fill(color).frame(width:3) }
            .overlay { RoundedRectangle(cornerRadius:4).strokeBorder(color.opacity(0.45),lineWidth:0.5) }
            .contentShape(RoundedRectangle(cornerRadius:4))
            .accessibilityLabel(task.title+", approximately "+BankTask.durationLabel(task.minutes)+". Drag to schedule.")
    }
}
private struct BankThumbnailDetails: View {
    let task: BankTask
    let source: CalendarSource?
    var body: some View {
        VStack(alignment:.leading,spacing:8) {
            HStack(spacing:5) {
                Circle().fill(source.map { Color(nsColor:$0.color) } ?? .gray).frame(width:7,height:7)
                Text(source?.title ?? "Calendar unavailable").appFont(size:10).foregroundStyle(.secondary).lineLimit(1)
            }
            Text(task.title).appFont(size:13,weight:.semibold).lineLimit(3)
            Label("~"+BankTask.durationLabel(task.minutes),systemImage:"clock").appFont(size:11)
            if !task.notes.isEmpty { Text(CalendarNotePreview.plainText(task.notes)).appFont(size:9).foregroundStyle(Color(nsColor:source?.color ?? .secondaryLabelColor).opacity(0.55)).frame(maxHeight:.infinity,alignment:.topLeading).clipped() }
            Text("Drag the thumbnail to schedule").appFont(size:9).foregroundStyle(.tertiary)
        }.padding(12).frame(maxWidth:.infinity,alignment:.leading)
            .background(.regularMaterial,in:RoundedRectangle(cornerRadius:9))
            .overlay { RoundedRectangle(cornerRadius:9).strokeBorder(Color.primary.opacity(0.12),lineWidth:0.5) }
            .shadow(color:.black.opacity(0.18),radius:9,y:3)
    }
}

struct BankCreationArea: View {
    @ObservedObject private var textSize = AppTextSize.shared
    var empty: Bool
    var enabled: Bool
    var onCreate: (Int) -> Void
    @State private var span: (start: CGFloat, end: CGFloat)?
    private func minutes(_ distance: CGFloat) -> Int {
        max(NSEvent.modifierFlags.contains(.shift) ? 1 : CalendarMath.defaultSnapMinutes,min(1440,CalendarMath.snappedMinutes(abs(distance),fine:NSEvent.modifierFlags.contains(.shift))))
    }
    var body: some View {
        GeometryReader { geo in
            ZStack {
                RoundedRectangle(cornerRadius:8)
                    .strokeBorder(Color.secondary.opacity(0.25),style:StrokeStyle(lineWidth:1,lineCap:.round,dash:[1,4]))
                if let span {
                    let length = minutes(span.end-span.start)
                    RoundedRectangle(cornerRadius:6)
                        .fill(Color.accentColor.opacity(0.12))
                        .overlay { RoundedRectangle(cornerRadius:6).strokeBorder(Color.accentColor.opacity(0.5),lineWidth:1) }
                        .frame(height:max(28,abs(span.end-span.start)))
                        .overlay { Text("New Task · ~"+BankTask.durationLabel(length)).appFont(size:12,weight:.medium).padding(6) }
                        .position(x:geo.size.width/2,y:(span.start+span.end)/2)
                } else {
                    VStack(spacing:8) {
                        Text(empty ? "Your event bank is empty." : "Drag here to add a task")
                            .appFont(size:12,weight:.medium)
                        Text(enabled ? "Drag up or down to set an estimated duration." : "Connect your calendars and choose a bank folder to add tasks.")
                            .appFont(size:11).foregroundStyle(.secondary)
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
            .appHelp("Drag vertically to choose an estimated duration, then enter the task details")
        }
    }
}

struct BankDropDelegate: DropDelegate {
    let model: CalendarModel
    let frames: [UUID: CGRect]
    let sectionFrames: [UUID: CGRect]
    @Binding var collapsed: Bool
    @Binding var targeted: Bool
    @Binding var before: UUID?
    @Binding var atEnd: Bool
    @Binding var categoryBefore: UUID?
    @Binding var receivingCategory: Bool
    @Binding var taskCategory: UUID?
    var onNew: (UUID) -> Void
    func validateDrop(info: DropInfo) -> Bool { model.bank.ready && info.hasItemsConforming(to:[CalendarEventDrag.identifier,BankDrag.identifier,NewTaskDrag.identifier,BankCategoryDrag.identifier]) }
    private func insertion(_ info: DropInfo) -> BankDropDestination {
        if !collapsed {
            return BankSectionDropLayout.destination(at:info.location,sections:model.bank.sections,sectionFrames:sectionFrames,taskFrames:frames)
        }
        let before = BankDropLayout.before(at:info.location,orderedIDs:model.bank.tasks.map(\.id),frames:frames)
        let task = before.flatMap { model.bank.records[$0] } ?? model.bank.tasks.last
        return BankDropDestination(categoryID:task.map { model.bank.categoryID(for:$0) } ?? BankCategory.uncategorizedID,before:before)
    }
    private func update(_ info: DropInfo) {
        targeted = true
        receivingCategory = info.hasItemsConforming(to:[BankCategoryDrag.identifier])
        if receivingCategory {
            categoryBefore = BankDropLayout.before(at:info.location,orderedIDs:model.bank.categories.map(\.id),frames:sectionFrames)
            before = nil; atEnd = false; taskCategory = nil
        } else {
            let destination = insertion(info)
            before = destination.before; taskCategory = destination.categoryID
            atEnd = before == nil && destination.categoryID == model.bank.categories.last?.id
        }
    }
    private func clear() { targeted = false; before = nil; atEnd = false; categoryBefore = nil; receivingCategory = false; taskCategory = nil }
    func dropEntered(info: DropInfo) { update(info) }
    func dropExited(info: DropInfo) { clear() }
    func dropUpdated(info: DropInfo) -> DropProposal? {
        update(info)
        return DropProposal(operation:info.hasItemsConforming(to:[NewTaskDrag.identifier]) ? .copy : .move)
    }
    func performDrop(info: DropInfo) -> Bool {
        guard validateDrop(info:info) else { clear(); return false }
        let target = insertion(info)
        let categoryTarget = categoryBefore
        clear()
        if let provider = info.itemProviders(for:[BankCategoryDrag.identifier]).first {
            provider.loadDataRepresentation(forTypeIdentifier:BankCategoryDrag.identifier) { data,_ in
                guard let data, let string = String(data:data,encoding:.utf8), let id = UUID(uuidString:string) else { return }
                Task { @MainActor in
                    do { try model.bank.reorderCategory(id,before:categoryTarget) }
                    catch { model.message = error.localizedDescription }
                }
            }
            return true
        }
        if info.hasItemsConforming(to:[NewTaskDrag.identifier]) { collapsed = false; onNew(target.categoryID); return true }
        if let provider = info.itemProviders(for:[BankDrag.identifier]).first {
            provider.loadDataRepresentation(forTypeIdentifier:BankDrag.identifier) { data,_ in
                guard let data, let string = String(data:data,encoding:.utf8), let id = UUID(uuidString:string) else { return }
                Task { @MainActor in
                    do { try model.reorderBankTasks(id,before:target.before,categoryID:target.categoryID) }
                    catch { model.message = error.localizedDescription }
                }
            }
            return true
        }
        guard let provider = info.itemProviders(for:[CalendarEventDrag.identifier]).first else { return false }
        provider.loadDataRepresentation(forTypeIdentifier:CalendarEventDrag.identifier) { data,_ in
            guard let data, let ids = try? JSONDecoder().decode([String].self,from:data) else { return }
            Task { @MainActor in
                collapsed = false
                _ = model.moveEventsToBank(ids,before:target.before,categoryID:target.categoryID)
            }
        }
        return true
    }
}

private struct BankCategoryEditor: View {
    @ObservedObject var bank: EventBankStore
    let category: BankCategory
    let close: () -> Void
    let expectedRevision: UUID?
    @State private var title: String
    @State private var error: String?
    @FocusState private var focused: Bool
    init(bank: EventBankStore, category: BankCategory, close: @escaping () -> Void) {
        self.bank = bank; self.category = category; self.close = close
        expectedRevision = bank.categoryRecords[category.id]?.revision
        _title = State(initialValue:category.title)
    }
    var body: some View {
        VStack(alignment:.leading,spacing:14) {
            Text(expectedRevision == nil ? "New Category" : "Rename Category").appFont(size:15,weight:.semibold)
            TextField("Category name",text:$title).textFieldStyle(.roundedBorder).focused($focused)
                .accessibilityLabel("Category name")
            if let error { Text(error).appFont(size:10).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button("Cancel",action:close).keyboardShortcut(.cancelAction)
                Button(expectedRevision == nil ? "Create" : "Save") {
                    var saved = category; saved.title = title
                    if expectedRevision == nil { saved.position = (bank.categories.last?.position ?? 0)+1 }
                    do { try bank.saveCategory(saved,expectedRevision:expectedRevision); close() }
                    catch { self.error = error.localizedDescription }
                }.keyboardShortcut(.defaultAction).disabled(title.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)
            }
        }.padding(20).frame(width:300).onAppear { focused = true }
    }
}

struct BankTaskCard: View {
    @ObservedObject private var textSize = AppTextSize.shared
    let task: BankTask
    let source: CalendarSource?
    var selected = false
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
                    Text(task.title).appFont(size:11,weight:.medium).lineLimit(1)
                    Spacer(minLength:0)
                }
            } else {
                Text(task.title).appFont(size:12,weight:.medium)
                    .lineLimit(height >= AppTextSize.points(64) ? 2 : 1)
                    .fixedSize(horizontal:false,vertical:true)
                    .layoutPriority(1)
                    .frame(maxWidth:.infinity,alignment:.leading)
                if height > 145 && !task.notes.isEmpty { Text(CalendarNotePreview.plainText(task.notes)).appFont(size:9).foregroundStyle(ink.opacity(0.55)).frame(maxHeight:.infinity,alignment:.topLeading).clipped() }
                Spacer(minLength:0)
                HStack(spacing:4) {
                    Image(systemName:"clock").appFont(size:10)
                    Text("~"+BankTask.durationLabel(task.minutes)).appFont(size:11,weight:.medium)
                    Spacer()
                    Image(systemName:"hand.draw").appFont(size:10).foregroundStyle(.tertiary)
                }.foregroundStyle(ink)
            }
        }
        .padding(.horizontal,11).padding(.vertical,height < 45 ? 3 : 8)
        .frame(maxWidth:.infinity).frame(height:height).clipped()
        .background(color.opacity(selected ? 0.22 : 0.075),in:RoundedRectangle(cornerRadius:8))
        .overlay(alignment:.leading) { RoundedRectangle(cornerRadius:1.5).fill(color).frame(width:3) }
        .overlay { RoundedRectangle(cornerRadius:8).strokeBorder(Color.primary.opacity(0.045),lineWidth:0.5) }
        .contentShape(RoundedRectangle(cornerRadius:8))
        .accessibilityElement(children:.combine)
        .accessibilityLabel("\(task.title), approximately \(task.minutes) minutes, \(source?.title ?? "calendar unavailable")")
        .appHelp(source == nil ? "Edit this task to choose an available calendar." : "Drag onto the calendar to schedule \(task.minutes) minutes.")
    }
}

struct BankTaskEditor: View {
    @ObservedObject private var textSize = AppTextSize.shared
    @ObservedObject var session: BankEditorSession
    var close: (Bool) -> Void
    @FocusState private var titleFocused: Bool
    private var hairline: Color { Color.primary.opacity(0.09) }
    var body: some View {
        VStack(alignment:.leading,spacing:16) {
            HStack(alignment:.top,spacing:12) {
                TextField("Task title",text:$session.task.title,axis:.vertical)
                    .appFont(size:20,weight:.semibold).lineLimit(nil)
                    .fixedSize(horizontal:false,vertical:true).layoutPriority(1).focused($titleFocused)
                CalendarColorPicker(sources:session.model.sources.filter { $0.writable && !$0.title.hasPrefix("- ") },selection:$session.task.calendarID,compact:true)
                    .frame(width:AppTextSize.points(66),height:AppTextSize.points(34)).appHelp("Choose calendar")
            }.padding(12)
                .background(Color.primary.opacity(0.025),in:RoundedRectangle(cornerRadius:9))
                .overlay(RoundedRectangle(cornerRadius:9).strokeBorder(hairline,lineWidth:0.5))
            VStack(alignment:.leading,spacing:10) {
                HStack {
                    Text("Category").foregroundStyle(.secondary)
                    Spacer()
                    Picker("Category",selection:Binding(get:{ session.bank.categoryID(for:session.task) },set:{ session.task.categoryID = $0 == BankCategory.uncategorizedID ? nil : $0 })) {
                        ForEach(session.bank.categories) { category in Text(category.title).tag(category.id) }
                    }.labelsHidden().pickerStyle(.menu)
                }
                HStack {
                    Text("Duration").foregroundStyle(.secondary)
                    Spacer()
                    TextField("Minutes",value:$session.task.minutes,format:.number).frame(width:65)
                        .textFieldStyle(.roundedBorder).multilineTextAlignment(.trailing)
                    Text("min").foregroundStyle(.secondary)
                    Stepper("Duration",value:$session.task.minutes,in:1...10080,step:CalendarMath.defaultSnapMinutes).labelsHidden()
                }
                HStack(spacing:5) {
                    ForEach([15,30,45,60,90,120],id:\.self) { minutes in
                        Button(BankTask.durationLabel(minutes)) { session.task.minutes = minutes }
                            .buttonStyle(.plain).appFont(size:10)
                            .padding(.horizontal,7).padding(.vertical,4)
                            .background(Color.primary.opacity(session.task.minutes == minutes ? 0.10 : 0.035),in:Capsule())
                    }
                }
                Text("Unscheduled · Drag onto the calendar to choose a time")
                    .appFont(size:9).foregroundStyle(.tertiary)
            }.padding(12).frame(maxWidth:.infinity,alignment:.leading)
                .background(Color.primary.opacity(0.025),in:RoundedRectangle(cornerRadius:9))
                .overlay(RoundedRectangle(cornerRadius:9).strokeBorder(hairline,lineWidth:0.5))
            HStack(alignment:.top,spacing:8) {
                EventFieldIcon(name:"sticky-note")
                RichNotesEditor(notes:$session.task.notes)
            }.padding(10)
                .background(Color.primary.opacity(0.025),in:RoundedRectangle(cornerRadius:9))
                .overlay(RoundedRectangle(cornerRadius:9).strokeBorder(hairline,lineWidth:0.5))
            if let error = session.error { Text(error).appFont(size:10).foregroundStyle(.red).fixedSize(horizontal:false,vertical:true) }
            HStack(spacing:10) {
                Spacer()
                Button("Cancel") { close(true) }.keyboardShortcut(.cancelAction)
                Button("Save") { close(false) }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
                    .disabled(session.task.title.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || session.task.calendarID.isEmpty || !(1...10080).contains(session.task.minutes))
            }
        }.padding(20).appFont(size:13).textFieldStyle(.plain)
            .frame(width:AppTextSize.points(400)).fixedSize(horizontal:false,vertical:true)
            .onAppear { titleFocused = true }
    }
}
