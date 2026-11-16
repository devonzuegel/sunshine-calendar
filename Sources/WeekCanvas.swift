import AppKit
import SwiftUI
import QuartzCore
import CoreText

struct TimedInterval {
    var id: String
    var start: Date
    var end: Date
}
struct EventColumn {
    var column: Int
    var count: Int
    var span: Int = 1
    var depth: Int = 0
}
enum OverlapLayout {
    // Equal starts share columns; staggered starts overlay with a small inset.
    // Reuse the lowest free inset so successive events return to the left edge.
    static func columns(_ items: [TimedInterval]) -> [String: EventColumn] {
        let sorted = items.sorted {
            $0.start == $1.start ? ($0.end == $1.end ? $0.id < $1.id : $0.end > $1.end) : $0.start < $1.start
        }
        var result: [String: EventColumn] = [:]
        var active: [(end: Date, depth: Int)] = []
        var index = 0
        while index < sorted.count {
            let start = sorted[index].start
            var endIndex = index+1
            while endIndex < sorted.count && sorted[endIndex].start == start { endIndex += 1 }
            active.removeAll { $0.end <= start }
            let occupied = Set(active.map(\.depth))
            var depth = 0
            while occupied.contains(depth) { depth += 1 }
            let band = Array(sorted[index..<endIndex])
            for (column,item) in band.enumerated() {
                result[item.id] = EventColumn(column:column,count:band.count,depth:depth)
            }
            active.append((band.map(\.end).max()!,depth))
            index = endIndex
        }
        return result
    }
}

enum DaylightGradientRenderer {
    static func draw(_ elevations: [Double], in rect: NSRect, nightColor: NSColor, maximumAlpha: CGFloat, mode: TwilightMode = .civil) {
        guard !elevations.isEmpty else { return }
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        // Point-to-point NSGradient drawing otherwise fills the whole clipping
        // region, including neighboring days and the comparison ribbons.
        NSBezierPath(rect:rect).addClip()
        let colors = elevations.map { nightColor.withAlphaComponent(maximumAlpha*CGFloat(DaylightMath.darkness(elevation:$0,mode:mode))) }
        NSGradient(colors:colors)?.draw(from:NSPoint(x:rect.midX,y:rect.minY),to:NSPoint(x:rect.midX,y:rect.maxY),options:[])
    }
}

enum EventCardInsets {
    static let accentWidth: CGFloat = 3
    static let textLeading: CGFloat = 6
    static let textTrailing: CGFloat = 5
}

enum ProtectedTitleLayout {
    static func frames(_ cards: [NSRect], textScale: CGFloat = 1) -> [NSRect] {
        var placed: [NSRect] = []
        for card in cards {
            let compact = card.height < 24
            let height = compact ? max(1,card.height-0.5) : min(14*textScale,max(1,card.height-4))
            var label = NSRect(x:card.minX+EventCardInsets.textLeading,y:card.minY+(compact ? 0.25 : 2),width:max(1,card.width-EventCardInsets.textLeading-EventCardInsets.textTrailing),height:height)
            // Move only the label, never the event's actual start/end geometry.
            for previous in placed.sorted(by:{ $0.minY < $1.minY }) where label.intersects(previous) {
                let next = previous.maxY+2
                if next+height <= card.maxY-1 { label.origin.y = next }
            }
            placed.append(label)
        }
        return placed
    }
}

enum EventCardLabelLayout {
    static func time(_ label: String, font: NSFont, color: NSColor, durationFirst: Bool = false) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle(); paragraph.lineBreakMode = .byTruncatingTail
        let attributed = NSMutableAttributedString(string:label,attributes:[.font:font,.foregroundColor:color.withAlphaComponent(0.85),.paragraphStyle:paragraph])
        let separator = (label as NSString).range(of:" · ")
        if separator.location != NSNotFound {
            attributed.addAttribute(.foregroundColor,value:color.withAlphaComponent(0.48),range:NSRange(location:separator.location,length:attributed.length-separator.location))
            if durationFirst {
                let start = NSMaxRange(separator)
                let reordered = NSMutableAttributedString(attributedString:attributed.attributedSubstring(from:NSRange(location:start,length:attributed.length-start)))
                reordered.append(attributed.attributedSubstring(from:separator))
                reordered.append(attributed.attributedSubstring(from:NSRange(location:0,length:separator.location)))
                return reordered
            }
        }
        return attributed
    }
    static func inline(title: String, time: NSAttributedString, titleFont: NSFont, color: NSColor, in frame: NSRect) -> (title: NSAttributedString, time: NSAttributedString, titleFrame: NSRect, timeFrame: NSRect)? {
        guard title.rangeOfCharacter(from:.newlines) == nil else { return nil }
        let title = NSAttributedString(string:title,attributes:[.font:titleFont,.foregroundColor:color])
        let titleSize = title.size(), timeSize = time.size()
        let titleWidth = ceil(titleSize.width)+1, timeWidth = ceil(timeSize.width)+1
        // Preserve the full title and time; a small card must not squeeze or
        // truncate either label just to force them onto the same line.
        guard titleWidth+8+timeWidth <= frame.width, ceil(max(titleSize.height,timeSize.height)) <= frame.height else { return nil }
        return (title,time,
                NSRect(x:frame.minX,y:frame.minY,width:titleWidth,height:frame.height),
                NSRect(x:frame.maxX-timeWidth,y:frame.minY,width:timeWidth,height:frame.height))
    }
}

struct AllDaySpan {
    let id: String
    let firstDay: Int
    let endDay: Int
    let row: Int
}
enum AllDayLayout {
    static func spans(_ items: [TimedInterval], weekStart: Date, calendar: Calendar = .current, dayCount: Int = 7) -> [AllDaySpan] {
        let end = calendar.date(byAdding:.day,value:dayCount,to:weekStart)!
        let sorted = items.filter { $0.end > $0.start && $0.start < end && $0.end > weekStart }.sorted {
            $0.start == $1.start ? ($0.end == $1.end ? $0.id < $1.id : $0.end > $1.end) : $0.start < $1.start
        }
        var rowEnds: [Int] = []
        return sorted.map { item in
            let start = max(0,calendar.dateComponents([.day],from:weekStart,to:calendar.startOfDay(for:item.start)).day!)
            // End instants are exclusive, but a non-midnight end still overlaps
            // its display date. Time-zone conversion can put an all-day end in
            // the afternoon; flooring it drops that final visible day.
            let endDay = calendar.startOfDay(for:item.end)
            let rawFinish = calendar.dateComponents([.day],from:weekStart,to:endDay).day! + (item.end > endDay ? 1 : 0)
            // A valid event that intersects the range must occupy a day even
            // if timezone conversion or clipping rounds its end onto its start.
            let finish = min(dayCount,max(start+1,rawFinish))
            let row = rowEnds.firstIndex(where:{ $0 <= start }) ?? rowEnds.count
            if row == rowEnds.count { rowEnds.append(finish) } else { rowEnds[row] = finish }
            return AllDaySpan(id:item.id,firstDay:start,endDay:finish,row:row)
        }
    }
}

enum AllDayTrayLayout {
    static func collapsedHeight(rows: Int) -> CGFloat { 40+CGFloat(max(0,rows-2))*7 }
    static func expandedHeight(rows: Int) -> CGFloat { max(40,CGFloat(rows)*18+4) }
    static func expansion(height: CGFloat, rows: Int) -> CGFloat {
        let compact = collapsedHeight(rows:rows), full = expandedHeight(rows:rows)
        return full > compact ? min(1,max(0,(height-compact)/(full-compact))) : 1
    }
    static func rowFrame(row: Int, expansion: CGFloat) -> (y: CGFloat, height: CGFloat) {
        guard row >= 2 else { return (CGFloat(row)*18+2,16) }
        let progress = min(1,max(0,expansion))
        let compactY = 38+CGFloat(row-2)*7
        return (compactY+(CGFloat(row)*18+2-compactY)*progress,6+10*progress)
    }
}

struct DayScrollGesture {
    enum Axis { case undecided, horizontal, vertical }
    private var axis: Axis = .undecided
    private var accumulatedX: CGFloat = 0
    private var accumulatedY: CGFloat = 0
    private var lastTime: TimeInterval = -.infinity
    private var fired = false

    // A deliberate horizontal swipe advances exactly one day. Momentum never
    // advances additional days, and a vertical gesture stays vertical.
    mutating func consume(x: CGFloat, y: CGFloat, time: TimeInterval, began: Bool = false, momentum: Bool = false, precise: Bool = true) -> (horizontal: Bool, days: Int) {
        if momentum { return (axis == .horizontal, 0) }
        if began || time-lastTime > 0.3 {
            axis = .undecided; accumulatedX = 0; accumulatedY = 0; fired = false
        }
        lastTime = time
        accumulatedX += x; accumulatedY += y
        if axis == .undecided {
            if abs(accumulatedX) > 5 && abs(accumulatedX) > abs(accumulatedY)*1.25 { axis = .horizontal }
            else if abs(accumulatedY) > 5 && abs(accumulatedY) >= abs(accumulatedX) { axis = .vertical }
        }
        guard axis == .horizontal else { return (false, 0) }
        let threshold: CGFloat = precise ? 32 : 8
        guard !fired, abs(accumulatedX) >= threshold else { return (true, 0) }
        fired = true
        return (true, accumulatedX < 0 ? 1 : -1)
    }
}

enum DaySwipeMath {
    static let trackpadGain: CGFloat = 1.6
    static let snapDuration: Double = 0.09
    static let navigationDuration: Double = 0.16
    static func jumpDistance(days: Int, dayWidth: CGFloat, viewportWidth: CGFloat) -> CGFloat {
        let distance = min(abs(CGFloat(days))*max(1,dayWidth),max(1,viewportWidth))
        return days < 0 ? -distance : (days > 0 ? distance : 0)
    }
    static func jumpDuration(days: Int) -> Double {
        navigationDuration+0.04*min(5,max(0,abs(Double(days))-1))
    }

    static func imageShifts(toward offset: CGFloat) -> [Int] { offset < 0 ? [0,1] : [-1,0] }
    static func advance(offset: CGFloat, delta: CGFloat, width: CGFloat) -> (days: Int, offset: CGFloat) {
        let width = max(1,width), total = offset+delta
        let days = Int(-total/width)
        return (days,total+CGFloat(days)*width)
    }
    static func snapOffset(from: CGFloat, to: CGFloat, progress: Double) -> CGFloat {
        let t = min(1,max(0,progress))
        let eased = 1-pow(1-t,3)
        return from+(to-from)*CGFloat(eased)
    }
    static func settle(offset: CGFloat, width: CGFloat) -> Int {
        abs(offset) >= max(1,width)*0.5 ? (offset < 0 ? 1 : -1) : 0
    }
}

struct TrackpadDayGesture {
    struct Update {
        var handled = false
        var delta: CGFloat = 0
        var finished = false
        var cancelled = false
    }
    private var axis: DayScrollGesture.Axis = .undecided
    private(set) var isTracking = false
    private(set) var swallowingMomentum = false
    mutating func consume(x: CGFloat, y: CGFloat, phase: NSEvent.Phase, momentum: NSEvent.Phase = []) -> Update {
        if phase.contains(.began) { axis = .undecided; swallowingMomentum = false }
        if !momentum.isEmpty {
            let handled = swallowingMomentum
            if momentum.contains(.ended) || momentum.contains(.cancelled) { swallowingMomentum = false }
            return Update(handled:handled)
        }
        if axis == .undecided {
            if abs(x) > 0.5 && abs(x) > abs(y)*1.15 { axis = .horizontal }
            else if abs(y) > 0.5 && abs(y) > abs(x)*1.15 { axis = .vertical }
        }
        guard axis == .horizontal else { return Update() }
        let cancelled = phase.contains(.cancelled)
        let finished = phase.contains(.ended) || cancelled
        isTracking = !finished
        if finished { swallowingMomentum = !cancelled; axis = .undecided }
        return Update(handled:true,delta:x*DaySwipeMath.trackpadGain,finished:finished,cancelled:cancelled)
    }
}

struct DaySwipeSnapshotCache<Image> {
    private var images: [Date: Image] = [:]
    mutating func image(for day: Date, render: () -> Image?) -> Image? {
        if let image = images[day] { return image }
        guard let image = render() else { return nil }
        images[day] = image
        return image
    }
    mutating func retain(_ dates: Set<Date>) { images = images.filter { dates.contains($0.key) } }
    mutating func clear() { images.removeAll() }
}

