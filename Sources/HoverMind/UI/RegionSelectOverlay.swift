import AppKit

/// Full-screen transparent overlay for region selection.
/// Click once to set the start corner, move the mouse to see the selection,
/// click again to set the end corner. Escape cancels.
final class RegionSelectOverlay {

    var onRegionSelected: ((CGRect) -> Void)?

    private var overlayWindow: NSWindow?
    private var overlayView: SelectionView?
    private var clickMonitor: Any?
    private var moveMonitor: Any?
    private var keyMonitor: Any?
    private var startPoint: NSPoint = .zero
    private var hasStartPoint = false

    deinit {
        removeMonitors()
    }

    func show() {
        let view = SelectionView()
        self.overlayView = view

        // Union of all screens so the overlay covers the entire multi-display workspace
        let screenFrame = NSScreen.screens.reduce(NSRect.zero) { $0.union($1.frame) }
        let window = NSWindow(
            contentRect: screenFrame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.level = .statusBar + 1
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.contentView = view
        window.orderFrontRegardless()
        self.overlayWindow = window

        hasStartPoint = false
        startPoint = .zero
        NSCursor.crosshair.push()
        installMonitors()
        Log.info("Region select overlay shown (click-click mode)")
    }

    func dismiss() {
        removeMonitors()
        NSCursor.pop()
        overlayWindow?.orderOut(nil)
        overlayWindow = nil
        overlayView = nil
        hasStartPoint = false
        Log.info("Region select overlay dismissed")
    }

    private func installMonitors() {
        clickMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            self?.handleClick()
            return nil // Consume the click so it doesn't propagate
        }
        moveMonitor = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
            self?.handleMouseMove()
            return event
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { self?.dismiss() }
            return nil
        }
    }

    private func removeMonitors() {
        [clickMonitor, moveMonitor, keyMonitor].compactMap { $0 }.forEach(NSEvent.removeMonitor)
        clickMonitor = nil
        moveMonitor = nil
        keyMonitor = nil
    }

    private func handleClick() {
        let point = NSEvent.mouseLocation

        if !hasStartPoint {
            // First click: set start corner
            startPoint = point
            hasStartPoint = true
            overlayView?.selectionRect = .zero
        } else {
            // Second click: finalize selection
            let endPoint = point
            let screenRect = NSRect(
                x: min(startPoint.x, endPoint.x),
                y: min(startPoint.y, endPoint.y),
                width: abs(endPoint.x - startPoint.x),
                height: abs(endPoint.y - startPoint.y)
            )

            dismiss()

            guard screenRect.width > 10 && screenRect.height > 10 else { return }

            guard let primaryHeight = NSScreen.screens.first?.frame.height else { return }
            let cgRect = CGRect(
                x: screenRect.origin.x,
                y: primaryHeight - screenRect.origin.y - screenRect.height,
                width: screenRect.width,
                height: screenRect.height
            )

            Log.info("Region select: screen=\(screenRect) -> cg=\(cgRect)")
            onRegionSelected?(cgRect)
        }
    }

    private func handleMouseMove() {
        guard hasStartPoint, let window = overlayWindow else { return }
        let current = NSEvent.mouseLocation

        let startInWindow = window.convertPoint(fromScreen: startPoint)
        let currentInWindow = window.convertPoint(fromScreen: current)

        overlayView?.selectionRect = NSRect(
            x: min(startInWindow.x, currentInWindow.x),
            y: min(startInWindow.y, currentInWindow.y),
            width: abs(currentInWindow.x - startInWindow.x),
            height: abs(currentInWindow.y - startInWindow.y)
        )
    }
}

// MARK: - Selection drawing view

private final class SelectionView: NSView {
    var selectionRect: NSRect = .zero {
        didSet { needsDisplay = true }
    }

    override var acceptsFirstResponder: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        ctx.setFillColor(NSColor(white: 0, alpha: 0.3).cgColor)
        ctx.fill(bounds)

        guard selectionRect.width > 0, selectionRect.height > 0 else { return }

        ctx.setBlendMode(.clear)
        ctx.fill(selectionRect)

        ctx.setBlendMode(.normal)
        ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.9).cgColor)
        ctx.setLineWidth(1.5)
        ctx.stroke(selectionRect.insetBy(dx: -1, dy: -1))
    }
}
