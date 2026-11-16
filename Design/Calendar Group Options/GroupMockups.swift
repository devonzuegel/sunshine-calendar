import SwiftUI
import AppKit

private struct CalendarRow: View {
    let title:String
    let color:Color
    var checked = true
    var locked = false
    var body: some View {
        HStack(spacing:8) {
            Image(systemName:checked ? "checkmark.square.fill" : "square").foregroundStyle(color).font(.system(size:12))
            Text(title).font(.system(size:12)).foregroundStyle(Color.primary.opacity(0.78)).lineLimit(1)
            Spacer(minLength:0)
            if locked { Image(systemName:"lock").font(.system(size:9)).foregroundStyle(.secondary) }
        }.frame(height:25)
    }
}
private struct GroupHeading: View {
    let style:Int
    let title:String
    let count:String
    var checked = false
    var body: some View {
        Group {
            if style == 1 {
                HStack(spacing:6) {
                    Text(title.uppercased()).font(.system(size:9,weight:.semibold)).tracking(0.4)
                    Spacer(minLength:0)
                    Text(count).font(.system(size:9)).foregroundStyle(.tertiary)
                    Image(systemName:checked ? "checkmark.square.fill" : "minus.square.fill").font(.system(size:11))
                }.foregroundStyle(.secondary).frame(height:24)
            } else if style == 2 {
                HStack(spacing:6) {
                    Text(title).font(.system(size:11,weight:.semibold))
                    Spacer(minLength:0)
                    Text(count).font(.system(size:9)).foregroundStyle(.secondary)
                    Image(systemName:checked ? "checkmark.square.fill" : "minus.square.fill").font(.system(size:11)).foregroundStyle(.secondary)
                }.padding(.horizontal,8).frame(height:29)
                    .background(Color.primary.opacity(0.045),in:RoundedRectangle(cornerRadius:6))
            } else if style == 3 {
                VStack(spacing:5) {
                    Rectangle().fill(Color.primary.opacity(0.08)).frame(height:0.5)
                    HStack(spacing:5) {
                        Text(title).font(.system(size:11,weight:.semibold))
                        Spacer(minLength:0)
                        Text("All").font(.system(size:9,weight:.medium)).foregroundStyle(.secondary)
                        Text("/").font(.system(size:8)).foregroundStyle(.tertiary)
                        Text("None").font(.system(size:9,weight:.medium)).foregroundStyle(.secondary)
                    }
                }.frame(height:29)
            } else {
                HStack(spacing:6) {
                    Image(systemName:"chevron.down").font(.system(size:8,weight:.semibold))
                    Text(title).font(.system(size:11,weight:.semibold))
                    Spacer(minLength:0)
                    Text(count).font(.system(size:9)).foregroundStyle(.tertiary)
                    Image(systemName:checked ? "checkmark.square.fill" : "minus.square.fill").font(.system(size:11)).foregroundStyle(.secondary)
                }.foregroundStyle(Color.primary.opacity(0.7)).frame(height:27)
            }
        }
    }
}
private struct Sidebar: View {
    let style:Int
    var body: some View {
        VStack(alignment:.leading,spacing:0) {
            HStack {
                Text("CALENDARS").font(.system(size:10,weight:.semibold)).foregroundStyle(.secondary)
                Spacer();Image(systemName:"eye").font(.system(size:12)).foregroundStyle(.secondary)
            }.frame(height:24).padding(.bottom,15)
            GroupHeading(style:style,title:"Google",count:"3/8")
            VStack(spacing:0) {
                CalendarRow(title:"Devon ELC",color:.green,checked:false)
                CalendarRow(title:"ELC Key Dates [SHARED]",color:.purple.opacity(0.65))
                CalendarRow(title:"Michael ELC",color:.green,checked:false)
                CalendarRow(title:"Michael’s availability",color:.brown.opacity(0.4),checked:false)
                CalendarRow(title:"PTO – Esmeralda Team",color:.brown)
                CalendarRow(title:"Transferred from jes…",color:.green.opacity(0.6),checked:false)
                CalendarRow(title:"Transferred from team…",color:.red.opacity(0.7))
                CalendarRow(title:"pavel@esmeralda.org",color:.green.opacity(0.6),checked:false)
            }.padding(.top,4)
            GroupHeading(style:style,title:"Other",count:"1/1",checked:true).padding(.top,15)
            CalendarRow(title:"Birthdays",color:.blue.opacity(0.5),locked:true).padding(.top,4)
            GroupHeading(style:style,title:"Subscribed Calendars",count:"1/1",checked:true).padding(.top,15)
            CalendarRow(title:"US Holidays",color:.purple,locked:true).padding(.top,4)
            GroupHeading(style:style,title:"iCloud",count:"2/2",checked:true).padding(.top,15)
            CalendarRow(title:"Calendar",color:.blue).padding(.top,4)
            CalendarRow(title:"Partiful",color:.purple,locked:true)
            Spacer(minLength:0)
        }.padding(.horizontal,18).padding(.top,18).frame(width:218,height:595)
            .background(Color.white)
            .overlay(Rectangle().strokeBorder(Color.primary.opacity(0.06),lineWidth:0.5))
    }
}
private struct Comparison: View {
    let names = ["1. Compact sections","2. Soft section bars","3. Explicit All / None","4. Collapsible groups"]
    let details = ["Quiet uppercase label.\nGroup checkbox at right.","A subtle background\nseparates each heading.","Clear text actions instead\nof a group checkbox.","Chevron folds the group.\nCheckbox still selects all."]
    var body: some View {
        VStack(alignment:.leading,spacing:9) {
            Text("Four calendar-group styles").font(.system(size:24,weight:.semibold))
            Text("Native SwiftUI rendering · 218-point sidebar · same calendar rows in every option")
                .font(.system(size:12)).foregroundStyle(.secondary).padding(.bottom,16)
            HStack(alignment:.top,spacing:18) {
                ForEach(0..<4) { index in
                    VStack(alignment:.leading,spacing:10) {
                        Text(names[index]).font(.system(size:14,weight:.semibold))
                        Text(details[index]).font(.system(size:11)).foregroundStyle(.secondary).frame(height:32,alignment:.top)
                        Sidebar(style:index+1)
                    }.frame(width:218,alignment:.leading)
                }
            }
        }.padding(22).background(Color(red:0.95,green:0.96,blue:0.95)).environment(\.colorScheme,.light)
    }
}
@main struct Render {
    @MainActor static func main() {
        let renderer=ImageRenderer(content:Comparison());renderer.scale=2
        guard let image=renderer.cgImage else {fatalError("Render failed")}
        let bitmap=NSBitmapImageRep(cgImage:image)
        try! bitmap.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:CommandLine.arguments[1]))
    }
}
