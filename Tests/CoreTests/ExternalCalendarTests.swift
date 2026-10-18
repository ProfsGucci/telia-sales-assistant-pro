import XCTest
@testable import TeliaCore

// MARK: - External calendar merge tests (duplicate prevention)

final class ExternalCalendarMergeTests: XCTestCase {

    private func record(provider: CalendarProvider = .google,
                        eventID: String,
                        calendarID: String = "cal-1",
                        title: String,
                        start: Date = Date(timeIntervalSince1970: 1_800_000_000),
                        end: Date = Date(timeIntervalSince1970: 1_800_003_600)) -> ExternalEventRecord {
        ExternalEventRecord(provider: provider, providerEventID: eventID,
                            providerCalendarID: calendarID, calendarName: "Kalender",
                            title: title, start: start, end: end)
    }

    // MARK: Duplicate prevention

    func testRepeatedRefreshDoesNotDuplicate() {
        let incoming = [record(eventID: "a", title: "Möte"), record(eventID: "b", title: "Lunch")]
        var stored: [ExternalEventRecord] = []

        stored = ExternalCalendarMerge.merge(existing: stored, incoming: incoming, provider: .google)
        XCTAssertEqual(stored.count, 2)

        // Same snapshot again — must stay 2, not 4.
        stored = ExternalCalendarMerge.merge(existing: stored, incoming: incoming, provider: .google)
        XCTAssertEqual(stored.count, 2, "Re-refresh with identical events must not duplicate")
    }

    func testEditedEventUpdatesInPlaceKeepingLocalID() {
        let original = record(eventID: "a", title: "Gamla titeln")
        var stored = ExternalCalendarMerge.merge(existing: [], incoming: [original], provider: .google)
        let localID = stored[0].id

        let edited = record(eventID: "a", title: "Nya titeln")
        stored = ExternalCalendarMerge.merge(existing: stored, incoming: [edited], provider: .google)

        XCTAssertEqual(stored.count, 1)
        XCTAssertEqual(stored[0].title, "Nya titeln")
        XCTAssertEqual(stored[0].id, localID, "Stable local identity keeps SwiftUI list state")
    }

    func testDeletedAtSourceDisappears() {
        let a = record(eventID: "a", title: "Möte")
        let b = record(eventID: "b", title: "Borttaget")
        var stored = ExternalCalendarMerge.merge(existing: [], incoming: [a, b], provider: .google)
        XCTAssertEqual(stored.count, 2)

        // Next refresh only contains "a" — "b" was deleted in Google.
        stored = ExternalCalendarMerge.merge(existing: stored, incoming: [a], provider: .google)
        XCTAssertEqual(stored.count, 1)
        XCTAssertEqual(stored[0].providerEventID, "a")
    }

    func testOtherProvidersUntouched() {
        let apple = record(provider: .apple, eventID: "x", title: "Apple-pass")
        var stored = ExternalCalendarMerge.merge(existing: [], incoming: [apple], provider: .apple)

        // Google refresh comes in — Apple records must pass through.
        let google = record(provider: .google, eventID: "g1", title: "Google-möte")
        stored = ExternalCalendarMerge.merge(existing: stored, incoming: [google], provider: .google)

        XCTAssertEqual(stored.count, 2)
        XCTAssertTrue(stored.contains { $0.provider == .apple })

        // An empty GOOGLE snapshot clears only Google records — Apple stays.
        stored = ExternalCalendarMerge.merge(existing: stored, incoming: [], provider: .google)
        XCTAssertEqual(stored.filter { $0.provider == .apple }.count, 1)
        XCTAssertEqual(stored.filter { $0.provider == .google }.count, 0)
    }

    // MARK: Day/upcoming queries

    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Stockholm")!
        return c
    }

    func testEventsOnDayFiltersAndSorts() {
        let base = cal.date(from: DateComponents(year: 2026, month: 10, day: 18, hour: 0))!
        let late = base.addingTimeInterval(10 * 3600)
        let early = base.addingTimeInterval(2 * 3600)
        let otherDay = base.addingTimeInterval(86400 + 3600)
        let allDay = base.addingTimeInterval(-3600) // starts yesterday, spans midnight

        let records = [
            record(eventID: "1", title: "Sent", start: late, end: late.addingTimeInterval(3600)),
            record(eventID: "2", title: "Tidigt", start: early, end: early.addingTimeInterval(3600)),
            record(eventID: "3", title: "Annan dag", start: otherDay, end: otherDay.addingTimeInterval(3600)),
            record(eventID: "4", title: "Över midnatt", start: allDay, end: base.addingTimeInterval(3600)),
        ]
        let onDay = ExternalCalendarMerge.events(on: base, from: records, calendar: cal)
        XCTAssertEqual(onDay.map(\.providerEventID), ["4", "2", "1"], "Sorted by start (midnight-spanning first); day overlap only")
    }

    func testUpcomingLimitAndOrder() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var records: [ExternalEventRecord] = []
        for i in 0..<10 {
            let start = now.addingTimeInterval(TimeInterval(60 + i * 100))
            let end = now.addingTimeInterval(TimeInterval(120 + i * 100))
            records.append(record(eventID: "e\(i)", title: "E\(i)", start: start, end: end))
        }
        let upcoming = ExternalCalendarMerge.upcoming(from: records, after: now, limit: 5)
        XCTAssertEqual(upcoming.count, 5)
        XCTAssertEqual(upcoming.map(\.providerEventID), ["e0", "e1", "e2", "e3", "e4"])
    }

    func testConflictDetection() {
        let a = record(eventID: "a", title: "A",
                       start: Date(timeIntervalSince1970: 1000),
                       end: Date(timeIntervalSince1970: 2000))
        let b = record(eventID: "b", title: "B",
                       start: Date(timeIntervalSince1970: 1500),
                       end: Date(timeIntervalSince1970: 2500))
        let c = record(eventID: "c", title: "C",
                       start: Date(timeIntervalSince1970: 3000),
                       end: Date(timeIntervalSince1970: 4000))
        XCTAssertTrue(ExternalCalendarMerge.hasConflict(a, b))
        XCTAssertFalse(ExternalCalendarMerge.hasConflict(a, c))
        XCTAssertFalse(ExternalCalendarMerge.hasConflict(a, a), "An event never conflicts with itself")
    }

    // MARK: Provider metadata

    func testProviderMetadataComplete() {
        for provider in CalendarProvider.allCases {
            XCTAssertFalse(provider.displayName.isEmpty)
            XCTAssertFalse(provider.symbolName.isEmpty)
            XCTAssertEqual(provider.tintHex.count, 6, "\(provider) needs a 6-digit hex tint")
            XCTAssertTrue(provider.tintHex.allSatisfy { $0.isHexDigit })
        }
    }
}
