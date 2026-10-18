import Foundation

// MARK: - Sales goals (manual targets + daily calculator)
//
// All numbers come from the user's manual input. Nothing here fabricates or
// estimates sales results.

public enum SalesGoalCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case subscriptions, devices, accessories, broadbandTV, extraServices, revenue, other

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .subscriptions: return "Abonnemang"
        case .devices: return "Enheter"
        case .accessories: return "Tillbehör"
        case .broadbandTV: return "Bredband & TV"
        case .extraServices: return "Extratjänster"
        case .revenue: return "Intäkt (kr)"
        case .other: return "Annat"
        }
    }

    public var symbolName: String {
        switch self {
        case .subscriptions: return "antenna.radiowaves.left.and.right"
        case .devices: return "iphone.gen3"
        case .accessories: return "headphones"
        case .broadbandTV: return "wifi.router"
        case .extraServices: return "plus.circle"
        case .revenue: return "banknote"
        case .other: return "target"
        }
    }

    /// Whole units are counted in integers; revenue in kronor.
    public var isWholeUnit: Bool { self != .revenue }
}

/// How "remaining selling days" are counted.
public enum SalesGoalDayBasis: String, Codable, CaseIterable, Identifiable, Sendable {
    case calendarDays, workingDays, shiftDays

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .calendarDays: return "Kalenderdagar"
        case .workingDays: return "Arbetstider (mån–fre)"
        case .shiftDays: return "Mina planerade pass"
        }
    }

    public var hint: String {
        switch self {
        case .calendarDays: return "Räknar varje dag fram till måldatum."
        case .workingDays: return "Räknar bara måndag–fredag."
        case .shiftDays: return "Räknar bara dagar med pass i appens Schema — realistiskt för säljplanering."
        }
    }
}

public struct SalesGoal: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var title: String
    public var category: SalesGoalCategory
    /// Total target in the category's unit (units or SEK). Always > 0.
    public var totalTarget: Double
    /// Manually entered actual progress so far. Never auto-filled.
    public var actualProgress: Double
    public var startDate: Date
    public var targetDate: Date
    public var dayBasis: SalesGoalDayBasis

    public init(id: UUID = UUID(),
                title: String,
                category: SalesGoalCategory,
                totalTarget: Double,
                actualProgress: Double = 0,
                startDate: Date = Date(),
                targetDate: Date,
                dayBasis: SalesGoalDayBasis = .shiftDays) {
        self.id = id
        self.title = title
        self.category = category
        self.totalTarget = totalTarget
        self.actualProgress = actualProgress
        self.startDate = startDate
        self.targetDate = targetDate
        self.dayBasis = dayBasis
    }
}

public enum SalesGoalStatus: String, Codable, Sendable {
    case notStarted, inProgress, completed, exceeded, noDaysRemaining, overdue

    public var displayName: String {
        switch self {
        case .notStarted: return "Ej påbörjat"
        case .inProgress: return "Pågår"
        case .completed: return "Klart"
        case .exceeded: return "Målet slagna!"
        case .noDaysRemaining: return "Inga säljdagar kvar"
        case .overdue: return "Måldatum passerat"
        }
    }
}

/// Everything the UI needs to render one goal — computed, never stored.
public struct SalesGoalSnapshot: Hashable, Sendable {
    public let goal: SalesGoal
    public let remaining: Double
    /// Days left to sell, per the goal's day basis.
    public let remainingDays: Int
    /// Remaining ÷ remainingDays. 0 when there is nothing left to do.
    public let requiredPerDay: Double
    /// Whole-unit goals: the practical "aim for this many per day" number.
    public let roundedUpPerDay: Int
    public let progressFraction: Double
    public let status: SalesGoalStatus
    /// Short human message for edge cases (overdue, no days, done…).
    public let message: String?

    public var progressPercent: Int { Int((progressFraction * 100).rounded()) }
}

public enum SalesGoalEngine {

