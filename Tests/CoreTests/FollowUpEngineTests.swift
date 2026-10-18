import XCTest
@testable import TeliaCore

// MARK: - Check Later Customer engine tests

final class FollowUpEngineTests: XCTestCase {

    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Stockholm")!
        return c
    }

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: 12))!
    }

    private func record(name: String, due: Date, completed: Date? = nil,
                        pnr: String = "198112189876") -> FollowUpRecord {
        FollowUpRecord(personnummer: pnr, name: name, reason: "Kolla kampanj",
                       dueDate: due, completedAt: completed)
    }

    // MARK: Status

    func testStatusBuckets() {
        let today = date(2026, 10, 18)
        let overdue = record(name: "Försenad", due: date(2026, 10, 16))
        let dueToday = record(name: "Idag", due: date(2026, 10, 18))
        let upcoming = record(name: "Senare", due: date(2026, 10, 25))
        let done = record(name: "Klar", due: date(2026, 10, 16), completed: date(2026, 10, 16))

        XCTAssertEqual(FollowUpEngine.status(of: overdue, on: today, calendar: cal), .overdue)
        XCTAssertEqual(FollowUpEngine.status(of: dueToday, on: today, calendar: cal), .dueToday)
        XCTAssertEqual(FollowUpEngine.status(of: upcoming, on: today, calendar: cal), .upcoming)
        XCTAssertEqual(FollowUpEngine.status(of: done, on: today, calendar: cal), .completed)
        // Completed beats overdue even if the due date has passed.
    }

    func testGroupingSortsByDueDateThenName() {
        let today = date(2026, 10, 18)
        let records = [
            record(name: "Berta", due: date(2026, 10, 20)),
            record(name: "Adam", due: date(2026, 10, 25)),
            record(name: "Cesar", due: date(2026, 10, 20)),
            record(name: "Över", due: date(2026, 10, 17)),
            record(name: "Klar", due: date(2026, 10, 15), completed: date(2026, 10, 15)),
        ]
        let groups = FollowUpEngine.group(records, on: today, calendar: cal)
        XCTAssertEqual(groups.overdue.map(\.name), ["Över"])
        XCTAssertEqual(groups.upcoming.map(\.name), ["Berta", "Cesar", "Adam"])
        XCTAssertEqual(groups.completed.map(\.name), ["Klar"])
        XCTAssertEqual(groups.open.count, 4)
    }

    func testSearchByNameAndReasonNotByPersonnummer() {
        let records = [
            record(name: "Anna Andersson", due: date(2026, 10, 20), pnr: "198112189876"),
            record(name: "Bosse", due: date(2026, 10, 21), pnr: "196408233234"),
        ]
        XCTAssertEqual(FollowUpEngine.search(records, query: "anna").count, 1)
        XCTAssertEqual(FollowUpEngine.search(records, query: "bosse").count, 1)
        XCTAssertEqual(FollowUpEngine.search(records, query: "").count, 2)
        // Personnummer must NOT be searchable — keep sensitive digits out of
        // search behavior.
        XCTAssertEqual(FollowUpEngine.search(records, query: "9876").count, 0)
    }

    func testOpenDuplicateDetection() {
        let records = [
            record(name: "Anna", due: date(2026, 10, 20)),                    // open, same pnr
            record(name: "Anna klar", due: date(2026, 10, 15),
                   completed: date(2026, 10, 15)),                            // completed
            record(name: "Bosse", due: date(2026, 10, 21), pnr: "196408233234"),
        ]
        XCTAssertTrue(FollowUpEngine.hasOpenDuplicate(personnummer: "811218-9876", in: records))
        // Bosse (640823…) is open too — so his number IS an open duplicate;
        // a completely different number is not.
        XCTAssertTrue(FollowUpEngine.hasOpenDuplicate(personnummer: "640823-3234", in: records))
        XCTAssertFalse(FollowUpEngine.hasOpenDuplicate(personnummer: "010101-0015", in: records))
        // The completed record doesn't count as an open duplicate of the
        // same number... it does not block: 811218 is open via "Anna".
        XCTAssertTrue(FollowUpEngine.hasOpenDuplicate(personnummer: "19811218-9876", in: records),
                      "10 and 12 digit forms must both normalize before comparing")
    }

    func testReschedulingReopens() {
        var r = record(name: "Anna", due: date(2026, 10, 15), completed: date(2026, 10, 15))
        r.completedAt = nil
        XCTAssertEqual(FollowUpEngine.status(of: r, on: date(2026, 10, 18), calendar: cal), .overdue)
    }
}
