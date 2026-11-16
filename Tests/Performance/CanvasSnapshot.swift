import Foundation
import AppKit

// Offscreen synthetic rendering only: no app windows, calendar permissions,
// personal events, or shared UI state are accessed.
@main struct CanvasSnapshot {
    @MainActor static func main() throws {
        let bank = EventBankStore(folder:nil,watch:false)
        let model = CalendarModel(bank:bank,reconnectIfAuthorized:false)
        let start = Date(timeIntervalSince1970:1_800_000_000)
        let day = model.calendar.startOfDay(for:start)
        model.jump(to:day)
        model.entries = (0..<70).map { i in
            let date = model.calendar.date(byAdding:.day,value:i%7,to:day)!.addingTimeInterval(Double(7+i/7)*3600)
            return CalendarEntry(id:"synthetic-\(i)",title:i%4 == 0 ? "Long event title that wraps onto another line" : "Example event \(i)",start:date,end:date.addingTimeInterval(i%3 == 0 ? 5400 : 2700),calendarID:i%2 == 0 ? "work" : "personal",color:i%2 == 0 ? .systemTeal : .systemPurple,writable:i%7 != 0,invitationStatus:i%5 == 0 ? .unanswered : (i%6 == 0 ? .maybe : .none),notes:i%4 == 0 ? "A subtle notes preview\nWith another line" : "")
        }
        model.entries.append(CalendarEntry(id:"all-day-a",title:"A continuous all-day event",start:day,end:day.addingTimeInterval(86400*4),calendarID:"work",color:.systemPink,allDay:true))
        model.entries.append(CalendarEntry(id:"all-day-b",title:"Another all-day event",start:day.addingTimeInterval(86400),end:day.addingTimeInterval(86400*6),calendarID:"personal",color:.systemOrange,allDay:true))
        let canvas = CalendarCanvas(model:model)
        canvas.appearance = NSAppearance(named:CommandLine.arguments.count > 2 && CommandLine.arguments[2] == "dark" ? .darkAqua : .aqua)
        canvas.frame = NSRect(x:0,y:0,width:1280,height:1600)
        canvas.effectiveAppearance.performAsCurrentDrawingAppearance {
            let bitmap = NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:1280,pixelsHigh:1600,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
            let context = NSGraphicsContext(bitmapImageRep:bitmap)!
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext:context.cgContext,flipped:true)
            context.cgContext.translateBy(x:0,y:1600); context.cgContext.scaleBy(x:1,y:-1)
            canvas.draw(canvas.bounds)
            NSGraphicsContext.restoreGraphicsState()
            try! bitmap.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:CommandLine.arguments[1]))
        }
    }
}
