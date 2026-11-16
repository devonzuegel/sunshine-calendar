import AppKit
import SwiftUI

struct EmojiEntry: Decodable, Identifiable {
    let emoji: String
    let name: String
    let keywords: [String]
    var id: String { emoji }
    var displayName: String {
        name.hasPrefix("flag: ") ? String(name.dropFirst(6))+" Flag" : name.localizedCapitalized
    }
}
enum EmojiCatalog {
    static func decode(_ data: Data) -> [EmojiEntry] {
        ((try? JSONDecoder().decode([EmojiEntry].self,from:data)) ?? []).filter {
            $0.emoji.unicodeScalars.contains { ($0.properties.isEmoji && $0.value > 127) || $0.value == 0x20E3 }
        }
    }
    static let entries: [EmojiEntry] = {
        guard let url = Bundle.main.url(forResource:"EmojiCatalog",withExtension:"json"), let data = try? Data(contentsOf:url) else { return [] }
        return decode(data)
    }()
    private static let queryPattern = try! NSRegularExpression(pattern:#"(?<![\p{L}\p{N}/:]):([\p{L}\p{N}_+\-]+)$"#)
    static func query(in text: String, caret: NSRange) -> (range: NSRange, query: String)? {
        let string = text as NSString
        guard caret.length == 0, caret.location <= string.length else { return nil }
        let prefix = string.substring(to:caret.location)
        guard let match = queryPattern.firstMatch(in:prefix,range:NSRange(location:0,length:(prefix as NSString).length)) else { return nil }
        return (match.range,(prefix as NSString).substring(with:match.range(at:1)))
    }
    static func matches(_ query: String, in entries: [EmojiEntry] = entries) -> [EmojiEntry] {
        let query = query.replacingOccurrences(of:"_",with:" ").lowercased().trimmingCharacters(in:.whitespaces)
        func rank(_ item: EmojiEntry) -> Int {
            let name = item.name.lowercased()
            if name == query { return 0 }
            if name.hasPrefix(query) || item.displayName.lowercased().hasPrefix(query) { return 1 }
            if name.split(separator:" ").contains(where:{ $0.hasPrefix(query) }) { return 2 }
            return 3
        }
        return entries.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) || $0.keywords.contains(where:{ $0.localizedCaseInsensitiveContains(query) }) }
            .sorted { let a = rank($0), b = rank($1); return a == b ? $0.displayName < $1.displayName : a < b }
    }
}

private struct EmojiSuggestionMenu: View {
    let items: [EmojiEntry]
    let selected: Int
    let choose: (Int) -> Void
    let highlight: (Int) -> Void
    var body: some View {
        VStack(spacing:1) {
            ForEach(Array(items.enumerated()),id:\.element.id) { index,item in
                Button { choose(index) } label: {
                    HStack(spacing:9) {
                        Text(item.emoji).font(.system(size:18)).frame(width:24)
                        Text(item.displayName).appFont(size:12).lineLimit(1)
                        Spacer(minLength:0)
                    }.padding(.horizontal,8).frame(height:29).contentShape(Rectangle())
                        .foregroundStyle(index == selected ? Color.white : Color.primary)
                        .background(index == selected ? Color.accentColor : .clear,in:RoundedRectangle(cornerRadius:5))
                }.buttonStyle(.plain).onHover { if $0 { highlight(index) } }
            }
        }.padding(5).frame(width:320)
            .background(Color(nsColor:.windowBackgroundColor),in:RoundedRectangle(cornerRadius:9))
            .overlay(RoundedRectangle(cornerRadius:9).strokeBorder(Color.primary.opacity(0.12),lineWidth:0.5)).padding(1)
    }
}

