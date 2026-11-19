import AppKit
import SwiftUI

/// Owns the Settings window. AppKit-managed, like the Until window, so
/// every entry point (menu, ⌘,, `caffe://settings`, re-opening the app)
/// can open it and an `LSUIElement` app can bring it to front.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let settings: AppSettings
    private var window: NSWindow?

    init(settings: AppSettings) {
        self.settings = settings
    }

    func show() {
        LaunchAtLogin.shared.refresh()
        if let window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }
        let hosting = NSHostingController(rootView: SettingsView(settings: settings, login: .shared))
        hosting.sizingOptions = [.preferredContentSize]        // window follows each tab's size
        let w = NSWindow(contentViewController: hosting)
        w.title = String(localized: "Caffe Island Settings")
        w.styleMask = [.titled, .closable, .miniaturizable]
        w.isReleasedWhenClosed = false
        w.delegate = self
        w.center()
        window = w
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
        // No focus ring on a control when the window opens.
        w.makeFirstResponder(nil)
    }

    /// Re-fronts the window if it is open (after an activation policy change).
    func bringToFrontIfOpen() {
        guard let window, window.isVisible else { return }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) { window = nil }
}

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var login: LaunchAtLogin
    /// Re-opens on the tab used last.
    @AppStorage("settingsTab") private var tab = Tab.general

    enum Tab: String, Hashable { case general, island, menuBar, battery }

    var body: some View {
        TabView(selection: $tab) {
            GeneralTab(settings: settings, login: login)
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(Tab.general)
            IslandTab(settings: settings)
                .tabItem { Label("Island", systemImage: "capsule.portrait") }
                .tag(Tab.island)
            MenuBarTab(settings: settings)
                .tabItem { Label("Menu Bar", systemImage: "menubar.rectangle") }
                .tag(Tab.menuBar)
            BatteryTab(settings: settings)
                .tabItem { Label("Battery", systemImage: "battery.75") }
                .tag(Tab.battery)
        }
        .padding(.top, 8)
        .frame(width: 500)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// A grouped form sized to its content (no empty space, no scrolling).
private struct SettingsForm<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        Form { content }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Section footer, leading-aligned like System Settings.
private struct Footer: View {
    let text: Text
    init(_ key: LocalizedStringKey) { text = Text(key) }

    var body: some View {
        text.multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct GeneralTab: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var login: LaunchAtLogin

    var body: some View {
        SettingsForm {
            Section {
                Toggle("Open at login", isOn: Binding(
                    get: { login.isEnabled || login.requiresApproval },
                    set: { login.setEnabled($0) }
                ))
                if login.requiresApproval {
                    HStack {
                        Text("Allow Caffe Island in System Settings › Login Items.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Open Login Items…") { login.openLoginItemsSettings() }
                    }
                }
                if let error = login.lastError {
                    Text(verbatim: error)
                        .font(.callout)
                        .foregroundStyle(.red)
                }
            } footer: {
                Footer("Opening at login never keeps the Mac awake by itself.")
            }
            Section {
                Picker("Show Caffe Island in", selection: $settings.presence) {
                    Text("Menu bar").tag(AppPresence.menuBar)
                    Text("Dock").tag(AppPresence.dock)
                    Text("Menu bar and Dock").tag(AppPresence.both)
                    Text("Island only").tag(AppPresence.islandOnly)
                }
                Toggle("Show time remaining on the Dock icon", isOn: $settings.dockBadge)
                    .disabled(!settings.showInDock)
                if settings.presence == .islandOnly {
                    ComeBackHint(settings: settings)
                }
            } footer: {
                Footer("In the Dock, click the icon to open Settings, or right-click it to keep your Mac awake.")
            }
            Section {
                Picker("Default duration", selection: $settings.defaultMinutes) {
                    ForEach(AppSettings.durationChoices, id: \.self) { minutes in
                        Text(verbatim: CaffeinationDurationLabel.text(minutes)).tag(minutes)
                    }
                }
                Toggle("Toggle with ⌃⌥C", isOn: $settings.hotKeyEnabled)
            } footer: {
                Footer("Used by the keyboard shortcut and `caffe toggle`.")
            }
        }
    }
}

private struct IslandTab: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        SettingsForm {
            Section {
                Picker("Style", selection: $settings.islandStyle) {
                    Text("Automatic").tag(IslandStyle.automatic)
                    Text("Notch").tag(IslandStyle.notch)
                    Text("Floating pill").tag(IslandStyle.pill)
                }
                Toggle("Hide when idle", isOn: $settings.hideIslandWhenIdle)
            } footer: {
                Footer("Automatic uses the notch on displays that have one and a floating pill below the menu bar elsewhere. When hidden, point at the top centre of the screen to open it.")
            }
            Section {
                Picker("Show on", selection: $settings.islandScreen) {
                    Text("Main display").tag(IslandScreenChoice.main)
                    Text("Display with the pointer").tag(IslandScreenChoice.active)
                    Text("All displays").tag(IslandScreenChoice.all)
                }
                Picker("Over full-screen apps", selection: $settings.fullScreenBehavior) {
                    Text("Hide").tag(FullScreenBehavior.hide)
                    Text("Show alerts only").tag(FullScreenBehavior.alertsOnly)
                    Text("Show").tag(FullScreenBehavior.show)
                }
            }
        }
    }
}

private struct MenuBarTab: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        SettingsForm {
            Section {
                Toggle("Show in menu bar", isOn: $settings.showMenuBarItem)
                if !settings.showMenuBarItem && !settings.showInDock {
                    ComeBackHint(settings: settings)
                }
            }
            Section {
                Picker("Icon", selection: $settings.menuBarIcon) {
                    Text("Mug").tag(MenuBarIconStyle.mug)
                    Text("Classic cup").tag(MenuBarIconStyle.classic)
                    Text("Timer only").tag(MenuBarIconStyle.timerOnly)
                }
                Toggle("Keep a fixed width", isOn: $settings.menuBarFixedWidth)
            } footer: {
                Footer("Reserves room for the timer so icons next to it never move.")
            }
            .disabled(!settings.showMenuBarItem)
        }
    }
}

/// How to reach Settings again once neither the menu bar item nor the Dock
/// icon is shown.
private struct ComeBackHint: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Label {
            Text(settings.hideIslandWhenIdle
                 ? "The menu bar item and the idle island are both hidden. To come back here, open Caffe Island again from Spotlight or Finder, or run `caffe settings`."
                 : "To come back here, open Caffe Island again from Spotlight or Finder, or run `caffe settings`.")
        } icon: {
            Image(systemName: "info.circle")
        }
        .font(.callout)
        .foregroundStyle(.secondary)
    }
}

private struct BatteryTab: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        SettingsForm {
            Section {
                Picker("Stop when battery is below", selection: $settings.batteryThreshold) {
                    Text("Never").tag(0)
                    ForEach(AppSettings.batteryThresholdChoices.filter { $0 > 0 }, id: \.self) { percent in
                        Text(verbatim: percent.formatted(.percent.scale(1))).tag(percent)
                    }
                }
                Toggle("Only keep awake on power adapter", isOn: $settings.onlyOnPowerAdapter)
            } footer: {
                Footer("Has no effect on Macs without a battery.")
            }
        }
    }
}

enum CaffeinationDurationLabel {
    static func text(_ minutes: Int) -> String {
        let f = DateComponentsFormatter()
        f.allowedUnits = minutes >= 60 ? [.hour, .minute] : [.minute]
        f.unitsStyle = .full
        f.zeroFormattingBehavior = .dropAll
        return f.string(from: TimeInterval(minutes * 60)) ?? "\(minutes)"
    }
}
