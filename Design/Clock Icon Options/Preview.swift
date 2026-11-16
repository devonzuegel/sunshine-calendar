import SwiftUI
import AppKit
let ink=Color(red:0.58,green:0.42,blue:0.04)
let icons=["clock","clock.fill","clock.circle","alarm","stopwatch","timer"]
let names=["Classic clock","Filled clock","Circled clock","Alarm clock","Stopwatch","Timer"]
let details=["Familiar outline with unmistakable hands","A solid face makes the hands stand out","An extra circle separates it from nearby text","Bells give it a distinct clock silhouette","Strong timekeeping shape with a top button","A partial dial suggests elapsed time"]
struct Preview:View {
 var body:some View {
 VStack(alignment:.leading,spacing:16) {
  Text("Time icons for event cards").font(.system(size:21,weight:.semibold))
  ForEach(0..<6,id:\.self) { i in
   HStack(spacing:18) {
    Image(systemName:icons[i]).font(.system(size:25,weight:.regular)).foregroundStyle(ink).frame(width:40)
    VStack(alignment:.leading,spacing:5) {
     Text("\(i+1). \(names[i])").font(.system(size:13,weight:.semibold))
     Text(details[i]).font(.system(size:11)).foregroundStyle(.secondary)
    }.frame(width:285,alignment:.leading)
    VStack(alignment:.leading,spacing:5) {
     Text("AA 3263 · SFO → MIA").font(.system(size:11,weight:.semibold))
     HStack(spacing:4) {
      Image(systemName:icons[i]).font(.system(size:10,weight:.regular)).frame(width:10)
      Text("11:52am–5:17pm").font(.system(size:10))
      Text("· 5h 25m").font(.system(size:10)).opacity(0.5)
     }
    }.foregroundStyle(ink).padding(10).frame(width:240,alignment:.leading)
      .background(Color(red:0.99,green:0.96,blue:0.87),in:RoundedRectangle(cornerRadius:5))
   }.padding(.vertical,6)
  }
 }.padding(24).background(.white).environment(\.colorScheme,.light)
 }
}
@main struct Render {
 @MainActor static func main() {
 let renderer=ImageRenderer(content:Preview());renderer.scale=2
 let image=renderer.nsImage!, rep=NSBitmapImageRep(data:image.tiffRepresentation!)!
 try! rep.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:CommandLine.arguments[1]))
 }
}
