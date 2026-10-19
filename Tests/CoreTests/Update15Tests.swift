import XCTest
@testable import TeliaCore

// MARK: - Update 1.5: pace engine, daily brief, privacy-safe reminders

final class Update15PaceTests: XCTestCase {

    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Stockholm")!
        return c
    }

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: 12))!
    }

    private func goal(total: Double, done: Double, from: Date, to: Date,
                      basis: SalesGoalDayBasis) -> SalesGoal {
        SalesGoal(title: "Pacetest", category: .subscriptions, totalTarget: total,
                  actualProgress: done, startDate: from, targetDate: to, dayBasis: basis)
    }

    /// Calendar-day goal started 10 days ago, 10 days left (21 total):
    /// elapsed 10 → expected = 10/21 × 20 ≈ 9.52.
    private func calendarSnapshot(done: Double) -> SalesGoalSnapshot {
        let g = goal(total: 20, done: done, from: date(2026, 10, 8), to: date(2026, 10, 28), basis: .calendarDays)
        return SalesGoalEngine.snapshot(goal: g, on: date(2026, 10, 18), calendar: cal)
    }

    func testPaceAheadAboveExpectedPlusTolerance() {
        // Expected ≈ 9.52; 11 ≥ 9.52 × 1.05 = 10.0 → ahead.
        let snap = calendarSnapshot(done: 11)
        XCTAssertEqual(snap.pace, .ahead)
        XCTAssertEqual(snap.expectedProgress ?? -1, 200.0 / 21.0, accuracy: 0.0001)
    }

    func testPaceOnTrackWithinFivePercentBand() {
        // Expected ≈ 9.52; 9.52 is within ±5% → onTrack (9.52 ≥ 9.04).
        let snap = calendarSnapshot(done: 9.52)
        XCTAssertEqual(snap.pace, .onTrack)
    }

    func testPaceBehindBelowExpectedMinusTolerance() {
        // Expected ≈ 9.52; 8 < 9.04 → behind.
        let snap = calendarSnapshot(done: 8)
        XCTAssertEqual(snap.pace, .behind)
    }

    func testPaceNotApplicableBeforeStartAndWhenCompleted() {
        // Future start: elapsed 0, no progress → notApplicable (with any progress it is ahead).
        let future = goal(total: 10, done: 0, from: date(2026, 10, 25), to: date(2026, 11, 5), basis: .calendarDays)
        let snap = SalesGoalEngine.snapshot(goal: future, on: date(2026, 10, 18), calendar: cal)
        XCTAssertEqual(snap.pace, .notApplicable)
        XCTAssertEqual(snap.expectedProgress ?? -1, 0, accuracy: 0.0001)

        // Progress before the start date counts as ahead (early start).
        let early = goal(total: 10, done: 2, from: date(2026, 10, 25), to: date(2026, 11, 5), basis: .calendarDays)
        let snap2 = SalesGoalEngine.snapshot(goal: early, on: date(2026, 10, 18), calendar: cal)
        XCTAssertEqual(snap2.pace, .ahead)

        // Completed goals have no pace — the race is over.
        let done = goal(total: 10, done: 10, from: date(2026, 10, 8), to: date(2026, 10, 28), basis: .calendarDays)
        let snap3 = SalesGoalEngine.snapshot(goal: done, on: date(2026, 10, 18), calendar: cal)
        XCTAssertEqual(snap3.pace, .notApplicable)
        XCTAssertEqual(snap3.status, .completed)
    }

    func testPaceShiftDaysUsesPlannedShiftsElapsedExcludingToday() {
        // Shifts on Oct 12, 13, 14 (past) and Oct 19, 20 (remaining): elapsed 3,
        // total 5 → expected = 30 × 3/5 = 18. Done 14 → behind (14 < 17.1);
        // done 19 → ahead (19 ≥ 18.9).
        let shifts = [date(2026, 10, 12), date(2026, 10, 13), date(2026, 10, 14),
                      date(2026, 10, 19), date(2026, 10, 20)]
        let behind = goal(total: 30, done: 14, from: date(2026, 10, 12), to: date(2026, 10, 20), basis: .shiftDays)
        XCTAssertEqual(
            SalesGoalEngine.snapshot(goal: behind, on: date(2026, 10, 18), calendar: cal, plannedShiftDates: shifts).pace,
            .behind)
        let ahead = goal(total: 30, done: 19, from: date(2026, 10, 12), to: date(2026, 10, 20), basis: .shiftDays)
        let snap = SalesGoalEngine.snapshot(goal: ahead, on: date(2026, 10, 18), calendar: cal, plannedShiftDates: shifts)
        XCTAssertEqual(snap.pace, .ahead)
        XCTAssertEqual(snap.remainingDays, 2) // today's shift is still remaining
    }
}

// MARK: - Daily brief engine tests

