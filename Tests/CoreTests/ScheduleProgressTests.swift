import XCTest
@testable import TeliaCore

final class ScheduleProgressTests: XCTestCase {

    var cal: Calendar { CalendarEngine.workCalendar() }

    // MARK: - Month grid

    func testMonthGridHas42DaysStartingMonday() {
        let date = cal.date(from: DateComponents(year: 2026, month: 10, day: 15))! // Oct 2026
        let grid = CalendarEngine.monthGrid(containing: date, calendar: cal)
        XCTAssertEqual(grid.count, 42)
        // Monday must be the first cell.
        XCTAssertEqual(cal.component(.weekday, from: grid[0]), 2)
        // Grid covers the 1st of the month.
        XCTAssertTrue(grid.contains { d in
            let c = cal.dateComponents([.year, .month, .day], from: d)
            return c.year == 2026 && c.month == 10 && c.day == 1
        })
    }

    func testSameMonth() {
        let a = cal.date(from: DateComponents(year: 2026, month: 3, day: 1))!
        let b = cal.date(from: DateComponents(year: 2026, month: 3, day: 31))!
        let c = cal.date(from: DateComponents(year: 2026, month: 4, day: 1))!
        XCTAssertTrue(CalendarEngine.isSameMonth(a, b, calendar: cal))
        XCTAssertFalse(CalendarEngine.isSameMonth(a, c, calendar: cal))
    }

    // MARK: - Recurrence

