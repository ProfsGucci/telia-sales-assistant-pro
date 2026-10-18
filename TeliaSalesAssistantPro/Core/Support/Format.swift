import Foundation

/// Shared formatting helpers used across the app. Pure Foundation so they run in tests too.
public enum Format {

    public static let sek: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        f.locale = Locale(identifier: "sv_SE")
        return f
    }()

    /// "349 kr/mån" — currency style used everywhere in the catalog.
    public static func monthly(_ value: Double?) -> String {
        guard let value else { return "pris ej verifierat" }
        let rounded = value.rounded()
        if rounded == value {
            return "\(Int(rounded)) kr/mån"
        }
        return String(format: "%.2f kr/mån", value)
    }

    public static func sekPlain(_ value: Double) -> String {
        "\(sek.string(from: NSNumber(value: value.rounded())) ?? String(Int(value))) kr"
    }

    public static let dayMonth: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "sv_SE")
        f.dateFormat = "d MMMM"
        return f
    }()

    public static let time: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "sv_SE")
        f.dateFormat = "HH:mm"
        return f
    }()

    public static let dateTime: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "sv_SE")
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    public static let dayShort: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "sv_SE")
        f.dateFormat = "EEE d"
        return f
    }()

    /// Compact weekday label for calendar grids, e.g. "M", "T", "O"...
    public static let weekdayLetter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "sv_SE")
        f.dateFormat = "EEEEE"
        return f
    }()

    public static func relativeDays(_ date: Date?, now: Date = Date(), calendar: Calendar = .current) -> String {
        guard let date else { return "aldrig" }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: date)).day ?? 0
        switch days {
        case 0: return "idag"
        case 1: return "igår"
        case 2...7: return "för \(days) dagar sedan"
        case -1: return "imorgon"
        case -7..<0: return "om \(-days) dagar"
        default:
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "sv_SE")
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
            return formatter.string(from: date)
        }
    }

    public static func minutes(_ value: Int) -> String {
        value >= 60 ? "\(value / 60) h \(value % 60) min" : "\(value) min"
    }
}
