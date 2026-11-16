import SwiftUI
import AppKit

// Numeric dates deliberately use month/day, independent of system locale.
// Missing years use the current year; the picker always previews the full date.
enum DateJumpParser {
    private static let whitespace = try! NSRegularExpression(pattern:"\\s+")
    private static let formats = [
        #"^(\d{4})[/-](\d{1,2})[/-](\d{1,2})$"#,
        #"^(\d{1,2})[/-](\d{1,2})(?:[/-](\d{4}|\d{2}))?$"#,
        #"^([a-z]+)\s*(\d{1,2})(?:st|nd|rd|th)?(?:[ /-]+(\d{4}|\d{2}))?$"#,
        #"^(\d{1,2})(?:st|nd|rd|th)?\s*([a-z]+)(?:[ /-]+(\d{4}|\d{2}))?$"#
    ].map { try! NSRegularExpression(pattern:$0) }
    private static let months: [String:Int] = {
        let names = ["january","february","march","april","may","june","july","august","september","october","november","december"]
        var values = ["sept":9]
        for (index,name) in names.enumerated() { values[name] = index+1; values[String(name.prefix(3))] = index+1 }
        return values
    }()
    static func parse(_ input: String, reference: Date = Date(), calendar: Calendar = .current) -> Date? {
        guard !input.isEmpty, input.utf16.count <= 128 else { return nil }
        let normalized = input.lowercased().replacingOccurrences(of:",",with:" ").replacingOccurrences(of:".",with:" ")
        let text = whitespace.stringByReplacingMatches(in:normalized,range:NSRange(normalized.startIndex...,in:normalized),withTemplate:" ").trimmingCharacters(in:.whitespacesAndNewlines)
        let relative = ["today":0,"tomorrow":1,"yesterday":-1]
        if let days = relative[text] { return calendar.date(byAdding:.day,value:days,to:calendar.startOfDay(for:reference)) }
        let currentYear = calendar.component(.year,from:reference)
        func captures(_ index: Int) -> [String]? {
            guard let match = formats[index].firstMatch(in:text,range:NSRange(text.startIndex...,in:text)) else { return nil }
            return (1..<match.numberOfRanges).map { Range(match.range(at:$0),in:text).map { String(text[$0]) } ?? "" }
        }
        func date(month: Int, day: Int, year: String = "") -> Date? {
            var yearValue = year.isEmpty ? currentYear : (Int(year) ?? 0)
            if year.count == 2 { yearValue += 2000 }
            guard (1...9999).contains(yearValue), (1...12).contains(month), (1...31).contains(day),
                  let result = calendar.date(from:DateComponents(year:yearValue,month:month,day:day)),
                  calendar.component(.year,from:result) == yearValue,
                  calendar.component(.month,from:result) == month,
                  calendar.component(.day,from:result) == day else { return nil }
            return calendar.startOfDay(for:result)
        }
        if let parts = captures(0) {
            return date(month:Int(parts[1])!,day:Int(parts[2])!,year:parts[0])
        }
        if let parts = captures(1) {
            return date(month:Int(parts[0])!,day:Int(parts[1])!,year:parts[2])
        }
        if let parts = captures(2), let number = months[parts[0]] {
            return date(month:number,day:Int(parts[1])!,year:parts[2])
        }
        if let parts = captures(3), let number = months[parts[1]] {
            return date(month:number,day:Int(parts[0])!,year:parts[2])
        }
        return nil
    }
}


@MainActor final class DateJumpSession: ObservableObject {
    @Published var query = "" { didSet { if query != oldValue { result = DateJumpParser.parse(query,reference:reference,calendar:calendar) } } }
    @Published private(set) var result: Date?
    @Published private(set) var generation = UUID()
    private(set) var calendar = Calendar.current
    private(set) var reference = Date()
    func reset(calendar: Calendar, reference: Date = Date()) {
        self.calendar = calendar; self.reference = reference
        query = ""; result = nil; generation = UUID()
    }
}

