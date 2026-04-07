import AppKit
import SwiftUI

final class TooltipPanel: NSPanel {
    let viewModel = TooltipViewModel()
    private var pinnedTopLeft: NSPoint = .zero

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 60),
            styleMask: [.nonactivatingPanel],
            backing: .buffered,
            defer: true
        )

        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = true
        level = NSWindow.Level(rawValue: 201) // Above native tooltips (level 200)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]

        contentView = NSHostingView(rootView: TooltipView(viewModel: viewModel))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Intercepts all content size changes to enforce pinned position.
    override func setContentSize(_ size: NSSize) {
        if pinnedTopLeft != .zero {
            super.setFrame(NSRect(
                x: pinnedTopLeft.x,
                y: pinnedTopLeft.y - size.height,
                width: size.width,
                height: size.height
            ), display: true)
        } else {
            super.setContentSize(size)
        }
    }

    func show(near screenPoint: NSPoint) {
        let screen = NSScreen.screens.first { NSMouseInRect(screenPoint, $0.frame, false) }
            ?? NSScreen.main
        guard let screen else { return }

        // Set initial size large enough for streaming content.
        // No resizing happens during streaming - text fills this space.
        let initialSize = NSSize(width: 400, height: 300)
        setContentSize(initialSize)

        let visible = screen.visibleFrame
        var topLeft = NSPoint(x: screenPoint.x + 16, y: screenPoint.y - 8)

        // Flip left if too far right
        if topLeft.x + initialSize.width > visible.maxX {
            topLeft.x = screenPoint.x - initialSize.width - 8
        }
        // Flip above cursor if too close to bottom.
        // Use a conservative content height estimate since the window is 300px
        // but content starts at the top (topLeading alignment).
        if topLeft.y - initialSize.height < visible.minY {
            topLeft.y = screenPoint.y + initialSize.height + 8
        }
        // Clamp to screen top
        if topLeft.y > visible.maxY {
            topLeft.y = visible.maxY
        }

        setFrameTopLeftPoint(topLeft)
        pinnedTopLeft = topLeft

        if !isVisible {
            alphaValue = 0
            orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.12
                animator().alphaValue = 1
            }
        } else {
            orderFrontRegardless()
        }
    }

    func hide() {
        guard isVisible else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.08
            animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.orderOut(nil)
        })
        viewModel.text = ""
        viewModel.isStreaming = false
        viewModel.appName = ""
        viewModel.elementRole = ""
        pinnedTopLeft = .zero
    }

    func updateContent(text: String, isStreaming: Bool, appName: String = "", elementRole: String = "", modelLabel: String = "") {
        viewModel.text = text
        viewModel.isStreaming = isStreaming
        if !appName.isEmpty { viewModel.appName = appName }
        if !elementRole.isEmpty { viewModel.elementRole = elementRole }
        viewModel.modelLabel = modelLabel

        if !isStreaming {
            // Streaming complete: resize to fit the final content
            contentView?.layoutSubtreeIfNeeded()
            let fitting = contentView?.fittingSize ?? frame.size
            setContentSize(NSSize(
                width: min(max(fitting.width, 200), 400),
                height: min(max(fitting.height, 40), 500)
            ))
        }
        // During streaming: no resize. Text fills the 400x300 space.
    }
}
