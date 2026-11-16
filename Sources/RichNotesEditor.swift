import AppKit
import SwiftUI

@MainActor enum RichNotesHTML {
    static func decode(_ source: String, fontSize: CGFloat) -> NSAttributedString {
        let html = source.range(of:"</?[a-z][^>]*>",options:[.regularExpression,.caseInsensitive]) != nil
        let value: NSMutableAttributedString
        if html {
            // Notes are text, not a web page: exclude executable and remote content.
            var safe = source.replacingOccurrences(of:"(?is)<(script|iframe|object|embed)\\b[^>]*>.*?</\\1\\s*>",with:"",options:.regularExpression)
            safe = safe.replacingOccurrences(of:"(?is)<(?:img|link|meta|iframe|object|embed)\\b[^>]*>",with:"",options:.regularExpression)
            safe = safe.replacingOccurrences(of:"(?is)url\\s*\\([^)]*\\)|@import[^;]*;",with:"",options:.regularExpression)
            if let data = safe.data(using:.utf8), let parsed = try? NSAttributedString(data:data,options:[.documentType:NSAttributedString.DocumentType.html,.characterEncoding:String.Encoding.utf8.rawValue],documentAttributes:nil) {
                value = NSMutableAttributedString(attributedString:parsed)
            } else { value = NSMutableAttributedString(string:CalendarNotePreview.plainText(source)) }
        } else { value = decodeMarkdown(source,fontSize:fontSize) }
        let range = NSRange(location:0,length:value.length)
        value.enumerateAttribute(.font,in:range) { font,range,_ in
            let traits = (font as? NSFont).map { NSFontManager.shared.traits(of:$0) } ?? []
            var normalized = (font as? NSFont)?.isFixedPitch == true ? NSFont.monospacedSystemFont(ofSize:fontSize,weight:.regular) : NSFont.systemFont(ofSize:fontSize)
            if traits.contains(.boldFontMask) { normalized = NSFontManager.shared.convert(normalized,toHaveTrait:.boldFontMask) }
            if traits.contains(.italicFontMask) { normalized = NSFontManager.shared.convert(normalized,toHaveTrait:.italicFontMask) }
            value.addAttribute(.font,value:normalized,range:range)
        }
        value.addAttribute(.foregroundColor,value:NSColor.labelColor,range:range)
        return value
    }
    static func decodeMarkdown(_ source: String, fontSize: CGFloat) -> NSMutableAttributedString {
        guard let parsed = try? AttributedString(markdown:source,options:.init(interpretedSyntax:.inlineOnlyPreservingWhitespace)) else {
            return NSMutableAttributedString(string:source)
        }
        let result = NSMutableAttributedString(string:"")
        for run in parsed.runs {
            var font = NSFont.systemFont(ofSize:fontSize)
            let intent = run.inlinePresentationIntent ?? []
            if intent.contains(.stronglyEmphasized) { font = NSFontManager.shared.convert(font,toHaveTrait:.boldFontMask) }
            if intent.contains(.emphasized) { font = NSFontManager.shared.convert(font,toHaveTrait:.italicFontMask) }
            if intent.contains(.code) { font = NSFont.monospacedSystemFont(ofSize:fontSize,weight:.regular) }
            var attributes: [NSAttributedString.Key:Any] = [.font:font]
            if intent.contains(.strikethrough) { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
            if let link = run.link { attributes[.link] = link }
            result.append(NSAttributedString(string:String(parsed[run.range].characters),attributes:attributes))
        }
        return result
    }
    private struct InlineStyle: Equatable {
        var bold: Bool
        var italic: Bool
        var code: Bool
        var strike: Bool
        var link: String?
    }
    // Prefer a plain string or portable inline Markdown. Only formatting that
    // Markdown cannot faithfully carry (such as imported tables) needs HTML.
    static func encode(_ text: NSAttributedString) -> String {
        guard text.length > 0 else { return "" }
        if let portable = markdown(text) { return portable }
        return encodeHTML(text)
    }
    private static func markdown(_ text: NSAttributedString) -> String? {
        var supported = true
        var formatted = false
        var parts: [(String,InlineStyle)] = []
        text.enumerateAttributes(in:NSRange(location:0,length:text.length)) { attributes,range,_ in
            let font = attributes[.font] as? NSFont ?? NSFont.systemFont(ofSize:13)
            let traits = NSFontManager.shared.traits(of:font)
            let string = (text.string as NSString).substring(with:range)
            let originalLink = (attributes[.link] as? URL)?.absoluteString ?? attributes[.link] as? String
            let link = originalLink == string ? nil : originalLink
            let strike = (attributes[.strikethroughStyle] as? NSNumber)?.intValue ?? 0
            let style = InlineStyle(bold:traits.contains(.boldFontMask),italic:traits.contains(.italicFontMask),code:font.isFixedPitch,strike:strike != 0,link:link)
            formatted = formatted || style.bold || style.italic || style.code || style.strike || link != nil
            if strike != 0 && strike != NSUnderlineStyle.single.rawValue { supported = false }
            if let paragraph = attributes[.paragraphStyle] as? NSParagraphStyle,
               !paragraph.textLists.isEmpty || !paragraph.textBlocks.isEmpty || ![NSTextAlignment.natural,.left].contains(paragraph.alignment) || paragraph.headIndent != 0 || paragraph.firstLineHeadIndent != 0 { supported = false }
            for key in [NSAttributedString.Key.underlineStyle,.superscript,.baselineOffset,.kern,.strokeWidth] {
                if let value = attributes[key] as? NSNumber, value.doubleValue != 0, !(key == .underlineStyle && originalLink != nil) { supported = false }
            }
            if attributes[.attachment] != nil || attributes[.backgroundColor] != nil { supported = false }
            if let last = parts.last, last.1 == style { parts[parts.count-1].0 += string }
            else { parts.append((string,style)) }
        }
        guard supported else { return nil }
        guard formatted else { return text.string }
        func escape(_ source: String) -> String {
            var result = ""
            for character in source {
                if "\\*_[]`~<>".contains(character) { result.append("\\") }
                result.append(character)
            }
            return result
        }
        let candidate = parts.map { string,style in
            string.components(separatedBy:"\n").map { line in
                guard let first = line.firstIndex(where:{ !$0.isWhitespace }), let last = line.lastIndex(where:{ !$0.isWhitespace }) else { return line }
                let end = line.index(after:last)
                let core = String(line[first..<end])
                var content = escape(core)
                if style.code {
                    let longest = core.split(whereSeparator:{ $0 != "`" }).map(\.count).max() ?? 0
                    let fence = String(repeating:"`",count:longest+1)
                    content = fence+" "+core+" "+fence
                }
                let marker = style.bold ? (style.italic ? "***" : "**") : (style.italic ? "*" : "")
                content = marker+content+marker
                if style.strike { content = "~~"+content+"~~" }
                if let link = style.link {
                    // Markdown destinations may contain spaces or parentheses.
                    let destination = link.replacingOccurrences(of:" ",with:"%20").replacingOccurrences(of:"(",with:"%28").replacingOccurrences(of:")",with:"%29")
                    content = "["+content+"]("+destination+")"
                }
                return String(line[..<first])+content+String(line[end...])
            }.joined(separator:"\n")
        }.joined()
        // Ambiguous delimiter combinations must never silently change the text.
        guard decodeMarkdown(candidate,fontSize:13).string == text.string else { return nil }
        return candidate
    }
    private static func encodeHTML(_ text: NSAttributedString) -> String {
        let saved = NSMutableAttributedString(attributedString:text)
        // Avoid saving adaptive UI colors as fixed dark/light text colors.
        saved.removeAttribute(.foregroundColor,range:NSRange(location:0,length:saved.length))
        guard let data = try? saved.data(from:NSRange(location:0,length:saved.length),documentAttributes:[.documentType:NSAttributedString.DocumentType.html]), let html = String(data:data,encoding:.utf8) else { return text.string }
        return html
    }
}

@MainActor final class RichNotesActions: ObservableObject {
    weak var editor: NSTextView?
    @Published private(set) var isFocused = false
    func setFocused(_ focused: Bool) {
        if isFocused != focused { isFocused = focused }
    }
    func fontTrait(_ trait: NSFontTraitMask) {
        guard let editor, editor.isEditable else { return }
        let range = editor.selectedRange()
        let storage = editor.textStorage!
        let attributes = range.length == 0 ? editor.typingAttributes : storage.attributes(at:range.location,effectiveRange:nil)
        let font = attributes[.font] as? NSFont ?? NSFont.systemFont(ofSize:AppTextSize.points(13))
        let remove = NSFontManager.shared.traits(of:font).contains(trait)
        if range.length == 0 {
            editor.typingAttributes[.font] = remove ? NSFontManager.shared.convert(font,toNotHaveTrait:trait) : NSFontManager.shared.convert(font,toHaveTrait:trait)
        } else if editor.shouldChangeText(in:range,replacementString:nil) {
            storage.enumerateAttribute(.font,in:range) { value,part,_ in
                let original = value as? NSFont ?? font
                storage.addAttribute(.font,value:remove ? NSFontManager.shared.convert(original,toNotHaveTrait:trait) : NSFontManager.shared.convert(original,toHaveTrait:trait),range:part)
            }
            editor.didChangeText()
        }
        editor.window?.makeFirstResponder(editor)
    }
    func bulletList() {
        guard let editor, editor.isEditable else { return }
        let range = (editor.string as NSString).paragraphRange(for:editor.selectedRange())
        let text = (editor.string as NSString).substring(with:range)
        let lines = text.components(separatedBy:"\n")
        let remove = lines.filter { !$0.isEmpty }.allSatisfy { $0.hasPrefix("- ") || $0.hasPrefix("• ") }
        guard let storage = editor.textStorage else { return }
        let replacement = NSMutableAttributedString(attributedString:storage.attributedSubstring(from:range))
        var offsets: [(Int,String)] = []; var offset = 0
        for (index,line) in lines.enumerated() {
            if !(index == lines.count-1 && line.isEmpty && lines.count > 1) { offsets.append((offset,line)) }
            offset += (line as NSString).length+1
        }
        for (offset,line) in offsets.reversed() {
            if remove {
                if line.hasPrefix("- ") || line.hasPrefix("• ") { replacement.deleteCharacters(in:NSRange(location:offset,length:2)) }
            } else {
                let attributes = replacement.length > offset ? replacement.attributes(at:offset,effectiveRange:nil) : editor.typingAttributes
                replacement.insert(NSAttributedString(string:"- ",attributes:attributes),at:offset)
            }
        }
        editor.insertText(replacement,replacementRange:range)
        editor.window?.makeFirstResponder(editor)
    }
    func link(_ url: String) {
        guard let editor, editor.isEditable, let value = URL(string:url), value.scheme != nil else { return }
        let range = editor.selectedRange()
        if range.length == 0 {
            editor.insertText(NSAttributedString(string:url,attributes:[.link:value,.font:NSFont.systemFont(ofSize:AppTextSize.points(13))]),replacementRange:range)
        } else if editor.shouldChangeText(in:range,replacementString:nil) {
            editor.textStorage?.addAttribute(.link,value:value,range:range); editor.didChangeText()
        }
        editor.window?.makeFirstResponder(editor)
    }
}

struct RichNotesEditor: View {
    @Binding var notes: String
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var actions = RichNotesActions()
    @State private var height: CGFloat = 40
    @State private var addingLink = false
    @State private var link = ""
    private var showTools: Bool { enabled && (actions.isFocused || addingLink) }
    var body: some View {
        VStack(alignment:.leading,spacing:showTools ? 5 : 0) {
            HStack(spacing:12) {
                Button { actions.fontTrait(.boldFontMask) } label: { Text("B").bold() }.accessibilityLabel("Bold")
                Button { actions.fontTrait(.italicFontMask) } label: { Text("I").italic() }.accessibilityLabel("Italic")
                Button { actions.bulletList() } label: { Image(systemName:"list.bullet") }.accessibilityLabel("Bullet list")
                Button { addingLink = true } label: { Image(systemName:"link") }.accessibilityLabel("Add link")
                    .popover(isPresented:$addingLink) {
                        HStack {
                            TextField("https://…",text:$link).textFieldStyle(.roundedBorder).frame(width:220)
                            Button("Add") { actions.link(link); addingLink = false; link = "" }.keyboardShortcut(.defaultAction)
                        }.padding(12)
                    }
                Spacer(minLength:0)
            }.buttonStyle(.plain).appFont(size:10).foregroundStyle(.secondary).disabled(!enabled)
                .frame(height:showTools ? AppTextSize.points(16) : 0,alignment:.top)
                .opacity(showTools ? 1 : 0)
                .offset(y:showTools || reduceMotion ? 0 : -3)
                .clipped().allowsHitTesting(showTools).accessibilityHidden(!showTools)
            ZStack(alignment:.topLeading) {
                if notes.isEmpty { Text("Add notes").foregroundStyle(.tertiary).padding(.leading,5).padding(.top,4).allowsHitTesting(false) }
                RichNotesTextView(notes:$notes,height:$height,actions:actions,enabled:enabled)
                    .frame(height:min(max(AppTextSize.points(40),height),min(AppTextSize.points(240),(NSScreen.main?.visibleFrame.height ?? 900)*0.28)))
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration:0.16),value:showTools)
    }
}

private struct RichNotesTextView: NSViewRepresentable {
    @Binding var notes: String
    @Binding var height: CGFloat
    let actions: RichNotesActions
    let enabled: Bool
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView(); scroll.drawsBackground = false; scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
        let text = NotesTextView(frame:NSRect(x:0,y:0,width:300,height:40))
        text.isRichText = true; text.importsGraphics = false; text.allowsUndo = true
        text.drawsBackground = false; text.isVerticallyResizable = true; text.isHorizontallyResizable = false
        text.textContainerInset = NSSize(width:0,height:4)
        text.textContainer?.containerSize = NSSize(width:300,height:CGFloat.greatestFiniteMagnitude)
        text.textContainer?.widthTracksTextView = true
        text.textContainer?.heightTracksTextView = false
        text.autoresizingMask = [.width]; text.minSize = .zero; text.maxSize = NSSize(width:CGFloat.greatestFiniteMagnitude,height:CGFloat.greatestFiniteMagnitude)
        text.font = .systemFont(ofSize:AppTextSize.points(13)); text.textColor = .labelColor
        text.isAutomaticLinkDetectionEnabled = true
        text.delegate = context.coordinator
        text.onFocusChange = { [weak actions] focused in actions?.setFocused(focused) }
        text.onLayout = { [weak coordinator = context.coordinator] in coordinator?.requestMeasurement() }
        scroll.documentView = text; actions.editor = text
        context.coordinator.text = text
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let text = scroll.documentView as? NSTextView else { return }
        text.isEditable = enabled; text.isSelectable = true
        if scroll.contentSize.width > 0, abs(text.frame.width-scroll.contentSize.width) > 0.5 {
            text.setFrameSize(NSSize(width:scroll.contentSize.width,height:max(40,text.frame.height)))
        }
        if context.coordinator.lastSource != notes {
            context.coordinator.lastSource = notes
            text.textStorage?.setAttributedString(RichNotesHTML.decode(notes,fontSize:AppTextSize.points(13)))
            text.typingAttributes = [.font:NSFont.systemFont(ofSize:AppTextSize.points(13)),.foregroundColor:NSColor.labelColor]
        }
        context.coordinator.requestMeasurement()
    }
    @MainActor final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: RichNotesTextView
        weak var text: NSTextView?
        var lastSource: String?
        init(_ parent: RichNotesTextView) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            guard let text, !text.hasMarkedText(), let value = text.textStorage else { return }
            let source = RichNotesHTML.encode(value)
            lastSource = source; parent.notes = source; requestMeasurement()
        }
        private var measurementPending = false
        private var measuring = false
        func requestMeasurement() {
            guard !measurementPending else { return }
            measurementPending = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.measurementPending = false
                self.measure()
            }
        }
        private func measure() {
            guard !measuring, let text, let container = text.textContainer, let layout = text.layoutManager else { return }
            measuring = true
            defer { measuring = false }
            layout.ensureLayout(for:container)
            let measured = ceil(layout.usedRect(for:container).height+text.textContainerInset.height*2+4)
            if abs(parent.height-measured) > 0.5 { parent.height = measured }
        }
    }
}

private final class NotesTextView: NSTextView {
    var onFocusChange: ((Bool) -> Void)?
    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { onFocusChange?(true) }
        return accepted
    }
    override func resignFirstResponder() -> Bool {
        let accepted = super.resignFirstResponder()
        if accepted { onFocusChange?(false) }
        return accepted
    }
    var onLayout: (() -> Void)?
    override func layout() { super.layout(); onLayout?() }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // Keep rich-text shortcuts inside the notes editor, even when the
        // calendar uses the same letters for panel commands.
        if window?.firstResponder === self, event.modifierFlags.intersection([.command,.control,.option,.shift]) == .command {
            if event.charactersIgnoringModifiers?.lowercased() == "b" { RichNotesActionsFor(self,.boldFontMask); return true }
            if event.charactersIgnoringModifiers?.lowercased() == "i" { RichNotesActionsFor(self,.italicFontMask); return true }
        }
        return super.performKeyEquivalent(with:event)
    }
    private func RichNotesActionsFor(_ editor: NSTextView, _ trait: NSFontTraitMask) {
        let actions = RichNotesActions(); actions.editor = editor; actions.fontTrait(trait)
    }
}