struct DateJumpPicker: View {
    @ObservedObject var session: DateJumpSession
    var choose: (Date) -> Void
    var cancel: () -> Void
    @FocusState private var focused: Bool
    var body: some View {
        VStack(alignment:.leading,spacing:0) {
            HStack(spacing:7) {
                Image(systemName:"calendar").foregroundStyle(Color.accentColor)
                Text("Jump to date").fontWeight(.medium)
                Spacer()
                Text("esc").appFont(size:9).foregroundStyle(.tertiary)
                    .padding(.horizontal,5).padding(.vertical,2)
                    .overlay(RoundedRectangle(cornerRadius:4).strokeBorder(Color.primary.opacity(0.09),lineWidth:0.5))
            }.appFont(size:11).foregroundStyle(.secondary).padding(.bottom,12)
            HStack(spacing:10) {
                Image(systemName:"magnifyingglass").appFont(size:17).foregroundStyle(.tertiary)
                TextField("Go to a date…",text:$session.query).textFieldStyle(.plain)
                    .appFont(size:21,weight:.medium).focused($focused)
                    .accessibilityLabel("Date to jump to")
                    .onSubmit { if let date = session.result { choose(date) } }
            }.padding(.bottom,14)
            Rectangle().fill(Color.primary.opacity(0.07)).frame(height:0.5)
            Group {
                if let date = session.result {
                    Button { choose(date) } label: {
                        HStack(spacing:12) {
                            VStack(spacing:1) {
                                Text(CalendarDateFormatting.string(date,timeZone:session.calendar.timeZone,format:"MMM").uppercased()).appFont(size:8,weight:.semibold)
                                Text(String(session.calendar.component(.day,from:date))).appFont(size:19,weight:.semibold)
                            }.foregroundStyle(Color.accentColor).frame(width:42,height:43)
                                .background(Color.accentColor.opacity(0.09),in:RoundedRectangle(cornerRadius:8))
                            VStack(alignment:.leading,spacing:3) {
                                Text(CalendarDateFormatting.string(date,timeZone:session.calendar.timeZone,format:"EEEE, MMMM d, yyyy")).appFont(size:12,weight:.medium)
                                Text("Jump to this date").appFont(size:10).foregroundStyle(.secondary)
                            }
                            Spacer(minLength:3)
                            Image(systemName:"return").appFont(size:12).foregroundStyle(.secondary)
                        }.contentShape(Rectangle())
                    }.buttonStyle(.plain)
                } else if session.query.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty {
                    HStack(spacing:8) {
                        quickDate("Today",days:0)
                        quickDate("Tomorrow",days:1)
                        Spacer(minLength:0)
                    }
                } else {
                    Label("Try a date like Dec 11 or 12/11/2027",systemImage:"calendar.badge.exclamationmark")
                        .appFont(size:11).foregroundStyle(.secondary)
                }
            }.frame(height:64,alignment:.center)
            HStack {
                Text("12/11 · dec11 · December 11").appFont(size:10).foregroundStyle(.tertiary)
                Spacer()
                Text("Month/day · \(String(session.calendar.component(.year,from:session.reference)))").appFont(size:9).foregroundStyle(.tertiary)
            }
        }.padding(18)
            .frame(width:AppTextSize.points(440),height:AppTextSize.points(190))
            .background(Color(nsColor:.windowBackgroundColor),in:RoundedRectangle(cornerRadius:14))
            .overlay(RoundedRectangle(cornerRadius:14).strokeBorder(Color.primary.opacity(0.10),lineWidth:0.5))
            .onAppear { focused = true }
            .onChange(of:session.generation) { _,_ in focused = true }
            .onExitCommand { cancel() }
    }
    private func quickDate(_ title: String, days: Int) -> some View {
        Button {
            if let date = session.calendar.date(byAdding:.day,value:days,to:session.calendar.startOfDay(for:session.reference)) { choose(date) }
        } label: {
            Text(title).appFont(size:11,weight:.medium).padding(.horizontal,11).padding(.vertical,7)
                .background(Color.primary.opacity(0.045),in:RoundedRectangle(cornerRadius:7))
        }.buttonStyle(.plain)
    }
}

