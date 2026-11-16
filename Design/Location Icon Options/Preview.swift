import SwiftUI
import AppKit

let choices = [
    ("mappin.and.ellipse","Pin with landing ring","A base makes the pin easier to recognize."),
    ("mappin.circle","Circled pin","An outline circle pairs closely with the clock."),
    ("mappin.circle.fill","Filled circled pin","The strongest silhouette at a small size."),
    ("location.circle","Circled direction arrow","A clear circle with a familiar location arrow."),
    ("map","Folded map","An outline map emphasizes the place itself."),
    ("building.2","Building outline","A physical venue rather than a navigation symbol.")
]
let eventInk = Color(red:0.20,green:0.16,blue:0.52)
struct LocationOptionsPreview: View {
    var body: some View {
        VStack(alignment:.leading,spacing:16) {
            VStack(alignment:.leading,spacing:5) {
                Text("Location icons to pair with the classic clock").font(.system(size:19,weight:.semibold))
                Text("Enlarged pair at left · Actual event-card size at right")
                    .font(.system(size:12)).foregroundStyle(.secondary)
            }
            ForEach(0..<choices.count,id:\.self) { index in
                HStack(spacing:16) {
                    HStack(spacing:10) {
                        Image(systemName:"clock")
                        Image(systemName:choices[index].0)
                    }.font(.system(size:23,weight:.regular)).foregroundStyle(eventInk.opacity(0.8))
                        .frame(width:72)
                    VStack(alignment:.leading,spacing:6) {
                        Text("\(index+1). \(choices[index].1)").font(.system(size:12,weight:.semibold))
                        Text(choices[index].2).font(.system(size:11)).foregroundStyle(.secondary)
                            .fixedSize(horizontal:false,vertical:true)
                    }.frame(width:192,alignment:.leading)
                    VStack(alignment:.leading,spacing:5) {
                        Text("Itsi’s birthday · An Itsi big one").font(.system(size:10,weight:.semibold))
                        HStack(spacing:4) {
                            Image(systemName:"clock").font(.system(size:10,weight:.regular)).frame(width:10)
                            Text("7:50–9:50pm").font(.system(size:9))
                            Text("· 2h").font(.system(size:9)).opacity(0.48)
                        }.foregroundStyle(eventInk.opacity(0.85))
                        HStack(alignment:.top,spacing:4) {
                            Image(systemName:choices[index].0).font(.system(size:10,weight:.regular)).frame(width:10,height:12)
                            Text("VILF Manor, 3122 22nd St").font(.system(size:9))
                        }.foregroundStyle(eventInk.opacity(0.8))
                        Text("Friends! I have aged…").font(.system(size:9)).foregroundStyle(eventInk.opacity(0.55))
                    }.foregroundStyle(eventInk).padding(.horizontal,10).padding(.vertical,9)
                        .frame(width:308,alignment:.leading)
                        .background(Color(red:0.93,green:0.92,blue:0.98),in:RoundedRectangle(cornerRadius:5))
                        .overlay(alignment:.leading) { RoundedRectangle(cornerRadius:1.5).fill(eventInk).frame(width:3) }
                }.padding(.vertical,4)
            }
        }.padding(22).background(.white).environment(\.colorScheme,.light)
    }
}
@main struct RenderLocationOptions {
    @MainActor static func main() throws {
        for choice in choices { precondition(NSImage(systemSymbolName:choice.0,accessibilityDescription:nil) != nil,"Missing SF Symbol: "+choice.0) }
        let renderer = ImageRenderer(content:LocationOptionsPreview()); renderer.scale = 2
        let bitmap = NSBitmapImageRep(data:renderer.nsImage!.tiffRepresentation!)!
        try bitmap.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:CommandLine.arguments[1]))
    }
}
