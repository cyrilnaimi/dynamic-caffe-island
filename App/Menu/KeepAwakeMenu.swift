import AppKit
import BuiltInProfiles
import SwiftUI

/// FR-002 preset durations + "Until a specific time" + Indefinite + Deactivate.
struct KeepAwakeMenu: View {
    @ObservedObject var state: AppState

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

            Divider()

            Button("Quit Dynamic Caffe Island") {
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q")
        }
    }
}
