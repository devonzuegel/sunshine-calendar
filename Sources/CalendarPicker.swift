import SwiftUI
import AppKit

struct CalendarPickerAccount: Identifiable {
    let account: String
    let sources: [CalendarSource]
    var id: String { account }
    var title: String { account.isEmpty ? "Other calendars" : account }
    static func sections(_ sources: [CalendarSource], query: String = "") -> [Self] {
        let terms = query.split(whereSeparator:\.isWhitespace).map(String.init)
        let matches = sources.filter { source in
            let account = source.account.isEmpty ? "Other calendars" : source.account
            return terms.allSatisfy { term in
                source.title.range(of:term,options:[.caseInsensitive,.diacriticInsensitive]) != nil || account.range(of:term,options:[.caseInsensitive,.diacriticInsensitive]) != nil
            }
        }
        return Dictionary(grouping:matches,by:\.account).map { account,values in
            Self(account:account,sources:values.sorted {
                let order = $0.title.localizedStandardCompare($1.title)
                return order == .orderedSame ? $0.id < $1.id : order == .orderedAscending
            })
        }.sorted {
            let order = $0.title.localizedStandardCompare($1.title)
            return order == .orderedSame ? $0.account < $1.account : order == .orderedAscending
        }
    }
}

struct CalendarColorPicker: View {
    var sources: [CalendarSource]
    @Binding var selection: String
    var compact = false
    @ObservedObject private var textSize = AppTextSize.shared
    @State private var showing = false
    private var selected: CalendarSource? { sources.first { $0.id == selection } }
    var body: some View {
        Button { showing = true } label: {
            HStack(spacing:6) {
                Circle().fill(selected.map { Color(nsColor:$0.color) } ?? .secondary)
                    .frame(width:AppTextSize.points(11),height:AppTextSize.points(11))
                    .overlay { Circle().strokeBorder(Color.primary.opacity(0.08),lineWidth:0.5) }
                if !compact { Text(selected?.title ?? "Choose a calendar").appFont(size:13).lineLimit(1) }
                Image(systemName:"chevron.up.chevron.down").appFont(size:8,weight:.medium)
            }.frame(minWidth:compact ? AppTextSize.points(42) : nil,minHeight:AppTextSize.points(26))
        }.buttonStyle(.bordered).controlSize(.regular).disabled(sources.isEmpty)
            .accessibilityLabel("Calendar")
            .accessibilityValue(selected.map { $0.title+", "+$0.account } ?? "Choose a calendar")
            .appHelp(selected.map { $0.title+" · "+$0.account } ?? "Choose a calendar")
            .popover(isPresented:$showing) {
                CalendarAccountPicker(sources:sources,selection:selection,onChoose:{ id in selection = id; showing = false },onCancel:{ showing = false })
            }
    }
}

