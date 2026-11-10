import BuiltInProfiles
import SleepClock
import SwiftUI

@main
struct DynamicCaffeIslandApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @ObservedObject private var state = AppRuntime.shared.state

    var body: some Scene {
        MenuBarExtra {
            KeepAwakeMenu(state: state)
        } label: {
            MenuBarLabelHost(state: state)
        }
        .menuBarExtraStyle(.menu)
    }
}

/// Menu-bar label. Startup itself happens in `AppDelegate` via
/// `AppRuntime.ensureStarted()`; the `.task` here is an idempotent backstop.
struct MenuBarLabelHost: View {
    @ObservedObject var state: AppState

    var body: some View {
        menuBarLabel
            .task { await AppRuntime.shared.ensureStarted() }
    }

    @ViewBuilder
    private var menuBarLabel: some View {
        if case let .active(session) = state.caffeineState {
            HStack(spacing: 2) {
                Image(systemName: "cup.and.saucer.fill")
                if let r = session.remaining() {
                    Text(compact(r))
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                } else {
                    Text("∞")
                }
            }
        } else if case .expiring = state.caffeineState {
            Image(systemName: "cup.and.saucer.fill")
        } else if case .error = state.caffeineState {
            Image(systemName: "exclamationmark.triangle.fill")
        } else {
            sleepLabel
        }
    }

    @ViewBuilder
    private var sleepLabel: some View {
        switch state.sleepState {
        case .suppressed:
            Image(systemName: "cup.and.saucer")
        case let .idle(event):
            switch event {
            case let .displaySleep(r), let .screensaver(r), let .systemSleep(r):
                HStack(spacing: 2) {
                    Image(systemName: iconName(for: event))
                    Text(compact(r))
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                }
            case .none:
                Image(systemName: "moon.slash")
            case .suppressed:
                Image(systemName: "cup.and.saucer")
            }
        }
    }

    private func iconName(for event: SleepClock.NextEvent) -> String {
        switch event {
        case .displaySleep: return "display"
        case .screensaver: return "lock.display"
        case .systemSleep: return "moon.zzz.fill"
        case .none: return "moon.slash"
        case .suppressed: return "cup.and.saucer.fill"
        }
    }

    private func compact(_ remaining: TimeInterval) -> String {
        let total = Int(remaining.rounded())
        let m = total / 60
        let s = total % 60
        if m >= 60 { return "\(m / 60)h" }
        return String(format: "%d:%02d", m, s)
    }
}
