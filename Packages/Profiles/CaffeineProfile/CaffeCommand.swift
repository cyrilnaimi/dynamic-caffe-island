import Foundation

/// Every external command the app understands, independent of where it came
/// from (`caffe://` URL, CLI, App Intent, hotkey, menu). Pure and testable.
public enum CaffeCommand: Equatable, Sendable {
    case start(minutes: Int)
    case indefinite
    case until(hour: Int, minute: Int)
    case stop
    case toggle
    case peek
    case pickTime

    public static let defaultMinutes = 30

    /// Parses `caffe://…` URLs:
    ///
    ///   caffe://start?minutes=30   caffe://start/45   caffe://30   caffe://start
    ///   caffe://indefinite         caffe://until?time=19:45   caffe://until/1945
    ///   caffe://stop  caffe://toggle  caffe://peek  caffe://pick
    public static func parse(_ url: URL) -> CaffeCommand? {
        guard url.scheme?.lowercased() == "caffe" else { return nil }
        let host = (url.host ?? "").lowercased()
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func query(_ names: String...) -> String? {
            items.first { names.contains($0.name.lowercased()) }?.value
        }
        let firstPath = url.pathComponents.dropFirst().first

        switch host {
        case "stop", "off": return .stop
        case "toggle": return .toggle
        case "peek", "open": return .peek
        case "pick", "picker": return .pickTime
        case "indefinite", "forever", "on": return .indefinite
        case "until", "till":
            guard let text = query("time", "t") ?? firstPath,
                  let (h, m) = parseClock(text) else { return nil }
            return .until(hour: h, minute: m)
        case "start", "":
            let raw = query("minutes", "m") ?? firstPath
            if let raw {
                guard let minutes = Int(raw), (1...1440).contains(minutes) else { return nil }
                return .start(minutes: minutes)
            }
            return .start(minutes: defaultMinutes)
        default:
            if let minutes = Int(host), (1...1440).contains(minutes) { return .start(minutes: minutes) }
            return nil
        }
    }

    /// Accepts "19:45", "19h45", "1945", "9", "09:05".
    public static func parseClock(_ text: String) -> (Int, Int)? {
        let t = text.trimmingCharacters(in: .whitespaces).lowercased()
        let parts = t.split(whereSeparator: { $0 == ":" || $0 == "h" || $0 == "." }).map(String.init)
        let h: Int?, m: Int?
        switch parts.count {
        case 1 where parts[0].count >= 3:
            let digits = parts[0]
            h = Int(digits.dropLast(2)); m = Int(digits.suffix(2))
        case 1:
            h = Int(parts[0]); m = 0
        case 2:
            h = Int(parts[0]); m = Int(parts[1])
        default:
            return nil
        }
        guard let h, let m, (0...23).contains(h), (0...59).contains(m) else { return nil }
        return (h, m)
    }

    /// Next occurrence of a wall-clock time: today if still ahead, else
    /// tomorrow. "Until 08:00" at 23:00 means tomorrow morning — not
    /// "one minute from now".
    public static func nextOccurrence(hour: Int, minute: Int, after now: Date = Date(), calendar: Calendar = .current) -> Date {
        var parts = calendar.dateComponents([.year, .month, .day], from: now)
        parts.hour = hour
        parts.minute = minute
        parts.second = 0
        let today = calendar.date(from: parts) ?? now
        if today > now { return today }
        return calendar.date(byAdding: .day, value: 1, to: today) ?? today.addingTimeInterval(86_400)
    }
}
