import SwiftUI
import AppKit

private let purple = Color(red:0.43,green:0.29,blue:0.71)
private let blue = Color(red:0.29,green:0.59,blue:0.83)
private let teal = Color(red:0.15,green:0.63,blue:0.65)
private let gutter: CGFloat = 54
private let days = ["Sat 14","Sun 15","Mon 16","Tue 17","Wed 18","Thu 19","Fri 20"]
private let titles = ["1. A horizontal forecast across the week","2. Vertical weather lanes aligned to your hours","3. Compact weekly overview + hourly lanes","4. Expand one day into a detailed horizontal strip"]
private let subtitles = ["Each day contains its own left-to-right 24-hour chart, directly above all-day events.","Time runs downward everywhere. Temperature bends sideways; blue areas show rain chance.","Daily highs/lows sit above all-day events; narrow vertical lanes show the hourly details.","Choose a day for the top chart. A matching vertical lane keeps it connected to the calendar."]
private func temp(_ d: Int,_ h: Double) -> Double { 54 + 4*sin((h-8)*Double.pi/14) + Double([1,0,2,1,-1,-2,0][d]) }
private func rain(_ d: Int,_ h: Double) -> Double { max(0,min(0.95,Double([0.14,0.3,0.65,0.18,0.78,0.72,0.25][d])+0.23*sin(h/4+Double(d)))) }
private func clouds(_ d: Int,_ h: Double) -> Double { min(0.95,0.18+rain(d,h)*0.85) }
private func wind(_ d:Int) -> Int { [6,8,12,7,14,11,5][d] }
private func symbol(_ d:Int) -> String { ["cloud.sun.fill","cloud.fill","cloud.rain.fill","cloud.sun.fill","cloud.rain.fill","cloud.rain.fill","cloud.sun.fill"][d] }

