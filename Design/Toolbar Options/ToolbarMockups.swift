import SwiftUI
import AppKit

// The mockups use real SF Symbols, SF system fonts, and reusable SwiftUI
// control labels at app size. These styles can be transferred into the toolbar.
struct ToolbarOption: View {
    let option: Int
    private let ink = Color.primary.opacity(0.76)
    private var labels: Bool { option == 6 }
    private func symbol(_ name: String, text: String? = nil, dropdown: Bool = false, active: Bool = false) -> some View {
        HStack(spacing:5) {
            Image(systemName:name).font(.system(size:14,weight:option == 1 ? .regular : .medium))
                .symbolRenderingMode(.monochrome)
            if let text { Text(text).font(.system(size:12,weight:.medium)) }
            if dropdown { Image(systemName:"chevron.down").font(.system(size:8,weight:.semibold)) }
        }
        .foregroundStyle(option == 5 && active ? Color.accentColor : ink)
        .frame(minWidth:text == nil ? 29 : nil,minHeight:28)
        .padding(.horizontal,text != nil || dropdown ? 7 : 0)
        .background {
            if option == 2 { RoundedRectangle(cornerRadius:7).fill(Color.primary.opacity(0.045)) }
            if option == 3 { RoundedRectangle(cornerRadius:7).strokeBorder(Color.primary.opacity(0.12),lineWidth:0.7) }
            if option == 5 && active { RoundedRectangle(cornerRadius:7).fill(Color.accentColor.opacity(0.09)) }
        }
    }
    private var group: some View {
        HStack(spacing:option == 4 ? 0 : 5) {
            symbol(option == 5 ? "cloud.sun.fill" : "cloud.sun",text:labels ? "Weather" : nil,dropdown:option != 4,active:true)
            if option == 4 { Divider().frame(height:14) }
            symbol("globe",text:labels ? "Zones" : nil)
            if option == 4 { Divider().frame(height:14) }
            symbol("sun.max",text:labels ? "Daylight" : nil,dropdown:option != 4,active:true)
        }
        .padding(.horizontal,option == 4 ? 3 : 0)
        .background { if option == 4 { RoundedRectangle(cornerRadius:8).fill(Color.primary.opacity(0.04)) } }
    }
    var body: some View {
        VStack(spacing:0) {
            HStack(spacing:12) {
                HStack(spacing:8) {
                    ForEach([Color(red:1,green:0.37,blue:0.35),Color(red:1,green:0.74,blue:0.18),Color(red:0.16,green:0.78,blue:0.26)],id:\.self) { color in Circle().fill(color).frame(width:12,height:12) }
                }
                Text("November 2026").font(.system(size:18,weight:.semibold)).foregroundStyle(Color.primary.opacity(0.8))
                Spacer(minLength:24)
                HStack(spacing:10) {
                    group
                    HStack(spacing:5) {
                        Text("Week").font(.system(size:12,weight:.medium))
                        Image(systemName:"chevron.down").font(.system(size:8,weight:.semibold))
                    }.padding(.horizontal,8).frame(height:28)
                    symbol("plus",text:labels ? "New" : nil)
                    HStack(spacing:3) {
                        symbol("chevron.left")
                        Text("Today").font(.system(size:12,weight:.medium)).frame(width:46,height:28)
                        symbol("chevron.right")
                    }
                    symbol("sidebar.right")
                }.foregroundStyle(ink).fixedSize()
            }.padding(.horizontal,15).frame(height:46)
            HStack(spacing:0) {
                HStack(spacing:14) { Text("BA"); Text("SF").fontWeight(.semibold) }.frame(width:90)
                ForEach(["Thu 12","Fri 13","Sat 14","Sun 15","Mon 16","Tue 17","Wed 18"],id:\.self) { value in Text(value).frame(maxWidth:.infinity) }
            }.font(.system(size:11)).foregroundStyle(.secondary).frame(height:30)
            HStack(spacing:1) {
                Color.white.frame(width:90)
                ForEach(0..<7) { index in
                    Rectangle().fill(index % 3 == 0 ? Color.green.opacity(0.08) : Color.white)
                        .overlay(alignment:.leading) { Rectangle().fill(Color.primary.opacity(0.055)).frame(width:0.5) }
                }
            }.frame(height:20)
        }.background(Color.white).environment(\.colorScheme,.light)
    }
}
struct Comparison: View {
    let titles = ["1. Clean outline","2. Quiet individual buttons","3. Fine outlined buttons","4. One compact segmented group","5. Active-state accents","6. Icons with short labels"]
    let details = ["Monochrome, consistent stroke weight; no button backgrounds.","Small, flat rounded rectangles; no glass, shadows, or gradients.","Hairline borders define each target without a shaded fill.","Weather, zones, and daylight share a subtle flat container.","Color identifies enabled overlays; other controls stay monochrome.","Weather, Zones, and Daylight labels make the symbols explicit."]
    var body: some View {
        VStack(alignment:.leading,spacing:0) {
            Text("Six toolbar treatments — rendered with native fonts and SF Symbols")
                .font(.system(size:23,weight:.semibold)).padding(.bottom,8)
            Text("Actual-size controls · identical spacing, month title, navigation, and date row in every option")
                .font(.system(size:13)).foregroundStyle(.secondary).padding(.bottom,25)
            ForEach(0..<6) { i in
                HStack(alignment:.firstTextBaseline) {
                    Text(titles[i]).font(.system(size:16,weight:.semibold))
                    Text(details[i]).font(.system(size:12)).foregroundStyle(.secondary)
                }.padding(.bottom,9)
                ToolbarOption(option:i+1).frame(width:1200)
                    .overlay(Rectangle().strokeBorder(Color.primary.opacity(0.06),lineWidth:0.5))
                    .padding(.bottom,23)
            }
        }.padding(22).background(Color(red:0.95,green:0.96,blue:0.95)).environment(\.colorScheme,.light)
    }
}
@main struct Render {
    @MainActor static func main() {
        let directory = URL(fileURLWithPath:CommandLine.arguments[1])
        func save<V: View>(_ view: V, name: String) {
            let renderer = ImageRenderer(content:view)
            renderer.scale = 2
            guard let image = renderer.cgImage else { fatalError("No rendered image") }
            let bitmap = NSBitmapImageRep(cgImage:image)
            try! bitmap.representation(using:.png,properties:[:])!.write(to:directory.appendingPathComponent(name))
        }
        save(Comparison(),name:"comparison.png")
        for option in 1...6 { save(ToolbarOption(option:option).frame(width:1200),name:"option-\(option).png") }
    }
}
