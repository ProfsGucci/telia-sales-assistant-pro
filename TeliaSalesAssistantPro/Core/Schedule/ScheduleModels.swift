import Foundation

// MARK: - Models

public enum EventKind: String, Codable, CaseIterable, Sendable {
    case shift, training, meeting, reminder, personal

    public var displayName: String {
        switch self {
        case .shift: return "Pass"
        case .training: return "Träning"
        case .meeting: return "Möte"
        case .reminder: return "Påminnelse"
        case .personal: return "Privat"
        }
    }

    public var symbolName: String {
        switch self {
        case .shift: return "bag.fill"
        case .training: return "book.fill"
        case .meeting: return "person.3.fill"
        case .reminder: return "bell.fill"
        case .personal: return "heart.fill"
        }
    }
}

public enum Recurrence: String, Codable, CaseIterable, Sendable {
    case none, daily, weekly, biweekly, monthly

    public var displayName: String {
        switch self {
        case .none: return "Upprepas inte"
        case .daily: return "Varje dag"
        case .weekly: return "Varje vecka"
        case .biweekly: return "Varannan vecka"
        case .monthly: return "Varje månad"
        }
    }
}

public struct ScheduleEvent: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var title: String
    public var kind: EventKind
    public var start: Date
    public var end: Date
    public var notes: String
    public var location: String
    public var recurrence: Recurrence
    /// Inclusive last day the recurrence applies (nil = open-ended).
    public var recurrenceEnd: Date?

    public init(id: UUID = UUID(), title: String, kind: EventKind, start: Date, end: Date,
                notes: String = "", location: String = "",
                recurrence: Recurrence = .none, recurrenceEnd: Date? = nil) {
        self.id = id
        self.title = title
        self.kind = kind
        self.start = start
        self.end = end
        self.notes = notes
        self.location = location
        self.recurrence = recurrence
        self.recurrenceEnd = recurrenceEnd
    }
}

public struct DayTask: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var title: String
    public var done: Bool
    public var due: Date
    public var notes: String

    public init(id: UUID = UUID(), title: String, done: Bool = false, due: Date, notes: String = "") {
        self.id = id
        self.title = title
        self.done = done
        self.due = due
        self.notes = notes
    }
}

// MARK: - Engine

public enum CalendarEngine {

    /// Swedish convention: weeks start on Monday.
    public static func workCalendar() -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 2
        cal.locale = Locale(identifier: "sv_SE")
        return cal
    }

    /// 42-cell grid (6 weeks) covering the month containing `date`. Monday first.
    public static func monthGrid(containing date: Date, calendar: Calendar) -> [Date] {
        let comps = calendar.dateComponents([.year, .month], from: date)
        guard let firstOfMonth = calendar.date(from: comps) else { return [] }
        let weekday = calendar.component(.weekday, from: firstOfMonth)
        let daysBack = (weekday - calendar.firstWeekday + 7) % 7
        guard let gridStart = calendar.date(byAdding: .day, value: -daysBack, to: firstOfMonth) else { return [] }
        return (0..<42).compactMap { calendar.date(byAdding: .day, value: $0, to: gridStart) }
    }

    public static func isSameMonth(_ a: Date, _ b: Date, calendar: Calendar) -> Bool {
        let ac = calendar.dateComponents([.year, .month], from: a)
        let bc = calendar.dateComponents([.year, .month], from: b)
        return ac == bc
    }

    /// All occurrences of an event inside the interval, expanding simple recurrences.
    public static func occurrences(
        of event: ScheduleEvent,
        between start: Date,
        and end: Date,
        calendar: Calendar
    ) -> [ScheduleEvent] {
        var result: [ScheduleEvent] = []
        let duration = event.end.timeIntervalSince(event.start)
        // recurrenceEnd is day-granular: an occurrence any time that day counts.
        let hardEnd: Date
        if let re = event.recurrenceEnd {
            let endOfRecurrenceDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: re)) ?? re
            hardEnd = min(end, endOfRecurrenceDay)
        } else {
            hardEnd = end
        }

        var cursor = event.start
        var guardCounter = 0
        while cursor < hardEnd && guardCounter < 800 {
            guardCounter += 1
            if cursor >= start {
                if let occEnd = calendar.date(byAdding: .second, value: Int(duration), to: cursor) {
                    result.append(ScheduleEvent(
                        id: event.id, title: event.title, kind: event.kind,
                        start: cursor, end: occEnd, notes: event.notes,
                        location: event.location, recurrence: .none, recurrenceEnd: nil
                    ))
                }
            }
            switch event.recurrence {
            case .none:
                return result
            case .daily:
                cursor = calendar.date(byAdding: .day, value: 1, to: cursor) ?? cursor
            case .weekly:
                cursor = calendar.date(byAdding: .weekOfYear, value: 1, to: cursor) ?? cursor
            case .biweekly:
                cursor = calendar.date(byAdding: .weekOfYear, value: 2, to: cursor) ?? cursor
            case .monthly:
                cursor = calendar.date(byAdding: .month, value: 1, to: cursor) ?? cursor
            }
        }
        return result
    }

    public static func events(
        on day: Date,
        from events: [ScheduleEvent],
        calendar: Calendar
    ) -> [ScheduleEvent] {
        let dayStart = calendar.startOfDay(for: day)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return [] }
        let all = events.flatMap { occurrences(of: $0, between: dayStart, and: dayEnd, calendar: calendar) }
        return all.filter { occ in
            occ.start < dayEnd && occ.start >= dayStart
        }.sorted { $0.start < $1.start }
    }

    public static func upcoming(
        from events: [ScheduleEvent],
        after date: Date,
        limit: Int = 8,
        calendar: Calendar
    ) -> [ScheduleEvent] {
        let horizon = calendar.date(byAdding: .day, value: 60, to: date) ?? date
        let all = events.flatMap { occurrences(of: $0, between: date, and: horizon, calendar: calendar) }
        return Array(all.filter { $0.start >= date }.sorted { $0.start < $1.start }.prefix(limit))
    }

    public static func nextShift(
        from events: [ScheduleEvent],
        after date: Date,
        calendar: Calendar
    ) -> ScheduleEvent? {
        upcoming(from: events.filter { $0.kind == .shift }, after: date, limit: 1, calendar: calendar).first
    }

    public static func tasks(
        on day: Date,
        from tasks: [DayTask],
        calendar: Calendar
    ) -> [DayTask] {
        let dayStart = calendar.startOfDay(for: day)
        return tasks.filter { calendar.startOfDay(for: $0.due) == dayStart }
    }
}
