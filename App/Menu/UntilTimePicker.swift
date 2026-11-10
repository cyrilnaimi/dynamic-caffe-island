import AppKit
import BuiltInProfiles
import SwiftUI

/// Owns the "Keep awake until…" window. AppKit-managed (not a SwiftUI
/// `Window` scene) so every entry point — menu, island chip, `caffe://pick`,
/// Spotlight — can open it, and an `LSUIElement` app can bring it to front.
@MainActor
final class UntilPickerController: NSObject, NSWindowDelegate {
    private let state: AppState
    private var window: NSWindow?

    init(state: AppState) { self.state = state }

    func show() {
        if let window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }
        let view = UntilTimePicker(
            onConfirm: { [weak self] hour, minute in
                AppRuntime.shared.until(hour: hour, minute: minute)
                self?.close()
            },
            onCancel: { [weak self] in self?.close() }
        )
        let hosting = NSHostingController(rootView: view)
        let w = NSWindow(contentViewController: hosting)
        w.title = String(localized: "Keep Awake Until")
        w.styleMask = [.titled, .closable, .fullSizeContentView]
        w.titlebarAppearsTransparent = true
        w.isReleasedWhenClosed = false
        w.level = .floating
        w.delegate = self
        w.setFrameAutosaveName("")
        w.center()
        window = w
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }

    func close() { window?.close() }

    func windowWillClose(_ notification: Notification) { window = nil }
}

/// "Keep awake until a specific time". Picks a wall-clock time; a time that
/// has already passed today means *tomorrow* (e.g. 08:00 chosen at 23:00).
struct UntilTimePicker: View {
    let onConfirm: (Int, Int) -> Void
    let onCancel: () -> Void

    @State private var selected: Date = UntilTimePicker.roundedNextHalfHour()

    private var components: (hour: Int, minute: Int) {
        let c = Calendar.current.dateComponents([.hour, .minute], from: selected)
        return (c.hour ?? 0, c.minute ?? 0)
    }

    private var target: Date {
        CaffeCommand.nextOccurrence(hour: components.hour, minute: components.minute)
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { ctx in
            VStack(alignment: .leading, spacing: 20) {
                header
                timeRow(now: ctx.date)
                quickPicks
                footer
            }
            .padding(20)
            .padding(.top, 8)
            .frame(width: 380)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "cup.and.saucer.fill")
                .font(.system(size: 22))
                .foregroundStyle(.brown)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Keep awake until")
                    .font(.title3.weight(.semibold))
                Text("Your Mac won't sleep before this time.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func timeRow(now: Date) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            DatePicker("Time", selection: $selected, displayedComponents: [.hourAndMinute])
                .labelsHidden()
                .datePickerStyle(.stepperField)
                .controlSize(.large)
                .accessibilityLabel("Keep awake until time")
            VStack(alignment: .leading, spacing: 2) {
                Text(Self.dayLabel(for: target, now: now))
                    .font(.headline)
                Text("in \(Self.relative(from: now, to: target))")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Spacer(minLength: 0)
        }
    }

    private var quickPicks: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Quick picks")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                pick(Text("+1 hour")) { Date().addingTimeInterval(3600) }
                pick(Text("+2 hours")) { Date().addingTimeInterval(7200) }
                pick(Text(verbatim: Self.today(hour: 18).formatted(date: .omitted, time: .shortened))) { Self.today(hour: 18) }
                pick(Text("Midnight")) { Self.today(hour: 0) }
            }
        }
    }

    private func pick(_ title: Text, _ make: @escaping () -> Date) -> some View {
        Button(action: { selected = make() }, label: { title })
            .controlSize(.regular)
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("Cancel", action: onCancel)
                .keyboardShortcut(.cancelAction)
            Button("Keep Awake") { onConfirm(components.hour, components.minute) }
                .keyboardShortcut(.defaultAction)
                .help("Keep the Mac awake until the chosen time (Return)")
        }
        .controlSize(.large)
    }

    // MARK: - Helpers

    static func roundedNextHalfHour(now: Date = Date()) -> Date {
        let cal = Calendar.current
        let minute = cal.component(.minute, from: now)
        let add = minute < 30 ? 30 - minute + 30 : 60 - minute + 30
        let date = now.addingTimeInterval(TimeInterval(add * 60))
        return cal.date(bySetting: .second, value: 0, of: date) ?? date
    }

    static func today(hour: Int) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: Date()) ?? Date()
    }

    static func dayLabel(for target: Date, now: Date) -> String {
        Calendar.current.isDate(target, inSameDayAs: now) ? String(localized: "Today") : String(localized: "Tomorrow")
    }

    static func relative(from now: Date, to target: Date) -> String {
        let minutes = max(1, Int((target.timeIntervalSince(now) / 60).rounded(.up)))
        return CaffeinationSession.Duration.durationText(TimeInterval(minutes * 60))
    }
}
