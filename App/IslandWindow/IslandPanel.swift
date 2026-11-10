import AppKit
import SwiftUI

/// Borderless, non-activating, fully transparent `NSPanel` that sits *above*
/// the menu bar so the island can hang from the top edge of the screen like a
/// hardware notch. The SwiftUI content draws the black notch shape itself;
/// everything else in the panel is transparent and click-through (the
/// controller toggles `ignoresMouseEvents` from the pointer position).
final class IslandPanel: NSPanel {
    init(contentView: NSView, frame: NSRect) {
        super.init(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        self.contentView = contentView

        isFloatingPanel = true
        // Above the main menu so the shape can cover the menu-bar centre.
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        acceptsMouseMovedEvents = true
        isMovable = false
        ignoresMouseEvents = true
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Hosting view that accepts the first click, so buttons inside the
/// non-key panel respond immediately instead of eating the first click.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
