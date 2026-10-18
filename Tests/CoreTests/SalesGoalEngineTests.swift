import XCTest
@testable import TeliaCore

// MARK: - Sales goal calculator tests

final class SalesGoalEngineTests: XCTestCase {

    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Stockholm")!
        return c
    }

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: 12))!
    }

    private func goal(total: Double, done: Double = 0,
                      from: Date, to: Date,
                      basis: SalesGoalDayBasis = .shiftDays,
                      category: SalesGoalCategory = .subscriptions) -> SalesGoal {
        SalesGoal(title: "Test", category: category, totalTarget: total,
                  actualProgress: done, startDate: from, targetDate: to, dayBasis: basis)
    }

    // MARK: The spec's worked example
    // 60 target, 15 done, 9 planned selling days → 45 remaining, 5/day.
    // (Dates/shifts are constructed for this test only — NOT user data.)

    func testWorkedExampleFivePerDay() {
        // 9 shift days: Oct 19–27 minus weekends (19,20,21,22,23,26,27 = 7)…
        // explicit shift dates make this exact regardless of weekends:
        let shifts = (0..<9).compactMap { cal.date(byAdding: .day, value: $0, to: date(2026, 10, 18)) }
        let g = goal(total: 60, done: 15, from: date(2026, 10, 18), to: date(2026, 10, 26))
        let snap = SalesGoalEngine.snapshot(goal: g, on: date(2026, 10, 18), calendar: cal, plannedShiftDates: shifts)
        XCTAssertEqual(snap.remaining, 45)
        XCTAssertEqual(snap.remainingDays, 9)
        XCTAssertEqual(snap.requiredPerDay, 5, accuracy: 0.0001)
        XCTAssertEqual(snap.roundedUpPerDay, 5)
        XCTAssertEqual(snap.status, .inProgress)
        XCTAssertNil(snap.message)
        XCTAssertEqual(snap.progressFraction, 0.25, accuracy: 0.0001)
    }

    // MARK: Rounding

    func testWholeUnitGoalRoundsUp() {
        // 45 remaining over 7 days = 6.43 → aim for 7.
        let shifts = (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: date(2026, 10, 18)) }
        let g = goal(total: 60, done: 15, from: date(2026, 10, 18), to: date(2026, 10, 24))
        let snap = SalesGoalEngine.snapshot(goal: g, on: date(2026, 10, 18), calendar: cal, plannedShiftDates: shifts)
        XCTAssertEqual(snap.requiredPerDay, 45.0 / 7.0, accuracy: 0.0001)
        XCTAssertEqual(snap.roundedUpPerDay, 7, "Whole-unit goals show a practical ceiling")
    }

    // MARK: Edge cases

    func testNoProgressEntered() {
        let shifts = [date(2026, 10, 19), date(2026, 10, 20)]
        let g = goal(total: 10, from: date(2026, 10, 18), to: date(2026, 10, 20))
        let snap = SalesGoalEngine.snapshot(goal: g, on: date(2026, 10, 18), calendar: cal, plannedShiftDates: shifts)
        XCTAssertEqual(snap.remaining, 10)
        XCTAssertEqual(snap.status, .notStarted)
        XCTAssertEqual(snap.requiredPerDay, 5, accuracy: 0.0001)
    }

    func testCompletedGoal() {
        let g = goal(total: 50, done: 50, from: date(2026, 10, 1), to: date(2026, 10, 31))
        let snap = SalesGoalEngine.snapshot(goal: g, on: date(2026, 10, 18), calendar: cal, plannedShiftDates: [])
        XCTAssertEqual(snap.status, .completed)
        XCTAssertEqual(snap.remaining, 0)
        XCTAssertEqual(snap.requiredPerDay, 0)
        XCTAssertEqual(snap.progressFraction, 1)
        XCTAssertNotNil(snap.message)
    }

    func testExceededGoal() {
        let g = goal(total: 50, done: 62, from: date(2026, 10, 1), to: date(2026, 10, 31))
        let snap = SalesGoalEngine.snapshot(goal: g, on: date(2026, 10, 18), calendar: cal, plannedShiftDates: [])
        XCTAssertEqual(snap.status, .exceeded)
        XCTAssertEqual(snap.remaining, 0)
        // Progress caps at 1 for the bar even when exceeded.
        XCTAssertEqual(snap.progressFraction, 1)
    }

    func testZeroRemainingDaysDoesNotDivideByZero() {
        // No shifts at all with .shiftDays.
        let g = goal(total: 30, done: 10, from: date(2026, 10, 1), to: date(2026, 10, 30))
        let snap = SalesGoalEngine.snapshot(goal: g, on: date(2026, 10, 18), calendar: cal, plannedShiftDates: [])
        XCTAssertEqual(snap.status, .noDaysRemaining)
        XCTAssertEqual(snap.requiredPerDay, 0)
        XCTAssertNotNil(snap.message, "A clear message instead of division by zero")
    }

    func testPastTargetDateIsOverdue() {
        let g = goal(total: 30, done: 10, from: date(2026, 9, 1), to: date(2026, 10, 1))
        let snap = SalesGoalEngine.snapshot(goal: g, on: date(2026, 10, 18), calendar: cal, plannedShiftDates: [])
        XCTAssertEqual(snap.status, .overdue)
        XCTAssertEqual(snap.remaining, 20)
        XCTAssertNotNil(snap.message)
    }

    // MARK: Day bases

    func testWorkingDaysExcludeWeekends() {
        // Oct 19 2026 = Monday. Working days Mon 19 → Fri 23 = 5.
        let g = goal(total: 10, from: date(2026, 10, 19), to: date(2026, 10, 23), basis: .workingDays)
        let snap = SalesGoalEngine.snapshot(goal: g, on: date(2026, 10, 19), calendar: cal, plannedShiftDates: [])
        XCTAssertEqual(snap.remainingDays, 5)
        // Spanning a weekend: Oct 19 → Nov 2 has 11 working days.
        let g2 = goal(total: 10, from: date(2026, 10, 19), to: date(2026, 11, 2), basis: .workingDays)
        let snap2 = SalesGoalEngine.snapshot(goal: g2, on: date(2026, 10, 19), calendar: cal, plannedShiftDates: [])
        XCTAssertEqual(snap2.remainingDays, 11)
    }

    func testCalendarDaysCountEveryDay() {
        // Oct 19 → Oct 25 = 7 days regardless of weekend.
        let g = goal(total: 7, from: date(2026, 10, 19), to: date(2026, 10, 25), basis: .calendarDays)
        let snap = SalesGoalEngine.snapshot(goal: g, on: date(2026, 10, 19), calendar: cal, plannedShiftDates: [])
        XCTAssertEqual(snap.remainingDays, 7)
    }

    func testShiftDaysUseOnlyPlannedShifts() {
        // 5 calendar days but only 2 planned shifts → 2 selling days.
        let shifts = [date(2026, 10, 19), date(2026, 10, 22)]
        let g = goal(total: 8, from: date(2026, 10, 19), to: date(2026, 10, 23), basis: .shiftDays)
        let snap = SalesGoalEngine.snapshot(goal: g, on: date(2026, 10, 19), calendar: cal, plannedShiftDates: shifts)
        XCTAssertEqual(snap.remainingDays, 2)
        XCTAssertEqual(snap.requiredPerDay, 4, accuracy: 0.0001)
    }

    func testShiftsOutsideWindowIgnored() {
        // Shifts after the target date or before today don't count.
        let shifts = [date(2026, 10, 15), date(2026, 10, 19), date(2026, 11, 15)]
        let g = goal(total: 8, from: date(2026, 10, 18), to: date(2026, 10, 23), basis: .shiftDays)
        let snap = SalesGoalEngine.snapshot(goal: g, on: date(2026, 10, 18), calendar: cal, plannedShiftDates: shifts)
        XCTAssertEqual(snap.remainingDays, 1, "Only the shift inside today…target counts")
    }

    // MARK: Changes and persistence-shape

    func testChangedProgressAndDatesRecompute() {
        let shifts = (0..<10).compactMap { cal.date(byAdding: .day, value: $0, to: date(2026, 10, 18)) }
        var g = goal(total: 40, done: 0, from: date(2026, 10, 18), to: date(2026, 10, 27))
        var snap = SalesGoalEngine.snapshot(goal: g, on: date(2026, 10, 18), calendar: cal, plannedShiftDates: shifts)
        XCTAssertEqual(snap.requiredPerDay, 4, accuracy: 0.0001)

        g.actualProgress = 30 // changed progress
        snap = SalesGoalEngine.snapshot(goal: g, on: date(2026, 10, 18), calendar: cal, plannedShiftDates: shifts)
        XCTAssertEqual(snap.remaining, 10)
        XCTAssertEqual(snap.requiredPerDay, 1, accuracy: 0.0001)

        g.targetDate = date(2026, 11, 10) // rescheduled completion
        let moreShifts = (0..<24).compactMap { cal.date(byAdding: .day, value: $0, to: date(2026, 10, 18)) }
        snap = SalesGoalEngine.snapshot(goal: g, on: date(2026, 10, 18), calendar: cal, plannedShiftDates: moreShifts)
        XCTAssertEqual(snap.remainingDays, 24)
    }

    func testRevenueGoalFormatsAsCurrency() {
        let shifts = [date(2026, 10, 19), date(2026, 10, 20)]
        let g = goal(total: 12000, done: 4000, from: date(2026, 10, 18), to: date(2026, 10, 20), basis: .shiftDays, category: .revenue)
        let snap = SalesGoalEngine.snapshot(goal: g, on: date(2026, 10, 18), calendar: cal, plannedShiftDates: shifts)
        XCTAssertEqual(snap.remaining, 8000)
        XCTAssertEqual(snap.requiredPerDay, 4000, accuracy: 0.0001)
        XCTAssertEqual(snap.roundedUpPerDay, 0, "Revenue goals don't round to whole units")
    }

    func testValidation() {
        let bad = SalesGoal(title: "x", category: .subscriptions, totalTarget: 0,
                            startDate: date(2026, 10, 1), targetDate: date(2026, 10, 31))
        XCTAssertFalse(SalesGoalEngine.isValid(goal: bad))
        let badDates = SalesGoal(title: "x", category: .subscriptions, totalTarget: 10,
                                 startDate: date(2026, 10, 31), targetDate: date(2026, 10, 1))
        XCTAssertFalse(SalesGoalEngine.isValid(goal: badDates))
        let good = SalesGoal(title: "x", category: .subscriptions, totalTarget: 10,
                             startDate: date(2026, 10, 1), targetDate: date(2026, 10, 31))
        XCTAssertTrue(SalesGoalEngine.isValid(goal: good))
    }
}
