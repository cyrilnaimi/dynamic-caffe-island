import AppKit
import CoreGraphics

/// Tells whether another app is full screen on a given display.
///
/// Uses only window *bounds* from `CGWindowListCopyWindowInfo` (no Screen
/// Recording permission needed). Called on events — space change, app
/// activation, display change — never on a timer.
enum FullScreenDetector {
    static func isFullScreenAppFront(on screen: NSScreen) -> Bool {
        guard let primary = NSScreen.screens.first,
              let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else { return false }

        // Screen rect in CG global coordinates (origin top-left of the primary display).
        let f = screen.frame
        let screenRect = CGRect(x: f.minX, y: primary.frame.maxY - f.maxY, width: f.width, height: f.height)
        let topInset = screen.safeAreaInsets.top      // notched displays: full-screen windows sit below the notch
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let menuLevel = Int(CGWindowLevelForKey(.mainMenuWindow))

        var covered = false
        var coveredBelowNotchOnly = false
        var menuBarVisible = false
        for w in list {
            guard let pid = w[kCGWindowOwnerPID as String] as? pid_t, pid != ownPID,
                  let layer = w[kCGWindowLayer as String] as? Int,
                  let dict = w[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: dict),
                  bounds.intersects(screenRect)
            else { continue }
            if layer == menuLevel, bounds.minY <= screenRect.minY + 1 { menuBarVisible = true }
            guard layer == 0, (w[kCGWindowAlpha as String] as? Double ?? 1) > 0 else { continue }
            let spansWidth = bounds.minX <= screenRect.minX + 1 && bounds.maxX >= screenRect.maxX - 1
            let reachesBottom = bounds.maxY >= screenRect.maxY - 1
            guard spansWidth, reachesBottom else { continue }
            if bounds.minY <= screenRect.minY + 1 {
                covered = true
            } else if topInset > 0, bounds.minY <= screenRect.minY + topInset + 1 {
                coveredBelowNotchOnly = true
            }
        }
        // Below the notch, a zoomed window looks the same as a full-screen
        // one; the hidden menu bar tells them apart.
        return covered || (coveredBelowNotchOnly && !menuBarVisible)
    }
}
