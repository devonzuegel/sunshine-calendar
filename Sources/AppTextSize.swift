import AppKit
import SwiftUI

@MainActor final class AppTextSize: ObservableObject {
    static let shared = AppTextSize()
    static let minimum = 0.8
    static let maximum = 1.6
    @Published private(set) var scale: Double
    private let preferences: UserDefaults
    private var keyboardMonitor: Any?
    init(preferences: UserDefaults = .standard) {
        self.preferences = preferences
        let saved = preferences.object(forKey:"appTextScale") as? Double ?? 1
        scale = saved.isFinite ? min(Self.maximum,max(Self.minimum,saved)) : 1
    }
    func adjust(_ steps: Int) { setScale(scale + Double(steps)*0.1) }
    func reset() { setScale(1) }
    private func setScale(_ value: Double) {
        let newValue = min(Self.maximum,max(Self.minimum,(value*10).rounded()/10))
        guard newValue != scale else { return }
        scale = newValue; preferences.set(newValue,forKey:"appTextScale")
    }
    static func points(_ size: CGFloat) -> CGFloat { size * shared.scale }
    @discardableResult func handleShortcut(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command,.control,.option,.shift])
        guard modifiers.contains(.command), !modifiers.contains(.control), !modifiers.contains(.option) else { return false }
        switch event.charactersIgnoringModifiers {
        case "-", "−": adjust(-1)
        case "+", "=": adjust(1)
        case "0" where !modifiers.contains(.shift): reset()
        default: return false
        }
        return true
    }
    func startKeyboardHandling() {
        guard keyboardMonitor == nil else { return }
        // App-local so these shortcuts also work while an editor popover has focus.
        keyboardMonitor = NSEvent.addLocalMonitorForEvents(matching:.keyDown) { [weak self] event in
            if EmojiAutocomplete.shared.handle(event) { return nil }
            if LocationAutocomplete.handle(event) { return nil }
            return self?.handleShortcut(event) == true ? nil : event
        }
    }
}

private struct AppFontModifier: ViewModifier {
    @ObservedObject private var textSize = AppTextSize.shared
    var size: CGFloat
    var weight: Font.Weight
    func body(content: Content) -> some View {
        content.font(.system(size:size*textSize.scale,weight:weight))
    }
}
extension View {
    func appFont(size: CGFloat, weight: Font.Weight = .regular) -> some View {
        modifier(AppFontModifier(size:size,weight:weight))
    }
}

// Shared outline lock geometry for SwiftUI lists and the native event canvas.
enum ReadOnlyLockGlyph {
    static func path(in rect: CGRect) -> CGPath {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x:rect.minX+x*rect.width,y:rect.minY+y*rect.height) }
        let path = CGMutablePath()
        path.addRoundedRect(in:CGRect(x:rect.minX+rect.width*0.2,y:rect.minY+rect.height*0.43,width:rect.width*0.6,height:rect.height*0.48),cornerWidth:rect.width*0.08,cornerHeight:rect.height*0.08)
        path.move(to:point(0.32,0.43)); path.addLine(to:point(0.32,0.27))
        path.addCurve(to:point(0.68,0.27),control1:point(0.32,0.06),control2:point(0.68,0.06))
        path.addLine(to:point(0.68,0.43))
        return path
    }
}
private struct ReadOnlyLockShape: Shape {
    func path(in rect: CGRect) -> Path { Path(ReadOnlyLockGlyph.path(in:rect)) }
}
struct ReadOnlyLockIcon: View {
    var scale: CGFloat = 1
    var color: Color = .secondary
    var body: some View {
        ReadOnlyLockShape().stroke(color,style:StrokeStyle(lineWidth:1.1*scale,lineCap:.round,lineJoin:.round))
            .frame(width:AppTextSize.points(12)*scale,height:AppTextSize.points(14)*scale)
    }
}

struct ToolbarControlLabel: View {
    let symbol: String
    var title: String? = nil
    var dropdown = false
    var body: some View {
        HStack(spacing:5) {
            Image(systemName:symbol).appFont(size:14,weight:.medium).symbolRenderingMode(.monochrome)
            if let title { Text(title).appFont(size:12,weight:.medium) }
            if dropdown { Image(systemName:"chevron.down").appFont(size:8,weight:.semibold) }
        }
        .foregroundStyle(Color.primary.opacity(0.76))
        .frame(minWidth:title == nil ? AppTextSize.points(29) : nil,minHeight:AppTextSize.points(28))
        .padding(.horizontal,title != nil || dropdown ? AppTextSize.points(7) : 0)
        .fixedSize(horizontal:true,vertical:false)
    }
}
