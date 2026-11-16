import AppKit
import SwiftUI

@MainActor final class MeasuredPopoverHostingView: NSHostingView<AnyView> {
    var onSizeInvalidated: (() -> Void)?
    override func layout() {
        super.layout()
        onSizeInvalidated?()
    }
    override func viewWillDraw() {
        super.viewWillDraw()
        onSizeInvalidated?()
    }
    override func invalidateIntrinsicContentSize() {
        super.invalidateIntrinsicContentSize()
        onSizeInvalidated?()
    }
}

// SwiftUI's automatic hosting-window sizing can recursively lay out macOS 26
// popover materials while a field loses focus. Keep a plain AppKit container
// in charge of the window and apply measured sizes on a later run-loop turn.
@MainActor final class StablePopoverController: NSViewController {
    let hosting = MeasuredPopoverHostingView(rootView:AnyView(EmptyView()))
    private weak var panel: NSPopover?
    private var pendingSize: CGSize?
    private var resizeQueued = false
    private var measurementQueued = false
    private var measuring = false
    private(set) var resizingEnabled = true
    private(set) var appliedSize: CGSize = .zero
    init<Content: View>(content: Content, popover: NSPopover) {
        panel = popover
        super.init(nibName:nil,bundle:nil)
        hosting.rootView = AnyView(content)
        // Measure before attachment, when there is no popover window to resize.
        let initial = Self.validSize(hosting.fittingSize) ?? CGSize(width:400,height:500)
        // Intrinsic measurement remains available for growing notes. Min/max
        // window sizing is disabled, and the hosting view has no constraints
        // connecting its intrinsic size to the popover's plain container.
        hosting.sizingOptions = [.intrinsicContentSize]
        hosting.onSizeInvalidated = { [weak self] in self?.requestMeasurement() }
        view = NSView(frame:NSRect(origin:.zero,size:initial))
        hosting.frame = view.bounds
        hosting.autoresizingMask = [.width,.height]
        view.addSubview(hosting)
        appliedSize = initial
        popover.contentSize = initial
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    static func validSize(_ size: CGSize) -> CGSize? {
        guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0 else { return nil }
        return CGSize(width:ceil(size.width*2)/2,height:ceil(size.height*2)/2)
    }
    private func requestMeasurement() {
        guard resizingEnabled, !measurementQueued, !measuring else { return }
        measurementQueued = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.measurementQueued = false
            guard self.resizingEnabled else { return }
            self.measuring = true
            let size = self.hosting.intrinsicContentSize
            self.measuring = false
            self.requestSize(size)
        }
    }
    func requestSize(_ size: CGSize) {
        guard resizingEnabled, let size = Self.validSize(size) else { return }
        pendingSize = size
        guard !resizeQueued else { return }
        resizeQueued = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.resizeQueued = false
            guard self.resizingEnabled, let size = self.pendingSize else { return }
            self.pendingSize = nil
            guard abs(size.width-self.appliedSize.width) > 0.5 || abs(size.height-self.appliedSize.height) > 0.5 else { return }
            self.appliedSize = size
            // This executes outside SwiftUI/AppKit's current layout pass.
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0
                self.panel?.contentSize = size
            }
        }
    }
    func stopResizing() { resizingEnabled = false; pendingSize = nil }
}
