import AppKit
import BuiltInProfiles

/// The Dock icon's menu (right-click / long-press). Mirrors the menu bar
/// menu through `KeepAwakeCommands`; macOS appends its own Options, Show
/// All Windows, Hide and Quit items below.
@MainActor
enum DockMenu {
    static func make(runtime: AppRuntime = .shared) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        if runtime.state.caffeineState.isActive {
            menu.addItem(ActionItem(String(localized: "Stop")) { runtime.stop() })
            menu.addItem(.separator())
        }

        for preset in KeepAwakeCommands.presets {
            menu.addItem(ActionItem(String(localized: preset.title)) { runtime.start(minutes: preset.minutes) })
        }
        menu.addItem(.separator())

        menu.addItem(ActionItem(String(localized: "Until a specific time…")) { runtime.showUntilPicker() })
        menu.addItem(ActionItem(String(localized: "Indefinite")) { runtime.start(minutes: nil) })

        let apps = NSMenu()
        for app in KeepAwakeCommands.runningApps() {
            let pid = app.processIdentifier
            let item = ActionItem(app.localizedName ?? app.bundleIdentifier ?? "#\(pid)") {
                runtime.keepAwake(whileProcess: pid)
            }
            if let icon = app.icon?.copy() as? NSImage {
                icon.size = NSSize(width: 16, height: 16)
                item.image = icon
            }
            apps.addItem(item)
        }
        let whileApp = NSMenuItem(title: String(localized: "While an App Runs"), action: nil, keyEquivalent: "")
        whileApp.submenu = apps
        menu.addItem(whileApp)

        menu.addItem(.separator())
        menu.addItem(ActionItem(String(localized: "Settings…")) { runtime.showSettings() })
        return menu
    }
}

/// A menu item that runs a closure; it is its own target.
private final class ActionItem: NSMenuItem {
    private let handler: () -> Void

    init(_ title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    @objc private func run() { handler() }
}