    func testWeeklyRecurrenceExpands() {
        let start = cal.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: 9))! // Monday
        let event = ScheduleEvent(title: "Pass", kind: .shift, start: start,
                                  end: cal.date(byAdding: .hour, value: 8, to: start)!,
                                  recurrence: .weekly)
        let weekStart = cal.date(from: DateComponents(year: 2026, month: 10, day: 1))!
        let end = cal.date(from: DateComponents(year: 2026, month: 10, day: 31))!
        let occurrences = CalendarEngine.occurrences(of: event, between: weekStart, and: end, calendar: cal)
        XCTAssertEqual(occurrences.count, 4, "October 2026 has 4 Mondays from the 5th")
        XCTAssertTrue(occurrences.allSatisfy { cal.component(.weekday, from: $0.start) == 2 })
    }

    func testRecurrenceRespectsEndDate() {
        let start = cal.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: 9))!
        let event = ScheduleEvent(title: "Pass", kind: .shift, start: start,
                                  end: cal.date(byAdding: .hour, value: 8, to: start)!,
                                  recurrence: .daily,
                                  recurrenceEnd: cal.date(from: DateComponents(year: 2026, month: 10, day: 7))!)
        let rangeStart = cal.date(from: DateComponents(year: 2026, month: 10, day: 1))!
        let rangeEnd = cal.date(from: DateComponents(year: 2026, month: 10, day: 31))!
        let occurrences = CalendarEngine.occurrences(of: event, between: rangeStart, and: rangeEnd, calendar: cal)
        XCTAssertEqual(occurrences.count, 3, "Daily event from the 5th with recurrence end on the 7th")
    }

    func testNonRecurringSingleEvent() {
        let start = cal.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: 9))!
        let event = ScheduleEvent(title: "Möte", kind: .meeting, start: start,
                                  end: cal.date(byAdding: .hour, value: 1, to: start)!)
        let day = cal.date(from: DateComponents(year: 2026, month: 10, day: 5))!
        let events = CalendarEngine.events(on: day, from: [event], calendar: cal)
        XCTAssertEqual(events.count, 1)
        let otherDay = cal.date(from: DateComponents(year: 2026, month: 10, day: 6))!
        XCTAssertTrue(CalendarEngine.events(on: otherDay, from: [event], calendar: cal).isEmpty)
    }

    func testUpcomingAndNextShift() {
        let now = Date()
        let soon = cal.date(byAdding: .hour, value: 3, to: now)!
        let later = cal.date(byAdding: .day, value: 2, to: now)!
        let events = [
            ScheduleEvent(title: "Kvällspass", kind: .shift, start: later,
                          end: cal.date(byAdding: .hour, value: 8, to: later)!),
            ScheduleEvent(title: "Utbildning", kind: .training, start: soon,
                          end: cal.date(byAdding: .hour, value: 1, to: soon)!),
        ]
        let upcoming = CalendarEngine.upcoming(from: events, after: now, calendar: cal)
        XCTAssertEqual(upcoming.first?.title, "Utbildning")
        XCTAssertEqual(CalendarEngine.nextShift(from: events, after: now, calendar: cal)?.title, "Kvällspass")
    }

    func testTasksOnDay() {
        let day = cal.date(from: DateComponents(year: 2026, month: 10, day: 18))!
        let tasks = [
            DayTask(title: "Kolla dagens erbjudanden", due: day),
            DayTask(title: "Annat datum", done: true, due: cal.date(byAdding: .day, value: 1, to: day)!),
        ]
        XCTAssertEqual(CalendarEngine.tasks(on: day, from: tasks, calendar: cal).count, 1)
    }

    // MARK: - Progress

    func testDayAggregateAndConversion() {
        let cal2 = Calendar.current
        let today = cal2.startOfDay(for: Date())
        let entries = [
            SalesEntry(date: today, customersAssisted: 10, completedSales: 3, devicesSold: 1, mobilePlansSold: 2),
            SalesEntry(date: today, customersAssisted: 5, completedSales: 2, accessoriesSold: 4),
            SalesEntry(date: cal2.date(byAdding: .day, value: -1, to: today)!, customersAssisted: 99, completedSales: 99),
        ]
        let agg = ProgressEngine.aggregate(entries: entries, on: today, calendar: cal2)
        XCTAssertEqual(agg.customers, 15)
        XCTAssertEqual(agg.sales, 5)
        XCTAssertEqual(agg.accessories, 4)
        assertClose(agg.conversion ?? 0, 5.0 / 15.0, accuracy: 0.001)
    }

    func testConversionNilWithoutCustomers() {
        let agg = DayAggregate(date: Date(), customers: 0, sales: 0, devices: 0, plans: 0,
                               accessories: 0, broadbandTV: 0, services: 0, revenue: 0)
        XCTAssertNil(agg.conversion, "Never fabricate conversion from zero customers")
    }

    func testWeeklyAggregatesLengthAndOrder() {
        let cal2 = Calendar.current
        let weeks = ProgressEngine.weeklyAggregates(entries: [], endingOn: Date(), weeksBack: 8, calendar: cal2)
        XCTAssertEqual(weeks.count, 8)
    }

    func testTrendDetectsChange() {
        let values = [1.0, 1.0, 2.0, 2.0, 4.0, 4.0]
        let trend = ProgressEngine.trend(values: values)
        assertClose(trend ?? 0, 1.5, accuracy: 0.001)
        XCTAssertNil(ProgressEngine.trend(values: [1, 2]))
    }

    func testInsightsIncludeAccessoryOpportunity() {
        let cal2 = Calendar.current
        let today = Date()
        let entries = (0..<6).map { offset -> SalesEntry in
            SalesEntry(
                date: cal2.date(byAdding: .day, value: -offset, to: today)!,
                customersAssisted: 10, completedSales: 2, devicesSold: 2, accessoriesSold: 0
            )
        }
        let insights = InsightsEngine.suggestions(entries: entries, goals: Goals(), calendar: cal2, learningAnswers: [])
        XCTAssertTrue(insights.contains { $0.title.contains("Tillbehör") })
    }

    func testInsightsHonestWithoutEntries() {
        let insights = InsightsEngine.suggestions(entries: [], goals: Goals(), calendar: .current, learningAnswers: [])
        XCTAssertTrue(insights.contains { $0.title.contains("logga") })
        XCTAssertFalse(insights.contains { $0.title.contains("Konversion") })
    }

    // MARK: - Codable round trips

    func testProductRecordRoundTrip() throws {
        let record = ProductRecord(
            id: "x", name: "Obegränsad Plus", kind: .mobilePlan, category: "Plus",
            monthlyPriceSEK: 569, ordinaryMonthlyPriceSEK: 699, bindingMonths: 0,
            campaignMonths: 12, cashPriceSEK: nil, dataGB: nil, unlimitedData: true, speedMbit: 1000,
            includedServices: ["Telia Cloud"], highlights: ["x"],
            campaignStart: Date(timeIntervalSince1970: 1_700_000_000),
            mandatoryCharges: [ChargeItem(name: "Faktura", amountSEK: 59, recurring: true)],
            sourceURL: "https://www.telia.se/x", verifiedAt: Date(timeIntervalSince1970: 1_760_000_000),
            verification: .verified, tags: ["plus"]
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let round = try decoder.decode(ProductRecord.self, from: try encoder.encode(record))
        XCTAssertEqual(round, record)
    }

    func testConversationRoundTrip() throws {
        var convo = Conversation(title: "Test")
        convo.messages.append(ChatMessage(role: .user, text: "Hej"))
        convo.messages.append(ChatMessage(
            role: .assistant, text: "Svar",
            citations: [ChatCitation(productId: "p", productName: "P", sourceURL: "https://x.se", priceSEK: 100, verifiedAt: Date())],
            isDemo: true
        ))
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let round = try decoder.decode(Conversation.self, from: try encoder.encode(convo))
        XCTAssertEqual(round.messages.count, 2)
        XCTAssertEqual(round.messages[1].citations.first?.productName, "P")
        XCTAssertEqual(round.messages[1].isDemo, true)
    }

    func testSeedCatalogJSONDecodes() throws {
        // Locate SeedCatalog.json relative to the repository root.
        let urls = [
            URL(fileURLWithPath: "TeliaSalesAssistantPro/Resources/SeedCatalog.json"),
            URL(fileURLWithPath: "../TeliaSalesAssistantPro/Resources/SeedCatalog.json"),
        ]
        var data: Data?
        for url in urls {
            if FileManager.default.fileExists(atPath: url.path) {
                data = try Data(contentsOf: url)
                break
            }
        }
        let seed = try XCTUnwrap(data, "SeedCatalog.json not found")
        let (snapshot, report) = try PriceImport.parseJSON(seed)
        XCTAssertEqual(report.importedCount, snapshot.products.count)
        XCTAssertGreaterThan(snapshot.products.count, 40, "Seed catalog should contain the full verified set")
        // Every verified record must carry a source URL.
        XCTAssertTrue(snapshot.products.filter { $0.verification == .verified }.allSatisfy { $0.sourceURL != nil })
        // Sanity-check a known verified price read from telia.se on 2026-10-18.
        let obg = try XCTUnwrap(snapshot.product(id: "mobil-obegraensad"))
        XCTAssertEqual(obg.monthlyPriceSEK, 499)
    }
}
