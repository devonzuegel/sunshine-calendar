import AppKit

@MainActor enum AppRestart {
    static func restart(model: CalendarModel) {
        guard model.draft == nil, !NSApp.windows.contains(where:{ $0.attachedSheet != nil }) else {
            model.message = "Save or close the open editor before restarting."
            return
        }
        guard let script = Bundle.main.url(forResource:"Relaunch",withExtension:"sh") else {
            model.message = "The restart helper is missing. Reopen Sunshine Calendar manually."
            return
        }
        func canvas(in view: NSView?) -> CalendarCanvas? {
            guard let view else { return nil }
            if let calendar = view as? CalendarCanvas { return calendar }
            for child in view.subviews { if let found = canvas(in:child) { return found } }
            return nil
        }
        let calendar = NSApp.windows.compactMap { canvas(in:$0.contentView) }.first
        let helper = Process()
        helper.executableURL = URL(fileURLWithPath:"/bin/sh")
        helper.arguments = [script.path,String(ProcessInfo.processInfo.processIdentifier),Bundle.main.bundleURL.path]
        do {
            try helper.run()
            let preferences = UserDefaults.standard
            preferences.set(model.weekStart,forKey:"restartVisibleDay")
            preferences.set(Double(calendar?.visibleRect.minY ?? (48+7*CalendarMath.hourHeight)),forKey:"restartScrollY")
            preferences.set(true,forKey:"restoreAfterRestart")
            NSApp.terminate(nil)
        } catch { model.message = "Couldn’t restart Sunshine Calendar. \(error.localizedDescription)" }
    }
}