struct HorizontalForecast: View {
    let day: Int
    var detailed = false
    private var start: Double { detailed ? 6 : 0 }
    private var finish: Double { detailed ? 22 : 24 }
    var body: some View {
        GeometryReader { geo in
            Canvas { context,size in
                let bottom = size.height-18
                // Quiet yellow daylight, grey cloud cover, blue rain probability,
                // and a purple temperature curve, built from hourly samples.
                let count = 32
                let pts = (0...count).map { i -> (CGFloat,Double) in (size.width*CGFloat(i)/CGFloat(count),start+(finish-start)*Double(i)/Double(count)) }
                let dawn = CGFloat((7-start)/(finish-start))*size.width
                let dusk = CGFloat((17-start)/(finish-start))*size.width
                context.fill(Path(CGRect(x:max(0,dawn),y:0,width:min(size.width,dusk)-max(0,dawn),height:bottom)),with:.color(.yellow.opacity(0.09)))
                var cloud = Path(); cloud.move(to:CGPoint(x:0,y:0))
                for (x,h) in pts { cloud.addLine(to:CGPoint(x:x,y:12+clouds(day,h)*Double(bottom)*0.37)) }
                cloud.addLine(to:CGPoint(x:size.width,y:0));cloud.closeSubpath()
                context.fill(cloud,with:.color(.gray.opacity(0.16)))
                var precipitation = Path();precipitation.move(to:CGPoint(x:0,y:bottom))
                for (x,h) in pts { precipitation.addLine(to:CGPoint(x:x,y:bottom-CGFloat(rain(day,h))*bottom*0.55)) }
                precipitation.addLine(to:CGPoint(x:size.width,y:bottom));precipitation.closeSubpath()
                context.fill(precipitation,with:.color(blue.opacity(0.17)))
                var curve = Path()
                for (i,p) in pts.enumerated() {
                    let point = CGPoint(x:p.0,y:bottom*0.64-CGFloat(temp(day,p.1)-54)*bottom*0.025)
                    if i == 0 {curve.move(to:point)} else {curve.addLine(to:point)}
                }
                context.stroke(curve,with:.color(purple.opacity(0.85)),lineWidth:1.25)
                for h in stride(from:detailed ? 6 : 0,through:detailed ? 21 : 24,by:detailed ? 3 : 6) {
                    let x = CGFloat((Double(h)-start)/(finish-start))*size.width
                    let label = h == 0 || h == 24 ? "12a" : (h == 12 ? "12p" : "\(h > 12 ? h-12 : h)\(h > 12 ? "p" : "a")")
                    context.draw(Text(label).font(.system(size:8)).foregroundColor(.secondary),at:CGPoint(x:min(size.width-10,max(10,x)),y:size.height-7))
                    if detailed {
                        let y = bottom*0.64-CGFloat(temp(day,Double(h))-54)*bottom*0.025
                        context.fill(Path(ellipseIn:CGRect(x:x-2,y:y-2,width:4,height:4)),with:.color(purple))
                        context.draw(Text("\(Int(temp(day,Double(h))))°").font(.system(size:10,weight:.medium)).foregroundColor(purple),at:CGPoint(x:max(12,x),y:y-13))
                        context.fill(Path(CGRect(x:x+3,y:bottom-5,width:7,height:5)),with:.color(blue.opacity(rain(day,Double(h)))))
                    }
                }
            }
        }
    }
}
struct VerticalForecast: View {
    let day:Int
    var compact = false
    var body: some View {
        GeometryReader { geo in
            Canvas { context,size in
                let count = 60
                var area=Path();area.move(to:CGPoint(x:size.width,y:0))
                var curve=Path()
                for i in 0...count {
                    let h=8+10*Double(i)/Double(count), y=size.height*CGFloat(i)/CGFloat(count)
                    area.addLine(to:CGPoint(x:size.width-CGFloat(rain(day,h))*size.width*0.66,y:y))
                    let p=CGPoint(x:6+CGFloat(temp(day,h)-47)/16*(size.width-18),y:y)
                    if i==0 {curve.move(to:p)} else {curve.addLine(to:p)}
                }
                area.addLine(to:CGPoint(x:size.width,y:size.height));area.closeSubpath()
                context.fill(Path(CGRect(origin:.zero,size:size)),with:.color(.yellow.opacity(0.045)))
                context.fill(area,with:.color(blue.opacity(0.18)))
                context.stroke(curve,with:.color(purple.opacity(0.7)),lineWidth:1.15)
            }
            VStack {
                ForEach(0..<5) { i in
                    VStack(spacing:3) {
                        Image(systemName:symbol(day)).symbolRenderingMode(.hierarchical).foregroundStyle(rain(day,Double(9+i*2))>0.5 ? blue : .orange).font(.system(size:12))
                        Text("\(Int(temp(day,Double(9+i*2))))°").font(.system(size:9,weight:.medium)).foregroundStyle(purple)
                        if !compact { Text("\(Int(rain(day,Double(9+i*2))*100))%").font(.system(size:8)).foregroundStyle(blue) }
                    }.frame(maxHeight:.infinity)
                }
            }.frame(maxWidth:.infinity,maxHeight:.infinity)
        }
    }
}
struct EventBlock: View {
    let title:String
    let time:String
    let color:Color
    var body: some View {
        VStack(alignment:.leading,spacing:3) {
            Text(title).font(.system(size:10,weight:.semibold)).lineLimit(2)
            Text(time).font(.system(size:9)).lineLimit(1).opacity(0.8)
            Spacer(minLength:0)
        }.foregroundStyle(color).padding(.leading,7).padding(.trailing,3).padding(.top,4)
            .frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading)
            .background(color.opacity(0.10),in:RoundedRectangle(cornerRadius:5))
            .overlay(alignment:.leading) { RoundedRectangle(cornerRadius:1).fill(color).frame(width:3) }
            .overlay(RoundedRectangle(cornerRadius:5).strokeBorder(.white.opacity(0.9),lineWidth:0.5))
    }
}
struct CalendarWeatherMockup: View {
    let option:Int
    private var topHeight:CGFloat { option == 1 ? 108 : option == 3 ? 60 : option == 4 ? 142 : 0 }
    private var gridHeight:CGFloat { 650-topHeight }
    private func toolbarLabel(_ s:String,_ t:String) -> some View {
        HStack(spacing:5) { Image(systemName:s).font(.system(size:14,weight:.medium));Text(t).font(.system(size:12,weight:.medium)) }.foregroundStyle(Color.primary.opacity(0.76))
    }
    var body: some View {
        VStack(spacing:0) {
            HStack(spacing:12) {
                HStack(spacing:7) { ForEach([Color.red,Color.yellow,Color.green],id:\.self) { Circle().fill($0).frame(width:11,height:11) } }
                (Text("November ").fontWeight(.bold)+Text("2026").fontWeight(.light)).font(.system(size:18))
                Spacer()
                toolbarLabel("globe","Zones");toolbarLabel("cloud.sun","Weather");toolbarLabel("sun.max","Daylight")
                Text("⌄ Week").font(.system(size:12));toolbarLabel("plus","New")
                Image(systemName:"chevron.left");Text("Today").font(.system(size:12));Image(systemName:"chevron.right");Image(systemName:"sidebar.right")
            }.foregroundStyle(Color.primary.opacity(0.75)).padding(.horizontal,14).frame(height:44)
            HStack(spacing:0) {
                Text("SF").font(.system(size:9,weight:.semibold)).foregroundStyle(.secondary).frame(width:gutter)
                ForEach(0..<7) { d in
                    Text(days[d]).font(.system(size:12,weight:option == 4 && d == 4 ? .semibold : .regular))
                        .foregroundStyle(option == 4 && d == 4 ? purple : Color.primary.opacity(0.8)).frame(maxWidth:.infinity)
                }
            }.frame(height:28)
            if option == 1 {
                HStack(spacing:2) {
                    Text("°F\nrain %").font(.system(size:8)).foregroundStyle(.secondary).frame(width:gutter-2)
                    ForEach(0..<7) { d in
                        VStack(spacing:3) {
                            HStack {Image(systemName:symbol(d)).foregroundStyle(blue);Text("\(Int(temp(d,14)))° / \(Int(temp(d,4)))°").foregroundStyle(purple);Spacer(minLength:0);Text("\(wind(d))mph").foregroundStyle(teal)}.font(.system(size:9)).padding(.horizontal,5)
                            HorizontalForecast(day:d)
                        }.padding(.top,5).background(Color.primary.opacity(0.015)).frame(maxWidth:.infinity)
                    }
                }.frame(height:108)
            }
            if option == 3 {
                HStack(spacing:2) {
                    Text("Daily\nrange").font(.system(size:8)).foregroundStyle(.secondary).frame(width:gutter-2)
                    ForEach(0..<7) { d in
                        VStack(spacing:5) {
                            HStack(spacing:5) {Image(systemName:symbol(d)).foregroundStyle(blue);Text("\(Int(temp(d,14)))°").foregroundStyle(purple);Text("\(Int(temp(d,4)))°").foregroundStyle(.secondary)}.font(.system(size:11,weight:.medium))
                            HStack(spacing:5) {Text("\(Int(rain(d,12)*100))% rain").foregroundStyle(blue);Text("· \(wind(d))mph").foregroundStyle(teal)}.font(.system(size:8))
                        }.frame(maxWidth:.infinity,maxHeight:.infinity).background(Color.primary.opacity(0.018))
                    }
                }.frame(height:60)
            }
            if option == 4 {
                VStack(spacing:4) {
                    HStack {Text("WED 18 · SAN FRANCISCO").fontWeight(.semibold);Text("54° · Rain likely · Wind 14mph").foregroundStyle(.secondary);Spacer();Text("Temperature °F").foregroundStyle(purple);Text("Rain chance %").foregroundStyle(blue);Image(systemName:"chevron.up")}.font(.system(size:10)).padding(.horizontal,12)
                    HorizontalForecast(day:4,detailed:true)
                }.padding(.top,9).background(purple.opacity(0.025)).frame(height:142)
            }
            // All-day items always remain beneath the horizontal forecast.
            HStack(spacing:0) {
                Text("all-day").font(.system(size:8)).foregroundStyle(.secondary).frame(width:gutter)
                Text("Team offsite planning").font(.system(size:9,weight:.medium)).foregroundStyle(Color(red:0.65,green:0.16,blue:0.33)).padding(.leading,7).frame(maxWidth:.infinity,alignment:.leading).frame(height:18).background(Color.pink.opacity(0.12)).clipShape(RoundedRectangle(cornerRadius:4)).padding(.trailing,330)
            }.frame(height:26)
            HStack(spacing:0) {
                VStack(spacing:0) {
                    ForEach(8..<18) { h in Text(h == 12 ? "12pm" : "\(h>12 ? h-12 : h)\(h<12 ? "am" : "pm")").font(.system(size:9)).foregroundStyle(.secondary).frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topTrailing).padding(.trailing,8) }
                }.frame(width:gutter)
                ForEach(0..<7) { d in
                    GeometryReader { geo in
                        let lane:CGFloat = option == 2 ? 56 : option == 3 ? 36 : option == 4 && d == 4 ? 50 : 0
                        ZStack(alignment:.topLeading) {
                            Color.white
                            VStack(spacing:0) {ForEach(0..<10) { h in Rectangle().fill(rain(d,Double(h+8))>0.5 ? blue.opacity(0.045) : Color.yellow.opacity(0.015)).overlay(alignment:.top){Rectangle().fill(Color.primary.opacity(0.10)).frame(height:0.5)} }}
                            if lane > 0 { VerticalForecast(day:d,compact:option != 2).frame(width:lane).frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.trailing) }
                            let width = geo.size.width-lane-7
                            EventBlock(title:["Morning walk","Family brunch","Project review","Focus time","Michael × Devon","Project workshop","Weekly review"][d],time:["9–10am","10–11am","9–10:30am","10–11am","10–11am","9–11am","10–11am"][d],color:Color(red:0.35,green:0.57,blue:0.24))
                                .frame(width:width,height:geo.size.height*(d == 5 ? 0.2 : d == 2 ? 0.15 : 0.1)).offset(x:3,y:geo.size.height*Double([1,2,1,2,2,1,2][d])/10)
                            EventBlock(title:["Reading","Call with parents","Write proposal","Lunch with team","Ishaan × Devon","Deep work","Plan next week"][d],time:"1–2:30pm",color:d%2 == 0 ? teal : purple)
                                .frame(width:width,height:geo.size.height*0.15).offset(x:3,y:geo.size.height*0.5)
                            EventBlock(title:["Dinner","Travel planning","Team check-in","Run errands","Review notes","Walk","Wrap up"][d],time:"4–5pm",color:Color.orange.opacity(0.9))
                                .frame(width:width,height:geo.size.height*0.1).offset(x:3,y:geo.size.height*0.8)
                        }.overlay(alignment:.leading){Rectangle().fill(Color.primary.opacity(0.10)).frame(width:0.5)}
                    }
                }
            }.frame(height:gridHeight)
            HStack(spacing:12) {
                Text("Illustrative forecast · same sample data in all four options").foregroundStyle(.secondary)
                Spacer();Text("Temperature °F").foregroundStyle(purple);Text("Rain chance %").foregroundStyle(blue);Text("Wind mph").foregroundStyle(teal)
            }.font(.system(size:9)).padding(.horizontal,12).frame(height:23)
        }.frame(width:1200,height:771).background(Color.white).environment(\.colorScheme,.light)
    }
}
@main struct Render {
    @MainActor static func main() {
        let directory=URL(fileURLWithPath:CommandLine.arguments[1])
        for i in 1...4 {
            let view=VStack(alignment:.leading,spacing:9) {
                Text(titles[i-1]).font(.system(size:23,weight:.semibold))
                Text(subtitles[i-1]).font(.system(size:13)).foregroundStyle(.secondary).padding(.bottom,8)
                CalendarWeatherMockup(option:i).overlay(Rectangle().strokeBorder(Color.primary.opacity(0.08),lineWidth:0.5))
            }.padding(20).background(Color(red:0.95,green:0.96,blue:0.95)).environment(\.colorScheme,.light)
            let renderer=ImageRenderer(content:view.id(i));renderer.scale=2
            guard let image=renderer.cgImage else {fatalError("Render failed")}
            let bitmap=NSBitmapImageRep(cgImage:image)
            try! bitmap.representation(using:.png,properties:[:])!.write(to:directory.appendingPathComponent("option-\(i).png"))
        }
    }
}
