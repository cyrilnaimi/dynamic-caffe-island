import SwiftUI

@main
struct DynamicCaffeIslandApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @ObservedObject private var state = AppRuntime.shared.state
    @ObservedObject private var settings = AppSettings.shared

    var body: some Scene {
        // Hidden from the menu bar via Settings › Menu Bar; the app stays
        // reachable from the island, Spotlight, ⌃⌥C, `caffe://` and the CLI,
        // and opening it again shows Settings.
        MenuBarExtra(isInserted: menuBarItemInserted) {
            KeepAwakeMenu(state: state)
        } label: {
            MenuBarLabelHost(state: state, settings: settings)
        }
        .menuBarExtraStyle(.menu)
        // The main menu only shows in Dock mode (activation policy .regular).
        // There is no Settings scene (Settings is an AppKit window), so wire
        // App › Settings… ⌘, by hand; About, Hide and Quit ⌘Q come for free.
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { AppRuntime.shared.showSettings() }
                    .keyboardShortcut(",", modifiers: [.command])
            }
            CommandGroup(replacing: .appTermination) {
                Button("Quit Caffe Island") { AppRuntime.shared.quit() }
                    .keyboardShortcut("q", modifiers: [.command])
            }
        }
    }

    /// `MenuBarExtra` writes its binding on every scene update; publishing
    /// an unchanged value would re-render the scene and loop forever.
    private var menuBarItemInserted: Binding<Bool> {
        Binding(
            get: { settings.showMenuBarItem },
            set: { if settings.showMenuBarItem != $0 { settings.showMenuBarItem = $0 } }
        )
    }
}
