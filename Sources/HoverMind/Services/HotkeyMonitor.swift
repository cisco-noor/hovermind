import AppKit

/// Monitors global keyboard and mouse events for the Option-key + hover gesture
/// and the Cmd+Option snipping tool trigger.
final class HotkeyMonitor {
    var onHotkeyStateChanged: ((Bool) -> Void)?
    var onMouseMoved: ((NSPoint) -> Void)?
    var onRegionSelectTriggered: (() -> Void)?

    private var flagsMonitor: Any?
    private var mouseMonitor: Any?
    private var isOptionHeld = false
    private var regionSelectFired = false

    func start() {
        flagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            guard let self else { return }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let optionHeld = flags.contains(.option)
            let cmdHeld = flags.contains(.command)

            if optionHeld && cmdHeld {
                Log.info("Hotkey: Cmd+Option detected, regionSelectFired=\(self.regionSelectFired), isOptionHeld=\(self.isOptionHeld)")
                if !self.regionSelectFired {
                    self.regionSelectFired = true
                    if self.isOptionHeld {
                        self.isOptionHeld = false
                        self.onHotkeyStateChanged?(false)
                    }
                    Log.info("Hotkey: firing onRegionSelectTriggered")
                    self.onRegionSelectTriggered?()
                }
            } else if optionHeld && !cmdHeld {
                self.regionSelectFired = false
                guard !self.isOptionHeld else { return }
                self.isOptionHeld = true
                self.onHotkeyStateChanged?(true)
            } else {
                self.regionSelectFired = false
                guard self.isOptionHeld else { return }
                self.isOptionHeld = false
                self.onHotkeyStateChanged?(false)
            }
        }

        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
            guard let self, self.isOptionHeld else { return }
            self.onMouseMoved?(NSEvent.mouseLocation)
        }
    }

    func stop() {
        [flagsMonitor, mouseMonitor].compactMap { $0 }.forEach(NSEvent.removeMonitor)
        flagsMonitor = nil
        mouseMonitor = nil
        isOptionHeld = false
        regionSelectFired = false
    }

    deinit {
        stop()
    }
}
