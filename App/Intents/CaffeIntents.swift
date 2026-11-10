import AppIntents
import BuiltInProfiles

/// Spotlight / Siri / Shortcuts entry points. App Shortcuts declared in
/// `CaffeShortcuts` show up in Spotlight with zero setup once the app has
/// been launched from /Applications.

enum CaffeDuration: String, AppEnum {
    case fifteen, thirty, oneHour, twoHours, indefinite

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Duration"
    static var caseDisplayRepresentations: [CaffeDuration: DisplayRepresentation] = [
        .fifteen: "15 minutes",
        .thirty: "30 minutes",
        .oneHour: "1 hour",
        .twoHours: "2 hours",
        .indefinite: "Indefinitely",
    ]

    var minutes: Int? {
        switch self {
        case .fifteen: return 15
        case .thirty: return 30
        case .oneHour: return 60
        case .twoHours: return 120
        case .indefinite: return nil
        }
    }
}

struct StartCaffeIntent: AppIntent {
    static var title: LocalizedStringResource = "Keep Mac Awake"
    static var description = IntentDescription("Starts a caffeine timer in the island.")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Duration", default: .thirty)
    var duration: CaffeDuration

    static var parameterSummary: some ParameterSummary {
        Summary("Keep Mac awake for \(\.$duration)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        await AppRuntime.shared.ensureStarted()
        AppRuntime.shared.start(minutes: duration.minutes)
        let label = duration.minutes.map { CaffeinationSession.Duration.durationText(TimeInterval($0 * 60)) }
            ?? String(localized: "until you stop it")
        return .result(dialog: "☕ Awake: \(label)")
    }
}

struct StartCaffeMinutesIntent: AppIntent {
    static var title: LocalizedStringResource = "Keep Mac Awake for Minutes"
    static var description = IntentDescription("Starts a caffeine timer for a custom number of minutes.")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Minutes", default: 45, inclusiveRange: (1, 1440))
    var minutes: Int

    static var parameterSummary: some ParameterSummary {
        Summary("Keep Mac awake for \(\.$minutes) minutes")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        await AppRuntime.shared.ensureStarted()
        AppRuntime.shared.start(minutes: minutes)
        return .result(dialog: "☕ Awake: \(CaffeinationSession.Duration.durationText(TimeInterval(minutes * 60)))")
    }
}

struct StartCaffeUntilIntent: AppIntent {
    static var title: LocalizedStringResource = "Keep Mac Awake Until"
    static var description = IntentDescription("Keeps the Mac awake until a time of day. A time already passed today means tomorrow.")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Time", kind: .time)
    var time: Date

    static var parameterSummary: some ParameterSummary {
        Summary("Keep Mac awake until \(\.$time)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        await AppRuntime.shared.ensureStarted()
        let c = Calendar.current.dateComponents([.hour, .minute], from: time)
        AppRuntime.shared.until(hour: c.hour ?? 0, minute: c.minute ?? 0)
        let end = CaffeCommand.nextOccurrence(hour: c.hour ?? 0, minute: c.minute ?? 0)
        return .result(dialog: "☕ Awake until \(end.formatted(date: .omitted, time: .shortened))")
    }
}

struct StopCaffeIntent: AppIntent {
    static var title: LocalizedStringResource = "Let Mac Sleep"
    static var description = IntentDescription("Stops the caffeine timer.")
    static var openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        await AppRuntime.shared.ensureStarted()
        AppRuntime.shared.stop()
        return .result(dialog: "💤 Your Mac can sleep again")
    }
}

struct CaffeShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartCaffeIntent(),
            phrases: [
                "Start \(.applicationName)",
                "Caffeinate with \(.applicationName)",
                "Keep awake with \(.applicationName) for \(\.$duration)",
            ],
            shortTitle: "Keep Mac Awake",
            systemImageName: "cup.and.saucer.fill"
        )
        AppShortcut(
            intent: StopCaffeIntent(),
            phrases: [
                "Stop \(.applicationName)",
                "Let my Mac sleep with \(.applicationName)",
            ],
            shortTitle: "Let Mac Sleep",
            systemImageName: "moon.zzz.fill"
        )
    }
}
