import AppKit
import BuiltInProfiles
import SwiftUI

/// FR-002 preset durations + "Until a specific time" + Indefinite +
/// "While an app runs" + Deactivate, then Settings and Quit.
struct KeepAwakeMenu: View {
    @ObservedObject var state: AppState
    @ObservedObject var login = LaunchAtLogin.shared

    var body: some View {
        Group {
            if state.caffeineState.isActive {
                Button("Stop") {
                    state.cancelCaffeine()
                }
                .keyboardShortcut("d", modifiers: [.command])
                Divider()
            }

            ForEach(KeepAwakeCommands.presets, id: \.minutes) { preset in
                Button(String(localized: preset.title)) {
                    state.startCaffeine(duration: .preset(TimeInterval(preset.minutes * 60)))
                }
                .keyboardShortcut(preset.key, modifiers: [.command])
            }

            Divider()

            Button("Until a specific time…") {
                AppRuntime.shared.showUntilPicker()
            }

            Button("Indefinite") {
                state.startCaffeine(duration: .indefinite)
            }

            Menu("While an App Runs") {
                ForEach(Self.runningApps(), id: \.processIdentifier) { app in
                    Button {
                        AppRuntime.shared.keepAwake(whileProcess: app.processIdentifier)
                    } label: {
                        Text(verbatim: app.localizedName ?? app.bundleIdentifier ?? "#\(app.processIdentifier)")
                    }
                }
            }

            Divider()

            Toggle("Open at Login", isOn: Binding(
                get: { login.isEnabled || login.requiresApproval },
                set: { login.setEnabled($0) }
            ))
            Button("Settings…") {
                AppRuntime.shared.showSettings()
            }
            .keyboardShortcut(",", modifiers: [.command])

            Divider()

            Button("Quit Caffe Island") {
                AppRuntime.shared.quit()
            }
            .keyboardShortcut("q")
        }
    }

    static func runningApps() -> [NSRunningApplication] { KeepAwakeCommands.runningApps() }
}

/// What the menu bar menu and the Dock menu both offer, defined once.
enum KeepAwakeCommands {
    struct Preset {
        let minutes: Int
        let title: LocalizedStringResource
        let key: KeyEquivalent
    }

    static let presets: [Preset] = [
        Preset(minutes: 5, title: "5 minutes", key: "1"),
        Preset(minutes: 15, title: "15 minutes", key: "2"),
        Preset(minutes: 30, title: "30 minutes", key: "3"),
        Preset(minutes: 60, title: "1 hour", key: "4"),
        Preset(minutes: 120, title: "2 hours", key: "5"),
        Preset(minutes: 300, title: "5 hours", key: "6"),
    ]

    /// Regular (Dock) apps, alphabetically, excluding this one.
    static func runningApps() -> [NSRunningApplication] {
        let me = ProcessInfo.processInfo.processIdentifier
        return NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.processIdentifier != me && !$0.isTerminated }
            .sorted { ($0.localizedName ?? "").localizedStandardCompare($1.localizedName ?? "") == .orderedAscending }
    }
}
