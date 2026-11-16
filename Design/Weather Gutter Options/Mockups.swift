import SwiftUI
import AppKit
let purple = Color(red:0.43,green:0.29,blue:0.71)
struct Gutter: View {
 let option:Int
 var body: some View {
  VStack(spacing:5) {
   switch option {
   case 0:
    Text("NOW").font(.system(size:8,weight:.medium)).foregroundStyle(.secondary)
    Image(systemName:"cloud.sun").font(.system(size:16)).foregroundStyle(.secondary)
    Text("68°").font(.system(size:19,weight:.medium))
    Text("Feels 65°").font(.system(size:8)).foregroundStyle(.secondary)
   case 1:
    Image(systemName:"cloud.rain").font(.system(size:16)).foregroundStyle(.blue.opacity(0.7))
    Text("Rain").font(.system(size:10,weight:.medium))
    Text("in 2 hours").font(.system(size:8)).foregroundStyle(.secondary)
    Text("40% chance").font(.system(size:7)).foregroundStyle(.tertiary)
   case 2:
    Image(systemName:"location").font(.system(size:13)).foregroundStyle(.secondary)
    Text("SF").font(.system(size:13,weight:.semibold))
    Text("My location").font(.system(size:7)).foregroundStyle(.secondary)
    Image(systemName:"chevron.down").font(.system(size:8)).foregroundStyle(.secondary)
   case 3:
    HStack(spacing:6) { Image(systemName:"thermometer.medium").foregroundStyle(purple); Image(systemName:"drop").foregroundStyle(.blue) }
    HStack(spacing:6) { Image(systemName:"sun.max").foregroundStyle(.orange); Image(systemName:"wind").foregroundStyle(.teal) }
    HStack(spacing:6) { Image(systemName:"cloud").foregroundStyle(.gray); Image(systemName:"slider.horizontal.3").foregroundStyle(.secondary) }
   case 4:
    Image(systemName:"figure.walk").font(.system(size:16)).foregroundStyle(.green.opacity(0.8))
    Text("Go outside").font(.system(size:9,weight:.medium))
    Text("1–4pm").font(.system(size:11,weight:.medium))
    Text("Dry · mild").font(.system(size:7)).foregroundStyle(.secondary)
   default:
    Image(systemName:"chevron.down").font(.system(size:10,weight:.medium)).foregroundStyle(.secondary)
    Text("Forecast").font(.system(size:8)).foregroundStyle(.secondary)
   }
  }.frame(width:72,height:108).background(.white)
 }
}
struct Graph: View {
 var body: some View {
 VStack(spacing:2) {
 Canvas { c,s in
  let b=s.height-15
  for h in 0..<24 {
   let x=s.width*Double(h)/24
   let cloud=0.4+0.3*cos(Double(h)/3)
   if h>6 && h<18 { c.fill(Path(CGRect(x:x,y:0,width:s.width/24+0.5,height:b)),with:.color(.yellow.opacity(0.09))) }
   c.fill(Path(CGRect(x:x,y:0,width:s.width/24+0.5,height:8+cloud*25)),with:.color(.gray.opacity(0.15)))
   let rain=max(0,sin(Double(h-13)/4))*20
   c.fill(Path(CGRect(x:x+1,y:b-rain,width:s.width/24-2,height:rain)),with:.color(.blue.opacity(0.24)))
  }
  for (j,col) in [purple,Color.pink,Color.orange,Color.teal].enumerated() {
   var p=Path()
   for i in 0...120 {
    let x=s.width*Double(i)/120
    let y=j==2 ? b-4-max(0,sin((Double(i)/120-0.25)*6.28))*25 : 32+Double(j)*8+sin(Double(i)/18+Double(j))*9
    if i==0 {p.move(to:CGPoint(x:x,y:y))}else{p.addLine(to:CGPoint(x:x,y:y))}
   }
   c.stroke(p,with:.color(col.opacity(0.85)),style:StrokeStyle(lineWidth:1.1,dash:j==1 || j==2 ? [4,2]:[]))
  }
  for h in [0,6,12,18,24] { c.draw(Text([0:"12a",6:"6a",12:"12p",18:"6p",24:"12a"][h]!).font(.system(size:7)).foregroundColor(.secondary),at:CGPoint(x:max(9,min(s.width-9,s.width*Double(h)/24)),y:s.height-6)) }
 }
 HStack(spacing:5) { Image(systemName:"cloud.sun").foregroundStyle(.gray); Text("71° / 55°").foregroundStyle(purple); Text("UV 6").foregroundStyle(.orange); Text("12mph").foregroundStyle(.teal) }.font(.system(size:8)).frame(height:16)
 }.frame(height:108)
 }
}
let names=["1  Current conditions","2  Next weather change","3  Weather location","4  Quick layer controls","5  Best outdoor window","6  A quiet collapse control"]
let desc=["A glance at the weather right now.","The next useful change, rather than a legend.","A visible home for choosing the forecast city.","Toggle graph layers without opening the menu.","A small suggestion based on rain, wind, and temperature.","Keep it minimal; click to tuck the strip away."]
struct Card:View {
 let i:Int
 var body:some View {
 VStack(alignment:.leading,spacing:9) {
 Text(names[i]).font(.system(size:15,weight:.semibold))
 Text(desc[i]).font(.system(size:11)).foregroundStyle(.secondary)
 VStack(spacing:0) {
 HStack(spacing:0) { HStack { Text("BA"); Text("SF").fontWeight(.semibold) }.font(.system(size:8)).foregroundStyle(.secondary).frame(width:72); Text("Sat 14").font(.system(size:11)); Spacer(); Text("Sun 15").font(.system(size:11)); Spacer() }.frame(height:27)
 HStack(spacing:0) { Color.gray.opacity(0.035).frame(width:72); Text("  more intros for Ethan").font(.system(size:10,weight:.medium)).foregroundStyle(.teal).frame(maxWidth:.infinity,alignment:.leading).background(.teal.opacity(0.1)) }.frame(height:24)
 Rectangle().fill(.gray.opacity(0.2)).frame(height:0.5)
 HStack(spacing:0) { Gutter(option:i); Graph() }
 }.background(.white).clipShape(RoundedRectangle(cornerRadius:9)).overlay(RoundedRectangle(cornerRadius:9).stroke(.gray.opacity(0.18),lineWidth:0.5))
 }.padding(16).frame(width:590).background(.white,in:RoundedRectangle(cornerRadius:13))
 }
}
struct Board:View {
 var body:some View {
 VStack(alignment:.leading,spacing:18) {
 Text("A better home for the weather-strip corner").font(.system(size:24,weight:.semibold))
 Text("Same 72-point corner · same 108-point strip · no extra vertical space").font(.system(size:12)).foregroundStyle(.secondary)
 ForEach(0..<3) { row in HStack(alignment:.top,spacing:16) { Card(i:row*2); Card(i:row*2+1) } }
 }.padding(24).background(Color(nsColor:.windowBackgroundColor)).environment(\.colorScheme,.light)
 }
}
@main struct Render {
 @MainActor static func main() {
 let renderer=ImageRenderer(content:Board());renderer.scale=2
 guard let image=renderer.nsImage,let data=image.tiffRepresentation,let rep=NSBitmapImageRep(data:data),let png=rep.representation(using:.png,properties:[:]) else {return}
 try! png.write(to:URL(fileURLWithPath:CommandLine.arguments[1]))
 }
}
