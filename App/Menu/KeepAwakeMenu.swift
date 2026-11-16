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

            Button("5 minutes")  { state.startCaffeine(duration: .preset(5 * 60)) }
                .keyboardShortcut("1", modifiers: [.command])
            Button("15 minutes") { state.startCaffeine(duration: .preset(15 * 60)) }
                .keyboardShortcut("2", modifiers: [.command])
            Button("30 minutes") { state.startCaffeine(duration: .preset(30 * 60)) }
                .keyboardShortcut("3", modifiers: [.command])
            Button("1 hour")     { state.startCaffeine(duration: .preset(60 * 60)) }
                .keyboardShortcut("4", modifiers: [.command])
            Button("2 hours")    { state.startCaffeine(duration: .preset(2 * 60 * 60)) }
                .keyboardShortcut("5", modifiers: [.command])
            Button("5 hours")    { state.startCaffeine(duration: .preset(5 * 60 * 60)) }
                .keyboardShortcut("6", modifiers: [.command])

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
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q")
        }
    }

    /// Regular (Dock) apps, alphabetically, excluding this one.
    static func runningApps() -> [NSRunningApplication] {
        let me = ProcessInfo.processInfo.processIdentifier
        return NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.processIdentifier != me && !$0.isTerminated }
            .sorted { ($0.localizedName ?? "").localizedStandardCompare($1.localizedName ?? "") == .orderedAscending }
    }
}