final class FittingScrollView: NSScrollView {
    var onDayNavigation: ((Int) -> Void)?
    private var dayGesture = DayScrollGesture()
    private var trackpadGesture = TrackpadDayGesture()
    private var scrollMonitor: Any?
    private var boundsObserver: Any?
    deinit {
        if let scrollMonitor { NSEvent.removeMonitor(scrollMonitor) }
        if let boundsObserver { NotificationCenter.default.removeObserver(boundsObserver) }
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let scrollMonitor { NSEvent.removeMonitor(scrollMonitor); self.scrollMonitor = nil }
        if let boundsObserver { NotificationCenter.default.removeObserver(boundsObserver); self.boundsObserver = nil }
        guard window != nil else { return }
        contentView.postsBoundsChangedNotifications = true
        boundsObserver = NotificationCenter.default.addObserver(forName:NSView.boundsDidChangeNotification,object:contentView,queue:.main) { [weak self] _ in
            self?.documentView?.needsDisplay = true
        }
        window?.acceptsMouseMovedEvents = true
        // Receive horizontal gestures before AppKit's edge-swipe routing.
        // This monitor only sees events in this app, over this calendar view.
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching:.scrollWheel) { [weak self] event in
            guard let self, event.window === self.window,
                  self.bounds.contains(self.convert(event.locationInWindow,from:nil)),
                  self.trackpadGesture.isTracking || self.trackpadGesture.swallowingMomentum || event.scrollingDeltaX != 0 || event.modifierFlags.contains(.shift) else { return event }
            return self.handleDayScroll(event) ? nil : event
        }
    }
    override func wantsScrollEventsForSwipeTracking(on axis: NSEvent.GestureAxis) -> Bool {
        axis == .horizontal || super.wantsScrollEventsForSwipeTracking(on:axis)
    }
    private func handleDayScroll(_ event: NSEvent) -> Bool {
        let shiftWheel = event.modifierFlags.contains(.shift) && event.scrollingDeltaX == 0
        if event.hasPreciseScrollingDeltas && (!event.phase.isEmpty || trackpadGesture.isTracking || !event.momentumPhase.isEmpty) {
            let x = shiftWheel ? event.scrollingDeltaY : event.scrollingDeltaX
            let y = shiftWheel ? 0 : event.scrollingDeltaY
            let update = trackpadGesture.consume(x:x,y:y,phase:event.phase,momentum:event.momentumPhase)
            if update.handled {
                let canvas = documentView as? CalendarCanvas
                if update.delta != 0 { canvas?.trackHorizontal(delta:update.delta) }
                if update.finished { canvas?.finishHorizontal(cancelled:update.cancelled) }
                return true
            }
            return false
        }
        let result = dayGesture.consume(
            x:shiftWheel ? event.scrollingDeltaY : event.scrollingDeltaX,
            y:shiftWheel ? 0 : event.scrollingDeltaY,
            time:event.timestamp,
            began:event.phase.contains(.began),
            momentum:!event.momentumPhase.isEmpty,
            precise:event.hasPreciseScrollingDeltas)
        if result.horizontal {
            if result.days != 0 { onDayNavigation?(result.days) }
            return true
        }
        return false
    }
    override func scrollWheel(with event: NSEvent) {
        if !handleDayScroll(event) { super.scrollWheel(with:event) }
    }
    override func tile() {
        super.tile()
        if let documentView, abs(documentView.frame.width - contentSize.width) > 0.5 {
            documentView.setFrameSize(NSSize(width: contentSize.width, height: documentView.frame.height))
            documentView.needsDisplay = true
        }
    }
}

private final class EventDeletionSnapshot: NSImageView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

struct WeekCanvas: NSViewRepresentable {
    @ObservedObject private var textSize = AppTextSize.shared
    @ObservedObject var model: CalendarModel
    @ObservedObject var daylight: DaylightLocation
    @ObservedObject var weather: WeatherOverlay
    init(model: CalendarModel) { self.model = model; self.daylight = model.daylight; self.weather = model.weather }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = FittingScrollView()
        scroll.onDayNavigation = { [weak model] days in model?.navigateDays(days) }
        scroll.setAccessibilityCustomActions([
            NSAccessibilityCustomAction(name:"Expand or collapse all-day events") { [weak model] in
                guard let model else { return false }; model.allDayExpanded.toggle(); return true
            },
            NSAccessibilityCustomAction(name:"Next day") { [weak model] in
                guard let model else { return false }; model.navigateDays(1); return true
            },
            NSAccessibilityCustomAction(name:"Previous day") { [weak model] in
                guard let model else { return false }; model.navigateDays(-1); return true
            }
        ])
        scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
        scroll.drawsBackground = true; scroll.backgroundColor = .textBackgroundColor
        let canvas = CalendarCanvas(model: model)
        canvas.frame = NSRect(x: 0, y: 0, width: 900, height: model.allDayHeight + 24 * CalendarMath.hourHeight)
        canvas.autoresizingMask = []
        scroll.documentView = canvas
        DispatchQueue.main.async {
            let y = model.restoredScrollY ?? (7 * CalendarMath.hourHeight)
            canvas.scroll(NSPoint(x:0,y:max(0,min(y,canvas.bounds.height-scroll.contentSize.height))))
            model.restoredScrollY = nil
        }
        return scroll
    }
    func updateNSView(_ view: NSScrollView, context: Context) {
        model.daylight.prepareRibbonLocations(model.clockZones)
        (view.documentView as? CalendarCanvas)?.synchronize()
    }
}