final class DailyBriefEngineTests: XCTestCase {

    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Stockholm")!
        return c
    }

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: 12))!
    }

    private var emptyGroups: FollowUpEngine.Groups {
        FollowUpEngine.Groups(overdue: [], dueToday: [], upcoming: [], completed: [])
    }

    private func goalSnapshot(total: Double, done: Double, from: Date, to: Date,
                              paceExpected: Bool = true) -> SalesGoalSnapshot {
        let g = SalesGoal(title: "Månadsmål", category: .subscriptions, totalTarget: total,
                          actualProgress: done, startDate: from, targetDate: to, dayBasis: .calendarDays)
        return SalesGoalEngine.snapshot(goal: g, on: date(2026, 10, 18), calendar: cal)
    }

    private func record(name: String, due: Date, completed: Date? = nil) -> FollowUpRecord {
        FollowUpRecord(personnummer: "198112189876", name: name, reason: "Kolla kampanj",
                       dueDate: due, completedAt: completed)
    }

    func testBriefWithNoDataStatesUnavailableInsteadOfInventing() {
        let brief = DailyBriefEngine.build(
            date: date(2026, 10, 18), calendar: cal,
            goalSnapshots: [], followUps: emptyGroups, events: [], expiringCampaigns: []
        )
        // Goals: none — no fabricated goal content.
        XCTAssertTrue(brief.goalItems.isEmpty)
        XCTAssertTrue(brief.followUpItems.isEmpty)
        XCTAssertTrue(brief.campaignItems.isEmpty)
        // Events: the brief SAYS there are none rather than inventing any.
        XCTAssertEqual(brief.eventItems.count, 1)
        XCTAssertEqual(brief.eventItems[0].source, .manual)
        // Recommendation falls through to the no-goals branch.
        XCTAssertEqual(brief.recommendation?.title, "Skapa ett säljmål")
    }

    func testBriefGoalItemsAreCalculatedAndCappedAtThree() {
        let snaps = [
            goalSnapshot(total: 20, done: 5, from: date(2026, 10, 1), to: date(2026, 10, 31)),
            goalSnapshot(total: 20, done: 5, from: date(2026, 10, 1), to: date(2026, 10, 31)),
            goalSnapshot(total: 20, done: 5, from: date(2026, 10, 1), to: date(2026, 10, 31)),
            goalSnapshot(total: 20, done: 5, from: date(2026, 10, 1), to: date(2026, 10, 31)),
            // Completed goals are excluded from the briefing.
            goalSnapshot(total: 20, done: 20, from: date(2026, 10, 1), to: date(2026, 10, 31)),
        ]
        let brief = DailyBriefEngine.build(
            date: date(2026, 10, 18), calendar: cal,
            goalSnapshots: snaps, followUps: emptyGroups, events: [], expiringCampaigns: []
        )
        XCTAssertEqual(brief.goalItems.count, 3)
        XCTAssertTrue(brief.goalItems.allSatisfy { $0.source == .calculated })
        XCTAssertTrue(brief.goalItems[0].detail.contains("säljdagar kvar"))
    }

    func testBriefFollowUpItemsUseNamesNeverPersonnummer() {
        let groups = FollowUpEngine.group(
            [
                record(name: "Anna", due: date(2026, 10, 16)),
                record(name: "Bosse", due: date(2026, 10, 18)),
                record(name: "Cecilia", due: date(2026, 10, 18)),
                record(name: "Doris", due: date(2026, 10, 18)),
                record(name: "Erik", due: date(2026, 10, 18)),
                record(name: "Fredrik", due: date(2026, 10, 25)),
            ],
            on: date(2026, 10, 18), calendar: cal
        )
        let brief = DailyBriefEngine.build(
            date: date(2026, 10, 18), calendar: cal,
            goalSnapshots: [], followUps: groups, events: [], expiringCampaigns: []
        )
        XCTAssertEqual(brief.followUpItems.count, 3) // overdue + dueToday + upcoming
        let dueToday = brief.followUpItems[1]
        XCTAssertEqual(dueToday.title, "4 kunder att kolla idag")
        XCTAssertTrue(dueToday.detail.contains("Bosse, Cecilia, Doris"))
        XCTAssertTrue(dueToday.detail.contains("+1 till"))
        // Privacy: the personnummer never appears anywhere in the brief.
        let allText = (brief.followUpItems.map { $0.title + $0.detail }
            + (brief.recommendation.map { [$0.title + $0.detail] } ?? [])).joined()
        XCTAssertFalse(allText.contains("198112189876"))
    }

    func testBriefEventsShowConfiguredAndImported() {
        let events = [
            BriefEvent(title: "Kvällspass", start: date(2026, 10, 18), origin: "Pass"),
            BriefEvent(title: "Regionmöte", start: date(2026, 10, 19), origin: "Outlook"),
        ]
        let brief = DailyBriefEngine.build(
            date: date(2026, 10, 18), calendar: cal,
            goalSnapshots: [], followUps: emptyGroups, events: events, expiringCampaigns: []
        )
        // Today's event is preferred over future ones.
        XCTAssertEqual(brief.eventItems.count, 1)
        XCTAssertEqual(brief.eventItems[0].title, "Kvällspass")
        XCTAssertTrue(brief.eventItems[0].detail.contains("Pass"))
    }

    func testBriefCampaignsAreVerifiedWithDayCounts() {
        let brief = DailyBriefEngine.build(
            date: date(2026, 10, 18), calendar: cal,
            goalSnapshots: [], followUps: emptyGroups, events: [],
            expiringCampaigns: [
                BriefCampaign(title: "Rabatt på bredband", daysLeft: 2),
                BriefCampaign(title: "Gamla kampanj", daysLeft: 0),
            ]
        )
        XCTAssertEqual(brief.campaignItems.count, 2)
        XCTAssertTrue(brief.campaignItems.allSatisfy { $0.source == .verified })
        XCTAssertTrue(brief.campaignItems[0].detail.contains("2 dagar"))
        XCTAssertTrue(brief.campaignItems[1].detail.contains("Slutdatum har passerat"))
    }

    func testRecommendationPriorityOverdueBeatsEverything() {
        let groups = FollowUpEngine.group(
            [record(name: "Anna", due: date(2026, 10, 16))],
            on: date(2026, 10, 18), calendar: cal
        )
        let behind = goalSnapshot(total: 30, done: 2, from: date(2026, 10, 1), to: date(2026, 10, 31))
        XCTAssertEqual(behind.pace, .behind)
        let rec = DailyBriefEngine.recommendation(
            followUps: groups, snapshots: [behind],
            expiringCampaigns: [BriefCampaign(title: "Snart slut", daysLeft: 1)]
        )
        XCTAssertEqual(rec?.title, "Börja dagen med uppföljningarna")
        XCTAssertEqual(rec?.source, .calculated)
    }

    func testRecommendationDueTodayThenBehindGoal() {
        let dueToday = FollowUpEngine.group(
            [record(name: "Bosse", due: date(2026, 10, 18))],
            on: date(2026, 10, 18), calendar: cal
        )
        let rec = DailyBriefEngine.recommendation(
            followUps: dueToday, snapshots: [], expiringCampaigns: []
        )
        XCTAssertEqual(rec?.title, "Klara uppföljningarna tidigt")

        let behind = goalSnapshot(total: 30, done: 2, from: date(2026, 10, 1), to: date(2026, 10, 31))
        let rec2 = DailyBriefEngine.recommendation(
            followUps: emptyGroups, snapshots: [behind], expiringCampaigns: []
        )
        XCTAssertEqual(rec2?.title, "Du ligger efter schemat på Månadsmål")
        // Quoted numbers come from the real snapshot, not invented.
        XCTAssertTrue(rec2?.detail.contains("per säljdag") ?? false)
    }

    func testRecommendationExpiringCampaignThenDefault() {
        let rec = DailyBriefEngine.recommendation(
            followUps: emptyGroups, snapshots: [],
            expiringCampaigns: [BriefCampaign(title: "Snart slut", daysLeft: 3)]
        )
        XCTAssertEqual(rec?.title, "Nämn kampanjen som snart slutar")
        XCTAssertEqual(rec?.source, .verified)

        // Active, on-track goal → generic data-driven default.
        // (Elapsed 17 of 31 days → expected ≈10.97; done 12 is on-track.)
        let onTrack = goalSnapshot(total: 20, done: 12, from: date(2026, 10, 1), to: date(2026, 10, 31))
        let rec2 = DailyBriefEngine.recommendation(
            followUps: emptyGroups, snapshots: [onTrack], expiringCampaigns: []
        )
        XCTAssertEqual(rec2?.title, "En verifierad kampanj per samtal")
    }
}

// MARK: - Privacy-safe reminder text

final class FollowUpReminderTextTests: XCTestCase {

    func testReminderBodyContainsCountOnlyNeverCustomerData() {
        XCTAssertEqual(FollowUpEngine.reminderTitle, "Kunduppföljning")
        let body = FollowUpEngine.reminderBody(count: 3)
        XCTAssertEqual(body, "Du har 3 kunduppföljningar idag.")
        // Lock-screen safe: no names, no personnummer, no reasons.
        XCTAssertFalse(body.contains("Anna"))
        XCTAssertFalse(body.contains("1981"))
    }

    func testReminderBodySingularAndZero() {
        XCTAssertEqual(FollowUpEngine.reminderBody(count: 1), "Du har en kunduppföljning idag.")
        XCTAssertEqual(FollowUpEngine.reminderBody(count: 0), "Du har inga kunduppföljningar idag.")
    }
}