struct CalendarAccountPicker: View {
    let sources: [CalendarSource]
    let selection: String
    var onChoose: (String) -> Void
    var onCancel: () -> Void
    @ObservedObject private var textSize = AppTextSize.shared
    @State private var query = ""
    @State private var collapsedAccounts: Set<String> = []
    @State private var searchCollapsedAccounts: Set<String> = []
    @State private var highlighted: String?
    @State private var scrollTarget: String?
    @State private var initialListHeight: CGFloat?
    @FocusState private var searchFocused: Bool
    private var sections: [CalendarPickerAccount] { CalendarPickerAccount.sections(sources,query:query) }
    private var searching: Bool { !query.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty }
    private func expanded(_ account: String) -> Bool { searching ? !searchCollapsedAccounts.contains(account) : !collapsedAccounts.contains(account) }
    private var listHeight: CGFloat { initialListHeight ?? openingListHeight }
    private var openingListHeight: CGFloat {
        // Keep the opening footprint throughout this presentation. Collapsing
        // sections or filtering must not make AppKit reposition the popover.
        let accounts = CalendarPickerAccount.sections(sources)
        let content = AppTextSize.points(CGFloat(sources.count*28+accounts.count*32+8))
        // Grow to fit every row; only the actual display bounds require scrolling.
        let screen = NSApp.keyWindow?.screen ?? NSScreen.main
        let maximum = (screen?.visibleFrame.height ?? 900)-AppTextSize.points(90)-24
        return min(max(AppTextSize.points(60),maximum),max(AppTextSize.points(60),content))
    }
    var body: some View {
        VStack(alignment:.leading,spacing:10) {
            Text("Choose a calendar").appFont(size:13,weight:.semibold)
            HStack(spacing:6) {
                Image(systemName:"magnifyingglass").appFont(size:10).foregroundStyle(.secondary)
                TextField("Search calendars…",text:$query).textFieldStyle(.plain)
                    .appFont(size:11).focused($searchFocused).accessibilityLabel("Search calendars")
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName:"xmark.circle.fill").foregroundStyle(.tertiary) }
                        .buttonStyle(.plain).accessibilityLabel("Clear search")
                }
            }.padding(7).background(Color.primary.opacity(0.045),in:RoundedRectangle(cornerRadius:6))
            Group {
            if sections.isEmpty {
                Text("No matching calendars").appFont(size:11).foregroundStyle(.secondary)
                    .frame(maxWidth:.infinity).padding(.vertical,18)
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.vertical) {
                        LazyVStack(spacing:0,pinnedViews:[.sectionHeaders]) {
                            ForEach(sections) { section in
                                Section {
                                    if expanded(section.account) {
                                        ForEach(section.sources) { source in calendarRow(source).id(source.id) }
                                    }
                                } header: { accountHeader(section) }
                            }
                        }
                    }
                        .onChange(of:scrollTarget) { _,id in if let id { proxy.scrollTo(id,anchor:.center) } }
                }
            }
            }.frame(height:listHeight,alignment:.top)
        }.padding(14)
            .frame(width:min(AppTextSize.points(340),(NSScreen.main?.visibleFrame.width ?? 1000)-48))
            .background(Color(nsColor:.textBackgroundColor))
            .background(CalendarPickerKeyMonitor(handle:handleKey))
            .onAppear {
                if initialListHeight == nil { initialListHeight = openingListHeight }
                highlighted = sources.contains(where:{ $0.id == selection }) ? selection : sections.first?.sources.first?.id
                searchFocused = true
            }
            .onChange(of:query) { _,_ in
                searchCollapsedAccounts = []
                highlighted = sections.flatMap(\.sources).first?.id
            }
    }
    private func accountHeader(_ section: CalendarPickerAccount) -> some View {
        Button {
            if searching {
                if searchCollapsedAccounts.contains(section.account) { searchCollapsedAccounts.remove(section.account) }
                else { searchCollapsedAccounts.insert(section.account) }
            } else {
                if collapsedAccounts.contains(section.account) { collapsedAccounts.remove(section.account) }
                else { collapsedAccounts.insert(section.account) }
            }
            highlighted = sections.filter { expanded($0.account) }.flatMap(\.sources).first?.id
        } label: {
            HStack(spacing:6) {
                Image(systemName:"chevron.right").appFont(size:7,weight:.semibold)
                    .rotationEffect(.degrees(expanded(section.account) ? 90 : 0))
                Text(section.title).appFont(size:10,weight:.medium).lineLimit(1)
                Spacer(minLength:4)
                Text("\(section.sources.count)").appFont(size:9).monospacedDigit()
            }.foregroundStyle(.secondary).padding(.horizontal,5)
                .frame(maxWidth:.infinity).frame(height:AppTextSize.points(32)).contentShape(Rectangle())
        }.buttonStyle(.plain).background(Color(nsColor:.textBackgroundColor))
            .accessibilityLabel(section.title+", \(section.sources.count) calendars")
            .accessibilityValue(expanded(section.account) ? "Expanded" : "Collapsed")
            .appHelp(section.title)
    }
    private func calendarRow(_ source: CalendarSource) -> some View {
        Button { onChoose(source.id) } label: {
            HStack(spacing:8) {
                Circle().fill(Color(nsColor:source.color)).frame(width:AppTextSize.points(8),height:AppTextSize.points(8))
                    .overlay { Circle().strokeBorder(Color.primary.opacity(0.08),lineWidth:0.5) }
                Text(source.title).appFont(size:12,weight:source.id == selection ? .medium : .regular).lineLimit(1)
                Spacer(minLength:4)
                Image(systemName:"checkmark").appFont(size:9,weight:.semibold).opacity(source.id == selection ? 1 : 0)
            }.padding(.horizontal,7).frame(maxWidth:.infinity).frame(height:AppTextSize.points(28))
                .background(highlighted == source.id ? Color.primary.opacity(0.07) : (source.id == selection ? Color(nsColor:source.color).opacity(0.06) : .clear),in:RoundedRectangle(cornerRadius:5))
                .contentShape(Rectangle())
        }.buttonStyle(.plain).onHover { hovering in if hovering { highlighted = source.id } }
            .accessibilityLabel(source.title+", "+source.account)
            .accessibilityAddTraits(source.id == selection ? .isSelected : [])
            .appHelp(source.title+" · "+source.account)
    }
    private func handleKey(_ key: UInt16) -> Bool {
        if key == 53 { onCancel(); return true }
        let options = sections.flatMap(\.sources)
        guard !options.isEmpty else { return key == 36 || key == 76 }
        if key == 36 || key == 76 {
            let visible = sections.filter { expanded($0.account) }.flatMap(\.sources)
            if let source = visible.first(where:{ $0.id == highlighted }) ?? visible.first { onChoose(source.id) }
            return true
        }
        guard key == 125 || key == 126 else { return false }
        let index = options.firstIndex(where:{ $0.id == highlighted }) ?? (key == 125 ? -1 : 0)
        let next = options[(index+(key == 125 ? 1 : -1)+options.count)%options.count]
        if searching { searchCollapsedAccounts.remove(next.account) } else { collapsedAccounts.remove(next.account) }
        highlighted = next.id
        scrollTarget = next.id
        return true
    }
}

private struct CalendarPickerKeyMonitor: NSViewRepresentable {
    var handle: (UInt16) -> Bool
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> NSView { NSView() }
    func updateNSView(_ view: NSView, context: Context) {
        context.coordinator.handle = handle
        guard context.coordinator.monitor == nil else { return }
        context.coordinator.monitor = NSEvent.addLocalMonitorForEvents(matching:.keyDown) { [weak view, weak coordinator = context.coordinator] event in
            guard let window = view?.window, event.window === window,
                  event.modifierFlags.intersection([.command,.control,.option,.shift]).isEmpty,
                  [UInt16(125),126,36,76,53].contains(event.keyCode) else { return event }
            if let editor = window.firstResponder as? NSTextView, editor.hasMarkedText() { return event }
            return coordinator?.handle?(event.keyCode) == true ? nil : event
        }
    }
    static func dismantleNSView(_ view: NSView, coordinator: Coordinator) { coordinator.stop() }
    final class Coordinator {
        var handle: ((UInt16) -> Bool)?
        var monitor: Any?
        func stop() { if let monitor { NSEvent.removeMonitor(monitor) }; monitor = nil }
        deinit { stop() }
    }
}