@MainActor final class CalendarCanvas: NSView, NSDraggingSource {
    let model: CalendarModel
    private var translucentWholeCards = false
    private var renderedStart: Date
    private var renderedEntries: [CalendarEntry]
    private var slideOverlay: NSView?
    private var dateJumpTimer: Timer?
    private var dateJumpToken = UUID()
    private var deletionOverlay: NSImageView?
    private var seenDeletionID = 0
    private var trackingViews: [(NSImageView,CGFloat)] = []
    private var trackingOffset: CGFloat = 0
    private var trackingImages = DaySwipeSnapshotCache<NSImage>()
    private var trackingImageArea: NSRect = .zero
    private var trackingImageScale: CGFloat = 0
    private var trackingImageDirection = 0
    private var trackingToken = UUID()
    private var settling = false
    private var snapAnimation: Timer?
    var gutter: CGFloat { model.timeGutterWidth }
    private var animatedTop: CGFloat = 48
    var top: CGFloat { animatedTop }
    var stickyTop: CGFloat { visibleRect.minY }
    var stickyBottom: CGFloat { stickyTop+top }
    private var targetTop: CGFloat = 48
    private var allDayAnimation: Timer?
    private var weatherReveal: CGFloat = 0
    private var weatherRevealTarget: CGFloat = 0
    private var weatherAnimation: Timer?
    private func weatherHours(on day: Date) -> [WeatherHour] {
        let start = model.calendar.startOfDay(for:day)
        let end = model.calendar.date(byAdding:.day,value:1,to:start)!
        return model.weather.hours(from:start,to:end)
    }
    private func synchronizeWeatherVisibility() {
        let end = model.calendar.date(byAdding:.day,value:model.visibleDayCount,to:model.weekStart)!
        let target: CGFloat = model.weather.enabled && model.weather.hours.contains(where:{ $0.date >= model.weekStart && $0.date < end }) ? 1 : 0
        guard target != weatherRevealTarget else { return }
        weatherRevealTarget = target
        weatherAnimation?.invalidate(); weatherAnimation = nil
        guard window != nil, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            weatherReveal = target; needsDisplay = true; return
        }
        let from = weatherReveal, began = CACurrentMediaTime()
        let timer = Timer(timeInterval:1.0/120,repeats:true) { [weak self] timer in
            Task { @MainActor in
                guard let self else { timer.invalidate(); return }
                let t = min(1,(CACurrentMediaTime()-began)/0.22)
                let eased = t*t*(3-2*t)
                self.weatherReveal = from+(target-from)*CGFloat(eased)
                self.needsDisplay = true
                if t >= 1 { timer.invalidate(); self.weatherAnimation = nil }
            }
        }
        weatherAnimation = timer; RunLoop.main.add(timer,forMode:.common)
    }

    private var allDayToggleRects: [NSRect] = []
    var hits: [(NSRect, CalendarEntry)] = []
    private var resizeZones: [(rect: NSRect, entry: CalendarEntry, startEdge: Bool)] = []
    private var resizing: (entry: CalendarEntry, startEdge: Bool)?
    private var resizeMinutes = 0
    var down: NSPoint?
    var draggingID: String?
    var delta = 0
    var didDrag = false
    private var allDayCreationStart: Int?
    private var allDayCreationEnd: Int?
    private var creatingDay: Int?
    private var creation: ClosedRange<Int>?
    private var newTaskDrop: Date?
    private var bankDrop: (id: UUID, start: Date)?
    private var rulerTrackingArea: NSTrackingArea?
    private var rulerHoverInWindow: NSPoint?
    private var hoveringAllDayTray = false
    private var allDayOpenedByHover = false
    private var allDayHoverWork: DispatchWorkItem?
    private var allDayHoverToken = UUID()
    private var hoverRegions: [(rect: NSRect, text: String, weather: WeatherHour?)] = []
    private var hoverTooltip: (text: String, location: NSPoint, weather: WeatherHour?)?
    private var hoverCandidate: String?
    private var hoverDelay: DispatchWorkItem?
    private var daylightTooltipKey = ""
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override var undoManager: UndoManager? { model.eventUndoManager }
    init(model: CalendarModel) {
        self.model = model
        seenDeletionID = model.deletionAnimationID
        renderedStart = model.weekStart
        renderedEntries = model.shown
        super.init(frame:.zero)
        registerForDraggedTypes([BankDrag.pasteboardType,NewTaskDrag.pasteboardType])
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let rulerTrackingArea { removeTrackingArea(rulerTrackingArea) }
        let area = NSTrackingArea(rect:.zero,options:[.mouseMoved,.mouseEnteredAndExited,.activeInKeyWindow,.inVisibleRect],owner:self,userInfo:nil)
        addTrackingArea(area); rulerTrackingArea = area
    }
    private func updateRulerHover(_ event: NSEvent) {
        let point = convert(event.locationInWindow,from:nil)
        let insideTray = point.x >= 0 && point.x < bounds.width && point.y >= stickyTop && point.y < stickyBottom
        updateAllDayHover(inside:insideTray)
        let previousRuler = rulerHoverInWindow
        let hadTooltip = hoverTooltip != nil
        rulerHoverInWindow = point.x >= 0 && point.x < gutter && point.y >= stickyBottom ? event.locationInWindow : nil
        updateFastTooltip(event)
        // Cursor movement over an ordinary event has no visual effect. Avoid
        // repainting the whole calendar unless the ruler or tooltip changes.
        if previousRuler != rulerHoverInWindow || hadTooltip != (hoverTooltip != nil) { needsDisplay = true }
    }
    private func cancelAllDayHover() {
        allDayHoverWork?.cancel(); allDayHoverWork = nil; allDayHoverToken = UUID()
    }
    private func updateAllDayHover(inside: Bool) {
        guard inside != hoveringAllDayTray else { return }
        hoveringAllDayTray = inside
        scheduleAllDayHover()
    }
    private func scheduleAllDayHover() {
        cancelAllDayHover()
        let entering = hoveringAllDayTray
        guard entering ? !model.allDayExpanded : allDayOpenedByHover else { return }
        let token = allDayHoverToken
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.allDayHoverToken == token, self.hoveringAllDayTray == entering else { return }
            self.allDayHoverWork = nil
            guard self.model.draft == nil, self.down == nil, !self.model.trackingHorizontalScroll else { return }
            if entering {
                guard !self.model.allDayExpanded, self.model.allDayRowCount > 2 else { return }
                self.allDayOpenedByHover = true
                self.hideFastTooltip()
                self.model.allDayExpanded = true
            } else {
                guard self.allDayOpenedByHover else { return }
                self.allDayOpenedByHover = false
                self.model.allDayExpanded = false
            }
            self.synchronize()
        }
        allDayHoverWork = work
        DispatchQueue.main.asyncAfter(deadline:.now()+(entering ? 0.30 : 0.45),execute:work)
    }
    private func updateFastTooltip(_ event: NSEvent) {
        let point = convert(event.locationInWindow,from:nil)
        let region = hoverRegions.reversed().first { region in
            point.y >= stickyBottom && region.rect.contains(point) && (region.weather == nil || !hits.contains(where:{ $0.0.contains(point) }))
        }
        guard region?.text != hoverCandidate else { return }
        hoverDelay?.cancel(); hoverTooltip = nil; hoverCandidate = region?.text
        guard let region, model.draft == nil, down == nil else { return }
        let location = event.locationInWindow
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.hoverCandidate == region.text else { return }
            self.hoverTooltip = (region.text,location,region.weather); self.needsDisplay = true
        }
        hoverDelay = work
        DispatchQueue.main.asyncAfter(deadline:.now()+AppTooltipTiming.delay,execute:work)
    }
    private func hideFastTooltip() {
        hoverDelay?.cancel(); hoverDelay = nil; hoverTooltip = nil; hoverCandidate = nil
    }
    override func mouseEntered(with event: NSEvent) { updateRulerHover(event) }
    override func mouseMoved(with event: NSEvent) {
        updateRulerHover(event)
        let point = convert(event.locationInWindow,from:nil)
        if let (_,item) = hits.reversed().first(where:{ $0.0.contains(point) }), resizeZones.contains(where:{ $0.entry.id == item.id && $0.rect.contains(point) }) {
            if item.allDay { NSCursor.resizeLeftRight.set() } else { NSCursor.resizeUpDown.set() }
        } else { NSCursor.arrow.set() }
    }
    override func mouseExited(with event: NSEvent) { updateAllDayHover(inside:false); rulerHoverInWindow = nil; hideFastTooltip(); needsDisplay = true }
    required init?(coder: NSCoder) { fatalError() }
    var dayWidth: CGFloat { max(1, (bounds.width - gutter) / CGFloat(model.visibleDayCount)) }
    func day(_ index: Int) -> Date { model.calendar.date(byAdding: .day, value: index, to: renderedStart)! }
    private func updateAllDayHeight(_ height: CGFloat) {
        animatedTop = height
        setFrameSize(NSSize(width:frame.width,height:top+24*CalendarMath.hourHeight))
        needsDisplay = true
    }
    private func animateAllDayHeight(to height: CGFloat) {
        allDayAnimation?.invalidate(); allDayAnimation = nil
        targetTop = height
        guard window != nil, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { updateAllDayHeight(height); return }
        let from = top, began = CACurrentMediaTime()
        let timer = Timer(timeInterval:1.0/60,repeats:true) { [weak self] timer in
            Task { @MainActor in
                guard let self else { timer.invalidate(); return }
                let progress = min(1,(CACurrentMediaTime()-began)/0.25)
                let eased = progress*progress*(3-2*progress)
                self.updateAllDayHeight(from+(height-from)*CGFloat(eased))
                if progress >= 1 { timer.invalidate(); self.allDayAnimation = nil; self.needsDisplay = true }
            }
        }
        allDayAnimation = timer
        RunLoop.main.add(timer,forMode:.common)
    }
    func synchronize() {
        if allDayOpenedByHover && !model.allDayExpanded { allDayOpenedByHover = false; cancelAllDayHover() }
        if allDayOpenedByHover && !hoveringAllDayTray && allDayHoverWork == nil && model.draft == nil { scheduleAllDayHover() }
        synchronizeWeatherVisibility()
        if model.trackingHorizontalScroll || !trackingViews.isEmpty { return }
        if targetTop != model.allDayHeight { animateAllDayHeight(to:model.allDayHeight) }
        let days = model.calendar.dateComponents([.day],from:renderedStart,to:model.weekStart).day ?? 0
        let area = NSRect(x:gutter,y:visibleRect.minY,width:max(0,bounds.width-gutter),height:visibleRect.height)
        let deletionChanged = seenDeletionID != model.deletionAnimationID
        seenDeletionID = model.deletionAnimationID
        let fadeDeletion = deletionChanged && days == 0 && window != nil && area.width > 0 && area.height > 0 && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        deletionOverlay?.removeFromSuperview(); deletionOverlay = nil
        if deletionChanged { hideFastTooltip() }
        let animate = days != 0 && model.dateJump != nil && window != nil && area.width > 0 && area.height > 0 && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        // Weather/status refreshes during a date jump must not tear down its
        // animation. Replace it only for a new navigation or deletion.
        if days != 0 || fadeDeletion {
            dateJumpTimer?.invalidate(); dateJumpTimer = nil; dateJumpToken = UUID()
            slideOverlay?.removeFromSuperview(); slideOverlay = nil
            if fadeDeletion { model.dateJump = nil }
        }
        func snapshot() -> NSImage? {
            guard let bitmap = bitmapImageRepForCachingDisplay(in:area) else { return nil }
            cacheDisplay(in:area,to:bitmap)
            let image = NSImage(size:area.size); image.addRepresentation(bitmap); return image
        }
        let old = (animate || fadeDeletion) ? snapshot() : nil
        renderedStart = model.weekStart; renderedEntries = model.shown
        needsDisplay = true
        if fadeDeletion, let old {
            let fading = EventDeletionSnapshot(frame:area)
            fading.image = old; fading.imageScaling = .scaleAxesIndependently; fading.wantsLayer = true
            addSubview(fading); deletionOverlay = fading
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.12
                context.timingFunction = CAMediaTimingFunction(name:.easeOut)
                fading.animator().alphaValue = 0
            } completionHandler: { [weak self, weak fading] in
                Task { @MainActor in
                    fading?.removeFromSuperview()
                    if self?.deletionOverlay === fading { self?.deletionOverlay = nil }
                }
            }
            return
        }
        guard let old, let new = snapshot() else {
            if days != 0 {
                let destination = model.weekStart
                DispatchQueue.main.async { [weak self] in if self?.model.dateJump?.to == destination { self?.model.dateJump = nil } }
            }
            return
        }
        let overlay = NSView(frame:area)
        overlay.wantsLayer = true; overlay.layer?.masksToBounds = true
        let distance = DaySwipeMath.jumpDistance(days:days,dayWidth:dayWidth,viewportWidth:area.width)
        let before = NSImageView(frame:NSRect(origin:.zero,size:area.size))
        before.image = old; before.imageScaling = .scaleAxesIndependently; before.wantsLayer = true
        let after = NSImageView(frame:NSRect(x:distance,y:0,width:area.width,height:area.height))
        after.image = new; after.imageScaling = .scaleAxesIndependently; after.wantsLayer = true
        overlay.addSubview(before); overlay.addSubview(after)
        addSubview(overlay); slideOverlay = overlay
        let began = CACurrentMediaTime(), duration = DaySwipeMath.jumpDuration(days:days)
        let token = UUID(); dateJumpToken = token
        let transition = model.dateJump ?? CalendarDateJump(from:model.calendar.date(byAdding:.day,value:-days,to:model.weekStart)!,to:model.weekStart,days:days)
        let timer = Timer(timeInterval:1.0/60,repeats:true) { [weak self, weak overlay] timer in
            Task { @MainActor in
                guard let self, self.dateJumpToken == token else { timer.invalidate(); return }
                guard self.model.weekStart == transition.to, self.model.dateJump?.to == transition.to else {
                    timer.invalidate(); self.dateJumpTimer = nil
                    overlay?.removeFromSuperview()
                    if self.slideOverlay === overlay { self.slideOverlay = nil }
                    return
                }
                let raw = min(1,(CACurrentMediaTime()-began)/duration)
                var frame = transition
                frame.progress = 1-pow(1-raw,3)
                let offsets = frame.offsets(dayWidth:self.dayWidth,viewportWidth:area.width)
                before.setFrameOrigin(NSPoint(x:offsets.before,y:0))
                after.setFrameOrigin(NSPoint(x:offsets.after,y:0))
                // The native body and SwiftUI date headings share exactly this
                // position, with no independent implicit header animation.
                var transaction = Transaction(); transaction.disablesAnimations = true
                withTransaction(transaction) { self.model.dateJump = raw < 1 ? frame : nil }
                if raw >= 1 {
                    timer.invalidate(); self.dateJumpTimer = nil
                    overlay?.removeFromSuperview()
                    if self.slideOverlay === overlay { self.slideOverlay = nil }
                }
            }
        }
        dateJumpTimer = timer; RunLoop.main.add(timer,forMode:.common)
    }

    private var horizontalImageArea: NSRect {
        NSRect(x:gutter,y:visibleRect.minY,width:bounds.width-gutter,height:visibleRect.height)
    }
    private func prepareTrackingImages(toward direction: CGFloat) {
        slideOverlay?.removeFromSuperview(); slideOverlay = nil
        let area = horizontalImageArea
        guard area.width > 0, area.height > 0 else { return }
        let scale = window?.backingScaleFactor ?? 2
        if area != trackingImageArea || scale != trackingImageScale {
            trackingImages.clear(); trackingImageArea = area; trackingImageScale = scale
        }
        let overlay = NSView(frame:area); overlay.wantsLayer = true; overlay.layer?.masksToBounds = true
        renderedStart = model.weekStart; renderedEntries = model.shown
        let savedStart = renderedStart, savedEntries = renderedEntries
        let savedHits = hits
        trackingViews = []
        trackingImageDirection = direction < 0 ? -1 : 1
        let retained = Set((-1...1).map { model.calendar.date(byAdding:.day,value:$0,to:savedStart)! })
        trackingImages.retain(retained)
        for shift in DaySwipeMath.imageShifts(toward:direction) {
            renderedStart = model.calendar.date(byAdding:.day,value:shift,to:savedStart)!
            let day = renderedStart
            guard let image = trackingImages.image(for:day,render:{
                self.renderedEntries = shift == 0 ? savedEntries : self.model.scrollPreviewEntries(start:day)
                guard let bitmap = self.bitmapImageRepForCachingDisplay(in:area) else { return nil }
                self.cacheDisplay(in:area,to:bitmap)
                let image = NSImage(size:area.size); image.addRepresentation(bitmap); return image
            }) else { continue }
            let x = CGFloat(shift)*dayWidth
            let tile = NSImageView(frame:NSRect(x:x,y:0,width:area.width,height:area.height))
            tile.image = image; tile.imageScaling = .scaleAxesIndependently; tile.wantsLayer = true
            overlay.addSubview(tile); trackingViews.append((tile,x))
        }
        renderedStart = savedStart; renderedEntries = savedEntries; hits = savedHits
        slideOverlay = overlay; addSubview(overlay)
    }
    func trackHorizontal(delta: CGFloat) {
        dateJumpTimer?.invalidate(); dateJumpTimer = nil; dateJumpToken = UUID(); model.dateJump = nil
        if settling {
            snapAnimation?.invalidate(); snapAnimation = nil
            trackingToken = UUID(); settling = false
            slideOverlay?.removeFromSuperview(); slideOverlay = nil; trackingViews = []
            trackingOffset = model.horizontalOffset
        }
        model.trackingHorizontalScroll = true
        let movement = DaySwipeMath.advance(offset:trackingOffset,delta:delta,width:dayWidth)
        trackingOffset = movement.offset
        if movement.days != 0 {
            model.navigateDays(movement.days)
        }
        let direction = trackingOffset == 0 ? delta : trackingOffset
        if trackingViews.isEmpty || movement.days != 0 || trackingImageDirection != (direction < 0 ? -1 : 1)
            || trackingImageArea != horizontalImageArea || trackingImageScale != (window?.backingScaleFactor ?? 2) {
            prepareTrackingImages(toward:direction)
        }
        for (tile,x) in trackingViews { tile.setFrameOrigin(NSPoint(x:x+trackingOffset,y:0)) }
        model.horizontalOffset = trackingOffset
    }
    func finishHorizontal(cancelled: Bool = false) {
        guard !trackingViews.isEmpty else {
            trackingOffset = 0; trackingImages.clear()
            model.horizontalOffset = 0; model.trackingHorizontalScroll = false
            return
        }
        let step = cancelled ? 0 : DaySwipeMath.settle(offset:trackingOffset,width:dayWidth)
        let goal = -CGFloat(step)*dayWidth
        let token = UUID(); trackingToken = token; settling = true
        // Change the underlying range now, while snapshots cover it. The
        // retained tiles complete only the remaining distance, without a jump.
        if step != 0 {
            model.horizontalOffset = trackingOffset+CGFloat(step)*dayWidth
            model.navigateDays(step)
        }
        snapAnimation?.invalidate()
        let from = trackingOffset
        let began = CACurrentMediaTime()
        let duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0.0 : DaySwipeMath.snapDuration
        let update: (Double) -> Void = { [weak self] progress in
            guard let self else { return }
            let offset = DaySwipeMath.snapOffset(from:from,to:goal,progress:progress)
            // One position drives the native grid and SwiftUI header, including
            // the rebased date range. Never start a second implicit animation.
            for (tile,x) in self.trackingViews { tile.setFrameOrigin(NSPoint(x:x+offset,y:0)) }
            var transaction = Transaction(); transaction.disablesAnimations = true
            withTransaction(transaction) { self.model.horizontalOffset = offset+CGFloat(step)*self.dayWidth }
        }
        let complete: () -> Void = { [weak self] in
            guard let self else { return }
            self.slideOverlay?.removeFromSuperview(); self.slideOverlay = nil
            self.trackingViews = []; self.trackingOffset = 0; self.settling = false
            self.trackingImages.clear()
            self.renderedStart = self.model.weekStart; self.renderedEntries = self.model.shown
            self.model.trackingHorizontalScroll = false; self.snapAnimation = nil; self.needsDisplay = true
        }
        if duration == 0 { update(1); complete(); return }
        let timer = Timer(timeInterval:1.0/120,repeats:true) { [weak self] timer in
            Task { @MainActor in
                guard let self, self.trackingToken == token else { timer.invalidate(); return }
                let progress = min(1,(CACurrentMediaTime()-began)/duration)
                update(progress)
                if progress >= 1 { timer.invalidate(); complete() }
            }
        }
        snapAnimation = timer
        RunLoop.main.add(timer,forMode:.common)
    }

    func text(_ text: String, rect: NSRect, size: CGFloat = 11, color: NSColor = .secondaryLabelColor, weight: NSFont.Weight = .regular, alignment: NSTextAlignment = .left) {
        let paragraph = NSMutableParagraphStyle(); paragraph.lineBreakMode = .byTruncatingTail; paragraph.alignment = alignment
        let scaledSize = AppTextSize.points(size)
        var frame = rect
        frame.size.height = max(rect.height,ceil(scaledSize*1.3))
        frame.origin.y -= (frame.height-rect.height)/2
        (text as NSString).draw(in: frame, withAttributes: [.font: NSFont.systemFont(ofSize: scaledSize, weight: weight), .foregroundColor: color, .paragraphStyle: paragraph])
    }
    private func drawWeatherOverlay(dark: Bool) {
        guard weatherReveal > 0 else { return }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.cgContext.setAlpha(weatherReveal)
        defer { NSGraphicsContext.restoreGraphicsState() }
        let railSlide = 26*(1-weatherReveal)
        for index in 0..<model.visibleDayCount {
            let hours = weatherHours(on:day(index))
            let x = gutter+CGFloat(index)*dayWidth
            guard !hours.isEmpty else {
                text("No forecast",rect:NSRect(x:x+3,y:top+4,width:max(1,dayWidth-6),height:12),size:8,color:.tertiaryLabelColor)
                continue
            }
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(rect:NSRect(x:x,y:top,width:dayWidth,height:24*CalendarMath.hourHeight)).addClip()
            for hour in hours {
                let y = top+CGFloat(model.minuteOfDay(hour.date)/60)*CalendarMath.hourHeight
                let cloud = max(0,min(1,(hour.cloudCover ?? 0)/100))
                if model.weather.showSky {
                    (hour.isDay && cloud < 0.3 ? NSColor.systemYellow : NSColor.systemGray).withAlphaComponent(dark ? 0.02+cloud*0.035 : 0.018+cloud*0.03).setFill()
                    NSRect(x:x,y:y,width:dayWidth,height:CalendarMath.hourHeight).fill()
                }
                if model.weather.showRain, let rain = hour.precipitation, rain > 0 {
                    NSColor.systemBlue.withAlphaComponent(min(0.16,0.025+rain*0.025)).setFill()
                    NSRect(x:x,y:y,width:dayWidth,height:CalendarMath.hourHeight).fill()
                    NSColor.systemBlue.withAlphaComponent(min(0.7,0.2+rain*0.08)).setStroke()
                    let drops = NSBezierPath(); drops.lineWidth = 0.6
                    for dx in stride(from:CGFloat(7),to:dayWidth-4,by:14) {
                        for dy in stride(from:CGFloat(6),to:CalendarMath.hourHeight,by:14) {
                            drops.move(to:NSPoint(x:x+dx,y:y+dy)); drops.line(to:NSPoint(x:x+dx-2,y:y+dy+4))
                        }
                    }
                    drops.stroke()
                }
                if model.weather.showWind, let wind = hour.windSpeed {
                    NSColor.systemTeal.withAlphaComponent(min(0.65,wind/45)).setFill()
                    NSRect(x:x+dayWidth-4+railSlide,y:y,width:3,height:CalendarMath.hourHeight).fill()
                }
                if model.calendar.component(.hour,from:hour.date) % 3 == 0 {
                    if model.weather.showSky || (model.weather.showRain && (hour.precipitation ?? 0) > 0), let symbol = NSImage(systemSymbolName:hour.symbol,accessibilityDescription:hour.condition) {
                        let symbolColor: NSColor = hour.symbol.hasPrefix("sun.") ? .systemOrange : .secondaryLabelColor
                        let visibleSymbol = symbol.withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors:[symbolColor])) ?? symbol
                        visibleSymbol.draw(in:NSRect(x:x+dayWidth-23+railSlide,y:y+3,width:15,height:12))
                    }
                    if let temperature = hour.temperature {
                        let value = WeatherTemperature(fahrenheit:temperature)
                        text(value.celsiusLabel,rect:NSRect(x:x+dayWidth-26+railSlide,y:y+17,width:23,height:11),size:7.5,color:.secondaryLabelColor,weight:.medium,alignment:.right)
                        text(value.fahrenheitLabel,rect:NSRect(x:x+dayWidth-26+railSlide,y:y+28,width:23,height:10),size:6.5,color:.secondaryLabelColor.withAlphaComponent(0.6),alignment:.right)
                    }
                    if model.weather.showWind, let symbol = NSImage(systemSymbolName:"wind",accessibilityDescription:"Wind")?.withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors:[.systemTeal])) { symbol.draw(in:NSRect(x:x+dayWidth-23+railSlide,y:y+41,width:15,height:10)) }
                }
            }
            NSGraphicsContext.restoreGraphicsState()
        }
    }
    private func drawDaylightGradient(_ elevations: [Double], in rect: NSRect, nightColor: NSColor, maximumAlpha: CGFloat) {
        DaylightGradientRenderer.draw(elevations,in:rect,nightColor:nightColor,maximumAlpha:maximumAlpha,mode:model.daylight.twilightMode)
    }
    private func updateDaylightTooltips() {
        let location = model.daylight.coordinate.map { "\($0.latitude),\($0.longitude)" } ?? "none"
        let key = "\(renderedStart)-\(top)-\(bounds.width)-\(model.primaryTimeZoneID)-\(model.clockZones.map(\.identifier))-\(model.weather.enabled)-\(model.weather.revision)-\(model.daylight.enabled)-\(model.daylight.twilightMode.rawValue)-\(location)-\(model.calendar.startOfDay(for:Date()))-\(model.clockZones.map { model.daylight.hasRibbonLocation($0) })"
        guard daylightTooltipKey != key else { return }
        daylightTooltipKey = key; hoverRegions = []; hideFastTooltip()
        func register(day: Date, zone: TimeZone?, x: CGFloat, width: CGFloat, labelZone: TimeZone, place: String) {
            let base = model.calendar.startOfDay(for:day)
            let formatter = DateFormatter(); formatter.timeZone = labelZone; formatter.dateFormat = "h:mma"
            let twilight = model.daylight.elevationProfile(on:day,calendar:model.calendar,ribbonZone:zone).map { DaylightMath.twilightRanges(profile:$0,mode:model.daylight.twilightMode) } ?? []
            if let profile = model.daylight.elevationProfile(on:day,calendar:model.calendar,ribbonZone:zone),
               let peak = DaylightMath.peakMinute(profile:profile) {
                let instant = model.dateAtMinute(Int(peak.rounded()),on:base)
                let rect = NSRect(x:x,y:top+CGFloat(peak/60)*CalendarMath.hourHeight-6,width:width,height:12)
                hoverRegions.append((rect,"Solar noon: "+formatter.string(from:instant).lowercased()+" · "+place+"\nThe sun is at its highest point for this location.",nil))
            }
            for transition in model.daylight.sunTransitions(on:day,calendar:model.calendar,ribbonZone:zone) {
                let minute = Int(transition.minute.rounded())
                let instant = model.dateAtMinute(minute,on:base)
                let nearest = twilight.min { abs(($0.lowerBound+$0.upperBound)/2-transition.minute) < abs(($1.lowerBound+$1.upperBound)/2-transition.minute) }
                let from = max(0,min(transition.minute-5,nearest?.lowerBound ?? transition.minute-5))
                let to = min(1440,max(transition.minute+5,nearest?.upperBound ?? transition.minute+5))
                let rect = NSRect(x:x,y:top+CGFloat(from/60)*CalendarMath.hourHeight,width:width,height:CGFloat((to-from)/60)*CalendarMath.hourHeight)
                let message = (transition.sunrise ? "Official sunrise: " : "Official sunset: ")+formatter.string(from:instant).lowercased()+" · "+place+"\n"+model.daylight.twilightMode.label+" shading follows the sun’s elevation."
                hoverRegions.append((rect,message,nil))
            }
        }
        for (index,zone) in model.clockZones.enumerated() { register(day:Date(),zone:zone,x:CGFloat(index)*CalendarModel.timeColumnWidth,width:CalendarModel.timeColumnWidth,labelZone:zone,place:CalendarModel.zoneLabel(zone)+" · today") }

    }
    private func drawWeatherDetails(_ hour: WeatherHour, at point: NSPoint) {
        let scale = AppTextSize.shared.scale
        let width = min(350*scale,visibleRect.width-16), height = min(285*scale,visibleRect.height-16)
        let x = max(visibleRect.minX+8,min(point.x+14,visibleRect.maxX-width-8))
        let y = max(visibleRect.minY+8,min(point.y+16,visibleRect.maxY-height-8))
        let rect = NSRect(x:x,y:y,width:width,height:height)
        let path = NSBezierPath(roundedRect:rect,xRadius:12,yRadius:12)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(0.2); shadow.shadowBlurRadius = 14; shadow.shadowOffset = NSSize(width:0,height:-3); shadow.set()
        NSColor.windowBackgroundColor.setFill(); path.fill()
        NSGraphicsContext.restoreGraphicsState()
        NSColor.separatorColor.withAlphaComponent(0.5).setStroke(); path.lineWidth = 0.5; path.stroke()
        NSGraphicsContext.saveGraphicsState(); path.addClip()
        let pad = 16*scale, left = rect.minX+16*scale
        text(model.weather.city,rect:NSRect(x:left,y:y+pad,width:width-pad*2,height:18*scale),size:12,color:.labelColor,weight:.semibold)
        let end = hour.date.addingTimeInterval(3600)
        text(model.dateLabel(hour.date,template:"EEE MMM d")+" · "+model.dateLabel(hour.date,template:"ha").lowercased()+"–"+model.dateLabel(end,template:"ha").lowercased(),rect:NSRect(x:left,y:y+36*scale,width:width-pad*2,height:16*scale),size:10,color:.secondaryLabelColor)
        if let symbol = NSImage(systemSymbolName:hour.symbol,accessibilityDescription:hour.condition) { symbol.draw(in:NSRect(x:left,y:y+65*scale,width:34*scale,height:30*scale)) }
        let temperature = hour.temperature.map { WeatherTemperature(fahrenheit:$0).pairedLabel } ?? "—"
        text(temperature,rect:NSRect(x:left+46*scale,y:y+56*scale,width:width-90*scale,height:36*scale),size:20,color:.labelColor,weight:.medium)
        text(hour.condition,rect:NSRect(x:left,y:y+103*scale,width:width-pad*2,height:17*scale),size:12,color:.labelColor)
        if let feels = hour.apparentTemperature { text("Feels like "+WeatherTemperature(fahrenheit:feels).pairedLabel,rect:NSRect(x:left,y:y+123*scale,width:width-pad*2,height:15*scale),size:10,color:.secondaryLabelColor) }
        let cellWidth = (width-pad*2-12*scale)/2
        let rows: [(String,String,String,String)] = [
            ("Precipitation",hour.precipitation.map { String(format:"%.1f mm",$0) } ?? "—","Chance",hour.precipitationProbability.map { "\(Int($0.rounded()))%" } ?? "—"),
            ("Wind",hour.windSpeed.map { "\(Int($0.rounded())) mph" } ?? "—","From",hour.windDirection.map { WeatherHour.compass($0)+" · \(Int($0.rounded()))°" } ?? "—"),
            ("Gusts",hour.windGusts.map { "\(Int($0.rounded())) mph" } ?? "—","Humidity",hour.humidity.map { "\(Int($0.rounded()))%" } ?? "—"),
            ("Cloud cover",hour.cloudCover.map { "\(Int($0.rounded()))%" } ?? "—","Period",hour.isDay ? "Daytime" : "Nighttime")
        ]
        for (index,row) in rows.enumerated() {
            let rowY = y+148*scale+CGFloat(index)*25*scale
            for (column,pair) in [(row.0,row.1),(row.2,row.3)].enumerated() {
                let cellX = left+CGFloat(column)*(cellWidth+12*scale)
                text(pair.0,rect:NSRect(x:cellX,y:rowY,width:cellWidth*0.57,height:17*scale),size:9,color:.secondaryLabelColor)
                text(pair.1,rect:NSRect(x:cellX+cellWidth*0.5,y:rowY,width:cellWidth*0.5,height:17*scale),size:10,color:.labelColor,weight:.medium,alignment:.right)
            }
        }
        text("Hourly forecast · Open-Meteo",rect:NSRect(x:left,y:rect.maxY-23*scale,width:width-pad*2,height:14*scale),size:9,color:.tertiaryLabelColor)
        NSGraphicsContext.restoreGraphicsState()
    }
    private func drawFastTooltip() {
        guard let tooltip = hoverTooltip, !model.trackingHorizontalScroll, model.draft == nil, down == nil else { return }
        let point = convert(tooltip.location,from:nil)
        guard visibleRect.contains(point), hoverRegions.contains(where:{ $0.text == tooltip.text && $0.rect.contains(point) }) else { return }
        if let weather = tooltip.weather { drawWeatherDetails(weather,at:point); return }
        let lines = tooltip.text.components(separatedBy:"\n")
        let scale = AppTextSize.shared.scale
        let width = min(CGFloat(300)*scale,max(120,visibleRect.width-20))
        var attributed: [(NSAttributedString,CGFloat)] = []
        for (index,line) in lines.enumerated() {
            let style = NSMutableParagraphStyle(); style.lineBreakMode = .byWordWrapping
            let font = NSFont.systemFont(ofSize:AppTextSize.points(index == 0 ? 12 : 10),weight:index == 0 ? .semibold : .regular)
            let text = NSAttributedString(string:line,attributes:[.font:font,.foregroundColor:index == 0 ? NSColor.labelColor : NSColor.secondaryLabelColor,.paragraphStyle:style])
            let height = ceil(text.boundingRect(with:NSSize(width:width-24,height:1000),options:[.usesLineFragmentOrigin,.usesFontLeading]).height)
            attributed.append((text,height))
        }
        let height = attributed.reduce(CGFloat(24)) { $0+$1.1+4 }-4
        let x = max(visibleRect.minX+8,min(point.x+12,visibleRect.maxX-width-8))
        var y = point.y+16
        if y+height > visibleRect.maxY-8 { y = point.y-height-12 }
        y = max(visibleRect.minY+8,y)
        let rect = NSRect(x:x,y:y,width:width,height:height)
        let path = NSBezierPath(roundedRect:rect,xRadius:9,yRadius:9)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(0.17); shadow.shadowBlurRadius = 10; shadow.shadowOffset = NSSize(width:0,height:-2); shadow.set()
        NSColor.windowBackgroundColor.setFill(); path.fill()
        NSGraphicsContext.restoreGraphicsState()
        NSColor.separatorColor.withAlphaComponent(0.5).setStroke(); path.lineWidth = 0.5; path.stroke()
        var textY = rect.minY+12
        for (text,lineHeight) in attributed {
            text.draw(with:NSRect(x:rect.minX+12,y:textY,width:rect.width-24,height:lineHeight),options:[.usesLineFragmentOrigin,.usesFontLeading])
            textY += lineHeight+4
        }
    }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.textBackgroundColor.setFill(); bounds.fill()
        let dark = effectiveAppearance.bestMatch(from:[.darkAqua,.aqua]) == .darkAqua
        // Daylight shading is confined to the timezone ribbons.
        for (index,zone) in model.clockZones.enumerated() {
            guard let elevations = model.daylight.elevationProfile(on:Date(),calendar:model.calendar,ribbonZone:zone) else { continue }
            let rect = NSRect(x:CGFloat(index)*CalendarModel.timeColumnWidth,y:top,width:CalendarModel.timeColumnWidth,height:24*CalendarMath.hourHeight)
            NSColor(calibratedRed:dark ? 0.95 : 1,green:dark ? 0.82 : 0.91,blue:dark ? 0.5 : 0.62,alpha:dark ? 0.055 : 0.12).setFill(); rect.fill()
            drawDaylightGradient(elevations,in:rect,nightColor:dark ? .black : NSColor(calibratedRed:0.35,green:0.39,blue:0.49,alpha:1),maximumAlpha:dark ? 0.35 : 0.13)
        }
        drawWeatherOverlay(dark:dark)
        updateDaylightTooltips()
        let scale = window?.backingScaleFactor ?? 2
        let hairline = 1 / scale
        func aligned(_ value: CGFloat) -> CGFloat { (value * scale).rounded() / scale + hairline / 2 }
        let lines = NSBezierPath(); lines.lineWidth = hairline
        for d in 0...model.visibleDayCount {
            let x = aligned(d == 0 ? gutter-CalendarModel.timeRibbonGap : gutter+CGFloat(d)*dayWidth)
            lines.move(to:NSPoint(x:x,y:0)); lines.line(to:NSPoint(x:x,y:bounds.height))
        }
        let labelDay = model.calendar.startOfDay(for:Date())
        for h in 0...24 {
            let y = top+CGFloat(h)*CalendarMath.hourHeight
            lines.move(to:NSPoint(x:gutter,y:aligned(y))); lines.line(to:NSPoint(x:bounds.width,y:aligned(y)))
            if h < 24 {
                let instant = model.calendar.date(bySettingHour:h,minute:0,second:0,of:labelDay)!
                for (index,zone) in model.clockZones.enumerated() {
                    var clock = model.calendar; clock.timeZone = zone
                    let parts = clock.dateComponents([.hour,.minute],from:instant)
                    let clockLabel = CalendarDateFormatting.string(instant,timeZone:zone,format:parts.minute == 0 ? "ha" : "h:mma",locale:Locale(identifier:"en_US_POSIX")).lowercased()
                    let primary = index == model.clockZones.count-1
                    text(clockLabel,rect:NSRect(x:CGFloat(index)*CalendarModel.timeColumnWidth+2,y:y-6,width:CalendarModel.timeColumnWidth-6,height:12),size:parts.minute == 0 ? (primary ? 9 : 8) : 7,color:primary ? .secondaryLabelColor : .tertiaryLabelColor,weight:primary ? .medium : .regular,alignment:.right)
                    let local = clock.dateComponents([.era,.year,.month,.day],from:instant)
                    let reference = model.calendar.dateComponents([.era,.year,.month,.day],from:labelDay)
                    if !primary && local != reference {
                        var neutral = Calendar(identifier:.gregorian); neutral.timeZone = TimeZone(secondsFromGMT:0)!
                        if let a = neutral.date(from:reference), let b = neutral.date(from:local) {
                            let delta = neutral.dateComponents([.day],from:a,to:b).day ?? 0
                            text(delta > 0 ? "+1d" : "−1d",rect:NSRect(x:CGFloat(index)*CalendarModel.timeColumnWidth+2,y:y+6,width:CalendarModel.timeColumnWidth-6,height:9),size:6,color:.tertiaryLabelColor,alignment:.right)
                        }
                    }
                }
            }
        }
        for index in 1..<model.clockZones.count {
            lines.move(to:NSPoint(x:CGFloat(index)*CalendarModel.timeColumnWidth,y:0)); lines.line(to:NSPoint(x:CGFloat(index)*CalendarModel.timeColumnWidth,y:bounds.height))
        }
        NSColor(calibratedWhite:dark ? 0.29 : 0.87,alpha:1).setStroke()
        lines.stroke()
        if weatherReveal > 0 {
            // Separate the weather-painted days without changing event times
            // or column geometry. Fade the gaps with the weather transition.
            NSColor.textBackgroundColor.withAlphaComponent(weatherReveal).setFill()
            for index in 1..<model.visibleDayCount {
                NSRect(x:gutter+CGFloat(index)*dayWidth,y:top,width:5,height:24*CalendarMath.hourHeight).fill()
            }
        }
        for (index,zone) in model.clockZones.enumerated() {
            guard let profile = model.daylight.elevationProfile(on:Date(),calendar:model.calendar,ribbonZone:zone),
                  let minute = DaylightMath.peakMinute(profile:profile),
                  let sun = NSImage(systemSymbolName:"sun.max",accessibilityDescription:"Solar noon") else { continue }
            let ink = dark ? NSColor.systemYellow.withAlphaComponent(0.9) : NSColor(calibratedRed:0.72,green:0.45,blue:0.06,alpha:0.9)
            let icon = sun.withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors:[ink])) ?? sun
            let size: CGFloat = 10
            icon.draw(in:NSRect(x:CGFloat(index)*CalendarModel.timeColumnWidth+2,y:top+CGFloat(minute/60)*CalendarMath.hourHeight-size/2,width:size,height:size))
        }
        hits = []; resizeZones = []
        var displayed = renderedEntries
        if let preview = model.creationPreview { displayed.append(preview) }
        if let resizing {
            let preview = model.resizeChange(resizing.entry,startEdge:resizing.startEdge,minutes:resizeMinutes)
            displayed = displayed.map { item in
                guard item.id == resizing.entry.id else { return item }
                var changed = item; changed.start = preview.start; changed.end = preview.end; return changed
            }
        }
        if didDrag {
            displayed = displayed.map { item in
                var copy = item
                if model.selected.contains(item.id) { copy.start = copy.start.addingTimeInterval(Double(delta)*60); copy.end = copy.end.addingTimeInterval(Double(delta)*60) }
                return copy
            }
        }
        for d in 0..<model.visibleDayCount {
            let start = day(d), end = day(d+1)
            let items = displayed.filter { !$0.allDay && $0.start < end && $0.end > start }
            let placements = OverlapLayout.columns(items.map { TimedInterval(id:$0.id,start:max(start,$0.start),end:min(end,$0.end)) })
            var cards: [(CalendarEntry,NSRect)] = []
            for item in items.sorted(by: { $0.start == $1.start ? $0.id < $1.id : $0.start < $1.start }) {
                guard let placement = placements[item.id] else { continue }
                let begin = max(start,item.start), finish = min(end,item.end)
                let y = top + CGFloat(model.minuteOfDay(begin)/60) * CalendarMath.hourHeight
                let height = max(1,CGFloat((finish == end ? 1440 : model.minuteOfDay(finish))-model.minuteOfDay(begin))/60 * CalendarMath.hourHeight - 1)
                let weatherGapInset = 2*weatherReveal
                let availableWidth = dayWidth-(!weatherHours(on:start).isEmpty ? 26*weatherReveal : 0)
                let inset = min(CGFloat(placement.depth)*7,(availableWidth-6)/CGFloat(placement.count)*0.16)
                let gap: CGFloat = 2
                let width = max(1,(availableWidth-6-weatherGapInset-inset-gap*CGFloat(placement.count-1))/CGFloat(placement.count))
                let rect = NSRect(x:gutter+CGFloat(d)*dayWidth+3+weatherGapInset+inset+CGFloat(placement.column)*(width+gap),y:y+0.5,width:width,height:height)
                if item.writable && !item.id.hasPrefix("draft-") {
                    let edgeHeight = min(5,rect.height/3)
                    if item.start >= start { resizeZones.append((NSRect(x:rect.minX,y:rect.minY,width:rect.width,height:edgeHeight),item,true)) }
                    if item.end <= end { resizeZones.append((NSRect(x:rect.minX,y:rect.maxY-edgeHeight,width:rect.width,height:edgeHeight),item,false)) }
                }
                cards.append((item,rect))
            }
            let overlapping = cards.indices.filter { index in
                cards.indices.contains { $0 != index && cards[index].1.intersects(cards[$0].1) }
            }
            for (index,card) in cards.enumerated() {
                let intersections = cards.indices.filter { $0 < index }.map { card.1.intersection(cards[$0].1) }.filter { !$0.isEmpty }
                drawEvent(card.0,rect:card.1,backgroundOnly:overlapping.contains(index),overlapRects:intersections)
            }
            let labelFrames = ProtectedTitleLayout.frames(cards.map { $0.1 },textScale:AppTextSize.shared.scale)
            for index in overlapping {
                let title = labelFrames[index]
                let time = NSRect(x:title.minX,y:title.maxY+2,width:title.width,height:12)
                let canShowTime = cards[index].1.contains(time) && !labelFrames.enumerated().contains { $0.offset != index && $0.element.intersects(time) }
                let item = cards[index].0
                var titleFrame = title
                if !item.writable { titleFrame.size.width = max(1,title.width-min(10,max(4,cards[index].1.height-2))-5) }
                drawProtectedTitle(item,frame:titleFrame,timeFrame:canShowTime ? time : nil)
                let notesY = canShowTime ? time.maxY+4 : titleFrame.maxY+4
                var notesBottom = cards[index].1.maxY-4
                let notesLeft = titleFrame.minX
                let notesRight = titleFrame.maxX
                // Keep previews out of other cards and their protected titles.
                let blockers = cards.enumerated().filter { $0.offset != index }.map { $0.element.1 }
                    + labelFrames.enumerated().filter { $0.offset != index }.map { $0.element }
                for blocker in blockers where blocker.maxX > notesLeft && blocker.minX < notesRight && blocker.maxY > notesY {
                    notesBottom = min(notesBottom,max(notesY,blocker.minY-3))
                }
                drawEventDetails(item,in:NSRect(x:notesLeft,y:notesY,width:titleFrame.width,height:max(0,notesBottom-notesY)))
                if !item.writable { drawReadOnlyIndicator(in:cards[index].1,color:item.color) }
            }
            for card in cards where model.selected.contains(card.0.id) && card.0.writable {
                card.0.color.withAlphaComponent(0.85).setFill()
                for edge in resizeZones where edge.entry.id == card.0.id {
                    NSBezierPath(roundedRect:NSRect(x:edge.rect.midX-min(8,edge.rect.width/4),y:edge.startEdge ? edge.rect.minY+1 : edge.rect.maxY-2,width:min(16,edge.rect.width/2),height:1.5),xRadius:0.75,yRadius:0.75).fill()
                }
            }
        }
        if let drop = bankDrop {
            var taskStart = drop.start
            for task in model.bankDragTasks(drop.id) {
            guard let source = model.calendar(for:task) else { continue }
            let end = taskStart.addingTimeInterval(Double(task.minutes)*60)
            let ghost = CalendarEntry(id:"bank-drop",title:task.title,start:taskStart,end:end,calendarID:source.id,color:source.color)
            for d in 0..<model.visibleDayCount where taskStart < day(d+1) && end > day(d) {
                let start = max(taskStart,day(d)), finish = min(end,day(d+1))
                let rect = NSRect(x:gutter+CGFloat(d)*dayWidth+4,y:top+CGFloat(model.minuteOfDay(start)/60)*CalendarMath.hourHeight+1,width:dayWidth-8,height:max(19,CGFloat((finish == day(d+1) ? 1440 : model.minuteOfDay(finish))-model.minuteOfDay(start))/60*CalendarMath.hourHeight-2))
                drawEvent(ghost,rect:rect,registerHit:false)
                source.color.setStroke()
                let outline = NSBezierPath(roundedRect:rect,xRadius:5,yRadius:5)
                outline.lineWidth = 1.5; outline.setLineDash([4,3],count:2,phase:0); outline.stroke()
            }
            taskStart = end
            }
        }
        if let index = creatingDay, let range = creation {
            drawCreation(at:model.dateAtMinute(range.lowerBound,on:day(index)),minutes:range.upperBound-range.lowerBound)
        }
        if let date = newTaskDrop { drawCreation(at:date,minutes:30) }
        let now = Date()
        if now >= renderedStart && now < day(model.visibleDayCount) {
            let d = model.calendar.dateComponents([.day], from:renderedStart,to:model.calendar.startOfDay(for:now)).day!
            let y = top + CGFloat(model.minuteOfDay(now)/60)*CalendarMath.hourHeight
            let across = NSBezierPath(); across.lineWidth = 0.75
            NSColor.systemRed.withAlphaComponent(0.15).setStroke()
            across.move(to:NSPoint(x:gutter,y:y)); across.line(to:NSPoint(x:bounds.width,y:y)); across.stroke()
            NSColor.systemRed.setStroke(); let line = NSBezierPath(); line.lineWidth = 1
            line.move(to:NSPoint(x:gutter+CGFloat(d)*dayWidth,y:y)); line.line(to:NSPoint(x:gutter+CGFloat(d+1)*dayWidth,y:y)); line.stroke()
            let badge = NSRect(x:gutter-33,y:y-6,width:31,height:13)
            NSColor.systemRed.setFill(); NSBezierPath(roundedRect:badge,xRadius:6.5,yRadius:6.5).fill()
            let label = CalendarDateFormatting.string(now,timeZone:model.primaryTimeZone,format:"h:mm")
            let labelWidth = (label as NSString).size(withAttributes:[.font:NSFont.systemFont(ofSize:AppTextSize.points(8),weight:.semibold)]).width
            text(label,rect:NSRect(x:badge.midX-labelWidth/2,y:y-5,width:labelWidth+1,height:12),size:8,color:.white,weight:.semibold)
        }
        if let location = rulerHoverInWindow, !model.trackingHorizontalScroll {
            let point = convert(location,from:nil)
            if point.x >= 0 && point.x < gutter && point.y >= stickyBottom && point.y <= bounds.height && visibleRect.contains(point) {
                let guide = NSBezierPath(); guide.lineWidth = 0.75
                NSColor.controlAccentColor.withAlphaComponent(0.75).setStroke()
                guide.move(to:NSPoint(x:0,y:point.y)); guide.line(to:NSPoint(x:bounds.width,y:point.y)); guide.stroke()
                NSColor.controlAccentColor.setFill()
                NSBezierPath(ovalIn:NSRect(x:gutter-2.5,y:point.y-2.5,width:5,height:5)).fill()
            }
        }
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect:NSRect(x:0,y:stickyTop,width:bounds.width,height:top)).addClip()
        NSColor.textBackgroundColor.setFill()
        NSRect(x:0,y:stickyTop,width:bounds.width,height:top).fill()
        text("all-day",rect:NSRect(x:gutter-32,y:stickyTop+16,width:28,height:14),size:7,color:.tertiaryLabelColor,alignment:.right)
        let timedArea = NSRect(x:0,y:stickyBottom,width:bounds.width,height:max(0,bounds.height-stickyBottom))
        hits = hits.compactMap { rect,item in
            let visible = rect.intersection(timedArea)
            return visible.isEmpty ? nil : (visible,item)
        }
        resizeZones = resizeZones.filter { $0.rect.minY >= stickyBottom }

        let allDayItems = displayed.filter(\.allDay)
        let spans = AllDayLayout.spans(allDayItems.map { TimedInterval(id:$0.id,start:$0.start,end:$0.end) },weekStart:renderedStart,calendar:model.calendar,dayCount:model.visibleDayCount)
        let rowCount = (spans.map(\.row).max() ?? -1)+1
        let expansion = AllDayTrayLayout.expansion(height:top,rows:rowCount)
        allDayToggleRects = []
        for span in spans {
            guard span.endDay > span.firstDay,
                  let item = allDayItems.first(where:{ $0.id == span.id }) else { continue }
            let metrics = AllDayTrayLayout.rowFrame(row:span.row,expansion:expansion)
            let rect = NSRect(x:gutter+CGFloat(span.firstDay)*dayWidth+3,y:stickyTop+metrics.y,width:CGFloat(span.endDay-span.firstDay)*dayWidth-6,height:metrics.height)
            if item.writable && (span.row < 2 || expansion >= 0.999) {
                let edgeWidth = min(8,rect.width/2)
                if item.start >= renderedStart {
                    resizeZones.append((NSRect(x:rect.minX,y:rect.minY,width:edgeWidth,height:rect.height),item,true))
                }
                let visibleEnd = model.calendar.date(byAdding:.day,value:model.visibleDayCount,to:renderedStart)!
                if item.end <= visibleEnd {
                    resizeZones.append((NSRect(x:rect.maxX-edgeWidth,y:rect.minY,width:edgeWidth,height:rect.height),item,false))
                }
            }
            if span.row < 2 { drawEvent(item,rect:rect); drawAllDayResizeHandles(item,in:rect); continue }
            if expansion < 1 {
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current?.cgContext.setAlpha(1-expansion)
                drawEvent(item,rect:rect,registerHit:false,backgroundOnly:true)
                NSGraphicsContext.restoreGraphicsState()
            }
            if expansion > 0 {
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current?.cgContext.setAlpha(expansion)
                drawEvent(item,rect:rect,registerHit:expansion >= 0.999,backgroundOnly:expansion < 0.5)
                if expansion >= 0.999 { drawAllDayResizeHandles(item,in:rect) }
                NSGraphicsContext.restoreGraphicsState()
            }
            if !model.allDayExpanded { allDayToggleRects.append(rect.insetBy(dx:-2,dy:-0.5)) }
        }
        if let first = allDayCreationStart, let last = allDayCreationEnd {
            let lower = min(first,last), upper = max(first,last)
            let rect = NSRect(x:gutter+CGFloat(lower)*dayWidth+3,y:stickyTop+2,width:CGFloat(upper-lower+1)*dayWidth-6,height:max(16,top-4))
            let color = model.creationCalendar?.color ?? NSColor.controlAccentColor
            color.withAlphaComponent(0.18).setFill()
            let preview = NSBezierPath(roundedRect:rect,xRadius:4,yRadius:4)
            preview.fill(); color.setStroke(); preview.lineWidth = 1.5; preview.stroke()
        }
        let toggleRect = NSRect(x:max(0,gutter-32),y:stickyBottom-17,width:28,height:14)
        text(model.allDayExpanded ? "−" : "+",rect:toggleRect,size:12,color:.secondaryLabelColor,weight:.medium,alignment:.right)
        allDayToggleRects.append(NSRect(x:0,y:stickyTop,width:gutter,height:top))
        NSGraphicsContext.restoreGraphicsState()
        NSColor(calibratedWhite:dark ? 0.29 : 0.87,alpha:1).setFill()
        NSRect(x:0,y:stickyBottom-hairline,width:bounds.width,height:hairline).fill()
        drawFastTooltip()
    }
    private func drawAllDayResizeHandles(_ item: CalendarEntry, in rect: NSRect) {
        guard item.writable, model.selected.contains(item.id) else { return }
        item.color.withAlphaComponent(0.8).setFill()
        for edge in resizeZones where edge.entry.id == item.id {
            let x = edge.startEdge ? rect.minX+2 : rect.maxX-4
            NSBezierPath(roundedRect:NSRect(x:x,y:rect.midY-3,width:2,height:6),xRadius:1,yRadius:1).fill()
        }
    }
    func drawEvent(_ item: CalendarEntry, rect: NSRect, registerHit: Bool = true, backgroundOnly: Bool = false, overlapRects: [NSRect] = []) {
        let selected = model.selected.contains(item.id)
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let tint = item.color.usingColorSpace(.deviceRGB) ?? item.color
        let fill = NSColor.textBackgroundColor.blended(withFraction: selected ? 0.30 : (dark ? 0.22 : 0.14), of: tint) ?? tint
        let ink = tint.blended(withFraction: dark ? 0.35 : 0.48, of: dark ? .white : .black) ?? tint
        let path = NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5)
        // Trial: translucent fills across the entire card; text and accents
        // remain fully opaque. Keep the overlap-only treatment easy to restore.
        if translucentWholeCards {
            fill.withAlphaComponent(0.55).setFill(); path.fill()
        } else {
        // Preserve the normal fill outside intersections; only overlapping
        // portions let the underlying calendar color show through.
        NSGraphicsContext.saveGraphicsState()
        for overlap in overlapRects {
            let outside = NSBezierPath(rect:rect)
            outside.appendRect(overlap); outside.windingRule = .evenOdd; outside.addClip()
        }
        fill.setFill(); path.fill()
        NSGraphicsContext.restoreGraphicsState()
        if !overlapRects.isEmpty {
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current?.cgContext.clip(to:overlapRects.map { $0 })
            fill.withAlphaComponent(0.55).setFill(); path.fill()
            NSGraphicsContext.restoreGraphicsState()
        }
        }
        if item.invitationStatus == .unanswered {
            NSGraphicsContext.saveGraphicsState()
            path.addClip()
            tint.withAlphaComponent(dark ? 0.18 : 0.12).setStroke()
            let hatching = NSBezierPath(); hatching.lineWidth = 3
            var x = rect.minX-rect.height
            while x < rect.maxX {
                hatching.move(to:NSPoint(x:x,y:rect.maxY))
                hatching.line(to:NSPoint(x:x+rect.height,y:rect.minY))
                x += 9
            }
            hatching.stroke()
            NSGraphicsContext.restoreGraphicsState()
        }
        (dark ? NSColor.black : NSColor.white).withAlphaComponent(dark ? 0.36 : 0.85).setStroke()
        let separator = NSBezierPath(roundedRect:rect.insetBy(dx:0.25,dy:0.25),xRadius:4.75,yRadius:4.75)
        separator.lineWidth = 0.5; separator.stroke()
        if !overlapRects.isEmpty {
            NSGraphicsContext.saveGraphicsState()
            // Strengthen only the horizontal card edges inside an overlap.
            // Clipping the rounded outline preserves the existing corners.
            let edgeClips = overlapRects.flatMap { overlap -> [NSRect] in
                var edges: [NSRect] = []
                if overlap.minY <= rect.minY+1 {
                    edges.append(NSRect(x:overlap.minX,y:rect.minY-1,width:overlap.width,height:3))
                }
                if overlap.maxY >= rect.maxY-1 {
                    edges.append(NSRect(x:overlap.minX,y:rect.maxY-2,width:overlap.width,height:3))
                }
                return edges
            }
            if !edgeClips.isEmpty {
                NSGraphicsContext.current?.cgContext.clip(to:edgeClips)
                (dark ? NSColor.black : NSColor.white).setStroke()
                let overlapEdge = NSBezierPath(roundedRect:rect.insetBy(dx:0.25,dy:0.25),xRadius:4.75,yRadius:4.75)
                overlapEdge.lineWidth = 0.5; overlapEdge.stroke()
            }
            NSGraphicsContext.restoreGraphicsState()
        }
        if selected { tint.setStroke(); path.lineWidth = 1.5; path.stroke() }
        tint.setFill()
        let accent = NSRect(x:rect.minX,y:rect.minY,width:EventCardInsets.accentWidth,height:rect.height)
        if item.invitationStatus == .unanswered || item.invitationStatus == .maybe {
            let dash: CGFloat = item.invitationStatus == .unanswered ? 5 : 1.5
            let gap: CGFloat = 3
            var y = accent.minY
            while y < accent.maxY {
                let segment = NSRect(x:accent.minX,y:y,width:accent.width,height:min(dash,accent.maxY-y))
                NSBezierPath(roundedRect:segment,xRadius:1.5,yRadius:1.5).fill()
                y += dash+gap
            }
        } else {
            NSBezierPath(roundedRect:accent,xRadius:1.5,yRadius:1.5).fill()
        }
        if backgroundOnly {
            if registerHit && !item.id.hasPrefix("draft-") { hits.append((rect,item)) }
            return
        }
        NSGraphicsContext.saveGraphicsState()
        let compact = rect.height < 24
        NSBezierPath(rect:rect.insetBy(dx:3,dy:compact ? 0 : min(2,rect.height*0.1))).addClip()
        let contentX = rect.minX + EventCardInsets.textLeading
        let contentWidth = max(1,rect.width-EventCardInsets.textLeading-EventCardInsets.textTrailing-(item.writable ? 0 : min(10,max(4,rect.height-2))+5))
        let title = item.displayTitle
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = rect.height < 28 ? .byTruncatingTail : .byWordWrapping
        let fontSize: CGFloat = compact ? min(AppTextSize.points(item.allDay ? 9 : 10),max(1,(rect.height-0.5)/1.18)) : AppTextSize.points(10)
        let attributes: [NSAttributedString.Key: Any] = [.font:NSFont.systemFont(ofSize:fontSize,weight:.semibold), .foregroundColor:ink, .paragraphStyle:paragraph]
        let measured = (title as NSString).boundingRect(with:NSSize(width:contentWidth,height:1000),options:[.usesLineFragmentOrigin,.usesFontLeading],attributes:attributes).height
        let lineHeight: CGFloat = compact ? min(rect.height,fontSize*1.18) : ceil(fontSize*1.25)
        let titleRoom = rect.height >= 46 ? lineHeight * 2 : lineHeight
        let titleHeight = min(titleRoom, max(lineHeight,ceil(measured)))
        let timeY = rect.minY+4+titleHeight+2
        let canShowTime = !item.allDay && timeY+12 <= rect.maxY-3
        let titleFrame = NSRect(x:contentX,y:compact ? rect.minY : rect.minY+4,width:contentWidth,height:compact ? rect.height : titleHeight)
        let inline = !canShowTime && drawInlineEventLabel(item,in:titleFrame,font:NSFont.systemFont(ofSize:fontSize,weight:.semibold),color:ink)
        if !inline && compact {
            drawCenteredTitle(title,rect:NSRect(x:contentX,y:rect.minY,width:contentWidth,height:rect.height),font:NSFont.systemFont(ofSize:fontSize,weight:.semibold),color:ink)
        } else if !inline {
            (title as NSString).draw(with:NSRect(x:contentX,y:rect.minY+4,width:contentWidth,height:titleHeight),options:[.usesLineFragmentOrigin,.usesFontLeading,.truncatesLastVisibleLine],attributes:attributes)
        }
        if canShowTime {
            drawEventClock(at:NSPoint(x:contentX,y:timeY),color:ink)
            drawEventTime(item,rect:NSRect(x:contentX+12,y:timeY,width:max(1,contentWidth-12),height:13),color:ink)
        }
        if !item.allDay {
            let notesY = timeY+16
            drawEventDetails(item,in:NSRect(x:contentX,y:notesY,width:contentWidth,height:max(0,rect.maxY-4-notesY)))
        }
        NSGraphicsContext.restoreGraphicsState()
        if !item.writable { drawReadOnlyIndicator(in:rect,color:item.color) }
        if registerHit && !item.id.hasPrefix("draft-") { hits.append((rect,item)) }
    }
    private static let eventClockImage = NSImage(systemSymbolName:"clock",accessibilityDescription:"Time")?
        .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize:10,weight:.regular))
    private static let eventMapImage = NSImage(systemSymbolName:"map",accessibilityDescription:"Location")?
        .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize:10,weight:.regular))
    private func drawEventClock(at point: NSPoint, color: NSColor) {
        guard let image = Self.eventClockImage else { return }
        let tinted = image.withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors:[color.withAlphaComponent(0.8)])) ?? image
        tinted.draw(in:NSRect(x:point.x,y:point.y+1,width:10,height:10))
    }
    private func drawEventTime(_ item: CalendarEntry, rect: NSRect, color: NSColor) {
        let label = EventTimeLabel.string(start:item.start,end:item.end,calendar:model.calendar)
        let size = AppTextSize.points(9)
        let attributed = EventCardLabelLayout.time(label,font:NSFont.systemFont(ofSize:size),color:color)
        var frame = rect
        frame.size.height = max(rect.height,ceil(size*1.3))
        frame.origin.y -= (frame.height-rect.height)/2
        attributed.draw(in:frame)
    }
    private func drawInlineEventLabel(_ item: CalendarEntry, in frame: NSRect, font: NSFont, color: NSColor) -> Bool {
        guard !item.allDay else { return false }
        let label = EventTimeLabel.string(start:item.start,end:item.end,calendar:model.calendar)
        let time = EventCardLabelLayout.time(label,font:NSFont.systemFont(ofSize:AppTextSize.points(9)),color:color,durationFirst:true)
        guard let labels = EventCardLabelLayout.inline(title:item.displayTitle,time:time,titleFont:font,color:color,in:frame),
              let context = NSGraphicsContext.current?.cgContext else { return false }
        let titleLine = CTLineCreateWithAttributedString(labels.title), timeLine = CTLineCreateWithAttributedString(labels.time)
        let glyphs = CTLineGetBoundsWithOptions(titleLine,.useGlyphPathBounds).union(CTLineGetBoundsWithOptions(timeLine,.useGlyphPathBounds))
        context.saveGState()
        context.clip(to:frame)
        context.translateBy(x:frame.minX,y:frame.midY)
        context.scaleBy(x:1,y:-1)
        context.textMatrix = .identity
        context.textPosition = CGPoint(x:0,y:-glyphs.midY)
        CTLineDraw(titleLine,context)
        context.textPosition = CGPoint(x:labels.timeFrame.minX-frame.minX,y:-glyphs.midY)
        CTLineDraw(timeLine,context)
        context.restoreGState()
        return true
    }
    private func drawEventDetails(_ item: CalendarEntry, in rect: NSRect) {
        guard !item.allDay else { return }
        var remaining = rect
        let location = item.location.split(whereSeparator:{ $0.isWhitespace }).joined(separator:" ")
        let font = NSFont.systemFont(ofSize:AppTextSize.points(9))
        let lineHeight = ceil(font.ascender-font.descender+font.leading)
        if !location.isEmpty, rect.width >= 30, rect.height >= lineHeight {
            let dark = effectiveAppearance.bestMatch(from:[.darkAqua,.aqua]) == .darkAqua
            let tint = item.color.usingColorSpace(.deviceRGB) ?? item.color
            let ink = tint.blended(withFraction:dark ? 0.35 : 0.48,of:dark ? .white : .black) ?? tint
            let paragraph = NSMutableParagraphStyle(); paragraph.lineBreakMode = .byWordWrapping
            let attributes: [NSAttributedString.Key:Any] = [.font:font,.foregroundColor:ink.withAlphaComponent(0.8),.paragraphStyle:paragraph]
            let iconWidth = AppTextSize.points(10), indent = AppTextSize.points(12)
            let textWidth = max(1,rect.width-indent)
            let measured = (location as NSString).boundingRect(with:NSSize(width:textWidth,height:1000),options:[.usesLineFragmentOrigin,.usesFontLeading],attributes:attributes).height
            let rows = min(2,max(1,Int(floor(rect.height/lineHeight))))
            let height = min(CGFloat(rows)*lineHeight,max(lineHeight,ceil(measured)))
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(rect:rect).addClip()
            if let map = Self.eventMapImage?.withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors:[ink.withAlphaComponent(0.8)])) {
                map.draw(in:NSRect(x:rect.minX,y:rect.minY+1,width:iconWidth,height:iconWidth))
            }
            (location as NSString).draw(with:NSRect(x:rect.minX+indent,y:rect.minY,width:textWidth,height:height),options:[.usesLineFragmentOrigin,.usesFontLeading,.truncatesLastVisibleLine],attributes:attributes)
            NSGraphicsContext.restoreGraphicsState()
            remaining.origin.y += height+3
            remaining.size.height = max(0,rect.maxY-remaining.minY)
        }
        drawNotes(item,in:remaining)
    }
    private func drawNotes(_ item: CalendarEntry, in rect: NSRect) {
        let notes = CalendarNotePreview.plainText(item.notes)
        let font = NSFont.systemFont(ofSize:AppTextSize.points(9))
        let lineHeight = ceil(font.ascender-font.descender+font.leading)
        guard !item.allDay, !notes.isEmpty, rect.width >= 30, rect.height >= lineHeight else { return }
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.lineSpacing = 1
        let dark = effectiveAppearance.bestMatch(from:[.darkAqua,.aqua]) == .darkAqua
        let tint = item.color.usingColorSpace(.deviceRGB) ?? item.color
        let ink = tint.blended(withFraction:dark ? 0.35 : 0.48,of:dark ? .white : .black) ?? tint
        let preview = NSRect(x:rect.minX,y:rect.minY,width:rect.width,height:rect.height)
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect:preview).addClip()
        let attributed = NSMutableAttributedString(string:notes,attributes:[.font:font,.foregroundColor:ink.withAlphaComponent(0.55),.paragraphStyle:paragraph])
        let pattern = try! NSRegularExpression(pattern:#"(?i)⚙️?\s*(?=(?:Added|Made|Created) by (Claude|ChatGPT|ChatGBT))"#)
        for match in pattern.matches(in:notes,range:NSRange(location:0,length:attributed.length)).reversed() {
            let name = (notes as NSString).substring(with:match.range(at:1)).lowercased() == "claude" ? "claude" : "openai"
            if let url = Bundle.main.url(forResource:name,withExtension:"png",subdirectory:"AttributionIcons"), let image = NSImage(contentsOf:url) {
                let tinted = NSImage(size:image.size)
                tinted.lockFocus(); ink.withAlphaComponent(0.55).setFill(); NSRect(origin:.zero,size:image.size).fill()
                image.draw(at:.zero,from:.zero,operation:.destinationIn,fraction:1); tinted.unlockFocus()
                let attachment = NSTextAttachment(); attachment.image = tinted
                attachment.bounds = NSRect(x:0,y:font.descender,width:font.pointSize,height:font.pointSize)
                let replacement = NSMutableAttributedString(attachment:attachment); replacement.append(NSAttributedString(string:" "))
                attributed.replaceCharacters(in:match.range,with:replacement)
            }
        }
        attributed.draw(with:preview,options:[.usesLineFragmentOrigin,.usesFontLeading,.truncatesLastVisibleLine])
        NSGraphicsContext.restoreGraphicsState()
    }
    private func drawReadOnlyIndicator(in rect: NSRect, color: NSColor) {
        guard rect.width > 18 else { return }
        let size = min(10,max(4,rect.height-2))
        let icon = NSRect(x:rect.maxX-size-4,y:rect.height < 24 ? rect.midY-size/2 : rect.minY+4,width:size,height:size)
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        let dark = effectiveAppearance.bestMatch(from:[.darkAqua,.aqua]) == .darkAqua
        let tint = color.usingColorSpace(.deviceRGB) ?? color
        let ink = tint.blended(withFraction:dark ? 0.35 : 0.48,of:dark ? .white : .black) ?? tint
        context.setStrokeColor(ink.cgColor)
        context.setLineWidth(0.9); context.setLineCap(.round); context.setLineJoin(.round)
        context.addPath(ReadOnlyLockGlyph.path(in:icon)); context.strokePath()
        context.restoreGState()
    }
    private func drawCenteredTitle(_ title: String, rect: NSRect, font: NSFont, color: NSColor) {
        let attributes: [NSAttributedString.Key: Any] = [.font:font,.foregroundColor:color]
        drawCenteredText(NSAttributedString(string:title,attributes:attributes),rect:rect)
    }
    private func drawCenteredText(_ text: NSAttributedString, rect: NSRect) {
        let attributes = text.length > 0 ? text.attributes(at:0,effectiveRange:nil) : [:]
        let line = CTLineCreateWithAttributedString(text)
        let token = CTLineCreateWithAttributedString(NSAttributedString(string:"…",attributes:attributes))
        let fitted = CTLineCreateTruncatedLine(line,Double(rect.width),.end,token) ?? line
        let glyphs = CTLineGetBoundsWithOptions(fitted,.useGlyphPathBounds)
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        context.clip(to:rect)
        context.translateBy(x:rect.minX,y:rect.midY)
        context.scaleBy(x:1,y:-1)
        context.textMatrix = .identity
        context.textPosition = CGPoint(x:0,y:-glyphs.midY)
        CTLineDraw(fitted,context)
        context.restoreGState()
    }
    private func drawProtectedTitle(_ item: CalendarEntry, frame: NSRect, timeFrame: NSRect? = nil) {
        let dark = effectiveAppearance.bestMatch(from:[.darkAqua,.aqua]) == .darkAqua
        let tint = item.color.usingColorSpace(.deviceRGB) ?? item.color
        let ink = tint.blended(withFraction:dark ? 0.4 : 0.48,of:dark ? .white : .black) ?? tint
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect:frame).addClip()
        let fontSize = min(AppTextSize.points(10),max(1,(frame.height-0.5)/1.18))
        let font = NSFont.systemFont(ofSize:fontSize,weight:.semibold)
        if timeFrame != nil || !drawInlineEventLabel(item,in:frame,font:font,color:ink) {
            drawCenteredTitle(item.displayTitle,rect:frame,font:font,color:ink)
        }
        NSGraphicsContext.restoreGraphicsState()
        if let timeFrame, !item.allDay {
            drawEventClock(at:timeFrame.origin,color:ink)
            drawEventTime(item,rect:NSRect(x:timeFrame.minX+12,y:timeFrame.minY,width:max(1,timeFrame.width-12),height:12),color:ink)
            if !item.id.hasPrefix("draft-") { hits.append((timeFrame,item)) }
        }
        // Protected titles remain clickable even above another event's body.
        if !item.id.hasPrefix("draft-") { hits.append((frame,item)) }
    }
    private func drawCreation(at date: Date, minutes: Int) {
        let index = model.calendar.dateComponents([.day],from:renderedStart,to:model.calendar.startOfDay(for:date)).day ?? 0
        let source = model.creationCalendar
        let color = source?.color ?? .controlAccentColor
        let components = model.calendar.dateComponents([.hour,.minute],from:date)
        let minute = components.hour!*60 + components.minute!
        let rect = NSRect(x:gutter+CGFloat(index)*dayWidth+3,y:top+CGFloat(minute)/60*CalendarMath.hourHeight+1,width:dayWidth-6,height:max(16,CGFloat(minutes)/60*CalendarMath.hourHeight-2))
        let preview = CalendarEntry(id:"new-preview",title:"New Task",start:date,end:date.addingTimeInterval(Double(minutes)*60),calendarID:source?.id ?? "",color:color)
        drawEvent(preview,rect:rect,registerHit:false)
        color.setStroke(); let border = NSBezierPath(roundedRect:rect,xRadius:4,yRadius:4); border.lineWidth = 1; border.stroke()
    }
    private func editorAnchor(at date: Date) -> NSRect {
        let index = model.calendar.dateComponents([.day],from:renderedStart,to:model.calendar.startOfDay(for:date)).day ?? 0
        let parts = model.calendar.dateComponents([.hour,.minute],from:date)
        let y = top+CGFloat(parts.hour!*60+parts.minute!)/60*CalendarMath.hourHeight
        let rect = NSRect(x:gutter+CGFloat(index)*dayWidth+3,y:max(visibleRect.minY,min(y,visibleRect.maxY-16)),width:max(1,dayWidth-6),height:16)
        return convert(rect,to:nil)
    }
    private func newDropDate(_ sender: NSDraggingInfo) -> Date? {
        guard sender.draggingPasteboard.availableType(from:[NewTaskDrag.pasteboardType]) != nil else { return nil }
        let point = convert(sender.draggingLocation,from:nil)
        guard point.x >= gutter, point.x < bounds.width, point.y >= stickyBottom, point.y < top+24*CalendarMath.hourHeight else { return nil }
        let index = min(model.visibleDayCount-1,Int((point.x-gutter)/dayWidth))
        let minute = max(0,min(1410,CalendarMath.snappedMinutes(point.y-top,fine:NSEvent.modifierFlags.contains(.shift))))
        return model.dateAtMinute(minute,on:day(index))
    }
    private func bankDropInfo(_ sender: NSDraggingInfo) -> (UUID,Date)? {
        guard let data = sender.draggingPasteboard.data(forType:BankDrag.pasteboardType),
              let text = String(data:data,encoding:.utf8), let id = UUID(uuidString:text), !model.bankDragTasks(id).isEmpty, model.bankDragTasks(id).allSatisfy({ model.canScheduleBankTask($0.id) }) else { return nil }
        let point = convert(sender.draggingLocation,from:nil)
        guard point.x >= gutter, point.x < bounds.width, point.y >= stickyBottom, point.y < top+24*CalendarMath.hourHeight else { return nil }
        let index = min(model.visibleDayCount-1,max(0,Int((point.x-gutter)/dayWidth)))
        let minutes = max(0,min(1439,CalendarMath.snappedMinutes(point.y-top,fine:NSEvent.modifierFlags.contains(.shift))))
        return (id,model.dateAtMinute(minutes,on:day(index)))
    }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { updateBankDrag(sender) }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        if let event = NSApp.currentEvent { autoscroll(with:event) }
        return updateBankDrag(sender)
    }
    private func updateBankDrag(_ sender: NSDraggingInfo) -> NSDragOperation {
        if let date = newDropDate(sender) { newTaskDrop = date; bankDrop = nil; needsDisplay = true; return .copy }
        newTaskDrop = nil
        if let (id,start) = bankDropInfo(sender) { bankDrop = (id,start); needsDisplay = true; return .copy }
        bankDrop = nil; needsDisplay = true; return []
    }
    override func draggingExited(_ sender: NSDraggingInfo?) { bankDrop = nil; newTaskDrop = nil; needsDisplay = true }
    override func draggingEnded(_ sender: NSDraggingInfo) { bankDrop = nil; newTaskDrop = nil; needsDisplay = true }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { bankDropInfo(sender) != nil || newDropDate(sender) != nil }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        if let date = newDropDate(sender) {
            newTaskDrop = nil; needsDisplay = true; model.newEvent(at:date,durationMinutes:30,anchorInWindow:editorAnchor(at:date)); return true
        }
        let drop = bankDropInfo(sender)
        bankDrop = nil; needsDisplay = true
        guard let (id,date) = drop else { return false }
        let scheduled = model.scheduleBankTasks(id,at:date)
        if scheduled { window?.makeFirstResponder(self) }
        return scheduled
    }
    override func scrollWheel(with event: NSEvent) {
        enclosingScrollView?.scrollWheel(with:event)
    }
    override func mouseDown(with event: NSEvent) {
        hideFastTooltip()
        model.bankHasFocus = false; model.selectedBankTasks = []
        rulerHoverInWindow = nil
        window?.makeFirstResponder(self)
        let point = convert(event.locationInWindow, from:nil)
        allDayCreationStart = nil; allDayCreationEnd = nil
        if allDayToggleRects.contains(where:{ $0.contains(point) }) {
            cancelAllDayHover(); allDayOpenedByHover = false
            model.allDayExpanded.toggle(); synchronize(); needsDisplay = true
            down = nil; return
        }
        down = point; delta = 0; didDrag = false; draggingID = nil; creatingDay = nil; creation = nil; resizing = nil; resizeMinutes = 0
        if let (_,item) = hits.reversed().first(where: { $0.0.contains(point) }) {
            if event.clickCount == 2 { model.edit(item,anchorInWindow:editorAnchor(at:item.start)); return }
            model.select(item.id, extending:event.modifierFlags.contains(.command))
            if model.selected.contains(item.id) {
                if let edge = resizeZones.last(where:{ $0.entry.id == item.id && $0.rect.contains(point) }) {
                    resizing = (item,edge.startEdge)
                } else { draggingID = item.id }
            }
        } else {
            model.selected = []
            if point.x >= gutter && point.x < bounds.width && point.y >= stickyTop && point.y < stickyBottom {
                let column = min(model.visibleDayCount-1,max(0,Int((point.x-gutter)/dayWidth)))
                if event.clickCount == 2 {
                    let anchor = convert(NSRect(x:gutter+CGFloat(column)*dayWidth+3,y:stickyTop+2,width:max(1,dayWidth-6),height:16),to:nil)
                    model.newAllDayEvent(from:day(column),through:day(column),anchorInWindow:anchor)
                    down = nil
                } else { allDayCreationStart = column }
                needsDisplay = true; return
            }
            if point.x >= gutter && point.y >= stickyBottom {
                let column = min(model.visibleDayCount-1,max(0,Int((point.x-gutter)/dayWidth)))
                model.pasteTarget = model.dateAtMinute(max(0,min(1439,CalendarMath.snappedMinutes(point.y-top))),on:day(column))
            }
            if event.clickCount == 1 && point.x >= gutter && point.x < bounds.width && point.y >= stickyBottom && point.y < top+24*CalendarMath.hourHeight {
                creatingDay = min(model.visibleDayCount-1,max(0,Int((point.x-gutter)/dayWidth)))
            }
            if event.clickCount == 2 && point.x >= gutter && point.y >= stickyBottom {
                let d = min(model.visibleDayCount-1,max(0,Int((point.x-gutter)/dayWidth)))
                let minutes = max(0,min(1439,CalendarMath.snappedMinutes(point.y-top,fine:NSEvent.modifierFlags.contains(.shift))))
                let date = model.dateAtMinute(minutes,on:day(d))
                model.newEvent(at:date,anchorInWindow:editorAnchor(at:date))
            }
        }
        needsDisplay = true
    }
    override func mouseDragged(with event: NSEvent) {
        guard let down else { return }
        let point = convert(event.locationInWindow,from:nil)
        if allDayCreationStart != nil {
            guard allDayCreationEnd != nil || hypot(point.x-down.x,point.y-down.y) > 4 else { return }
            allDayCreationEnd = min(model.visibleDayCount-1,max(0,Int((point.x-gutter)/dayWidth)))
            needsDisplay = true; return
        }
        if resizing != nil {
            guard hypot(point.x-down.x,point.y-down.y) > 3 || resizeMinutes != 0 else { return }
            if resizing?.entry.allDay == true {
                resizeMinutes = Int(((point.x-down.x)/dayWidth).rounded())*1440
            } else {
                autoscroll(with:event)
                resizeMinutes = Int(((point.x-down.x)/dayWidth).rounded())*1440 + CalendarMath.snappedMinutes(point.y-down.y,fine:event.modifierFlags.contains(.shift))
            }
            needsDisplay = true; return
        }
        if creatingDay != nil {
            guard creation != nil || hypot(point.x-down.x,point.y-down.y) > 4 else { return }
            autoscroll(with:event)
            creation = CalendarMath.creationRange(from:down.y-top,to:point.y-top,fine:event.modifierFlags.contains(.shift))
            needsDisplay = true; return
        }
        guard draggingID != nil else { return }
        guard didDrag || hypot(point.x-down.x,point.y-down.y) > 4 else { return }
        guard model.selection.allSatisfy({ $0.writable && !$0.allDay }) else { draggingID = nil; return }
        // Hand off to native dragging when crossing the left edge into the bank.
        if point.x < bounds.minX {
            let ids = model.selection.map(\.id)
            guard let data = try? JSONEncoder().encode(ids) else { return }
            let pasteboard = NSPasteboardItem()
            pasteboard.setData(data,forType:CalendarEventDrag.pasteboardType)
            let drag = NSDraggingItem(pasteboardWriter:pasteboard)
            let image = NSImage(size:NSSize(width:180,height:36))
            image.lockFocus()
            NSColor.controlBackgroundColor.setFill(); NSBezierPath(roundedRect:NSRect(x:0,y:0,width:180,height:36),xRadius:7,yRadius:7).fill()
            let label = ids.count == 1 ? (model.selection.first?.title ?? "Event") : "\(ids.count) events"
            text(label,rect:NSRect(x:9,y:10,width:162,height:18),size:11,color:.labelColor)
            image.unlockFocus()
            drag.setDraggingFrame(NSRect(x:point.x-20,y:point.y-18,width:180,height:36),contents:image)
            self.down = nil; draggingID = nil; didDrag = false; delta = 0; needsDisplay = true
            beginDraggingSession(with:[drag],event:event,source:self)
            return
        }
        autoscroll(with:event)
        didDrag = true
        let days = Int(((point.x-down.x)/dayWidth).rounded())
        delta = days*1440 + CalendarMath.snappedMinutes(point.y-down.y,fine:event.modifierFlags.contains(.shift))
        needsDisplay = true
    }
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .withinApplication ? .move : []
    }
    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        down = nil; draggingID = nil; didDrag = false; delta = 0; needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) {
        if let first = allDayCreationStart {
            let last = allDayCreationEnd
            allDayCreationStart = nil; allDayCreationEnd = nil; down = nil
            if let last {
                let lower = min(first,last)
                let anchor = convert(NSRect(x:gutter+CGFloat(lower)*dayWidth+3,y:stickyTop+2,width:CGFloat(abs(last-first)+1)*dayWidth-6,height:16),to:nil)
                model.newAllDayEvent(from:day(first),through:day(last),anchorInWindow:anchor)
            }
            needsDisplay = true; return
        }
        if let edge = resizing {
            let minutes = resizeMinutes
            resizing = nil; resizeMinutes = 0; down = nil
            model.resizeEvent(edge.entry.id,startEdge:edge.startEdge,minutes:minutes)
            needsDisplay = true; return
        }
        if let index = creatingDay, let range = creation {
            let date = model.dateAtMinute(range.lowerBound,on:day(index))
            creatingDay = nil; creation = nil; down = nil; needsDisplay = true
            model.newEvent(at:date,durationMinutes:range.upperBound-range.lowerBound,anchorInWindow:editorAnchor(at:date))
            return
        }
        creatingDay = nil; creation = nil
        let minutes = delta, moved = didDrag
        down = nil; draggingID = nil; didDrag = false; delta = 0
        if moved { model.move(minutes:minutes) }
        needsDisplay = true
    }
    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow,from:nil)
        guard let (_,item) = hits.reversed().first(where:{ $0.0.contains(point) }) else { return nil }
        window?.makeFirstResponder(self)
        model.select(item.id,extending:false); needsDisplay = true
        let menu = NSMenu(); menu.autoenablesItems = false
        if item.invitationStatus != .none {
            let respond = NSMenuItem(title:"Respond in Apple Calendar…",action:#selector(respondToContextInvitation(_:)),keyEquivalent:"")
            respond.target = self; respond.representedObject = item.id; menu.addItem(respond); menu.addItem(.separator())
        }
        let edit = NSMenuItem(title:"Edit Event…",action:#selector(editContextEvent),keyEquivalent:"")
        edit.target = self; edit.isEnabled = model.selection.count == 1
        menu.addItem(edit)
        menu.addItem(.separator())
        let delete = NSMenuItem(title:model.selection.count > 1 ? "Delete Selected Events" : "Delete Event",action:#selector(deleteContextEvents),keyEquivalent:"")
        delete.target = self; delete.isEnabled = model.selection.allSatisfy(\.writable)
        menu.addItem(delete)
        return menu
    }
    @objc private func respondToContextInvitation(_ sender: NSMenuItem) {
        if let id = sender.representedObject as? String, let item = model.shown.first(where:{ $0.id == id }) { model.respondInAppleCalendar(item) }
    }
    @objc private func deleteContextEvents() { model.deleteSelectedEvents(); needsDisplay = true }
    @objc private func editContextEvent() { if let item = model.selection.first { model.edit(item,anchorInWindow:editorAnchor(at:item.start)) } }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // AppKit asks views about key equivalents even when another view or
        // a popover's field editor owns focus. Leave text editing to its responder.
        guard window?.firstResponder === self, model.draft == nil else { return false }
        if event.modifierFlags.intersection([.command,.option,.control,.shift]) == .command {
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "v": model.pasteEvents(); return true
            case "c": model.copySelectedEvents(); return true
            case "x": model.cutSelectedEvents(); return true
            default: break
            }
        }
        return super.performKeyEquivalent(with:event)
    }
    @objc func cut(_ sender: Any?) { model.cutSelectedEvents() }
    @objc func copy(_ sender: Any?) { model.copySelectedEvents() }
    @objc func paste(_ sender: Any?) { model.pasteEvents() }
    override func keyDown(with event: NSEvent) {
        if performKeyEquivalent(with:event) { return }
        if event.keyCode == 49, event.modifierFlags.intersection([.command,.control,.option,.shift]).isEmpty,
           let item = model.selection.first,
           model.openSelectedEventDetails(anchorInWindow:editorAnchor(at:item.start)) { return }
        if [51,117].contains(event.keyCode), event.modifierFlags.intersection([.command,.control,.option]).isEmpty {
            allDayCreationStart = nil; allDayCreationEnd = nil
            down = nil; draggingID = nil; didDrag = false; delta = 0; creatingDay = nil; creation = nil
            model.deleteSelectedEvents(); needsDisplay = true; return
        }
        if event.keyCode == 53 { allDayCreationStart = nil; allDayCreationEnd = nil; resizing = nil; resizeMinutes = 0; creatingDay = nil; creation = nil; newTaskDrop = nil; down = nil; draggingID = nil; didDrag = false; delta = 0; model.selected = []; needsDisplay = true }
        else { super.keyDown(with:event) }
    }
}