private final class DateJumpPanel: NSPanel {
    var cancel: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { cancel?() }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.keyCode == 53 || (event.charactersIgnoringModifiers?.lowercased() == "k" && event.modifierFlags.intersection([.command,.shift,.control,.option]) == .command) { cancel?(); return true }
        return super.performKeyEquivalent(with:event)
    }
}

@MainActor final class DateJumpPresenter: NSObject, NSWindowDelegate {
    static let shared = DateJumpPresenter()
    let session = DateJumpSession()
    private(set) var panel: NSPanel?
    private var hosting: NSHostingView<AnyView>?
    private var outsideMonitor: Any?
    private weak var model: CalendarModel?
    private weak var parent: NSWindow?
    var isPresented: Bool { panel?.isVisible == true }
    func prepare() {
        guard panel == nil else { return }
        let panel = DateJumpPanel(contentRect:.zero,styleMask:[.borderless],backing:.buffered,defer:false)
        panel.isReleasedWhenClosed = false; panel.isOpaque = false; panel.backgroundColor = .clear
        panel.hasShadow = true; panel.level = .floating; panel.hidesOnDeactivate = true
        panel.delegate = self; panel.cancel = { [weak self] in self?.dismiss() }
        let hosting = NSHostingView(rootView:AnyView(DateJumpPicker(session:session,choose:{ [weak self] in self?.choose($0) },cancel:{ [weak self] in self?.dismiss() })))
        hosting.sizingOptions = []
        let size = CGSize(width:AppTextSize.points(440),height:AppTextSize.points(190))
        hosting.frame = NSRect(origin:.zero,size:size)
        panel.contentView = hosting; panel.setContentSize(size)
        self.panel = panel; self.hosting = hosting
        // Build the tiny view and parser once, before the first invocation.
        _ = DateJumpParser.parse("12/11")
        hosting.layoutSubtreeIfNeeded()
    }
    func show(model: CalendarModel, parent: NSWindow) {
        prepare()
        guard let panel else { return }
        if panel.isVisible { dismiss(); return }
        self.model = model; self.parent = parent
        session.reset(calendar:model.calendar)
        let size = CGSize(width:AppTextSize.points(440),height:AppTextSize.points(190))
        panel.setContentSize(size)
        let screen = parent.screen?.visibleFrame ?? parent.frame
        let x = min(screen.maxX-size.width-12,max(screen.minX+12,parent.frame.midX-size.width/2))
        let y = min(screen.maxY-size.height-12,max(screen.minY+12,parent.frame.maxY-min(180,parent.frame.height*0.22)-size.height))
        panel.setFrameOrigin(NSPoint(x:x,y:y))
        parent.addChildWindow(panel,ordered:.above)
        hosting?.needsLayout = true; hosting?.layoutSubtreeIfNeeded()
        panel.makeKeyAndOrderFront(nil)
        func input(in view: NSView) -> NSTextField? {
            if let field = view as? NSTextField, field.isEditable { return field }
            return view.subviews.lazy.compactMap { input(in:$0) }.first
        }
        if let view = hosting, let field = input(in:view) { panel.makeFirstResponder(field); field.selectText(nil) }
        outsideMonitor = NSEvent.addLocalMonitorForEvents(matching:[.leftMouseDown,.rightMouseDown]) { [weak self, weak panel] event in
            if event.window !== panel { self?.dismiss() }
            return event
        }
    }
    func dismiss() {
        let owner = parent
        // Clear ownership before ordering out: resign-key notifications may
        // arrive synchronously and must not re-enter dismissal.
        model = nil; parent = nil
        if let outsideMonitor { NSEvent.removeMonitor(outsideMonitor); self.outsideMonitor = nil }
        if let panel { owner?.removeChildWindow(panel); panel.orderOut(nil) }
        if NSApp.isActive { owner?.makeKey() }
    }
    func windowDidResignKey(_ notification: Notification) { if model != nil { dismiss() } }
    private func choose(_ date: Date) {
        guard let model else { return }
        dismiss()
        model.jump(to:date)
    }
}
