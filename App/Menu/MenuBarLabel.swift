import AppKit
import BuiltInProfiles
import Combine
import SleepClock
import SwiftUI

/// Menu bar item label, drawn as one template `NSImage` of a fixed size.
///
/// SwiftUI `MenuBarExtra` labels ignore `.frame(width:)`, so a plain
/// `Text` countdown resizes the item every time the digits change and
/// neighbouring icons shift. An image has the width we give it: the timer
/// slot is always as wide as the widest string it can show ("00:00",
/// "00h00"), digits are monospaced, and macOS tints the template for
/// light/dark/highlighted menu bars.
struct MenuBarLabelHost: View {
    @ObservedObject var state: AppState
    @ObservedObject var settings: AppSettings
    /// Only an invalidation signal: the label always reads the current time.
    @ObservedObject private var clock = MenuBarClock.shared

    var body: some View {
        let _ = clock.tick
        let content = MenuBarLabelContent.make(caffeine: state.caffeineState, sleep: state.sleepState, now: Date())
        Image(nsImage: MenuBarLabelRenderer.image(
            for: content,
            icon: settings.menuBarIcon,
            reserveTimer: settings.menuBarFixedWidth
        ))
        .accessibilityLabel(Text(content.accessibilityLabel))
        .task { await AppRuntime.shared.ensureStarted() }
    }
}

/// What the label shows, independent of how it is drawn.
struct MenuBarLabelContent: Equatable {
    enum Glyph: Equatable { case idle, active, error, sleepEvent(String) }

    var glyph: Glyph
    var text: String?
    var accessibilityLabel: String

    static func make(caffeine: CaffeineState, sleep: SleepCountdownState, now: Date) -> MenuBarLabelContent {
        switch caffeine {
        case let .active(session), let .expiring(session):
            guard let remaining = session.remaining(now: now) else {
                let label = session.watchedProcess.map { String(localized: "Caffeinated while \($0.name) runs") }
                    ?? String(localized: "Caffeinated indefinitely")
                return .init(glyph: .active, text: "∞", accessibilityLabel: label)
            }
            let spoken = CaffeinationSession.Duration.durationText(max(60, remaining))
            return .init(glyph: .active, text: compact(remaining),
                         accessibilityLabel: String(localized: "Caffeinated, \(spoken) remaining"))
        case .error:
            return .init(glyph: .error, text: nil, accessibilityLabel: String(localized: "Couldn’t keep the Mac awake"))
        case .inactive:
            break
        }
        if case let .idle(event) = sleep, let remaining = event.remaining {
            return .init(glyph: .sleepEvent(symbol(for: event)), text: compact(remaining),
                         accessibilityLabel: Format.eventPhrase(event, in: CaffeinationSession.Duration.durationText(max(60, remaining))))       // the sleep source publishes its own 1 Hz updates
        }
        return .init(glyph: .idle, text: nil, accessibilityLabel: String(localized: "Caffe Island"))
    }

    /// One stable format per range: `m:ss` under an hour, `h`h`mm` above.
    static func compact(_ remaining: TimeInterval) -> String {
        let total = max(0, Int(remaining.rounded()))
        if total >= 3600 { return String(format: "%dh%02d", total / 3600, (total % 3600) / 60) }
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private static func symbol(for event: SleepClock.NextEvent) -> String {
        switch event {
        case .displaySleep: return "display"
        case .screensaver: return "lock.display"
        case .systemSleep: return "moon.zzz.fill"
        case .none: return "moon.slash"
        case .suppressed: return "cup.and.saucer.fill"
        }
    }
}

/// Re-renders the label only while a caffeine countdown is visible: every
/// second under an hour, when the minute digit changes above. Idle and
/// open-ended sessions cost nothing. Follows the session on its own, so it
/// doesn't depend on the label view's lifecycle.
@MainActor
final class MenuBarClock: ObservableObject {
    static let shared = MenuBarClock()

    @Published private(set) var tick = 0
    private var work: DispatchWorkItem?
    private var session: CaffeinationSession?
    private var cancellable: AnyCancellable?

    private init() {
        cancellable = AppRuntime.shared.state.$caffeineState
            .map(\.session)
            .removeDuplicates { $0?.id == $1?.id }
            .sink { [weak self] in self?.follow($0) }
    }

    private func follow(_ session: CaffeinationSession?) {
        self.session = session
        schedule()
    }

    private func schedule() {
        work?.cancel()
        work = nil
        guard let remaining = session?.remaining(), remaining > 0 else { return }
        // Under an hour the seconds show; above, wake as the minute changes.
        let delay = remaining < 3600 ? 1 : max(1, remaining.truncatingRemainder(dividingBy: 60) + 0.05)
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.tick &+= 1
            self.schedule()
        }
        work = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }
}

enum MenuBarLabelRenderer {
    private static let height: CGFloat = 18
    private static let iconSize: CGFloat = 18
    private static let gap: CGFloat = 3
    private static let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
    /// Widest strings the timer can show; the slot never shrinks below them.
    private static let timerSlotWidth: CGFloat = ["00:00", "00h00", "∞"]
        .map { ceil(($0 as NSString).size(withAttributes: [.font: font]).width) }
        .max() ?? 36

    static func image(for content: MenuBarLabelContent, icon style: MenuBarIconStyle, reserveTimer: Bool) -> NSImage {
        let glyph = glyphImage(content.glyph, style: style, hasText: content.text != nil)
        let showSlot = content.text != nil || reserveTimer
        var width: CGFloat = glyph == nil ? 0 : iconSize
        if showSlot { width += (glyph == nil ? 0 : gap) + timerSlotWidth }
        width = max(width, iconSize)

        let image = NSImage(size: NSSize(width: width, height: height), flipped: false) { rect in
            var x: CGFloat = 0
            if let glyph {
                // Fit inside an iconSize square, keeping the aspect ratio.
                let aspect = glyph.size.height > 0 ? glyph.size.width / glyph.size.height : 1
                let w = aspect >= 1 ? iconSize : iconSize * aspect
                let h = w / aspect
                glyph.draw(in: NSRect(x: (iconSize - w) / 2, y: (rect.height - h) / 2, width: w, height: h))
                x = iconSize + gap
            }
            if let text = content.text {
                let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black]
                let size = (text as NSString).size(withAttributes: attrs)
                // Right-align so the digits that change sit at a fixed spot.
                let originX = glyph == nil ? (rect.width - size.width) / 2 : x + timerSlotWidth - size.width
                (text as NSString).draw(at: NSPoint(x: originX, y: (rect.height - size.height) / 2), withAttributes: attrs)
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    private static func glyphImage(_ glyph: MenuBarLabelContent.Glyph, style: MenuBarIconStyle, hasText: Bool) -> NSImage? {
        if case let .sleepEvent(symbol) = glyph {
            if style == .timerOnly && hasText { return nil }
            return NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: 13, weight: .medium))
        }
        switch style {
        case .timerOnly where hasText:
            return nil
        case .mug, .timerOnly:
            switch glyph {
            case .active: return NSImage(named: "MenuBarMugActive")
            case .error: return NSImage(named: "MenuBarMugError")
            default: return NSImage(named: "MenuBarMug")
            }
        case .classic:
            let name: String
            switch glyph {
            case .active: name = "cup.and.saucer.fill"
            case .error: name = "exclamationmark.triangle.fill"
            default: name = "cup.and.saucer"
            }
            return NSImage(systemSymbolName: name, accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: 13, weight: .medium))
        }
    }
}
