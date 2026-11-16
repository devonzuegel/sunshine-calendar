import AppKit
import EventKit
import SwiftUI

enum InvitationStatus: String {
    case none, unanswered, accepted, maybe, declined, delegated
    init(participant: EKParticipantStatus) {
        switch participant {
        case .pending: self = .unanswered
        case .accepted: self = .accepted
        case .tentative: self = .maybe
        case .declined: self = .declined
        case .delegated: self = .delegated
        default: self = .none
        }
    }
    var label: String {
        switch self {
        case .none: return ""
        case .unanswered: return "Unanswered"
        case .accepted: return "Accepted"
        case .maybe: return "Maybe"
        case .declined: return "Declined"
        case .delegated: return "Delegated"
        }
    }
}

struct CalendarEntry: Identifiable {
    var id: String
    var title: String
    var start: Date
    var end: Date
    var calendarID: String
    var color: NSColor
    var allDay = false
    var writable = true
    var recurring = false
    var hasGuests = false
    var invitationStatus: InvitationStatus = .none
    var notes = ""
    var location = ""
    var displayTitle: String {
        let prefix = [.maybe,.declined,.delegated].contains(invitationStatus) ? invitationStatus.label+" · " : ""
        return prefix+title
    }
}
enum CalendarReadOnlyReason: Equatable {
    case subscription
    case birthdays
    case accountAccess(String)
    case unspecified
    static func resolve(type: EKCalendarType, subscribed: Bool, account: String) -> Self {
        if type == .birthday { return .birthdays }
        if subscribed || type == .subscription { return .subscription }
        if type == .calDAV || type == .exchange { return .accountAccess(account) }
        return .unspecified
    }
    var explanation: String {
        switch self {
        case .subscription:
            return "This is a subscribed calendar: its events come from an external feed. Changes must be made at the source that publishes the feed."
        case .birthdays:
            return "These events are generated from birthdays in Contacts. To change one, edit that person’s birthday in Contacts."
        case .accountAccess(let account):
            let name = account.isEmpty ? "This account" : "The “"+account+"” account"
            return name+" gives Sunshine read-only access to this calendar. macOS doesn’t say whether this is due to sharing permissions or an account restriction. If it’s shared, check your editing permissions with the calendar’s owner in its original service."
        case .unspecified:
            return "macOS marks this calendar as read-only but doesn’t provide a more specific reason. Check its account and sharing settings in Apple Calendar."
        }
    }
}

struct CalendarSource: Identifiable {
    var id: String
    var title: String
    var account: String
    var color: NSColor
    var writable: Bool
    var readOnlyReason: CalendarReadOnlyReason? = nil
    var readOnlyTooltip: String { "Read-only calendar\n"+(readOnlyReason ?? .unspecified).explanation }
}
enum EventRepeat: String, CaseIterable, Identifiable {
    case unchanged, never, daily, weekdays, weekly, biweekly, monthly, yearly
    var id: String { rawValue }
    var label: String {
        switch self {
        case .unchanged: return "Keep existing schedule"
        case .never: return "Never"
        case .daily: return "Every day"
        case .weekdays: return "Every weekday"
        case .weekly: return "Every week"
        case .biweekly: return "Every 2 weeks"
        case .monthly: return "Every month"
        case .yearly: return "Every year"
        }
    }
    var rule: EKRecurrenceRule? {
        switch self {
        case .unchanged, .never: return nil
        case .weekdays:
            return EKRecurrenceRule(recurrenceWith:.weekly,interval:1,daysOfTheWeek:[.monday,.tuesday,.wednesday,.thursday,.friday].map { EKRecurrenceDayOfWeek($0) },daysOfTheMonth:nil,monthsOfTheYear:nil,weeksOfTheYear:nil,daysOfTheYear:nil,setPositions:nil,end:nil)
        default:
            let frequency: EKRecurrenceFrequency = self == .daily ? .daily : (self == .monthly ? .monthly : (self == .yearly ? .yearly : .weekly))
            return EKRecurrenceRule(recurrenceWith:frequency,interval:self == .biweekly ? 2 : 1,end:nil)
        }
    }
}

struct EventAttendee: Identifiable {
    let id: String
    let name: String
    let email: String?
    let response: InvitationStatus
    let isOrganizer: Bool
    let isCurrentUser: Bool
    static func email(from url: URL) -> String? {
        guard url.scheme?.lowercased() == "mailto" else { return nil }
        return String(url.absoluteString.dropFirst(7)).components(separatedBy:"?").first?.removingPercentEncoding
    }
    var responseLabel: String { isOrganizer ? "Organizer" : (response == .none ? "Unknown" : response.label) }
    var responseIcon: String {
        if isOrganizer { return "person.crop.circle" }
        switch response {
        case .accepted: return "checkmark.circle"
        case .declined: return "xmark.circle"
        case .maybe: return "questionmark.circle"
        case .unanswered: return "clock"
        default: return "person.crop.circle"
        }
    }
}

struct CalendarDateJump {
    let from: Date
    let to: Date
    let days: Int
    var progress: Double = 0
    func offsets(dayWidth: CGFloat, viewportWidth: CGFloat) -> (before: CGFloat, after: CGFloat) {
        let distance = DaySwipeMath.jumpDistance(days:days,dayWidth:dayWidth,viewportWidth:viewportWidth)
        let position = distance*CGFloat(progress)
        return (-position,distance-position)
    }
}

struct EventDraft: Identifiable {
    var id = UUID()
    var original: CalendarEntry?
    var title: String = ""
    var start = Date()
    var end = Date().addingTimeInterval(3600)
    var calendarID = ""
    var allDay = false
    var location = ""
    var notes = ""
    var url = ""
    // EventKit stores all-day ends exclusively; the editor presents the last
    // included date, matching the way people describe a multi-day event.
    func displayedEndDate(calendar: Calendar) -> Date {
        allDay ? calendar.startOfDay(for:end.addingTimeInterval(-1)) : end
    }
    mutating func setDisplayedEndDate(_ date: Date, calendar: Calendar) {
        end = allDay ? calendar.date(byAdding:.day,value:1,to:calendar.startOfDay(for:date))! : date
    }
    func hasSameContent(as other: EventDraft) -> Bool {
        title == other.title && start == other.start && end == other.end && calendarID == other.calendarID && allDay == other.allDay && location == other.location && notes == other.notes && url == other.url && timeZoneID == other.timeZoneID && repeatSchedule == other.repeatSchedule
    }
    var eventURL: URL? {
        let trimmed = url.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.rangeOfCharacter(from:.whitespacesAndNewlines) == nil else { return nil }
        let candidate = trimmed.contains(":") ? trimmed : "https://"+trimmed
        guard let parsed = URL(string:candidate), let scheme = parsed.scheme else { return nil }
        if ["http","https"].contains(scheme.lowercased()), parsed.host?.isEmpty != false { return nil }
        return parsed
    }
    var timeZoneID = TimeZone.current.identifier
    var repeatSchedule: EventRepeat = .never
}
struct EventChange {
    var entry: CalendarEntry
    var start: Date
    var end: Date
}

