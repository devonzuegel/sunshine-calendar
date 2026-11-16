import SwiftUI
import AppKit

struct BankEditorPopover: NSViewRepresentable {
    let model: CalendarModel
    let bank: EventBankStore
    @Binding var editing: BankTask?
    let anchorID: UUID?
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> NSView { NSView() }
    func updateNSView(_ view: NSView, context: Context) {
        context.coordinator.editing = $editing
        guard let task = editing else { context.coordinator.dismiss(); return }
        let matches = anchorID == task.id || (anchorID == nil && bank.records[task.id] == nil)
        guard matches else { return }
        DispatchQueue.main.async { [weak view, coordinator = context.coordinator] in
            guard let view, view.window != nil, coordinator.editing?.wrappedValue?.id == task.id else { return }
            coordinator.present(task,model:model,bank:bank,in:view)
        }
    }
    static func dismantleNSView(_ view: NSView, coordinator: Coordinator) { coordinator.dismiss() }
    @MainActor final class Coordinator: NSObject, NSPopoverDelegate {
        var editing: Binding<BankTask?>?
        var popover: NSPopover?
        var session: BankEditorSession?
        var escapeMonitor: Any?
        var closing = false
        private var committing = false
        deinit { if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor) } }
        func present(_ task: BankTask, model: CalendarModel, bank: EventBankStore, in view: NSView) {
            guard popover == nil else { return }
            let session = BankEditorSession(model:model,bank:bank,task:task)
            self.session = session
            let panel = NSPopover(); panel.behavior = .semitransient; panel.animates = true; panel.delegate = self
            let host = StablePopoverController(content:BankTaskEditor(session:session,close:{ [weak self] cancel in self?.finish(cancel:cancel) }),popover:panel)
            panel.contentViewController = host
            popover = panel
            let rect = view.bounds.isEmpty ? NSRect(x:0,y:0,width:1,height:1) : view.bounds
            panel.show(relativeTo:rect,of:view,preferredEdge:.maxX)
            escapeMonitor = NSEvent.addLocalMonitorForEvents(matching:.keyDown) { [weak self, weak view, weak panel] event in
                guard let self, let panel, panel.isShown, event.keyCode == 53,
                      event.modifierFlags.intersection([.command,.control,.option]).isEmpty,
                      event.window != nil,
                      event.window === view?.window || event.window === panel.contentViewController?.view.window else { return event }
                if let editor = event.window?.firstResponder as? NSTextView, editor.hasMarkedText() { return event }
                self.finish(cancel:true); return nil
            }
        }
        func finish(cancel: Bool) {
            guard cancel || commit() else { return }
            (popover?.contentViewController as? StablePopoverController)?.stopResizing()
            closing = true; popover?.close(); editing?.wrappedValue = nil
            closing = false
        }
        private func commit() -> Bool {
            guard !committing else { return false }
            committing = true
            defer { committing = false }
            guard popover?.contentViewController?.view.window?.makeFirstResponder(nil) != false else { return false }
            return session?.commit() ?? true
        }
        func popoverShouldClose(_ popover: NSPopover) -> Bool { closing || commit() }
        func popoverWillClose(_ notification: Notification) {
            (popover?.contentViewController as? StablePopoverController)?.stopResizing()
        }
        func popoverDidClose(_ notification: Notification) {
            editing?.wrappedValue = nil
            dismiss()
        }
        func dismiss() {
            if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor); self.escapeMonitor = nil }
            let panel = popover; popover = nil
            (panel?.contentViewController as? StablePopoverController)?.stopResizing()
            panel?.delegate = nil; panel?.close(); session = nil
        }
    }
}