    /// The single calculation entry point. `plannedShiftDates` is only used
    /// for `.shiftDays` — pass the start-of-day dates that have shifts.
    public static func snapshot(
        goal: SalesGoal,
        on date: Date = Date(),
        calendar: Calendar = Calendar.current,
        plannedShiftDates: [Date]? = nil
    ) -> SalesGoalSnapshot {
        let today = calendar.startOfDay(for: date)
        let target = calendar.startOfDay(for: goal.targetDate)

        let remaining = goal.totalTarget - goal.actualProgress
        let fraction = goal.totalTarget > 0
            ? min(1, max(0, goal.actualProgress / goal.totalTarget))
            : 0

        // Status that needs no day math.
        if remaining <= 0 {
            let exceeded = goal.actualProgress > goal.totalTarget
            return SalesGoalSnapshot(
                goal: goal,
                remaining: 0,
                remainingDays: 0,
                requiredPerDay: 0,
                roundedUpPerDay: 0,
                progressFraction: 1,
                status: exceeded ? .exceeded : .completed,
                message: exceeded
                    ? "Målet är passerat med \(formatNumber(goal.actualProgress - goal.totalTarget, whole: goal.category.isWholeUnit)) — starkt jobbat!"
                    : "Målet är uppnått. Snyggt!"
            )
        }

        // Remaining selling days per the chosen basis.
        let days: Int
        switch goal.dayBasis {
        case .calendarDays:
            days = countCalendarDays(from: today, to: target, calendar: calendar)
        case .workingDays:
            days = countWorkingDays(from: today, to: target, calendar: calendar)
        case .shiftDays:
            let shifts = (plannedShiftDates ?? []).map { calendar.startOfDay(for: $0) }
            days = Set(shifts).filter { $0 >= today && $0 <= target }.count
        }

        // Edge cases with messages instead of division by zero.
        if target < today {
            return SalesGoalSnapshot(
                goal: goal, remaining: remaining, remainingDays: 0,
                requiredPerDay: 0, roundedUpPerDay: 0,
                progressFraction: fraction, status: .overdue,
                message: "Måldatum har passerat. Förläng datumet eller justera målet — \(formatNumber(remaining, whole: goal.category.isWholeUnit)) återstår."
            )
        }
        if days <= 0 {
            return SalesGoalSnapshot(
                goal: goal, remaining: remaining, remainingDays: 0,
                requiredPerDay: 0, roundedUpPerDay: 0,
                progressFraction: fraction, status: .noDaysRemaining,
                message: goal.dayBasis == .shiftDays
                    ? "Inga planerade pass kvar till måldatum — lägg till pass i Schema eller välj annan dagsbas."
                    : "Inga säljdagar kvar till måldatum — förläng datumet eller välj annan dagsbas."
            )
        }

        let perDay = remaining / Double(days)
        return SalesGoalSnapshot(
            goal: goal,
            remaining: remaining,
            remainingDays: days,
            requiredPerDay: perDay,
            roundedUpPerDay: goal.category.isWholeUnit ? Int(ceil(perDay)) : 0,
            progressFraction: fraction,
            status: goal.actualProgress <= 0 ? .notStarted : .inProgress,
            message: nil
        )
    }

    // MARK: Day counting

    /// Inclusive count of days in [from, to]; 0 when from > to.
    static func countCalendarDays(from: Date, to: Date, calendar: Calendar) -> Int {
        guard from <= to else { return 0 }
        let comps = calendar.dateComponents([.day], from: from, to: to)
        return (comps.day ?? -1) + 1
    }

    /// Monday–Friday count in [from, to]; 0 when from > to.
    static func countWorkingDays(from: Date, to: Date, calendar: Calendar) -> Int {
        guard from <= to else { return 0 }
        var count = 0
        var day = from
        while day <= to {
            let w = calendar.component(.weekday, from: day)
            if w != 7 && w != 1 { count += 1 } // not Saturday/Sunday
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return count
    }

    static func formatNumber(_ value: Double, whole: Bool) -> String {
        if whole {
            return "\(Int(value.rounded()))"
        }
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        f.locale = Locale(identifier: "sv_SE")
        return f.string(from: NSNumber(value: value)) ?? "\(Int(value))"
    }

    /// Validation for the editor: target date must be after start date and
    /// the total must be positive.
    public static func isValid(goal: SalesGoal) -> Bool {
        goal.totalTarget > 0 && goal.targetDate > goal.startDate
    }
}