@MainActor final class EmojiAutocomplete {
    static let shared = EmojiAutocomplete()
    private weak var editor: NSTextView?
    private var panel: NSPanel?
    private var items: [EmojiEntry] = []
    private var selected = 0
    private var range = NSRange(location:0,length:0)
    private var prefix = ""
    private var dismissedPrefix: String?
    private var observers: [NSObjectProtocol] = []
    private var mouseMonitor: Any?
    private init() {
        for name in [NSText.didChangeNotification,NSTextView.didChangeSelectionNotification] {
            observers.append(NotificationCenter.default.addObserver(forName:name,object:nil,queue:.main) { [weak self] note in
                guard let text = note.object as? NSTextView else { return }
                Task { @MainActor in self?.refresh(text) }
            })
        }
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching:[.leftMouseDown,.scrollWheel]) { [weak self] event in
            if event.window !== self?.panel { self?.hide() }
            return event
        }
    }
    func handle(_ event: NSEvent) -> Bool {
        guard let text = event.window?.firstResponder as? NSTextView, text.isEditable, !text.hasMarkedText() else { hide(); return false }
        guard event.modifierFlags.intersection([.command,.control,.option]).isEmpty else { hide(); return false }
        if panel != nil, text === editor {
            if event.keyCode == 53 { dismissedPrefix = prefix; hide(); return true }
            if [125,126].contains(event.keyCode) {
                selected = (selected+(event.keyCode == 125 ? 1 : items.count-1))%max(1,items.count)
                present(); return true
            }
            if [36,76,48].contains(event.keyCode) { insert(selected); return true }
        }
        DispatchQueue.main.async { [weak self, weak text] in if let text { self?.refresh(text) } }
        return false
    }
    private func refresh(_ text: NSTextView) {
        guard text.isEditable, !text.hasMarkedText(), text.window?.isKeyWindow == true, text.window?.firstResponder === text,
              let query = EmojiCatalog.query(in:text.string,caret:text.selectedRange()) else { hide(); dismissedPrefix = nil; return }
        let token = "\(query.range.location):\(query.query)"
        guard dismissedPrefix != token else { return }
        let changed = editor !== text || prefix != token
        editor = text; range = query.range; prefix = token
        if changed { selected = 0; items = Array(EmojiCatalog.matches(query.query).prefix(10)) }
        guard !items.isEmpty else { hide(); return }
        present()
    }
    private func present() {
        guard let editor, let parent = editor.window else { hide(); return }
        let caret = editor.firstRect(forCharacterRange:editor.selectedRange(),actualRange:nil)
        let content = NSHostingView(rootView:EmojiSuggestionMenu(items:items,selected:selected,choose:{ [weak self] in self?.insert($0) },highlight:{ [weak self] index in
            guard let self, self.selected != index else { return }; self.selected = index; self.present()
        }))
        let size = content.fittingSize
        let screen = parent.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        let x = max(screen.minX+8,min(caret.minX,screen.maxX-size.width-8))
        let above = caret.maxY+4
        let y = above+size.height <= screen.maxY-8 ? above : max(screen.minY+8,caret.minY-size.height-4)
        let frame = NSRect(x:x,y:y,width:size.width,height:size.height)
        let window: NSPanel
        if let panel { window = panel }
        else {
            window = NSPanel(contentRect:frame,styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
            window.isOpaque = false; window.backgroundColor = .clear; window.hasShadow = true
            window.hidesOnDeactivate = true; parent.addChildWindow(window,ordered:.above); panel = window
        }
        content.sizingOptions = []; content.setFrameSize(size)
        window.contentView = content; window.setFrame(frame,display:true); window.orderFront(nil)
    }
    private func insert(_ index: Int) {
        guard let editor, items.indices.contains(index), let query = EmojiCatalog.query(in:editor.string,caret:editor.selectedRange()), query.range == range else { hide(); return }
        let emoji = items[index].emoji
        hide(); dismissedPrefix = nil
        editor.window?.makeFirstResponder(editor)
        editor.insertText(emoji,replacementRange:query.range)
    }
    private func hide() {
        if let panel { panel.parent?.removeChildWindow(panel); panel.orderOut(nil) }
        panel = nil
    }
}
