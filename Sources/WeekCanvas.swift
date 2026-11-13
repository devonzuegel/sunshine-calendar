import AppKit
import SwiftUI
import QuartzCore

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

enum ProtectedTitleLayout {
    static func frames(_ cards: [NSRect]) -> [NSRect] {
        var placed: [NSRect] = []
        for card in cards {
            let height = min(14,max(1,card.height-4))
            var label = NSRect(x:card.minX+11,y:card.minY+2,width:max(1,card.width-15),height:height)
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

struct AllDaySpan {
    let id: String
    let firstDay: Int
    let endDay: Int
    let row: Int
}
enum AllDayLayout {
    static func spans(_ items: [TimedInterval], weekStart: Date, calendar: Calendar = .current) -> [AllDaySpan] {
        let end = calendar.date(byAdding:.day,value:7,to:weekStart)!
        let sorted = items.filter { $0.start < end && $0.end > weekStart }.sorted {
            $0.start == $1.start ? ($0.end == $1.end ? $0.id < $1.id : $0.end > $1.end) : $0.start < $1.start
        }
        var rowEnds: [Int] = []
        return sorted.map { item in
            let start = max(0,calendar.dateComponents([.day],from:weekStart,to:calendar.startOfDay(for:item.start)).day!)
            // All-day end dates are exclusive; never add a day at midnight.
            let finish = min(7,calendar.dateComponents([.day],from:weekStart,to:calendar.startOfDay(for:item.end)).day!)
            let row = rowEnds.firstIndex(where:{ $0 <= start }) ?? rowEnds.count
            if row == rowEnds.count { rowEnds.append(finish) } else { rowEnds[row] = finish }
            return AllDaySpan(id:item.id,firstDay:start,endDay:finish,row:row)
        }
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

final class FittingScrollView: NSScrollView {
    var onDayNavigation: ((Int) -> Void)?
    private var dayGesture = DayScrollGesture()
    private var scrollMonitor: Any?
    deinit { if let scrollMonitor { NSEvent.removeMonitor(scrollMonitor) } }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let scrollMonitor { NSEvent.removeMonitor(scrollMonitor); self.scrollMonitor = nil }
        guard window != nil else { return }
        // Receive horizontal gestures before AppKit's edge-swipe routing.
        // This monitor only sees events in this app, over this calendar view.
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching:.scrollWheel) { [weak self] event in
            guard let self, event.window === self.window,
                  self.bounds.contains(self.convert(event.locationInWindow,from:nil)),
                  event.scrollingDeltaX != 0 || event.modifierFlags.contains(.shift) else { return event }
            return self.handleDayScroll(event) ? nil : event
        }
    }
    override func wantsScrollEventsForSwipeTracking(on axis: NSEvent.GestureAxis) -> Bool {
        axis == .horizontal || super.wantsScrollEventsForSwipeTracking(on:axis)
    }
    private func handleDayScroll(_ event: NSEvent) -> Bool {
        let shiftWheel = event.modifierFlags.contains(.shift) && event.scrollingDeltaX == 0
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

struct WeekCanvas: NSViewRepresentable {
    @ObservedObject var model: CalendarModel
    @ObservedObject var daylight: DaylightLocation
    init(model: CalendarModel) { self.model = model; self.daylight = model.daylight }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = FittingScrollView()
        scroll.onDayNavigation = { [weak model] days in model?.navigateDays(days) }
        scroll.setAccessibilityCustomActions([
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
        canvas.frame = NSRect(x: 0, y: 0, width: 900, height: 48 + 24 * CalendarMath.hourHeight)
        canvas.autoresizingMask = []
        scroll.documentView = canvas
        DispatchQueue.main.async {
            let y = model.restoredScrollY ?? (48 + 7 * CalendarMath.hourHeight)
            canvas.scroll(NSPoint(x:0,y:max(0,min(y,canvas.bounds.height-scroll.contentSize.height))))
            model.restoredScrollY = nil
        }
        return scroll
    }
    func updateNSView(_ view: NSScrollView, context: Context) { (view.documentView as? CalendarCanvas)?.synchronize() }
}

@MainActor final class CalendarCanvas: NSView, NSDraggingSource {
    let model: CalendarModel
    private var renderedStart: Date
    private var renderedEntries: [CalendarEntry]
    private var slideOverlay: NSView?
    let gutter: CGFloat = 58
    let top: CGFloat = 48
    var hits: [(NSRect, CalendarEntry)] = []
    var down: NSPoint?
    var draggingID: String?
    var delta = 0
    var didDrag = false
    private var creatingDay: Int?
    private var creation: ClosedRange<Int>?
    private var newTaskDrop: Date?
    private var bankDrop: (id: UUID, start: Date)?
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    init(model: CalendarModel) {
        self.model = model
        renderedStart = model.weekStart
        renderedEntries = model.shown
        super.init(frame:.zero)
        registerForDraggedTypes([BankDrag.pasteboardType,NewTaskDrag.pasteboardType])
    }
    required init?(coder: NSCoder) { fatalError() }
    var dayWidth: CGFloat { max(1, (bounds.width - gutter) / 7) }
    func day(_ index: Int) -> Date { Calendar.current.date(byAdding: .day, value: index, to: renderedStart)! }
    func synchronize() {
        let days = Calendar.current.dateComponents([.day],from:renderedStart,to:model.weekStart).day ?? 0
        let area = NSRect(x:gutter,y:visibleRect.minY,width:max(0,bounds.width-gutter),height:visibleRect.height)
        let animate = abs(days) == 1 && window != nil && area.width > 0 && area.height > 0 && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        slideOverlay?.removeFromSuperview(); slideOverlay = nil
        func snapshot() -> NSImage? {
            guard let bitmap = bitmapImageRepForCachingDisplay(in:area) else { return nil }
            cacheDisplay(in:area,to:bitmap)
            let image = NSImage(size:area.size); image.addRepresentation(bitmap); return image
        }
        let old = animate ? snapshot() : nil
        renderedStart = model.weekStart; renderedEntries = model.shown
        needsDisplay = true
        guard let old, let new = snapshot() else { return }
        let overlay = NSView(frame:area)
        overlay.wantsLayer = true; overlay.layer?.masksToBounds = true
        let distance = CGFloat(days) * dayWidth
        let before = NSImageView(frame:NSRect(origin:.zero,size:area.size))
        before.image = old; before.imageScaling = .scaleAxesIndependently; before.wantsLayer = true
        let after = NSImageView(frame:NSRect(x:distance,y:0,width:area.width,height:area.height))
        after.image = new; after.imageScaling = .scaleAxesIndependently; after.wantsLayer = true
        overlay.addSubview(before); overlay.addSubview(after)
        addSubview(overlay); slideOverlay = overlay
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.26
            context.timingFunction = CAMediaTimingFunction(name:.easeInEaseOut)
            before.animator().setFrameOrigin(NSPoint(x:-distance,y:0))
            after.animator().setFrameOrigin(.zero)
        } completionHandler: { [weak self, weak overlay] in
            Task { @MainActor in
                overlay?.removeFromSuperview()
                if self?.slideOverlay === overlay { self?.slideOverlay = nil }
            }
        }
    }
    func text(_ text: String, rect: NSRect, size: CGFloat = 11, color: NSColor = .secondaryLabelColor, weight: NSFont.Weight = .regular) {
        let paragraph = NSMutableParagraphStyle(); paragraph.lineBreakMode = .byTruncatingTail
        (text as NSString).draw(in: rect, withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color, .paragraphStyle: paragraph])
    }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.textBackgroundColor.setFill(); bounds.fill()
        let today = Calendar.current.startOfDay(for: Date())
        let dark = effectiveAppearance.bestMatch(from:[.darkAqua,.aqua]) == .darkAqua
        for d in 0..<7 where Calendar.current.isDateInWeekend(day(d)) {
            NSColor.labelColor.withAlphaComponent(dark ? 0.025 : 0.018).setFill()
            NSRect(x:gutter+CGFloat(d)*dayWidth,y:0,width:dayWidth,height:bounds.height).fill()
        }
        // Nighttime tint stays below grid lines and event cards.
        for index in 0..<7 {
            for range in model.daylight.ranges(on:day(index)) {
                NSColor(calibratedRed:dark ? 0.48 : 0.23,green:dark ? 0.53 : 0.29,blue:dark ? 0.65 : 0.43,alpha:dark ? 0.10 : 0.045).setFill()
                NSRect(x:gutter+CGFloat(index)*dayWidth,y:top+CGFloat(range.lowerBound/60)*CalendarMath.hourHeight,width:dayWidth,height:CGFloat((range.upperBound-range.lowerBound)/60)*CalendarMath.hourHeight).fill()
            }
        }
        let scale = window?.backingScaleFactor ?? 2
        let hairline = 1 / scale
        func aligned(_ value: CGFloat) -> CGFloat { (value * scale).rounded() / scale + hairline / 2 }
        let lines = NSBezierPath(); lines.lineWidth = hairline
        for d in 0...7 {
            let x = aligned(gutter+CGFloat(d)*dayWidth)
            lines.move(to:NSPoint(x:x,y:0)); lines.line(to:NSPoint(x:x,y:bounds.height))
        }
        let formatter = DateFormatter(); formatter.dateFormat = "h"
        let periodFormatter = DateFormatter(); periodFormatter.dateFormat = "a"
        for h in 0...24 {
            let y = top+CGFloat(h)*CalendarMath.hourHeight
            lines.move(to:NSPoint(x:gutter,y:aligned(y))); lines.line(to:NSPoint(x:bounds.width,y:aligned(y)))
            if h < 24 {
                let date = Calendar.current.date(bySettingHour:h,minute:0,second:0,of:today)!
                let hour = h == 12 ? "Noon" : formatter.string(from:date)
                let period = h == 12 ? "" : periodFormatter.string(from:date)
                let hourWidth = (hour as NSString).size(withAttributes:[.font:NSFont.systemFont(ofSize:9)]).width
                (hour as NSString).draw(at:NSPoint(x:gutter-20-hourWidth,y:y-6),withAttributes:[.font:NSFont.systemFont(ofSize:9),.foregroundColor:NSColor.secondaryLabelColor])
                (period as NSString).draw(at:NSPoint(x:gutter-17,y:y-4),withAttributes:[.font:NSFont.systemFont(ofSize:6),.foregroundColor:NSColor.tertiaryLabelColor])
            }
        }
        NSColor(calibratedWhite:dark ? 0.24 : 0.92,alpha:1).setStroke()
        lines.stroke()
        text("all-day",rect:NSRect(x:12,y:16,width:40,height:14),size:8,color:.tertiaryLabelColor)
        hits = []
        var displayed = renderedEntries
        if didDrag {
            displayed = displayed.map { item in
                var copy = item
                if model.selected.contains(item.id) { copy.start = copy.start.addingTimeInterval(Double(delta)*60); copy.end = copy.end.addingTimeInterval(Double(delta)*60) }
                return copy
            }
        }
        for d in 0..<7 {
            let start = day(d), end = day(d+1)
            let items = displayed.filter { !$0.allDay && $0.start < end && $0.end > start }
            let placements = OverlapLayout.columns(items.map { TimedInterval(id:$0.id,start:max(start,$0.start),end:min(end,$0.end)) })
            var cards: [(CalendarEntry,NSRect)] = []
            for item in items.sorted(by: { $0.start == $1.start ? $0.id < $1.id : $0.start < $1.start }) {
                guard let placement = placements[item.id] else { continue }
                let begin = max(start,item.start), finish = min(end,item.end)
                let y = top + CGFloat(begin.timeIntervalSince(start) / 3600) * CalendarMath.hourHeight
                let height = max(1,CGFloat(finish.timeIntervalSince(begin) / 3600) * CalendarMath.hourHeight - 1)
                let width = (dayWidth - 5) / CGFloat(placement.count)
                let inset = min(CGFloat(placement.depth)*7,width*0.16)
                let rect = NSRect(x:gutter + CGFloat(d)*dayWidth + 3 + CGFloat(placement.column)*width+inset,y:y+0.5,width:max(1,width-2-inset),height:height)
                cards.append((item,rect))
            }
            let overlapping = cards.indices.filter { index in
                cards.indices.contains { $0 != index && cards[index].1.intersects(cards[$0].1) }
            }
            for (index,card) in cards.enumerated() {
                drawEvent(card.0,rect:card.1,backgroundOnly:overlapping.contains(index))
            }
            let labelFrames = ProtectedTitleLayout.frames(cards.map { $0.1 })
            for index in overlapping {
                drawProtectedTitle(cards[index].0,frame:labelFrames[index])
            }
        }
        let allDayItems = displayed.filter(\.allDay)
        let spans = AllDayLayout.spans(allDayItems.map { TimedInterval(id:$0.id,start:$0.start,end:$0.end) },weekStart:renderedStart)
        for span in spans where span.row < 2 {
            guard let item = allDayItems.first(where:{ $0.id == span.id }) else { continue }
            let rect = NSRect(x:gutter+CGFloat(span.firstDay)*dayWidth+3,y:CGFloat(span.row)*22+2,width:CGFloat(span.endDay-span.firstDay)*dayWidth-6,height:20)
            drawEvent(item,rect:rect)
        }
        for index in 0..<7 {
            let hidden = spans.filter { $0.row >= 2 && $0.firstDay <= index && $0.endDay > index }.count
            if hidden > 0 {
                let badge = NSRect(x:gutter+CGFloat(index+1)*dayWidth-29,y:31,width:27,height:13)
                NSColor.textBackgroundColor.setFill(); NSBezierPath(roundedRect:badge,xRadius:3,yRadius:3).fill()
                text("+\(hidden)",rect:badge.insetBy(dx:3,dy:0),size:9)
            }
        }
        if let drop = bankDrop, let task = model.bank.records[drop.id], let source = model.calendar(for:task) {
            let end = drop.start.addingTimeInterval(Double(task.minutes)*60)
            let ghost = CalendarEntry(id:"bank-drop",title:task.title,start:drop.start,end:end,calendarID:source.id,color:source.color)
            for d in 0..<7 where drop.start < day(d+1) && end > day(d) {
                let start = max(drop.start,day(d)), finish = min(end,day(d+1))
                let rect = NSRect(x:gutter+CGFloat(d)*dayWidth+4,y:top+CGFloat(start.timeIntervalSince(day(d))/3600)*CalendarMath.hourHeight+1,width:dayWidth-8,height:max(19,CGFloat(finish.timeIntervalSince(start)/3600)*CalendarMath.hourHeight-2))
                drawEvent(ghost,rect:rect,registerHit:false)
                source.color.setStroke()
                let outline = NSBezierPath(roundedRect:rect,xRadius:5,yRadius:5)
                outline.lineWidth = 1.5; outline.setLineDash([4,3],count:2,phase:0); outline.stroke()
            }
        }
        if let index = creatingDay, let range = creation {
            drawCreation(at:day(index).addingTimeInterval(Double(range.lowerBound)*60),minutes:range.upperBound-range.lowerBound)
        }
        if let date = newTaskDrop { drawCreation(at:date,minutes:30) }
        let now = Date()
        if now >= model.weekStart && now < model.weekEnd {
            let d = Calendar.current.dateComponents([.day], from:model.weekStart,to:Calendar.current.startOfDay(for:now)).day!
            let y = top + CGFloat(now.timeIntervalSince(Calendar.current.startOfDay(for:now))/3600)*CalendarMath.hourHeight
            let across = NSBezierPath(); across.lineWidth = 0.75
            NSColor.systemRed.withAlphaComponent(0.15).setStroke()
            across.move(to:NSPoint(x:gutter,y:y)); across.line(to:NSPoint(x:bounds.width,y:y)); across.stroke()
            NSColor.systemRed.setStroke(); let line = NSBezierPath(); line.lineWidth = 1
            line.move(to:NSPoint(x:gutter+CGFloat(d)*dayWidth,y:y)); line.line(to:NSPoint(x:gutter+CGFloat(d+1)*dayWidth,y:y)); line.stroke()
            let badge = NSRect(x:8,y:y-6,width:43,height:13)
            NSColor.systemRed.setFill(); NSBezierPath(roundedRect:badge,xRadius:6.5,yRadius:6.5).fill()
            let timeFormatter = DateFormatter(); timeFormatter.dateFormat = "h:mm"
            let label = timeFormatter.string(from:now)
            let labelWidth = (label as NSString).size(withAttributes:[.font:NSFont.systemFont(ofSize:8,weight:.semibold)]).width
            text(label,rect:NSRect(x:badge.midX-labelWidth/2,y:y-5,width:labelWidth+1,height:12),size:8,color:.white,weight:.semibold)
        }
        if didDrag {
            let label = "\(model.selected.count) selected · \(delta >= 0 ? "+" : "")\(delta) min"
            let y = min(max(visibleRect.minY+12, (down?.y ?? 0)+CGFloat(delta%1440)/60*CalendarMath.hourHeight-30), visibleRect.maxY-32)
            let badge = NSRect(x:gutter+8,y:y,width:225,height:25)
            NSColor.labelColor.withAlphaComponent(0.9).setFill(); NSBezierPath(roundedRect:badge,xRadius:7,yRadius:7).fill()
            text(label,rect:badge.insetBy(dx:8,dy:5),size:11,color:.textBackgroundColor,weight:.medium)
        }
    }
    func drawEvent(_ item: CalendarEntry, rect: NSRect, registerHit: Bool = true, backgroundOnly: Bool = false) {
        let selected = model.selected.contains(item.id)
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let tint = item.color.usingColorSpace(.deviceRGB) ?? item.color
        let fill = NSColor.textBackgroundColor.blended(withFraction: selected ? 0.30 : (dark ? 0.22 : 0.14), of: tint) ?? tint
        let ink = tint.blended(withFraction: dark ? 0.35 : 0.48, of: dark ? .white : .black) ?? tint
        let path = NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5)
        // Opaque pastel cards hide the text of the event underneath a stack.
        fill.setFill(); path.fill()
        if selected { tint.setStroke(); path.lineWidth = 1.5; path.stroke() }
        tint.setFill()
        let padding: CGFloat = min(4,rect.height*0.15)
        NSBezierPath(roundedRect:NSRect(x:rect.minX+4,y:rect.minY+padding,width:3,height:max(0.5,rect.height-2*padding)),xRadius:1.5,yRadius:1.5).fill()
        if backgroundOnly {
            if registerHit { hits.append((rect,item)) }
            return
        }
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect:rect.insetBy(dx:3,dy:min(2,rect.height*0.1))).addClip()
        let contentX = rect.minX + 12
        let contentWidth = max(1,rect.width-17)
        let title = (item.writable ? "" : "🔒 ") + item.title
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = rect.height < 28 ? .byTruncatingTail : .byWordWrapping
        let fontSize: CGFloat = rect.height < 14 ? max(5,rect.height-3) : (rect.height < 24 ? 9 : 10)
        let attributes: [NSAttributedString.Key: Any] = [.font:NSFont.systemFont(ofSize:fontSize,weight:.semibold), .foregroundColor:ink, .paragraphStyle:paragraph]
        let measured = (title as NSString).boundingRect(with:NSSize(width:contentWidth,height:1000),options:[.usesLineFragmentOrigin,.usesFontLeading],attributes:attributes).height
        let lineHeight: CGFloat = ceil(fontSize*1.25)
        let titleRoom = rect.height >= 46 ? lineHeight * 2 : lineHeight
        let titleHeight = min(titleRoom, max(lineHeight,ceil(measured)))
        (title as NSString).draw(with:NSRect(x:contentX,y:rect.minY+(rect.height < 24 ? max(0,(rect.height-lineHeight)/2) : 4),width:contentWidth,height:titleHeight),options:[.usesLineFragmentOrigin,.usesFontLeading,.truncatesLastVisibleLine],attributes:attributes)
        let timeY = rect.minY+4+titleHeight+2
        if !item.allDay && timeY+12 <= rect.maxY-3 {
            let clockSize: CGFloat = 8
            let clock = NSBezierPath(ovalIn:NSRect(x:contentX,y:timeY+2,width:clockSize,height:clockSize))
            ink.withAlphaComponent(0.8).setStroke(); clock.lineWidth = 0.65; clock.stroke()
            let hands = NSBezierPath(); hands.lineWidth = 0.65
            hands.move(to:NSPoint(x:contentX+2,y:timeY+5)); hands.line(to:NSPoint(x:contentX+4,y:timeY+7)); hands.line(to:NSPoint(x:contentX+6,y:timeY+4)); hands.stroke()
            func compactTime(_ date: Date) -> String {
                let formatter = DateFormatter()
                formatter.setLocalizedDateFormatFromTemplate(Calendar.current.component(.minute,from:date) == 0 ? "j" : "jm")
                return formatter.string(from:date).replacingOccurrences(of:" ",with:"").replacingOccurrences(of:"\u{202F}",with:"")
            }
            text(compactTime(item.start)+"–"+compactTime(item.end),rect:NSRect(x:contentX+12,y:timeY,width:max(1,contentWidth-12),height:13),size:9,color:ink.withAlphaComponent(0.85))
        }
        NSGraphicsContext.restoreGraphicsState()
        if registerHit { hits.append((rect,item)) }
    }
    private func drawProtectedTitle(_ item: CalendarEntry, frame: NSRect) {
        let dark = effectiveAppearance.bestMatch(from:[.darkAqua,.aqua]) == .darkAqua
        let tint = item.color.usingColorSpace(.deviceRGB) ?? item.color
        let fill = NSColor.textBackgroundColor.blended(withFraction:dark ? 0.32 : 0.19,of:tint) ?? tint
        let ink = tint.blended(withFraction:dark ? 0.4 : 0.48,of:dark ? .white : .black) ?? tint
        fill.setFill()
        let chip = NSBezierPath(roundedRect:frame,xRadius:3,yRadius:3)
        chip.fill()
        tint.withAlphaComponent(0.45).setStroke(); chip.lineWidth = 0.5; chip.stroke()
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect:frame).addClip()
        text((item.writable ? "" : "🔒 ")+item.title,rect:frame.insetBy(dx:3,dy:0.5),size:min(10,max(5,frame.height-3)),color:ink,weight:.semibold)
        NSGraphicsContext.restoreGraphicsState()
        // Protected titles remain clickable even above another event's body.
        hits.append((frame,item))
    }
    private func drawCreation(at date: Date, minutes: Int) {
        let index = Calendar.current.dateComponents([.day],from:renderedStart,to:Calendar.current.startOfDay(for:date)).day ?? 0
        let source = model.creationCalendar
        let color = source?.color ?? .controlAccentColor
        let components = Calendar.current.dateComponents([.hour,.minute],from:date)
        let minute = components.hour!*60 + components.minute!
        let rect = NSRect(x:gutter+CGFloat(index)*dayWidth+3,y:top+CGFloat(minute)/60*CalendarMath.hourHeight+1,width:dayWidth-6,height:max(16,CGFloat(minutes)/60*CalendarMath.hourHeight-2))
        let preview = CalendarEntry(id:"new-preview",title:"New Task",start:date,end:date.addingTimeInterval(Double(minutes)*60),calendarID:source?.id ?? "",color:color)
        drawEvent(preview,rect:rect,registerHit:false)
        color.setStroke(); let border = NSBezierPath(roundedRect:rect,xRadius:4,yRadius:4); border.lineWidth = 1; border.stroke()
    }
    private func newDropDate(_ sender: NSDraggingInfo) -> Date? {
        guard sender.draggingPasteboard.availableType(from:[NewTaskDrag.pasteboardType]) != nil else { return nil }
        let point = convert(sender.draggingLocation,from:nil)
        guard point.x >= gutter, point.x < bounds.width, point.y >= top, point.y < top+24*CalendarMath.hourHeight else { return nil }
        let index = min(6,Int((point.x-gutter)/dayWidth))
        let minute = max(0,min(1410,CalendarMath.snappedMinutes(point.y-top)))
        return day(index).addingTimeInterval(Double(minute)*60)
    }
    private func bankDropInfo(_ sender: NSDraggingInfo) -> (UUID,Date)? {
        guard let data = sender.draggingPasteboard.data(forType:BankDrag.pasteboardType),
              let text = String(data:data,encoding:.utf8), let id = UUID(uuidString:text), model.canScheduleBankTask(id) else { return nil }
        let point = convert(sender.draggingLocation,from:nil)
        guard point.x >= gutter, point.x < bounds.width, point.y >= top, point.y < top+24*CalendarMath.hourHeight else { return nil }
        let index = min(6,max(0,Int((point.x-gutter)/dayWidth)))
        let minutes = max(0,min(1425,CalendarMath.snappedMinutes(point.y-top)))
        return (id,day(index).addingTimeInterval(Double(minutes)*60))
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
            newTaskDrop = nil; needsDisplay = true; model.newEvent(at:date,durationMinutes:30); return true
        }
        let drop = bankDropInfo(sender)
        bankDrop = nil; needsDisplay = true
        guard let (id,date) = drop else { return false }
        return model.scheduleBankTask(id,at:date)
    }
    override func scrollWheel(with event: NSEvent) {
        enclosingScrollView?.scrollWheel(with:event)
    }
    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let point = convert(event.locationInWindow, from:nil)
        down = point; delta = 0; didDrag = false; draggingID = nil; creatingDay = nil; creation = nil
        if let (_,item) = hits.reversed().first(where: { $0.0.contains(point) }) {
            if event.clickCount == 2 { model.edit(item); return }
            model.select(item.id, extending:event.modifierFlags.contains(.command))
            if model.selected.contains(item.id) { draggingID = item.id }
        } else {
            model.selected = []
            if event.clickCount == 1 && point.x >= gutter && point.x < bounds.width && point.y >= top && point.y < top+24*CalendarMath.hourHeight {
                creatingDay = min(6,max(0,Int((point.x-gutter)/dayWidth)))
            }
            if event.clickCount == 2 && point.x >= gutter && point.y >= top {
                let d = min(6,max(0,Int((point.x-gutter)/dayWidth)))
                let minutes = max(0,min(1425,CalendarMath.snappedMinutes(point.y-top)))
                model.newEvent(at:day(d).addingTimeInterval(Double(minutes)*60))
            }
        }
        needsDisplay = true
    }
    override func mouseDragged(with event: NSEvent) {
        guard let down else { return }
        let point = convert(event.locationInWindow,from:nil)
        if creatingDay != nil {
            guard creation != nil || hypot(point.x-down.x,point.y-down.y) > 4 else { return }
            autoscroll(with:event)
            creation = CalendarMath.creationRange(from:down.y-top,to:point.y-top)
            needsDisplay = true; return
        }
        guard draggingID != nil else { return }
        guard didDrag || hypot(point.x-down.x,point.y-down.y) > 4 else { return }
        guard model.selection.allSatisfy({ $0.writable && !$0.allDay }) else { draggingID = nil; model.message = "Select only editable timed events to move a group."; return }
        // Keep normal group movement inside the calendar; hand off to native
        // dragging when the pointer crosses the right edge toward the bank.
        if point.x >= bounds.maxX {
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
        delta = days*1440 + CalendarMath.snappedMinutes(point.y-down.y)
        needsDisplay = true
    }
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .withinApplication ? .move : []
    }
    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        down = nil; draggingID = nil; didDrag = false; delta = 0; needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) {
        if let index = creatingDay, let range = creation {
            let date = day(index).addingTimeInterval(Double(range.lowerBound)*60)
            creatingDay = nil; creation = nil; down = nil; needsDisplay = true
            model.newEvent(at:date,durationMinutes:range.upperBound-range.lowerBound)
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
        let edit = NSMenuItem(title:"Edit Event…",action:#selector(editContextEvent),keyEquivalent:"")
        edit.target = self; edit.isEnabled = model.selection.count == 1 && item.writable
        menu.addItem(edit)
        menu.addItem(.separator())
        let delete = NSMenuItem(title:model.selection.count > 1 ? "Delete Selected Events…" : "Delete Event…",action:#selector(deleteContextEvents),keyEquivalent:"")
        delete.target = self; delete.isEnabled = model.selection.allSatisfy(\.writable)
        menu.addItem(delete)
        return menu
    }
    @objc private func deleteContextEvents() { model.deleteSelectedEvents(); needsDisplay = true }
    @objc private func editContextEvent() { if let item = model.selection.first { model.edit(item) } }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains([.command,.option]), event.charactersIgnoringModifiers?.lowercased() == "s" {
            // Handle this while the custom calendar canvas has keyboard focus.
            let defaults = UserDefaults.standard
            defaults.set(!defaults.bool(forKey:"sidebarVisible"),forKey:"sidebarVisible")
            return true
        }
        return super.performKeyEquivalent(with:event)
    }
    override func keyDown(with event: NSEvent) {
        if performKeyEquivalent(with:event) { return }
        if [51,117].contains(event.keyCode), event.modifierFlags.intersection([.command,.control,.option]).isEmpty {
            down = nil; draggingID = nil; didDrag = false; delta = 0; creatingDay = nil; creation = nil
            model.deleteSelectedEvents(); needsDisplay = true; return
        }
        if event.keyCode == 53 { creatingDay = nil; creation = nil; newTaskDrop = nil; down = nil; draggingID = nil; didDrag = false; delta = 0; model.selected = []; needsDisplay = true }
        else { super.keyDown(with:event) }
    }
}
