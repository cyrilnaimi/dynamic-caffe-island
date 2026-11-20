import Combine
import Foundation
import PowerAssertions

/// Shape of the island.
enum IslandStyle: String, CaseIterable, Identifiable {
    /// Notch on displays that have one, floating pill elsewhere.
    case automatic
    /// Hangs from the top edge like a hardware notch.
    case notch
    /// Rounded capsule below the menu bar; never covers menu items.
    case pill

    var id: String { rawValue }
}

/// Which display(s) show the island.
enum IslandScreenChoice: String, CaseIterable, Identifiable {
    /// The display with the menu bar (`NSScreen.screens.first`).
    case main
    /// The display with the pointer or the active window.
    case active
    /// One island per display.
    case all

    var id: String { rawValue }
}

/// What the island does while a full-screen app is in front.
enum FullScreenBehavior: String, CaseIterable, Identifiable {
    case hide
    /// Hidden, except for toasts and the last seconds of a session.
    case alertsOnly
    case show

    var id: String { rawValue }
}

/// Menu bar glyph.
enum MenuBarIconStyle: String, CaseIterable, Identifiable {
    case mug
    case classic
    /// Just the countdown; the mug shows only when there is no countdown.
    case timerOnly

    var id: String { rawValue }
}

/// Where the app shows up besides the island. Two independent switches
/// (`showMenuBarItem`, `showInDock`) presented as one choice.
enum AppPresence: String, CaseIterable, Identifiable {
    case menuBar
    case dock
    case both
    /// Island, Spotlight, ⌃⌥C, `caffe://` and the CLI only.
    case islandOnly

    var id: String { rawValue }

    init(menuBar: Bool, dock: Bool) {
        switch (menuBar, dock) {
        case (true, false): self = .menuBar
        case (false, true): self = .dock
        case (true, true): self = .both
        case (false, false): self = .islandOnly
        }
    }

    var showsMenuBar: Bool { self == .menuBar || self == .both }
    var showsDock: Bool { self == .dock || self == .both }
}

/// User preferences, persisted in `UserDefaults`. Every change applies
/// immediately: observers subscribe to the `@Published` properties.
@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    static let durationChoices = [15, 30, 60, 120]
    static let batteryThresholdChoices = [0, 10, 20, 30]

    private let defaults: UserDefaults

    @Published var islandStyle: IslandStyle { didSet { save(islandStyle.rawValue, Key.islandStyle) } }
    @Published var hideIslandWhenIdle: Bool { didSet { save(hideIslandWhenIdle, Key.hideIslandWhenIdle) } }
    @Published var islandScreen: IslandScreenChoice { didSet { save(islandScreen.rawValue, Key.islandScreen) } }
    @Published var fullScreenBehavior: FullScreenBehavior { didSet { save(fullScreenBehavior.rawValue, Key.fullScreenBehavior) } }
    @Published var showMenuBarItem: Bool { didSet { save(showMenuBarItem, Key.showMenuBarItem) } }
    /// Dock icon, ⌘⇥ and a main menu (activation policy `.regular`).
    @Published var showInDock: Bool { didSet { save(showInDock, Key.showInDock) } }
    /// Remaining time on the Dock icon while a session runs.
    @Published var dockBadge: Bool { didSet { save(dockBadge, Key.dockBadge) } }
    @Published var menuBarIcon: MenuBarIconStyle { didSet { save(menuBarIcon.rawValue, Key.menuBarIcon) } }
    /// Reserve the timer's width even when idle, so the item never resizes.
    @Published var menuBarFixedWidth: Bool { didSet { save(menuBarFixedWidth, Key.menuBarFixedWidth) } }
    /// Duration used by the ⌃⌥C hotkey and `caffe toggle`.
    @Published var defaultMinutes: Int { didSet { save(defaultMinutes, Key.defaultMinutes) } }
    @Published var hotKeyEnabled: Bool { didSet { save(hotKeyEnabled, Key.hotKeyEnabled) } }
    /// Stop at or below this battery level. 0 = off.
    @Published var batteryThreshold: Int { didSet { save(batteryThreshold, Key.batteryThreshold) } }
    @Published var onlyOnPowerAdapter: Bool { didSet { save(onlyOnPowerAdapter, Key.onlyOnPowerAdapter) } }

    private enum Key {
        static let islandStyle = "islandStyle"
        static let hideIslandWhenIdle = "hideIslandWhenIdle"
        static let islandScreen = "islandScreen"
        static let fullScreenBehavior = "fullScreenBehavior"
        static let showMenuBarItem = "showMenuBarItem"
        static let showInDock = "showInDock"
        static let dockBadge = "dockBadge"
        static let menuBarIcon = "menuBarIcon"
        static let menuBarFixedWidth = "menuBarFixedWidth"
        static let defaultMinutes = "defaultMinutes"
        static let hotKeyEnabled = "hotKeyEnabled"
        static let batteryThreshold = "batteryThreshold"
        static let onlyOnPowerAdapter = "onlyOnPowerAdapter"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        func string<T: RawRepresentable>(_ key: String, _ fallback: T) -> T where T.RawValue == String {
            defaults.string(forKey: key).flatMap(T.init(rawValue:)) ?? fallback
        }
        func bool(_ key: String, _ fallback: Bool) -> Bool {
            defaults.object(forKey: key) == nil ? fallback : defaults.bool(forKey: key)
        }
        func int(_ key: String, _ fallback: Int, in allowed: [Int]) -> Int {
            let v = defaults.object(forKey: key) == nil ? fallback : defaults.integer(forKey: key)
            return allowed.contains(v) ? v : fallback
        }
        islandStyle = string(Key.islandStyle, IslandStyle.notch)
        hideIslandWhenIdle = bool(Key.hideIslandWhenIdle, false)
        islandScreen = string(Key.islandScreen, IslandScreenChoice.main)
        fullScreenBehavior = string(Key.fullScreenBehavior, FullScreenBehavior.hide)
        showMenuBarItem = bool(Key.showMenuBarItem, true)
        showInDock = bool(Key.showInDock, false)
        dockBadge = bool(Key.dockBadge, true)
        menuBarIcon = string(Key.menuBarIcon, MenuBarIconStyle.mug)
        menuBarFixedWidth = bool(Key.menuBarFixedWidth, false)
        defaultMinutes = int(Key.defaultMinutes, 30, in: Self.durationChoices)
        hotKeyEnabled = bool(Key.hotKeyEnabled, true)
        batteryThreshold = int(Key.batteryThreshold, 0, in: Self.batteryThresholdChoices)
        onlyOnPowerAdapter = bool(Key.onlyOnPowerAdapter, false)
    }

    /// Read before `AppSettings` exists, so a Dock-only launch never waits
    /// for the main actor (and a menu-bar-only one never flashes a Dock icon).
    nonisolated static func launchShowsDock(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: Key.showInDock)
    }

    var presence: AppPresence {
        get { AppPresence(menuBar: showMenuBarItem, dock: showInDock) }
        set {
            if showMenuBarItem != newValue.showsMenuBar { showMenuBarItem = newValue.showsMenuBar }
            if showInDock != newValue.showsDock { showInDock = newValue.showsDock }
        }
    }

    var batteryGuard: BatteryGuard {
        BatteryGuard(threshold: batteryThreshold, onlyOnPowerAdapter: onlyOnPowerAdapter)
    }

    private func save(_ value: Any, _ key: String) {
        defaults.set(value, forKey: key)
    }
}