enum CalendarNotePreview {
    private static let cache = NSCache<NSString,NSString>()
    static func plainText(_ notes: String) -> String {
        if let saved = cache.object(forKey:notes as NSString) { return saved as String }
        // Rich-text editors commonly save a full HTML document, including a
        // doctype, metadata and CSS. None of those belong in a card preview.
        var text = notes.replacingOccurrences(of:#"(?is)<!--.*?-->"#,with:"",options:.regularExpression)
        text = text.replacingOccurrences(of:#"(?is)<!DOCTYPE\b(?:[^>"'\[]|"[^"]*"|'[^']*'|\[[\s\S]*?\])*>"#,with:"",options:.regularExpression)
        text = text.replacingOccurrences(of:#"(?is)<head\b[^>]*>.*?</head\s*>"#,with:"",options:.regularExpression)
        text = text.replacingOccurrences(of:#"(?is)<\?.*?\?>"#,with:"",options:.regularExpression)
        text = text.replacingOccurrences(of:"(?is)<(script|style)\\b[^>]*>.*?</\\1\\s*>",with:"",options:.regularExpression)
        text = text.replacingOccurrences(of:"(?i)<br\\s*/?>|</(?:p|div|li|h[1-6]|tr|blockquote)\\s*>",with:"\n",options:.regularExpression)
        text = text.replacingOccurrences(of:"(?i)</?[a-z][a-z0-9]*(?:\\s+[^<>]*|\\s*/?)>",with:"",options:.regularExpression)
        let entities = ["amp":"&","lt":"<","gt":">","quot":"\"","apos":"'","nbsp":" ","ndash":"–","mdash":"—","hellip":"…","rsquo":"’","lsquo":"‘","ldquo":"“","rdquo":"”","bull":"•"]
        let pattern = try! NSRegularExpression(pattern:"&(#x[0-9a-fA-F]+|#[0-9]+|[a-zA-Z]+);")
        for match in pattern.matches(in:text,range:NSRange(text.startIndex...,in:text)).reversed() {
            guard let range = Range(match.range,in:text), let keyRange = Range(match.range(at:1),in:text) else { continue }
            let key = String(text[keyRange])
            var replacement = entities[key]
            if key.hasPrefix("#") {
                let hex = key.hasPrefix("#x")
                if let value = UInt32(key.dropFirst(hex ? 2 : 1),radix:hex ? 16 : 10), let scalar = UnicodeScalar(value) { replacement = String(scalar) }
            }
            if let replacement { text.replaceSubrange(range,with:replacement) }
        }
        text = text.replacingOccurrences(of:"\n[ \t]*\n(?:[ \t]*\n)+",with:"\n\n",options:.regularExpression).trimmingCharacters(in:.whitespacesAndNewlines)
        if notes.range(of:"</?[a-z][^>]*>",options:[.regularExpression,.caseInsensitive]) == nil,
           let markdown = try? AttributedString(markdown:text,options:.init(interpretedSyntax:.inlineOnlyPreservingWhitespace)) {
            text = String(markdown.characters)
        }
        cache.countLimit = 500
        cache.setObject(text as NSString,forKey:notes as NSString)
        return text
    }
}

@MainActor enum EventTimeLabel {
    static func string(start: Date, end: Date, calendar: Calendar, includeDuration: Bool = true) -> String {
        func clock(_ date: Date) -> String {
            CalendarDateFormatting.string(date,timeZone:calendar.timeZone,format:calendar.component(.minute,from:date) == 0 ? "ha" : "h:mma",locale:Locale(identifier:"en_US_POSIX")).lowercased()
        }
        var first = clock(start)
        let last = clock(end)
        if (first.hasSuffix("am") && last.hasSuffix("am")) || (first.hasSuffix("pm") && last.hasSuffix("pm")) { first.removeLast(2) }
        let range = first+"–"+last
        guard includeDuration else { return range }
        let total = max(0,Int((end.timeIntervalSince(start)/60).rounded()))
        let hours = total/60, minutes = total%60
        var duration: [String] = []
        if hours > 0 { duration.append("\(hours)h") }
        if minutes > 0 { duration.append("\(minutes)m") }
        if duration.isEmpty { duration = ["<1m"] }
        return range+" · "+duration.joined(separator:" ")
    }
}

enum CalendarMath {
    static let hourHeight: CGFloat = 64
    static let defaultSnapMinutes = 5
    static func snappedMinutes(_ height: CGFloat, fine: Bool = false) -> Int {
        let step = fine ? 1 : defaultSnapMinutes
        return Int((height / hourHeight * 60 / CGFloat(step)).rounded()) * step
    }
    static func creationRange(from first: CGFloat, to last: CGFloat, fine: Bool = false) -> ClosedRange<Int> {
        let step = fine ? 1 : defaultSnapMinutes
        let a = max(0,min(1440-step,snappedMinutes(first,fine:fine)))
        let b = max(0,min(1440,snappedMinutes(last,fine:fine)))
        let lower = min(a,b), upper = max(a,b)
        return lower...min(1440,max(lower+step,upper))
    }
    static func resized(_ entry: CalendarEntry, startEdge: Bool, minutes: Int, calendar: Calendar = .current) -> EventChange {
        if entry.allDay {
            let shifted = calendar.date(byAdding:.day,value:minutes/1440,to:startEdge ? entry.start : entry.end)!
            return EventChange(entry:entry,
                start:startEdge ? min(shifted,calendar.date(byAdding:.day,value:-1,to:entry.end)!) : entry.start,
                end:startEdge ? entry.end : max(shifted,calendar.date(byAdding:.day,value:1,to:entry.start)!))
        }
        let shifted = (startEdge ? entry.start : entry.end).addingTimeInterval(Double(minutes)*60)
        return EventChange(entry:entry,start:startEdge ? min(shifted,entry.end.addingTimeInterval(-60)) : entry.start,end:startEdge ? entry.end : max(shifted,entry.start.addingTimeInterval(60)))
    }
    static func shifted(_ entries: [CalendarEntry], minutes: Int) -> [EventChange] {
        entries.map { EventChange(entry: $0, start: $0.start.addingTimeInterval(Double(minutes) * 60), end: $0.end.addingTimeInterval(Double(minutes) * 60)) }
    }
}

@MainActor final class CalendarModel: ObservableObject {
    private var persistViewChoice = false
    @Published private(set) var viewMode: CalendarViewMode = .week
    var visibleDayCount: Int { viewMode.dayCount }
    private var viewShortcutMonitor: Any?
    @discardableResult func handleViewLetter(_ letter: String, shift: Bool = false) -> Bool {
        guard draft == nil else { return false }
        let key = letter.lowercased()
        if shift {
            guard key == "w" else { return false }
            weather.enabled.toggle(); return true
        }
        let defaults = UserDefaults.standard
        switch key {
        case " ": return openSelectedEventDetails()
        case "1": setView(.day)
        case "2": setView(.twoDays)
        case "3": setView(.threeDays)
        case "4": setView(.fourDays)
        case "5": setView(.fiveDays)
        case "6": setView(.sixDays)
        case "7": setView(.week)
        case "s": defaults.set(!(defaults.object(forKey:"sidebarVisible") as? Bool ?? true),forKey:"sidebarVisible")
        case "b": defaults.set(!(defaults.object(forKey:"eventBankCollapsed") as? Bool ?? false),forKey:"eventBankCollapsed")
        case "t": today()
        case "w" where selected.isEmpty: setView(.week)
        case "m" where selected.isEmpty: setView(viewMode == .month ? .monthDetailed : .month)
        default: return false
        }
        return true
    }
    @discardableResult func openSelectedEventDetails(anchorInWindow: NSRect? = nil) -> Bool {
        guard draft == nil, !bankHasFocus, selection.count == 1, let item = selection.first else { return false }
        edit(item,anchorInWindow:anchorInWindow)
        return true
    }
    func startViewKeyboardHandling() {
        guard viewShortcutMonitor == nil else { return }
        viewShortcutMonitor = NSEvent.addLocalMonitorForEvents(matching:.keyDown) { [weak self] event in
            guard let window = event.window, window == NSApp.mainWindow,
                  window.attachedSheet == nil, window.sheetParent == nil,
                  !(window.firstResponder is NSTextView), !(window.firstResponder is NSTextField) else { return event }
            let modifiers = event.modifierFlags.intersection([.command,.control,.option,.shift])
            if let self, self.bankHasFocus, self.draft == nil {
                if modifiers == .command {
                    switch event.charactersIgnoringModifiers?.lowercased() {
                    case "c": self.copyBankTasks(); return nil
                    case "x": self.deleteBankTasks(cut:true); return nil
                    case "v": self.pasteBankTasks(); return nil
                    case "a": self.selectedBankTasks = Set(self.bank.tasks.map(\.id)); return nil
                    default: break
                    }
                }
                if modifiers.isEmpty && [51,117].contains(event.keyCode) { self.deleteBankTasks(); return nil }
                if modifiers.isEmpty && event.keyCode == 53 { self.selectedBankTasks = []; return nil }
            }
            if modifiers == .command, event.charactersIgnoringModifiers?.lowercased() == "x", self?.draft == nil, self?.selection.isEmpty == false {
                self?.cutSelectedEvents(); return nil
            }
            // The native canvas supplies the selected card's popover anchor.
            if modifiers.isEmpty, event.keyCode == 49, window.firstResponder is CalendarCanvas { return event }
            guard modifiers.intersection([.command,.control,.option]).isEmpty else { return event }
            return self?.handleViewLetter(event.charactersIgnoringModifiers ?? "",shift:event.modifierFlags.contains(.shift)) == true ? nil : event
        }
    }
    func setView(_ mode: CalendarViewMode) {
        guard mode != viewMode else { return }
        dateJump = nil
        viewMode = mode
        if persistViewChoice { UserDefaults.standard.set(mode.rawValue,forKey:"calendarViewMode") }
        if mode.isTimeline { firstVisibleDay = calendar.startOfDay(for:anchor) }
        selected = []; horizontalOffset = 0; trackingHorizontalScroll = false; reload()
    }
    @Published var anchor = Date()
    @Published var allDayExpanded = false
    var allDayRowCount: Int {
        let spans = AllDayLayout.spans(shown.filter(\.allDay).map { TimedInterval(id:$0.id,start:$0.start,end:$0.end) },weekStart:weekStart,calendar:calendar,dayCount:visibleDayCount)
        return (spans.map(\.row).max() ?? -1)+1
    }
    var allDayHeight: CGFloat { allDayExpanded ? AllDayTrayLayout.expandedHeight(rows:allDayRowCount) : AllDayTrayLayout.collapsedHeight(rows:allDayRowCount) }
    @Published private(set) var primaryTimeZoneID = TimeZone.current.identifier
    var primaryTimeZone: TimeZone { TimeZone(identifier:primaryTimeZoneID) ?? .current }
    var calendar: Calendar { var result = Calendar.current; result.timeZone = primaryTimeZone; return result }
    func dateLabel(_ date: Date, template: String) -> String {
        CalendarDateFormatting.string(date,timeZone:primaryTimeZone,format:template,localized:true)
    }
    func minuteOfDay(_ date: Date) -> Double {
        let parts = calendar.dateComponents([.hour,.minute,.second],from:date)
        return Double(parts.hour!*60+parts.minute!)+Double(parts.second!)/60
    }
    func dateAtMinute(_ minute: Int, on day: Date) -> Date {
        if minute >= 1440 { return calendar.date(byAdding:.day,value:1,to:calendar.startOfDay(for:day))! }
        return calendar.date(bySettingHour:max(0,minute)/60,minute:max(0,minute)%60,second:0,of:day)!
    }
    func setPrimaryTimeZone(_ identifier: String) {
        guard TimeZone(identifier:identifier) != nil, identifier != primaryTimeZoneID else { return }
        let old = primaryTimeZoneID
        let visibleDate = calendar.dateComponents([.year,.month,.day],from:firstVisibleDay)
        let selectedDate = calendar.dateComponents([.year,.month,.day],from:anchor)
        if let index = comparisonTimeZones.firstIndex(of:identifier) { comparisonTimeZones[index] = old }
        dateJump = nil
        primaryTimeZoneID = identifier
        comparisonTimeZones.removeAll { $0 == identifier }
        UserDefaults.standard.set(identifier,forKey:"primaryTimeZone")
        firstVisibleDay = calendar.date(from:visibleDate)!
        anchor = calendar.date(from:selectedDate)!
        selected = []; reload()
    }
    @discardableResult func moveTimeZone(_ identifier: String, toSlot slot: Int) -> Bool {
        guard (0...comparisonTimeZones.count).contains(slot),
              identifier == primaryTimeZoneID || comparisonTimeZones.contains(identifier) else { return false }
        if slot == 0 { setPrimaryTimeZone(identifier) }
        else if identifier == primaryTimeZoneID { setPrimaryTimeZone(comparisonTimeZones[slot-1]) }
        else { setComparisonZone(identifier,at:slot-1) }
        return true
    }
    func setComparisonZone(_ identifier: String?, at slot: Int) {
        guard (0..<2).contains(slot) else { return }
        if let identifier {
            guard TimeZone(identifier:identifier) != nil, identifier != primaryTimeZoneID else { return }
            if let existing = comparisonTimeZones.firstIndex(of:identifier), existing != slot {
                if slot < comparisonTimeZones.count { comparisonTimeZones.swapAt(existing,slot) }
                return
            }
            if slot < comparisonTimeZones.count { comparisonTimeZones[slot] = identifier }
            else { comparisonTimeZones.append(identifier) }
        } else if slot < comparisonTimeZones.count { comparisonTimeZones.remove(at:slot) }
    }
    @Published var horizontalOffset: CGFloat = 0
    @Published var trackingHorizontalScroll = false
    @Published var comparisonTimeZones: [String] = [] {
        didSet { UserDefaults.standard.set(comparisonTimeZones,forKey:"comparisonTimeZones") }
    }
    static var timeColumnWidth: CGFloat { AppTextSize.points(34) }
    static var timeRibbonGap: CGFloat { AppTextSize.points(4) }
    var timeGutterWidth: CGFloat { CGFloat(1+comparisonTimeZones.count)*Self.timeColumnWidth+Self.timeRibbonGap }
    var clockZones: [TimeZone] { comparisonTimeZones.compactMap(TimeZone.init(identifier:)) + [primaryTimeZone] }
    func toggleComparisonZone(_ identifier: String) {
        if comparisonTimeZones.contains(identifier) { comparisonTimeZones.removeAll { $0 == identifier } }
        else if comparisonTimeZones.count < 2 && identifier != primaryTimeZoneID { comparisonTimeZones.append(identifier) }
    }
    static func zoneLabel(_ zone: TimeZone) -> String {
        switch zone.identifier {
        case "America/New_York": return "Miami"
        case "America/Los_Angeles": return "SF"
        case "America/Argentina/Buenos_Aires", "America/Buenos_Aires": return "BA"
        case "America/Denver": return "MT"
        case "America/Chicago": return "CT"
        default: return zone.identifier.split(separator:"/").last.map(String.init)?.replacingOccurrences(of:"_",with:" ") ?? zone.identifier
        }
    }
    @Published private(set) var firstVisibleDay = Calendar.current.dateInterval(of:.weekOfYear,for:Date())!.start
    @Published var entries: [CalendarEntry] = []
    @Published var sources: [CalendarSource] = []
    @Published var visible: Set<String> = []
    @Published private(set) var calendarsHidden = false
    @Published var selected: Set<String> = []
    @Published private(set) var creationCalendarID: String?
    @Published var live = false
    @Published var connecting = false
    @Published var message: String?
    @Published var draft: EventDraft?
    var editorAnchorInWindow: NSRect?
    @Published var status = "Sample calendars · Changes stay in this preview"
    @Published private(set) var lastCalendarRefresh: Date?
    @Published private(set) var calendarRefreshSummary: String?
    private var refreshBaseline: (range: DateInterval, events: [String: CalendarEntry])?
    @Published private(set) var deletionAnimationID = 0
    @Published private(set) var undoHistory: [CalendarAction] = []
    @Published private(set) var redoHistory: [CalendarAction] = []
    private var historyHandles: [String: EventHandle] = [:]
    private var bankHistoryHandles: [UUID: BankHistoryHandle] = [:]
    lazy var eventUndoManager: CalendarUndoManager = { let manager = CalendarUndoManager(); manager.model = self; return manager }()
    var canUndo: Bool { !undoHistory.isEmpty }
    var canRedo: Bool { !redoHistory.isEmpty }
    var undoTitle: String { undoHistory.last.map { "Undo " + $0.name } ?? "Undo" }
    var redoTitle: String { redoHistory.last.map { "Redo " + $0.name } ?? "Redo" }
    var restoredScrollY: CGFloat?
    let daylight = DaylightLocation()
    let weather = WeatherOverlay()
    let store = EKEventStore()
    let bank: EventBankStore
    private var observer: NSObjectProtocol?
    private var sampleEntries: [CalendarEntry] = []
    private var sampleDetails: [String: EventDraft] = [:]
    private var ekEvents: [String: EKEvent] = [:]
    private var knownSources: Set<String> = []
    private var restoredCalendarVisibility = false
    var monthScrollRange: (start: Date, end: Date)?
    func loadMonthScrollRange(start: Date, end: Date) {
        monthScrollRange = (start,end)
        reload()
    }
    private var eventRangeStart: Date { !viewMode.isTimeline && viewMode != .year ? monthScrollRange?.start ?? weekStart : weekStart }
    private var eventRangeEnd: Date { !viewMode.isTimeline && viewMode != .year ? monthScrollRange?.end ?? weekEnd : weekEnd }
    var weekStart: Date {
        if viewMode == .year { return calendar.dateInterval(of:.year,for:anchor)!.start }
        if !viewMode.isTimeline { return CalendarViewDates.monthGridStart(anchor,calendar:calendar) }
        return firstVisibleDay
    }
    var weekEnd: Date {
        if viewMode == .year { return calendar.date(byAdding:.year,value:1,to:weekStart)! }
        return calendar.date(byAdding:.day,value:viewMode.isTimeline ? visibleDayCount : 42,to:weekStart)!
    }
    var shown: [CalendarEntry] {
        guard !calendarsHidden else { return [] }
        let activeIDs = Set(sources.filter { !$0.title.hasPrefix("- ") }.map(\.id))
        return entries.filter { visible.contains($0.calendarID) && activeIDs.contains($0.calendarID) }
    }
    var selection: [CalendarEntry] { shown.filter { selected.contains($0.id) } }

    init(bank: EventBankStore? = nil, reconnectIfAuthorized: Bool = true) {
        self.bank = bank ?? EventBankStore()
        persistViewChoice = reconnectIfAuthorized
        if reconnectIfAuthorized {
            lastCalendarRefresh = UserDefaults.standard.object(forKey:"lastSuccessfulCalendarRefresh") as? Date
            calendarsHidden = UserDefaults.standard.bool(forKey:"allCalendarsHidden")
            if let saved = UserDefaults.standard.string(forKey:"calendarViewMode"), let mode = CalendarViewMode(rawValue:saved == "monthCompact" ? "month" : saved) { viewMode = mode }
            if let saved = UserDefaults.standard.string(forKey:"primaryTimeZone"), TimeZone(identifier:saved) != nil { primaryTimeZoneID = saved }
            firstVisibleDay = calendar.dateInterval(of:.weekOfYear,for:Date())!.start
            comparisonTimeZones = Array((UserDefaults.standard.stringArray(forKey:"comparisonTimeZones") ?? []).filter { TimeZone(identifier:$0) != nil && $0 != primaryTimeZoneID }.reduce(into:[String]()) { if !$0.contains($1) { $0.append($1) } }.prefix(2))
        }
        if reconnectIfAuthorized && UserDefaults.standard.bool(forKey:"restoreAfterRestart") {
            let preferences = UserDefaults.standard
            if let date = preferences.object(forKey:"restartVisibleDay") as? Date {
                firstVisibleDay = calendar.startOfDay(for:date); anchor = date
            }
            restoredScrollY = CGFloat(preferences.double(forKey:"restartScrollY"))
            preferences.removeObject(forKey:"restoreAfterRestart")
            preferences.removeObject(forKey:"restartVisibleDay")
            preferences.removeObject(forKey:"restartScrollY")
        }
        sources = [CalendarSource(id: "work", title: "Work", account: "Preview", color: .systemBlue, writable: true), CalendarSource(id: "personal", title: "Personal", account: "Preview", color: .systemPurple, writable: true), CalendarSource(id: "shared", title: "Subscribed calendar", account: "Preview", color: .systemOrange, writable: false,readOnlyReason:.subscription)]
        visible = Set(sources.map(\.id))
        knownSources = visible
        let today = calendar.startOfDay(for: Date())
        func date(_ day: Int, _ hour: Int) -> Date { calendar.date(byAdding: .hour, value: hour, to: calendar.date(byAdding: .day, value: day, to: today)!)! }
        sampleEntries = [
            CalendarEntry(id: "one", title: "Project time", start: date(0,13), end: date(0,14), calendarID: "work", color: .systemBlue),
            CalendarEntry(id: "two", title: "Planning", start: date(0,14), end: date(0,15), calendarID: "work", color: .systemBlue),
            CalendarEntry(id: "three", title: "Morning walk", start: date(0,9), end: date(0,10), calendarID: "personal", color: .systemPurple),
            CalendarEntry(id: "four", title: "Community event", start: date(-1,11), end: date(-1,12), calendarID: "shared", color: .systemOrange, writable: false)
        ]
        reload()
        self.bank.onHistoryChange = { [weak self] name, before, after in
            self?.recordBank(name, before:before, after:after)
        }
        observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            Task { @MainActor in if self?.live == true { self?.reload() } }
        }
        if reconnectIfAuthorized && EKEventStore.authorizationStatus(for:.event) == .fullAccess {
            live = true; knownSources = []; visible = []; reload()
        }
    }
    func connect() {
        guard !connecting else { return }
        connecting = true
        Task {
            do {
                let allowed: Bool
                if EKEventStore.authorizationStatus(for:.event) == .fullAccess { allowed = true }
                else { allowed = try await store.requestFullAccessToEvents() }
                guard allowed else {
                    connecting = false
                    message = "Calendar access wasn’t granted. You can enable full access for Sunshine Calendar in System Settings → Privacy & Security → Calendars."
                    return
                }
                selected = []; clearHistory()
                knownSources = []; visible = []
                live = true; connecting = false
                reload()
            } catch { connecting = false; message = error.localizedDescription }
        }
    }
    private func key(_ event: EKEvent) -> String {
        "\(event.calendarItemIdentifier)|\(event.startDate.timeIntervalSince1970)"
    }
    private func entry(_ event: EKEvent) -> CalendarEntry {
        CalendarEntry(id: key(event), title: event.title ?? "Untitled", start: event.startDate, end: event.endDate, calendarID: event.calendar.calendarIdentifier, color: NSColor(cgColor: event.calendar.cgColor) ?? .systemBlue, allDay: event.isAllDay, writable: event.calendar.allowsContentModifications, recurring: event.hasRecurrenceRules || event.isDetached, hasGuests: !(event.attendees ?? []).isEmpty,invitationStatus:event.organizer?.isCurrentUser == true ? .none : event.attendees?.first(where:{ $0.isCurrentUser }).map { InvitationStatus(participant:$0.participantStatus) } ?? .none,notes:event.notes ?? "",location:event.location ?? event.structuredLocation?.title ?? "")
    }
    func scrollPreviewEntries(start: Date) -> [CalendarEntry] {
        guard !calendarsHidden else { return [] }
        let end = calendar.date(byAdding:.day,value:visibleDayCount,to:start)!
        if !live { return sampleEntries.filter { visible.contains($0.calendarID) && $0.start < end && $0.end > start } }
        let calendars = store.calendars(for:.event).filter { visible.contains($0.calendarIdentifier) && !$0.title.hasPrefix("- ") }
        guard !calendars.isEmpty else { return [] }
        return store.events(matching:store.predicateForEvents(withStart:start,end:end,calendars:calendars)).map(entry)
    }
    func reload() {
        if live {
            guard EKEventStore.authorizationStatus(for:.event) == .fullAccess else {
                live = false; entries = []; selected = []; status = "Calendar access unavailable"; return
            }
            let calendars = store.calendars(for:.event).filter { !$0.title.hasPrefix("- ") }
            sources = calendars.map { CalendarSource(id: $0.calendarIdentifier, title: $0.title, account: $0.source.title, color: NSColor(cgColor: $0.cgColor) ?? .systemBlue, writable: $0.allowsContentModifications,readOnlyReason:$0.allowsContentModifications ? nil : CalendarReadOnlyReason.resolve(type:$0.type,subscribed:$0.isSubscribed,account:$0.source.title)) }.sorted { ($0.account, $0.title) < ($1.account, $1.title) }
            let ids = Set(sources.map(\.id))
            if !restoredCalendarVisibility {
                if let saved = UserDefaults.standard.stringArray(forKey:"visibleCalendarIDs") { visible = Set(saved).intersection(ids) }
                else { visible = ids }
                knownSources = ids
                restoredCalendarVisibility = true
            }
            visible.formUnion(ids.subtracting(knownSources)); visible.formIntersection(ids); knownSources = ids
            let events: [EKEvent] = calendars.isEmpty ? [] : store.events(matching:store.predicateForEvents(withStart:eventRangeStart,end:eventRangeEnd,calendars:calendars))
            ekEvents = Dictionary(events.map { (key($0), $0) }, uniquingKeysWith: { a, _ in a })
            entries = events.map(entry)
            let range = DateInterval(start:eventRangeStart,end:eventRangeEnd)
            let current = Dictionary(events.map { event in
                // Ordinary events retain their identity when moved to a new time.
                let identity = event.hasRecurrenceRules || event.isDetached ? key(event) : event.calendarItemIdentifier
                return (identity,entry(event))
            },uniquingKeysWith:{ first,_ in first })
            var summary = "\(current.count) events read in the loaded date range"
            if let previous = refreshBaseline, previous.range == range {
                let added = current.keys.filter { previous.events[$0] == nil }.count
                let removed = previous.events.keys.filter { current[$0] == nil }.count
                let changed = current.filter { identity,item in
                    guard let old = previous.events[identity] else { return false }
                    return item.title != old.title || item.start != old.start || item.end != old.end
                        || item.calendarID != old.calendarID || item.notes != old.notes || item.location != old.location
                        || item.allDay != old.allDay || item.recurring != old.recurring || item.hasGuests != old.hasGuests
                        || item.invitationStatus != old.invitationStatus || item.writable != old.writable || item.color != old.color
                }.count
                summary += added+removed+changed == 0 ? " · No changes since the previous refresh" : " · \(added) added · \(changed) updated · \(removed) removed since the previous refresh"
            }
            refreshBaseline = (range,current)
            calendarRefreshSummary = summary
            UserDefaults.standard.set(Array(visible),forKey:"visibleCalendarIDs")
            lastCalendarRefresh = Date()
            UserDefaults.standard.set(lastCalendarRefresh,forKey:"lastSuccessfulCalendarRefresh")
            status = "Connected to calendars on this Mac"
        } else {
            entries = sampleEntries.filter { $0.start < eventRangeEnd && $0.end > eventRangeStart }
        }
        selected.formIntersection(Set(shown.map(\.id)))
    }
    func navigate(_ steps: Int) {
        if viewMode.isTimeline { navigateDays(steps*visibleDayCount) }
        else { jump(to:calendar.date(byAdding:viewMode == .year ? .year : .month,value:steps,to:anchor)!) }
    }
    func navigateDays(_ days: Int) {
        guard days != 0 else { return }
        jump(to:calendar.date(byAdding:.day,value:days,to:firstVisibleDay)!)
    }
    @Published var dateJump: CalendarDateJump?
    @Published private(set) var navigationDayDelta = 0
    func jump(to date: Date) {
        navigationDayDelta = calendar.dateComponents([.day],from:weekStart,to:calendar.startOfDay(for:date)).day ?? 0
        if viewMode.isTimeline, navigationDayDelta != 0, !trackingHorizontalScroll, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            dateJump = CalendarDateJump(from:weekStart,to:calendar.startOfDay(for:date),days:navigationDayDelta)
        } else if trackingHorizontalScroll || !viewMode.isTimeline || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion || dateJump?.to != calendar.startOfDay(for:date) {
            dateJump = nil
        }
        firstVisibleDay = calendar.startOfDay(for:date)
        anchor = date
        selected = []
        reload()
    }
    func today() { jump(to:Date()) }
    func calendarIDs(in account: String) -> Set<String> {
        Set(sources.filter { $0.account == account && !$0.title.hasPrefix("- ") }.map(\.id))
    }
    func toggleCalendarGroup(_ account: String) {
        let ids = calendarIDs(in:account)
        guard !ids.isEmpty else { return }
        if ids.isSubset(of:visible) { visible.subtract(ids) }
        else { visible.formUnion(ids) }
        if live { UserDefaults.standard.set(Array(visible),forKey:"visibleCalendarIDs") }
        selected.formIntersection(Set(shown.map(\.id)))
    }
    func toggleAllCalendarsHidden() {
        calendarsHidden.toggle()
        if persistViewChoice { UserDefaults.standard.set(calendarsHidden,forKey:"allCalendarsHidden") }
        selected.formIntersection(Set(shown.map(\.id)))
    }
    func toggle(_ id: String) {
        guard sources.contains(where:{ $0.id == id && !$0.title.hasPrefix("- ") }) else { return }
        if visible.contains(id) { visible.remove(id) } else { visible.insert(id) }
        if live { UserDefaults.standard.set(Array(visible),forKey:"visibleCalendarIDs") }
        selected.formIntersection(Set(shown.map(\.id)))
    }
    var creationCalendar: CalendarSource? {
        let editable = sources.filter { $0.writable && !$0.title.hasPrefix("- ") }
        return editable.first(where:{ $0.id == creationCalendarID })
            ?? editable.first(where:{ visible.contains($0.id) }) ?? editable.first
    }
    @Published var selectedBankTasks: Set<UUID> = []
    var bankHasFocus = false
    var bankDragIDs: [UUID] = []
    private static let bankClipboardType = NSPasteboard.PasteboardType("com.devon.calendarstudio.bank-clipboard")
    func selectBankTask(_ id: UUID, extending: Bool) {
        bankHasFocus = true; selected = []
        NSApp.keyWindow?.makeFirstResponder(nil)
        if extending {
            if selectedBankTasks.contains(id) { selectedBankTasks.remove(id) } else { selectedBankTasks.insert(id) }
        } else if !selectedBankTasks.contains(id) { selectedBankTasks = [id] }
        if let task = bank.records[id], let source = calendar(for:task) { creationCalendarID = source.id }
    }
    func beginBankDrag(_ id: UUID) -> NSItemProvider {
        if !selectedBankTasks.contains(id) { selectBankTask(id,extending:false) }
        bankDragIDs = bank.tasks.filter { selectedBankTasks.contains($0.id) }.map(\.id)
        return BankDrag.provider(for:id)
    }
    func bankDragTasks(_ id: UUID) -> [BankTask] {
        let ids = bankDragIDs.contains(id) ? bankDragIDs : [id]
        return ids.compactMap { bank.records[$0] }.filter { $0.state == .pending }
    }
    private func combineBankActions(since index: Int, name: String) {
        guard undoHistory.count > index else { return }
        let actions = Array(undoHistory[index...])
        undoHistory.removeSubrange(index...)
        undoHistory.append(CalendarAction(name:name,changes:actions.flatMap(\.changes),bankChanges:actions.flatMap(\.bankChanges)))
    }
    func reorderBankTasks(_ id: UUID, before target: UUID?, categoryID: UUID? = nil) throws {
        let tasks = bankDragTasks(id)
        guard !tasks.contains(where:{ $0.id == target }) else { return }
        let index = undoHistory.count
        defer { combineBankActions(since:index,name:"Reorder Bank Tasks") }
        for task in tasks { try bank.reorder(task.id,before:target,categoryID:categoryID) }
    }
    func moveSelectedBankTasks(to categoryID: UUID) throws {
        let tasks = bank.tasks.filter { selectedBankTasks.contains($0.id) }
        let index = undoHistory.count
        defer { combineBankActions(since:index,name:"Move Bank Tasks") }
        for task in tasks { try bank.reorder(task.id,before:nil,categoryID:categoryID) }
    }
    func scheduleBankTasks(_ id: UUID, at date: Date) -> Bool {
        let tasks = bankDragTasks(id)
        guard !tasks.isEmpty, tasks.allSatisfy({ canScheduleBankTask($0.id) }) else {
            message = "Choose an available editable calendar for every selected task."; return false
        }
        let index = undoHistory.count
        var start = date; var count = 0
        for task in tasks {
            guard scheduleBankTask(task.id,at:start) else { break }
            count += 1; start = start.addingTimeInterval(Double(task.minutes)*60)
        }
        combineBankActions(since:index,name:"Schedule Bank Tasks")
        selectedBankTasks.subtract(tasks.prefix(count).map(\.id)); bankDragIDs = []
        if count > 0 { bankHasFocus = false }
        if count < tasks.count { message = "Scheduled \(count) of \(tasks.count) tasks. The others remain in the bank. Undo restores the scheduled tasks together." }
        return count > 0
    }
    @discardableResult func copyBankTasks(pasteboard: NSPasteboard = .general) -> Bool {
        let tasks = bank.tasks.filter { selectedBankTasks.contains($0.id) }
        guard !tasks.isEmpty, let data = try? JSONEncoder().encode(tasks) else { return false }
        pasteboard.clearContents()
        guard pasteboard.setData(data,forType:Self.bankClipboardType) else {
            message = "Couldn’t copy tasks to the clipboard. Nothing was removed."; return false
        }
        pasteboard.setString(tasks.map { $0.title+" · "+BankTask.durationLabel($0.minutes) }.joined(separator:"\n"),forType:.string)
        return true
    }
    func deleteBankTasks(cut: Bool = false) {
        let tasks = bank.tasks.filter { selectedBankTasks.contains($0.id) }
        guard !tasks.isEmpty else { return }
        if cut && !copyBankTasks() { return }
        let recording = bank.recordingHistory; bank.recordingHistory = false
        defer { bank.recordingHistory = recording }
        var changes: [BankRestoration] = []
        for task in tasks {
            do { try bank.remove(task.id); changes.append(bankRestoration(before:task,after:bank.records[task.id])) }
            catch { message = error.localizedDescription; break }
        }
        if !changes.isEmpty {
            undoHistory.append(CalendarAction(name:cut ? "Cut Bank Tasks" : "Delete Bank Tasks",changes:[],bankChanges:changes)); redoHistory = []
        }
        selectedBankTasks = []
    }
    func pasteBankTasks(pasteboard: NSPasteboard = .general) {
        let tasks: [BankTask]
        if let data = pasteboard.data(forType:Self.bankClipboardType), let decoded = try? JSONDecoder().decode([BankTask].self,from:data) {
            tasks = decoded
        } else if pasteboard === NSPasteboard.general, copiedPasteboardChange == pasteboard.changeCount {
            tasks = copiedEvents.compactMap { snapshot in
                guard let source = sources.first(where:{ $0.id == snapshot.entry.calendarID && $0.writable }) ?? creationCalendar else { return nil }
                return BankTask(title:snapshot.entry.title,minutes:min(10080,max(1,Int(snapshot.entry.end.timeIntervalSince(snapshot.entry.start)/60))),calendarID:source.id,calendarTitle:source.title,account:source.account,notes:snapshot.notes ?? snapshot.entry.notes)
            }
        } else { return }
        guard !tasks.isEmpty else { return }
        let recording = bank.recordingHistory; bank.recordingHistory = false
        defer { bank.recordingHistory = recording }
        var changes: [BankRestoration] = []; var ids: Set<UUID> = []
        let position = (bank.tasks.last.map { $0.position ?? $0.createdAt.timeIntervalSince1970 } ?? Date().timeIntervalSince1970)+1
        for (index,original) in tasks.enumerated() {
            var task = original
            task.id = UUID(); task.createdAt = Date(); task.updatedAt = Date(); task.revision = UUID(); task.version = 1
            task.state = .pending; task.scheduledStart = nil; task.scheduledEventID = nil; task.position = position+Double(index)
            do {
                try bank.save(task); ids.insert(task.id)
                changes.append(bankRestoration(before:nil,after:bank.records[task.id]))
            } catch { message = error.localizedDescription; break }
        }
        if !changes.isEmpty {
            undoHistory.append(CalendarAction(name:"Paste Bank Tasks",changes:[],bankChanges:changes)); redoHistory = []
            selectedBankTasks = ids
        }
    }
    func select(_ id: String, extending: Bool) {
        bankHasFocus = false; selectedBankTasks = []
        if extending { if selected.contains(id) { selected.remove(id) } else { selected.insert(id) } }
        else if !selected.contains(id) { selected = [id] }
        if selected.contains(id), let item = shown.first(where:{ $0.id == id }),
           sources.contains(where:{ $0.id == item.calendarID && $0.writable && !$0.title.hasPrefix("- ") }) {
            creationCalendarID = item.calendarID
        }
    }
    @discardableResult func deleteSelectedEvents(actionName: String? = nil) -> Bool {
        let items = selection
        guard !items.isEmpty else { return false }
        guard items.allSatisfy(\.writable) else {
            message = "Read-only calendar events can’t be deleted. Select only editable events."
            return false
        }
        do {
            var deleted: [EventSnapshot] = []
            if live {
                // Resolve and validate the full selection before staging any removals.
                var resolved: [EKEvent] = []
                for item in items {
                    let predicate = store.predicateForEvents(withStart:item.start.addingTimeInterval(-1),end:item.end.addingTimeInterval(1),calendars:nil)
                    guard let event = store.events(matching:predicate).first(where:{ key($0) == item.id }),
                          event.calendar.allowsContentModifications, event.startDate == item.start,
                          event.endDate == item.end, event.calendar.calendarIdentifier == item.calendarID,
                          event.title == item.title else {
                        throw NSError(domain:"CalendarStudio",code:5,userInfo:[NSLocalizedDescriptionKey:"An event changed or is no longer editable. Refresh and select the events again. No events were deleted."])
                    }
                    resolved.append(event)
                }
                deleted = resolved.map { EventSnapshot($0, entry:entry($0), occurrenceOnly:true) }
                for event in resolved { try store.remove(event,span:.thisEvent,commit:false) }
                try store.commit()
            } else {
                deleted = items.map { snapshot($0) }
                let ids = Set(items.map(\.id))
                sampleEntries.removeAll { ids.contains($0.id) }
            }
            record(actionName ?? ("Delete " + (items.count == 1 ? "Event" : "Events")), before:deleted, after:[])
            deletionAnimationID += 1
            selected = []; reload()
            status = "Deleted \(items.count) event\(items.count == 1 ? "" : "s") · ⌘Z to undo"
            return true
        } catch {
            store.reset(); reload()
            message = "Couldn’t delete the events. " + error.localizedDescription
            return false
        }
    }
    func resizeChange(_ event: CalendarEntry, startEdge: Bool, minutes: Int) -> EventChange {
        var floating = Calendar.current
        if let zone = ekEvents[event.id]?.timeZone { floating.timeZone = zone }
        return CalendarMath.resized(event,startEdge:startEdge,minutes:minutes,calendar:floating)
    }
    @discardableResult func resizeEvent(_ id: String, startEdge: Bool, minutes: Int) -> Bool {
        guard minutes != 0, let event = shown.first(where:{ $0.id == id }) else { return false }
        guard event.writable else { message = "Read-only events can’t be resized."; return false }
        if live && (event.recurring || event.hasGuests) {
            let alert = NSAlert(); alert.messageText = "Change this event’s duration?"
            alert.informativeText = "Only this occurrence of a repeating event will change. Events with guests may send calendar updates."
            alert.addButton(withTitle:"Save Change"); alert.addButton(withTitle:"Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return false }
        }
        let change = resizeChange(event,startEdge:startEdge,minutes:minutes)
        guard change.start != event.start || change.end != event.end else { return false }
        if apply([change], actionName:"Resize Event") != nil {
            status = "Event resized · ⌘Z to undo"; return true
        }
        return false
    }
    func move(minutes: Int) {
        guard minutes != 0, !selection.isEmpty else { return }
        guard selection.allSatisfy({ $0.writable && !$0.allDay }) else { message = "Select only editable timed events to move a group. Subscribed calendars are read-only."; return }
        if live && selection.contains(where: { $0.recurring || $0.hasGuests }) {
            let alert = NSAlert()
            alert.messageText = "Move \(selection.count) selected event\(selection.count == 1 ? "" : "s")?"
            alert.informativeText = "Only the selected occurrences of repeating events will move. Changes to events with guests may send calendar updates."
            alert.addButton(withTitle: "Move Events"); alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        if let inverse = apply(CalendarMath.shifted(selection, minutes: minutes), actionName:selection.count == 1 ? "Move Event" : "Move Events") {
            status = "Moved \(inverse.count) event\(inverse.count == 1 ? "" : "s") · ⌘Z to undo"
        }
    }
    // Validate the complete group before staging changes; commit once, reset on failure.
    private func apply(_ changes: [EventChange], actionName: String) -> [EventChange]? {
        var inverse: [EventChange] = []
        var before: [EventSnapshot] = []
        var after: [EventSnapshot] = []
        do {
            if live {
                var resolved: [(EventChange, EKEvent)] = []
                for change in changes {
                    let predicate = store.predicateForEvents(withStart: change.entry.start.addingTimeInterval(-1), end: change.entry.end.addingTimeInterval(1), calendars: nil)
                    guard let event = store.events(matching: predicate).first(where: { key($0) == change.entry.id }), event.calendar.allowsContentModifications,
                          event.startDate == change.entry.start, event.endDate == change.entry.end else {
                        throw NSError(domain: "CalendarStudio", code: 1, userInfo: [NSLocalizedDescriptionKey: "An event changed or is no longer editable. Refresh and select the events again. No group move was saved."])
                    }
                    resolved.append((change, event))
                }
                before = resolved.map { EventSnapshot($0.1,entry:entry($0.1),occurrenceOnly:true) }
                for (change, event) in resolved {
                    event.startDate = change.start; event.endDate = change.end
                    try store.save(event, span: .thisEvent, commit: false)
                }
                try store.commit()
                after = resolved.map { EventSnapshot($0.1,entry:entry($0.1),occurrenceOnly:true) }
                for (change, event) in resolved { inverse.append(EventChange(entry: entry(event), start: change.entry.start, end: change.entry.end)) }
            } else {
                for change in changes {
                    guard let index = sampleEntries.firstIndex(where: { $0.id == change.entry.id }) else { continue }
                    before.append(snapshot(sampleEntries[index]))
                    sampleEntries[index].start = change.start; sampleEntries[index].end = change.end
                    after.append(snapshot(sampleEntries[index]))
                    inverse.append(EventChange(entry: sampleEntries[index], start: change.entry.start, end: change.entry.end))
                }
            }
            record(actionName,before:before,after:after)
            reload(); selected = Set(inverse.map { $0.entry.id })
            return inverse
        } catch { store.reset(); reload(); message = "Couldn’t save the change. \(error.localizedDescription)"; return nil }
    }
    private var copiedEvents: [EventSnapshot] = []
    private var copiedPasteboardChange = -1
    var pasteTarget: Date?
    func copySelectedEvents() {
        guard draft == nil, !selection.isEmpty else { return }
        putEventsOnClipboard(selection.sorted { $0.start < $1.start }.map(snapshot))
    }
    private func putEventsOnClipboard(_ events: [EventSnapshot]) {
        copiedEvents = events
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(copiedEvents.map { $0.entry.title }.joined(separator:"\n"),forType:.string)
        copiedPasteboardChange = NSPasteboard.general.changeCount
    }
    @discardableResult func cutSelectedEvents() -> Bool {
        guard draft == nil, !selection.isEmpty else { return false }
        let events = selection.sorted { $0.start < $1.start }.map(snapshot)
        guard deleteSelectedEvents(actionName:events.count == 1 ? "Cut Event" : "Cut Events") else { return false }
        putEventsOnClipboard(events)
        return true
    }
    func pasteEvents() {
        if draft == nil, let data = NSPasteboard.general.data(forType:Self.bankClipboardType),
           let tasks = try? JSONDecoder().decode([BankTask].self,from:data), !tasks.isEmpty {
            var start = pasteTarget ?? calendar.date(bySettingHour:9,minute:0,second:0,of:firstVisibleDay)!
            var copies: [EventSnapshot] = []
            for task in tasks {
                guard let source = self.calendar(for:task) ?? creationCalendar else { continue }
                let end = start.addingTimeInterval(Double(task.minutes)*60)
                let item = CalendarEntry(id:UUID().uuidString,title:task.title,start:start,end:end,calendarID:source.id,color:source.color,notes:task.notes)
                var snapshot = EventSnapshot(entry:item); snapshot.notes = task.notes
                copies.append(snapshot); start = end
            }
            copiedEvents = copies; copiedPasteboardChange = NSPasteboard.general.changeCount
        }
        guard draft == nil, !copiedEvents.isEmpty, copiedPasteboardChange == NSPasteboard.general.changeCount else { return }
        let first = copiedEvents.map { $0.entry.start }.min()!
        let clock = calendar.dateComponents([.hour,.minute,.second],from:first)
        let target = calendar.date(bySettingHour:clock.hour ?? 0,minute:clock.minute ?? 0,second:clock.second ?? 0,of:pasteTarget ?? firstVisibleDay)!
        let offset = target.timeIntervalSince(first)
        var after: [EventSnapshot] = []
        do {
            for source in copiedEvents {
                guard let destination = sources.first(where:{ $0.id == source.entry.calendarID && $0.writable }) ?? creationCalendar else {
                    throw NSError(domain:"Calendar",code:1,userInfo:[NSLocalizedDescriptionKey:"Choose an editable calendar for the copies."])
                }
                var item = source.entry
                item.id = UUID().uuidString; item.start = item.start.addingTimeInterval(offset); item.end = item.end.addingTimeInterval(offset)
                item.calendarID = destination.id; item.color = destination.color; item.writable = true
                item.recurring = false; item.hasGuests = false; item.invitationStatus = .none
                if live {
                    guard let calendar = store.calendar(withIdentifier:destination.id), calendar.allowsContentModifications else { throw NSError(domain:"Calendar",code:1) }
                    let event = EKEvent(eventStore:store)
                    source.apply(to:event,calendar:calendar)
                    event.startDate = item.start; event.endDate = item.end
                    event.recurrenceRules = nil
                    try store.save(event,span:.thisEvent,commit:false)
                    after.append(EventSnapshot(event,entry:entry(event)))
                } else {
                    var details = source.draft ?? EventDraft(original:nil,title:item.title,start:item.start,end:item.end,calendarID:item.calendarID,allDay:item.allDay)
                    details.original = item; details.start = item.start; details.end = item.end; details.calendarID = item.calendarID; details.repeatSchedule = .never
                    after.append(EventSnapshot(entry:item,draft:details))
                }
            }
            if live { try store.commit() }
            else { for item in after { sampleEntries.append(item.entry); sampleDetails[item.entry.id] = item.draft } }
            record("Paste Events",before:[],after:after)
            reload(); selected = Set(after.map { $0.entry.id })
        } catch { if live { store.reset() }; reload(); message = "Couldn’t paste events. \(error.localizedDescription)" }
    }
    private func clearHistory() { undoHistory = []; redoHistory = []; historyHandles = [:]; bankHistoryHandles = [:] }
    private func snapshot(_ item: CalendarEntry) -> EventSnapshot {
        if live, let event = ekEvents[item.id] { return EventSnapshot(event,entry:item) }
        return EventSnapshot(entry:item, draft:sampleDetails[item.id])
    }
    private func handle(for id: String) -> EventHandle {
        if let existing = historyHandles[id] { return existing }
        let handle = EventHandle(id); historyHandles[id] = handle; return handle
    }
    private func record(_ name: String, before: [EventSnapshot], after: [EventSnapshot], span: EKSpan = .thisEvent) {
        let count = max(before.count,after.count)
        guard count > 0 else { return }
        let changes = (0..<count).map { index -> EventRestoration in
            let old = index < before.count ? before[index] : nil
            let new = index < after.count ? after[index] : nil
            let handle = self.handle(for:old?.entry.id ?? new!.entry.id)
            handle.id = new?.entry.id
            if let new { historyHandles[new.entry.id] = handle }
            return EventRestoration(handle:handle, before:old, after:new, span:span)
        }
        undoHistory.append(CalendarAction(name:name,changes:changes))
        redoHistory = []
    }
    private func bankRestoration(before: BankTask?, after: BankTask?) -> BankRestoration {
        let id = before?.id ?? after!.id
        let handle = bankHistoryHandles[id] ?? BankHistoryHandle(after)
        handle.current = after
        bankHistoryHandles[id] = handle
        if let after { bankHistoryHandles[after.id] = handle }
        return BankRestoration(handle:handle,before:before,after:after)
    }
    private func recordBank(_ name: String, before: BankTask?, after: BankTask?) {
        undoHistory.append(CalendarAction(name:name,changes:[],bankChanges:[bankRestoration(before:before,after:after)]))
        redoHistory = []
    }
    func undo() {
        guard let action = undoHistory.last, restore(action, undo:true) else { return }
        undoHistory.removeLast(); redoHistory.append(action); status = action.name + " undone"
    }
    func redo() {
        guard let action = redoHistory.last, restore(action, undo:false) else { return }
        redoHistory.removeLast(); undoHistory.append(action); status = action.name + " restored"
    }
    private func restore(_ action: CalendarAction, undo: Bool) -> Bool {
        var restoredBank: [BankRestoration] = []
        do {
            for change in action.bankChanges { try bank.validateRestoration(change) }
            var staged: [(EventRestoration, EKEvent?)] = []
            // Validate every member before staging any writes. A sync conflict leaves history retryable.
            for change in action.changes {
                let expected = undo ? change.after : change.before
                let desired = undo ? change.before : change.after
                if live {
                    var current: EKEvent?
                    if let expected {
                        let predicate = store.predicateForEvents(withStart:expected.entry.start.addingTimeInterval(-1),end:expected.entry.end.addingTimeInterval(1),calendars:nil)
                        current = store.events(matching:predicate).first { key($0) == change.handle.id }
                        guard let current, expected.matches(current), current.calendar.allowsContentModifications else {
                            throw historyError("An event changed in another app or is no longer editable. Refresh before trying again.")
                        }
                    }
                    if let desired {
                        guard let calendar = store.calendar(withIdentifier:desired.entry.calendarID), calendar.allowsContentModifications else {
                            throw historyError("The original calendar is unavailable or read-only.")
                        }
                        let event = current ?? EKEvent(eventStore:store)
                        staged.append((change,event))
                    } else { staged.append((change,current)) }
                } else if let expected {
                    guard let current = sampleEntries.first(where:{ $0.id == change.handle.id }),
                          current.start == expected.entry.start, current.end == expected.entry.end, current.title == expected.entry.title else {
                        throw historyError("The event changed. Refresh before trying again.")
                    }
                }
            }
            // Write bank revisions first; roll them back if the calendar commit fails.
            for change in action.bankChanges {
                try bank.restore(change,undo:undo); restoredBank.append(change)
                if let current = change.handle.current { bankHistoryHandles[current.id] = change.handle }
            }
            if live {
                for (change,event) in staged {
                    let desired = undo ? change.before : change.after
                    if let desired, let event {
                        desired.apply(to:event, calendar:store.calendar(withIdentifier:desired.entry.calendarID)!)
                        try store.save(event,span:change.span,commit:false)
                    } else if let event { try store.remove(event,span:change.span,commit:false) }
                }
                try store.commit()
                for (change,event) in staged {
                    let desired = undo ? change.before : change.after
                    change.handle.id = desired == nil ? nil : event.map(key)
                    if let id = change.handle.id { historyHandles[id] = change.handle }
                }
            } else {
                for change in action.changes {
                    if let id = change.handle.id { sampleEntries.removeAll { $0.id == id }; sampleDetails.removeValue(forKey:id) }
                    if let desired = undo ? change.before : change.after {
                        sampleEntries.append(desired.entry); sampleDetails[desired.entry.id] = desired.draft
                        change.handle.id = desired.entry.id
                    } else { change.handle.id = nil }
                }
            }
            reload(); selected = Set(action.changes.compactMap { $0.handle.id })
            return true
        } catch {
            if live { store.reset() }
            var rollbackFailed = false
            for change in restoredBank.reversed() {
                do { try bank.restore(change,undo:!undo) } catch { rollbackFailed = true }
            }
            reload()
            message = "Couldn’t " + (undo ? "undo" : "redo") + " this change. " + error.localizedDescription
            if rollbackFailed { message! += " The bank rollback also failed. Check the bank before trying again." }
            return false
        }
    }
    private func historyError(_ text: String) -> NSError { NSError(domain:"CalendarUndo",code:1,userInfo:[NSLocalizedDescriptionKey:text]) }
    func calendar(for task: BankTask) -> CalendarSource? {
        let available = sources.filter { $0.writable && !$0.title.hasPrefix("- ") }
        if let exact = available.first(where:{ $0.id == task.calendarID }) { return exact }
        let matches = available.filter { $0.title == task.calendarTitle && $0.account == task.account }
        return matches.count == 1 ? matches[0] : nil
    }
    func canScheduleBankTask(_ id: UUID) -> Bool {
        guard live, let task = bank.records[id], task.state == .pending else { return false }
        return calendar(for:task) != nil
    }
    func recordScheduledBankTask(previousTask: BankTask?, event: EventSnapshot, taskID: UUID) {
        record("Schedule Bank Task",before:[],after:[event])
        undoHistory[undoHistory.count-1].bankChanges = [bankRestoration(before:previousTask,after:bank.records[taskID])]
    }
    func scheduleBankTask(_ id: UUID, at date: Date) -> Bool {
        guard live else { message = "Connect your calendars before scheduling a task."; return false }
        var previousTask: BankTask?
        var scheduledEvent: EventSnapshot?
        do {
            try bank.schedule(id,at:date) { task in
                previousTask = task
                guard let source = self.calendar(for:task), let calendar = self.store.calendar(withIdentifier:source.id), calendar.allowsContentModifications, !calendar.title.hasPrefix("- ") else {
                    throw NSError(domain:"EventBank",code:2,userInfo:[NSLocalizedDescriptionKey:"Choose an available, editable calendar for this task."])
                }
                let event = EKEvent(eventStore:self.store)
                event.title = task.title
                event.startDate = date
                event.endDate = date.addingTimeInterval(Double(task.minutes)*60)
                event.calendar = calendar
                event.notes = task.notes
                try self.store.save(event,span:.thisEvent,commit:true)
                self.visible.insert(source.id)
                scheduledEvent = EventSnapshot(event,entry:self.entry(event))
                return event.eventIdentifier
            }
            if let scheduledEvent {
                recordScheduledBankTask(previousTask:previousTask,event:scheduledEvent,taskID:id)
            }
            reload()
            status = "Task scheduled · removed from Event Bank"
            return true
        } catch {
            if bank.records[id]?.state == .scheduled {
                if let scheduledEvent {
                    recordScheduledBankTask(previousTask:previousTask,event:scheduledEvent,taskID:id)
                }
                reload(); status = "Task scheduled · bank sync pending"
                message = "The event is on your calendar. Its removal from the bank will sync when the folder is available again."
                return true
            }
            store.reset()
            message = "Couldn’t schedule the task. It is still in the bank. \(error.localizedDescription)"
            return false
        }
    }
    func moveEventsToBank(_ ids: [String], before target: UUID? = nil, categoryID: UUID? = nil) -> Bool {
        let items = entries.filter { Set(ids).contains($0.id) }
        guard !items.isEmpty, items.count == Set(ids).count,
              items.allSatisfy({ $0.writable && !$0.allDay }), bank.ready else {
            message = "Choose editable timed events and an available bank folder."; return false
        }
        if items.contains(where:{ $0.recurring || $0.hasGuests }) {
            let alert = NSAlert()
            alert.messageText = "Move these events to the Event Bank?"
            alert.informativeText = "Only the selected occurrences of repeating events will be removed. Removing events with guests may send cancellations. Undo restores event details, but cannot restore guest invitations or retract cancellations."
            alert.addButton(withTitle:"Move to Bank"); alert.addButton(withTitle:"Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return false }
        }
        let wasRecording = bank.recordingHistory
        bank.recordingHistory = false
        defer { bank.recordingHistory = wasRecording }
        var saved: [UUID] = []
        var removed: [EventSnapshot] = []
        var calendarRemoved = false
        do {
            var resolved: [EKEvent] = []
            if live {
                for item in items {
                    guard let event = ekEvents[item.id], event.refresh(), event.calendar.allowsContentModifications,
                          event.startDate == item.start, event.endDate == item.end else {
                        throw NSError(domain:"EventBank",code:3,userInfo:[NSLocalizedDescriptionKey:"An event changed. Refresh and drag it again."])
                    }
                    resolved.append(event)
                }
            }
            for item in items {
                guard let source = sources.first(where:{ $0.id == item.calendarID && !$0.title.hasPrefix("- ") }) else {
                    throw NSError(domain:"EventBank",code:4,userInfo:[NSLocalizedDescriptionKey:"The calendar is unavailable."])
                }
                let event = resolved.first(where:{ key($0) == item.id })
                var notes = live ? (event?.notes ?? "") : item.notes
                if let location = live ? (event?.location ?? event?.structuredLocation?.title) : item.location, !location.isEmpty { notes += (notes.isEmpty ? "" : "\n\n") + "Location: " + location }
                let task = BankTask(title:item.title,minutes:max(1,Int(ceil(item.end.timeIntervalSince(item.start)/60))),calendarID:source.id,calendarTitle:source.title,account:source.account,notes:notes)
                // Persist the unscheduled task before removing the original event.
                try bank.save(task); saved.append(task.id)
                let insertion = bank.tasks.contains(where:{ $0.id == target }) ? target : nil
                try bank.reorder(task.id,before:insertion,categoryID:categoryID)
            }
            removed = live ? resolved.map { EventSnapshot($0,entry:entry($0),occurrenceOnly:true) } : items.map(snapshot)
            if live {
                for event in resolved { try store.remove(event,span:.thisEvent,commit:false) }
                try store.commit()
            } else { sampleEntries.removeAll { Set(ids).contains($0.id) } }
            calendarRemoved = true
            record("Move to Event Bank",before:removed,after:[])
            undoHistory[undoHistory.count-1].bankChanges = saved.map { bankRestoration(before:nil,after:bank.records[$0]) }
            selected = []; reload()
            status = "Moved \(items.count) event\(items.count == 1 ? "" : "s") to Event Bank"
            return true
        } catch {
            store.reset()
            var rollbackFailed = false
            if !calendarRemoved {
                for id in saved { do { try bank.remove(id) } catch { rollbackFailed = true } }
            }
            reload()
            message = "Couldn’t move to the bank. The original events remain on your calendar. " + error.localizedDescription
            if rollbackFailed { message! += " Some bank copies could not be removed; check the bank before scheduling them." }
            return false
        }
    }
    var creationPreview: CalendarEntry? {
        guard let draft, draft.original == nil, draft.end > draft.start,
              let source = sources.first(where:{ $0.id == draft.calendarID }) else { return nil }
        return CalendarEntry(id:"draft-"+draft.id.uuidString,title:draft.title.isEmpty ? "New Event" : draft.title,start:draft.start,end:draft.end,calendarID:source.id,color:source.color,allDay:draft.allDay,notes:draft.notes,location:draft.location)
    }
    func respondInAppleCalendar(_ item: CalendarEntry) {
        guard live, let event = ekEvents[item.id], let uid = event.calendarItemExternalIdentifier else {
            message = "This invitation is unavailable. Refresh your calendars and try again."; return
        }
        func literal(_ value: String) -> String {
            "\"" + value.replacingOccurrences(of:"\\",with:"\\\\").replacingOccurrences(of:"\"",with:"\\\"").replacingOccurrences(of:"\r",with:"\\r").replacingOccurrences(of:"\n",with:"\\n") + "\""
        }
        // Apple's documented Calendar scripting interface locates events by UID.
        // This only reveals the invitation; the user submits their RSVP in Calendar.
        let source = """
        tell application "Calendar"
            set matchesFound to {}
            repeat with c in (every calendar whose name is \(literal(event.calendar.title)))
                set matchingEvents to (every event of c whose uid is \(literal(uid)))
                repeat with e in matchingEvents
                    set end of matchesFound to contents of e
                end repeat
            end repeat
            activate
            if (count of matchesFound) is 1 then
                show item 1 of matchesFound
            else if (count of matchesFound) is 0 then
                error "The event is not yet available in Apple Calendar. Let Calendar sync, then try again."
            else
                error "More than one copy was found. Choose the invitation in Apple Calendar."
            end if
        end tell
        """
        draft = nil
        guard let script = NSAppleScript(source:source) else { message = "Couldn’t prepare the Calendar handoff."; return }
        var error: NSDictionary?
        script.executeAndReturnError(&error)
        if let error {
            message = "Couldn’t reveal the invitation. " + (error[NSAppleScript.errorMessage] as? String ?? "Allow Sunshine Calendar to control Calendar in System Settings → Privacy & Security → Automation.")
        } else { status = "Respond in Apple Calendar · response refreshes when you return" }
    }
    func newEvent(at date: Date? = nil, durationMinutes: Int = 60, anchorInWindow: NSRect? = nil) {
        guard let source = creationCalendar else { message = "No editable calendars are available."; return }
        editorAnchorInWindow = anchorInWindow
        let start = date ?? calendar.date(bySettingHour: 13, minute: 0, second: 0, of: anchor)!
        draft = EventDraft(start: start, end: start.addingTimeInterval(Double(durationMinutes)*60), calendarID: source.id,timeZoneID:primaryTimeZoneID)
    }
    func newAllDayEvent(from first: Date, through last: Date, anchorInWindow: NSRect? = nil) {
        guard let source = creationCalendar else { message = "No editable calendars are available."; return }
        // All-day dates float in local time, even if the visible ribbon uses
        // another primary time zone. Preserve the selected column's date.
        let local = Calendar.current
        let start = local.date(from:calendar.dateComponents([.year,.month,.day],from:min(first,last)))!
        let final = local.date(from:calendar.dateComponents([.year,.month,.day],from:max(first,last)))!
        editorAnchorInWindow = anchorInWindow
        draft = EventDraft(start:start,end:local.date(byAdding:.day,value:1,to:final)!,calendarID:source.id,allDay:true,timeZoneID:"")
    }
    func eventAttendees(for id: String?) -> [EventAttendee] {
        guard let id, let event = ekEvents[id] else { return [] }
        let organizerURL = event.organizer?.url.absoluteString.lowercased()
        var participants = event.attendees ?? []
        if let organizer = event.organizer, !participants.contains(where:{ $0.url.absoluteString.lowercased() == organizerURL }) { participants.insert(organizer,at:0) }
        var seen: Set<String> = []
        return participants.compactMap { participant in
            let key = participant.url.absoluteString.lowercased()
            guard seen.insert(key).inserted else { return nil }
            let email = EventAttendee.email(from:participant.url)
            let name = participant.name?.trimmingCharacters(in:.whitespacesAndNewlines)
            return EventAttendee(id:key,name:name?.isEmpty == false ? name! : (email ?? "Attendee"),email:email,response:InvitationStatus(participant:participant.participantStatus),isOrganizer:key == organizerURL,isCurrentUser:participant.isCurrentUser)
        }.sorted { a,b in a.isOrganizer != b.isOrganizer ? a.isOrganizer : a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending }
    }
    func edit(_ event: CalendarEntry, anchorInWindow: NSRect? = nil) {
        editorAnchorInWindow = anchorInWindow
        let ek = ekEvents[event.id]
        if !live, var saved = sampleDetails[event.id] { saved.original = event; saved.id = UUID(); draft = saved; return }
        draft = EventDraft(original: event, title: event.title, start: event.start, end: event.end, calendarID: event.calendarID, allDay: event.allDay, location: ek?.location ?? "", notes: ek?.notes ?? "",url:ek?.url?.absoluteString ?? "",timeZoneID:ek?.timeZone?.identifier ?? "",repeatSchedule:event.recurring ? .unchanged : .never)
    }
    func save(_ draft: EventDraft) -> Bool {
        guard draft.original?.writable != false else { return false }
        guard !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, draft.end > draft.start else { message = "Enter a title and an end time after the start time."; return false }
        guard draft.url.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || draft.eventURL != nil else {
            message = "Enter a valid URL, such as https://example.com."; return false
        }
        do {
            var before: [EventSnapshot] = []
            var after: [EventSnapshot] = []
            let changesSeries = draft.original?.recurring == true && draft.repeatSchedule != .unchanged
            if live {
                guard let calendar = store.calendar(withIdentifier: draft.calendarID), calendar.allowsContentModifications else { message = "Choose an editable calendar."; return false }
                let event: EKEvent
                if let original = draft.original {
                    guard let existing = ekEvents[original.id], existing.refresh(), existing.startDate == original.start, existing.endDate == original.end else { message = "This event changed. Close the editor and open it again."; return false }
                    event = existing
                } else { event = EKEvent(eventStore: store) }
                if draft.original != nil { before = [EventSnapshot(event,entry:entry(event),occurrenceOnly:!changesSeries)] }
                let seriesBefore: EventSnapshot? = changesSeries ? (store.calendarItem(withIdentifier:event.calendarItemIdentifier) as? EKEvent).map { EventSnapshot($0,entry:entry($0)) } : nil
                if changesSeries || draft.original?.hasGuests == true {
                    let alert = NSAlert(); alert.messageText = "Save changes to this event?"
                    alert.informativeText = (changesSeries ? "Changing Repeat applies to this occurrence and future events in the series. " : "") + (draft.original?.hasGuests == true ? "This event has guests. Saving may send calendar updates." : "")
                    alert.addButton(withTitle: "Save"); alert.addButton(withTitle: "Cancel")
                    guard alert.runModal() == .alertFirstButtonReturn else { return false }
                }
                event.title = draft.title; event.calendar = calendar; event.startDate = draft.start; event.endDate = draft.end; event.isAllDay = draft.allDay; event.location = draft.location; event.notes = draft.notes; event.url = draft.eventURL
                event.timeZone = draft.allDay ? nil : TimeZone(identifier:draft.timeZoneID)
                if draft.repeatSchedule != .unchanged { event.recurrenceRules = draft.repeatSchedule.rule.map { [$0] } }
                try store.save(event, span: changesSeries ? .futureEvents : .thisEvent, commit: true)
                after = [EventSnapshot(event,entry:entry(event),occurrenceOnly:draft.original != nil && !changesSeries)]
                // EventKit may split a series when editing future occurrences.
                // Keep the truncated parent as well, so undo can merge the schedule
                // and a later undo of its creation still removes the whole series.
                if let seriesBefore, event.calendarItemIdentifier != seriesBefore.entry.id.components(separatedBy:"|")[0],
                   let parent = store.calendarItem(withIdentifier:seriesBefore.entry.id.components(separatedBy:"|")[0]) as? EKEvent {
                    before = [seriesBefore]
                    after = [EventSnapshot(parent,entry:entry(parent)),after[0]]
                }
            } else {
                let source = sources.first(where: { $0.id == draft.calendarID })!
                let event = CalendarEntry(id: draft.original?.id ?? UUID().uuidString, title: draft.title, start: draft.start, end: draft.end, calendarID: draft.calendarID, color: source.color, allDay: draft.allDay,notes:draft.notes,location:draft.location)
                if let old = sampleEntries.first(where:{ $0.id == event.id }) { before = [snapshot(old)] }
                sampleEntries.removeAll { $0.id == event.id }; sampleEntries.append(event)
                sampleDetails[event.id] = draft
                after = [snapshot(event)]
            }
            let span: EKSpan = changesSeries || (draft.original == nil && draft.repeatSchedule != .never) ? .futureEvents : .thisEvent
            record(draft.original == nil ? "Add Event" : "Edit Event",before:before,after:after,span:span)
            reload(); status = live ? "Event saved to your calendar" : "Sample event saved"; return true
        } catch { store.reset(); reload(); message = error.localizedDescription; return false }
    }
}
