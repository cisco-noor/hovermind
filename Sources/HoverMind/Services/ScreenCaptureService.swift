import ScreenCaptureKit
import AppKit
import CoreGraphics

/// Captures screenshots of windows for visual context sent to the AI model.
final class ScreenCaptureService {

    /// Returns true if Screen Recording permission is granted.
    static var hasScreenRecordingPermission: Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// Triggers the macOS Screen Recording permission prompt.
    @discardableResult
    static func requestScreenRecordingPermission() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    /// Captures the window belonging to the given PID as PNG data.
    /// Returns nil if Screen Recording permission is not granted or capture fails.
    func captureWindow(pid: pid_t) async -> Data? {
        do {
            Log.info("captureWindow: requesting SCShareableContent for pid=\(pid)")
            let content = try await SCShareableContent.excludingDesktopWindows(
                false, onScreenWindowsOnly: true
            )
            Log.info("captureWindow: got \(content.windows.count) windows, \(content.displays.count) displays")

            // Find the frontmost window for this PID using CGWindowList z-order.
            // Falls back to the largest window if z-order lookup fails.
            var targetWindowID: CGWindowID?
            if let cgWindows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] {
                for w in cgWindows {
                    guard let ownerPID = w[kCGWindowOwnerPID as String] as? pid_t, ownerPID == pid,
                          let layer = w[kCGWindowLayer as String] as? Int, layer == 0,
                          let bounds = w[kCGWindowBounds as String] as? [String: Any],
                          let ww = bounds["Width"] as? CGFloat, let wh = bounds["Height"] as? CGFloat,
                          ww > 50, wh > 50
                    else { continue }
                    targetWindowID = w[kCGWindowNumber as String] as? CGWindowID
                    break // First match in z-order = frontmost
                }
            }

            let window: SCWindow
            if let wid = targetWindowID,
               let match = content.windows.first(where: { $0.windowID == wid }) {
                window = match
            } else {
                // Fallback: largest window for the PID
                guard let fallback = content.windows
                    .filter({ $0.owningApplication?.processID == pid && $0.isOnScreen })
                    .max(by: { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height })
                else { return nil }
                window = fallback
            }

            let filter = SCContentFilter(desktopIndependentWindow: window)
            let config = SCStreamConfiguration()

            // Capture at half resolution to keep payload small for the API
            let scale = 0.5
            config.width = Int(window.frame.width * scale)
            config.height = Int(window.frame.height * scale)
            config.showsCursor = false

            let image = try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: config
            )

            Log.info("captureWindow: success \(image.width)x\(image.height)")
            return pngData(from: image)
        } catch {
            Log.error("captureWindow failed: \(error)")
            return nil
        }
    }

    /// Captures a screen region by finding the frontmost window at the selection center
    /// and cropping to the selection bounds.
    /// `rect` uses CoreGraphics global coordinates (origin at top-left of primary display).
    func captureRegion(rect: CGRect) async -> Data? {
        Log.info("captureRegion: CG global rect=\(rect)")
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(
                false, onScreenWindowsOnly: true
            )

            // CGWindowListCopyWindowInfo returns windows in front-to-back z-order.
            // Find the frontmost normal app window whose frame contains the selection center.
            let center = CGPoint(x: rect.midX, y: rect.midY)
            var targetWindowID: CGWindowID?

            if let cgWindows = CGWindowListCopyWindowInfo(
                [.optionOnScreenOnly], kCGNullWindowID
            ) as? [[String: Any]] {
                for w in cgWindows {
                    let layer = w[kCGWindowLayer as String] as? Int ?? -1
                    guard layer == 0 else { continue }
                    guard let bounds = w[kCGWindowBounds as String] as? [String: Any],
                          let wx = bounds["X"] as? CGFloat, let wy = bounds["Y"] as? CGFloat,
                          let ww = bounds["Width"] as? CGFloat, let wh = bounds["Height"] as? CGFloat,
                          ww > 50, wh > 50
                    else { continue }
                    if CGRect(x: wx, y: wy, width: ww, height: wh).contains(center) {
                        targetWindowID = w[kCGWindowNumber as String] as? CGWindowID
                        let owner = w[kCGWindowOwnerName as String] as? String ?? "?"
                        let name = w[kCGWindowName as String] as? String ?? ""
                        Log.info("captureRegion: frontmost at center: '\(owner) - \(name)' id=\(targetWindowID ?? 0)")
                        break
                    }
                }
            }

            // Match CGWindowID to SCWindow
            let window: SCWindow
            if let wid = targetWindowID,
               let match = content.windows.first(where: { $0.windowID == wid }) {
                window = match
            } else {
                // Fallback: first overlapping app window from SCShareableContent
                guard let fallback = content.windows.first(where: {
                    $0.isOnScreen && $0.frame.intersects(rect) &&
                    $0.windowLayer == 0 && $0.owningApplication != nil
                }) else {
                    Log.error("captureRegion: no window found at \(center)")
                    return nil
                }
                window = fallback
            }

            Log.info("captureRegion: capturing window frame=\(window.frame)")

            let filter = SCContentFilter(desktopIndependentWindow: window)
            let config = SCStreamConfiguration()
            // Don't set width/height — let SCK capture at native resolution (2x on Retina)
            config.showsCursor = false

            let image = try await SCScreenshotManager.captureImage(
                contentFilter: filter, configuration: config
            )

            // Crop to the selection rect relative to the window.
            // Compute scale from actual image pixels vs logical window points
            // to handle Retina (2x) displays correctly.
            let scaleX = CGFloat(image.width) / window.frame.width
            let scaleY = CGFloat(image.height) / window.frame.height
            let cropX = max(0, rect.origin.x - window.frame.origin.x) * scaleX
            let cropY = max(0, rect.origin.y - window.frame.origin.y) * scaleY
            let cropW = min(rect.width * scaleX, CGFloat(image.width) - cropX)
            let cropH = min(rect.height * scaleY, CGFloat(image.height) - cropY)
            let pixelCrop = CGRect(x: cropX, y: cropY, width: cropW, height: cropH)

            let final = image.cropping(to: pixelCrop) ?? image
            Log.info("captureRegion: result \(final.width)x\(final.height)")
            return pngData(from: final)
        } catch {
            Log.error("Region capture failed: \(error)")
            return nil
        }
    }

    private func pngData(from cgImage: CGImage) -> Data? {
        let rep = NSBitmapImageRep(cgImage: cgImage)
        return rep.representation(using: .png, properties: [.compressionFactor: 0.8])
    }
}
