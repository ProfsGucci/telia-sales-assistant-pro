import XCTest
@testable import TeliaCore

final class CampaignTests: XCTestCase {

    // MARK: - Fixtures

    private func makeCampaign(
        id: String = "test-1",
        priceKind: CampaignPriceKind = .monthly,
        campaignPrice: Double = 399,
        ordinary: Double? = 549,
        endDate: Date? = nil,
        promoMonths: Int? = nil,
        afterPrice: Double? = nil,
        verifiedAt: Date = Date(timeIntervalSince1970: 0)
    ) -> CampaignRecord {
        CampaignRecord(
            id: id,
            title: "Testkampanj",
            productName: "Testprodukt",
            category: .bredband,
            priceKind: priceKind,
            campaignPriceSEK: campaignPrice,
            ordinaryPriceSEK: ordinary,
            bindingMonths: 24,
            promoMonths: promoMonths,
            priceAfterCampaignSEK: afterPrice,
            endDate: endDate,
            sourceURL: "https://www.telia.se/erbjudanden",
            sourceName: "telia.se/erbjudanden",
            verifiedAt: verifiedAt
        )
    }

    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Stockholm")!
        return c
    }

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    /// Matches the day-month formatting used by the comparison rows.
    private var sweFormatter: DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "sv_SE")
        f.dateFormat = "d MMMM"
        return f
    }

    // MARK: - Status & expiry

    func testStatusNoEndDate() {
        let c = makeCampaign()
        XCTAssertEqual(CampaignEngine.status(c, calendar: calendar), .noVerifiedEndDate)
    }

    func testStatusActiveFarFromExpiry() {
        let c = makeCampaign(endDate: date(2026, 12, 24))
        XCTAssertEqual(CampaignEngine.status(c, now: date(2026, 10, 18), calendar: calendar), .active)
    }

    func testStatusExpiresSoonWithinThreshold() {
        let c = makeCampaign(endDate: date(2026, 10, 24))
        XCTAssertEqual(
            CampaignEngine.status(c, now: date(2026, 10, 18), calendar: calendar),
            .expiresSoon(days: 6)
        )
    }

    func testStatusExpiredYesterday() {
        let c = makeCampaign(endDate: date(2026, 10, 17))
        XCTAssertEqual(CampaignEngine.status(c, now: date(2026, 10, 18), calendar: calendar), .expired)
    }

    func testStatusExpiresSameDayStillActive() {
        let c = makeCampaign(endDate: date(2026, 10, 18))
        XCTAssertEqual(
            CampaignEngine.status(c, now: date(2026, 10, 18), calendar: calendar),
            .expiresSoon(days: 0)
        )
    }

    func testActiveCampaignsFiltersExpired() {
        let live = makeCampaign(id: "live")
        let dead = makeCampaign(id: "dead", endDate: date(2026, 10, 1))
        let result = CampaignEngine.activeCampaigns(
            [live, dead], now: date(2026, 10, 18), calendar: calendar
        )
        XCTAssertEqual(result.map(\.id), ["live"])
    }

    // MARK: - Savings (never invented, never cross-kind)

    func testMonthlySaving() {
        let c = makeCampaign(campaignPrice: 175, ordinary: 239)
        XCTAssertEqual(CampaignEngine.monthlySavingSEK(c) ?? 0, 64, accuracy: 0.01)
        XCTAssertEqual(CampaignEngine.savingPercent(c) ?? 0, 26.78, accuracy: 0.1)
    }

    func testOneTimeSaving() {
        let c = makeCampaign(priceKind: .oneTime, campaignPrice: 1199, ordinary: 1499)
        XCTAssertEqual(CampaignEngine.oneTimeSavingSEK(c) ?? 0, 300, accuracy: 0.01)
        XCTAssertNil(CampaignEngine.monthlySavingSEK(c), "One-time price must not produce a monthly saving")
        XCTAssertNil(CampaignEngine.savingPercent(c), "Percent saving must not mix price kinds")
    }

    func testNoSavingWithoutOrdinaryPrice() {
        let c = makeCampaign(ordinary: nil)
        XCTAssertNil(CampaignEngine.monthlySavingSEK(c))
        XCTAssertNil(CampaignEngine.savingPercent(c))
        XCTAssertNil(CampaignEngine.oneTimeSavingSEK(c))
    }

    // MARK: - Total cost over a period

    func testTotalCostMonthlyFlat() {
        let c = makeCampaign(campaignPrice: 469, ordinary: nil)
        XCTAssertEqual(CampaignEngine.totalCostSEK(c, months: 24) ?? 0, 469 * 24, accuracy: 0.01)
    }

    func testTotalCostMonthlyWithPromo() {
        // 175 kr for 12 months, then 239 kr -> 24 months = 12*175 + 12*239
        let c = makeCampaign(campaignPrice: 175, ordinary: 239, promoMonths: 12, afterPrice: 239)
        XCTAssertEqual(CampaignEngine.totalCostSEK(c, months: 24) ?? 0, 12 * 175 + 12 * 239, accuracy: 0.01)
    }

    func testTotalCostMonthlyPromoShorterThanHorizon() {
        // 499 for 3 months then 549 -> 12 months
        let c = makeCampaign(campaignPrice: 499, ordinary: 549, promoMonths: 3, afterPrice: 549)
        XCTAssertEqual(CampaignEngine.totalCostSEK(c, months: 12) ?? 0, 3 * 499 + 9 * 549, accuracy: 0.01)
    }

    func testTotalCostOneTimeIgnoresHorizon() {
        let c = makeCampaign(priceKind: .oneTime, campaignPrice: 1199, ordinary: 1499)
        XCTAssertEqual(CampaignEngine.totalCostSEK(c, months: 24) ?? 0, 1199, accuracy: 0.01)
        XCTAssertEqual(CampaignEngine.totalCostSEK(c, months: 1) ?? 0, 1199, accuracy: 0.01)
    }

    // MARK: - Filter, search, sort

    func testFilterByCategoryAndQuery() {
        let a = makeCampaign(id: "a")
        var b = makeCampaign(id: "b")
        b.category = .tvStreaming
        b.title = "Streama hockey"
        let result = CampaignEngine.filter(
            [a, b], category: .tvStreaming, query: "hockey",
            maxMonthlySEK: nil, needsVerificationOnly: false, staleAfterDays: 7,
            now: date(2026, 10, 18), calendar: calendar
        )
        XCTAssertEqual(result.map(\.id), ["b"])
    }

    func testFilterByMaxMonthlyExcludesOneTime() {
        let monthly = makeCampaign(id: "m", campaignPrice: 300)
        let oneTime = makeCampaign(id: "o", priceKind: .oneTime, campaignPrice: 199)
        let result = CampaignEngine.filter(
            [monthly, oneTime], category: nil, query: "",
            maxMonthlySEK: 500, needsVerificationOnly: false, staleAfterDays: 7,
            now: date(2026, 10, 18), calendar: calendar
        )
        XCTAssertEqual(result.map(\.id), ["m"], "A 199 kr one-time price is not a monthly price under 500")
    }

    func testFilterNeedsVerificationOnly() {
        let fresh = makeCampaign(id: "fresh", verifiedAt: date(2026, 10, 17))
        let stale = makeCampaign(id: "stale", verifiedAt: date(2026, 10, 1))
        let result = CampaignEngine.filter(
            [fresh, stale], category: nil, query: "",
            maxMonthlySEK: nil, needsVerificationOnly: true, staleAfterDays: 7,
            now: date(2026, 10, 18), calendar: calendar
        )
        XCTAssertEqual(result.map(\.id), ["stale"])
    }

    func testSortExpirySoonFirst() {
        let none = makeCampaign(id: "none")
        let late = makeCampaign(id: "late", endDate: date(2026, 12, 24))
        let soon = makeCampaign(id: "soon", endDate: date(2026, 10, 20))
        let result = CampaignEngine.sort(
            [none, late, soon], by: .expirySoonFirst,
            now: date(2026, 10, 18), calendar: calendar
        )
        XCTAssertEqual(result.map(\.id), ["soon", "late", "none"])
    }

    func testSortPriceLowFirst() {
        let result = CampaignEngine.sort(
            [makeCampaign(id: "a", campaignPrice: 549),
             makeCampaign(id: "b", campaignPrice: 175)],
            by: .priceLowFirst
        )
        XCTAssertEqual(result.map(\.id), ["b", "a"])
    }

    // MARK: - Diff

    func testDiffDetectsAddedRemovedAndPriceChange() {
        let oldA = makeCampaign(id: "a", campaignPrice: 399)
        let oldB = makeCampaign(id: "b", campaignPrice: 549)
        let newA = makeCampaign(id: "a", campaignPrice: 379) // price changed
        let newC = makeCampaign(id: "c", campaignPrice: 249) // added
        let diff = CampaignEngine.diff(old: [oldA, oldB], new: [newA, newC])
        XCTAssertEqual(diff.added.map(\.id), ["c"])
        XCTAssertEqual(diff.removed.map(\.id), ["b"])
        XCTAssertEqual(diff.priceChanges.count, 1)
        XCTAssertEqual(diff.priceChanges[0].id, "a")
        XCTAssertEqual(diff.priceChanges[0].fromSEK, 399, accuracy: 0.01)
        XCTAssertEqual(diff.priceChanges[0].toSEK, 379, accuracy: 0.01)
        XCTAssertFalse(diff.isEmpty)
    }

    func testDiffEmptyWhenUnchanged() {
        let a = makeCampaign(id: "a", campaignPrice: 399)
        let a2 = makeCampaign(id: "a", campaignPrice: 399)
        XCTAssertTrue(CampaignEngine.diff(old: [a], new: [a2]).isEmpty)
    }

    // MARK: - Merge (safe updates)

    func testMergeKeepsCachedRecordsMissingFromIncoming() {
        let cached = [makeCampaign(id: "a"), makeCampaign(id: "b")]
        let incoming = [makeCampaign(id: "b", campaignPrice: 299)]
        let merged = CampaignEngine.merge(cached: cached, incoming: incoming)
        XCTAssertEqual(Set(merged.map(\.id)), ["a", "b"])
        let b = merged.first { $0.id == "b" }!
        XCTAssertEqual(b.campaignPriceSEK, 299, accuracy: 0.01)
    }

    func testMergeRejectsInvalidIncomingRecords() {
        var zero = makeCampaign(id: "zero", campaignPrice: 0)
        var empty = makeCampaign(id: "empty")
        empty.title = ""
        let merged = CampaignEngine.merge(cached: [], incoming: [zero, empty])
        XCTAssertTrue(merged.isEmpty, "Records with zero price or empty title must be dropped")
    }

    // MARK: - Comparison rows

    func testComparisonRowsPresentMissingValuesExplicitly() {
        let monthly = makeCampaign(id: "m", campaignPrice: 399, ordinary: 549)
        let oneTime = makeCampaign(id: "o", priceKind: .oneTime, campaignPrice: 1199, ordinary: 1499)
        let rows = CampaignEngine.comparisonRows([monthly, oneTime], months: 24) { "\(Int($0)) kr" }
        let byLabel = Dictionary(rows.map { ($0.label, $0) }, uniquingKeysWith: { a, _ in a })

        XCTAssertEqual(byLabel["Månadskostnad"]?.cells[0].text, "399 kr")
        XCTAssertNil(byLabel["Månadskostnad"]?.cells[1].text, "One-time campaign has no monthly cost")
        XCTAssertEqual(byLabel["Engångspris"]?.cells[1].text, "1199 kr")
        XCTAssertNil(byLabel["Engångspris"]?.cells[0].text)
        XCTAssertEqual(byLabel["Månadsbesparing"]?.cells[0].text, "150 kr")
        XCTAssertNil(byLabel["Månadsbesparing"]?.cells[1].text)
        XCTAssertEqual(byLabel["Engångsbesparing"]?.cells[1].text, "300 kr")
        XCTAssertEqual(byLabel["Totalt 24 mån"]?.cells[0].text, "9576 kr")
        XCTAssertEqual(byLabel["Totalt 24 mån"]?.cells[1].text, "1199 kr")
        XCTAssertEqual(byLabel["Bindningstid"]?.cells[0].text, "24 mån")
        XCTAssertEqual(byLabel["Slutdatum"]?.cells[0].text, "Ej verifierat")
        XCTAssertEqual(rows.count, 13)
    }

    func testComparisonRowsRespectPromoHorizon() {
        let c = makeCampaign(campaignPrice: 175, ordinary: 239, promoMonths: 12, afterPrice: 239)
        let rows = CampaignEngine.comparisonRows([c], months: 24) { "\(Int($0)) kr" }
        let byLabel = Dictionary(rows.map { ($0.label, $0) }, uniquingKeysWith: { a, _ in a })
        XCTAssertEqual(byLabel["Totalt 24 mån"]?.cells[0].text, "4968 kr")
        XCTAssertEqual(byLabel["Pris efter kampanj"]?.cells[0].text, "239 kr")
        XCTAssertEqual(byLabel["Kampanjpris giltigt"]?.cells[0].text, "12 mån")
    }

    // MARK: - Seed data integrity

    struct CampaignSeedFile: Codable {
        let campaigns: [CampaignRecord]
        let generatedAt: Date
        let sourceNote: String
        let schemaVersion: Int
    }

    /// Mirrors the app's DataStore decoder settings.
    private var seedDecoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    private func loadSeed() throws -> CampaignSeedFile {
        let url = Bundle.main.url(forResource: "CampaignSeed", withExtension: "json")
            ?? URL(fileURLWithPath: "TeliaSalesAssistantPro/Resources/CampaignSeed.json")
        return try seedDecoder.decode(CampaignSeedFile.self, from: try Data(contentsOf: url))
    }

    private func loadCatalogIDs() throws -> Set<String> {
        let url = Bundle.main.url(forResource: "SeedCatalog", withExtension: "json")
            ?? URL(fileURLWithPath: "TeliaSalesAssistantPro/Resources/SeedCatalog.json")
        let catalog = try seedDecoder.decode(CatalogSnapshot.self, from: try Data(contentsOf: url))
        return Set(catalog.products.map(\.id))
    }

    func testCampaignSeedJSONDecodesAndIsValid() throws {
        let seed = try loadSeed()

        XCTAssertGreaterThanOrEqual(seed.campaigns.count, 15, "Expected a substantial seeded campaign set")
        XCTAssertEqual(seed.schemaVersion, 1)

        let ids = seed.campaigns.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count, "Campaign IDs must be unique")

        let knownIDs = try loadCatalogIDs()
        for campaign in seed.campaigns {
            XCTAssertFalse(campaign.title.isEmpty)
            XCTAssertGreaterThan(campaign.campaignPriceSEK, 0)
            XCTAssertTrue(campaign.sourceURL.hasPrefix("https://www.telia.se/"), "Every campaign needs its official source link")
            XCTAssertNotNil(campaign.verifiedAt)

            if campaign.ordinaryPriceSEK != nil {
                XCTAssertNotNil(
                    campaign.priceKind == .monthly
                        ? CampaignEngine.monthlySavingSEK(campaign)
                        : CampaignEngine.oneTimeSavingSEK(campaign),
                    "Ordinary price present but no comparable saving computable for \(campaign.id)"
                )
            }
            // Related products must reference known seed catalog IDs.
            for related in campaign.relatedProductIDs {
                XCTAssertTrue(knownIDs.contains(related), "\(campaign.id) references unknown product \(related)")
            }
        }

        // At least one campaign must carry an explicit verified end date.
        XCTAssertTrue(seed.campaigns.contains { $0.endDate != nil })
        // No campaign may be seeded as already expired.
        let now = Date()
        for campaign in seed.campaigns {
            if let end = campaign.endDate {
                XCTAssertGreaterThan(end, now, "Seeded campaign \(campaign.id) has an end date in the past")
            }
        }
    }

    func testHAALECampaignHasExplicitExpiry() throws {
        let seed = try loadSeed()
        let haale = try XCTUnwrap(seed.campaigns.first { $0.id == "haale-smart-band-1199" })
        XCTAssertEqual(haale.priceKind, .oneTime)
        XCTAssertNotNil(haale.endDate)
        XCTAssertEqual(haale.oneTimeValueSEK ?? 0, 0, "Smart band is not a bundle with hardware value field")
    }

    // MARK: - Formatting sanity for comparison cells

    func testComparisonRowForEndDateUsesDayMonth() {
        let c = makeCampaign(endDate: date(2026, 10, 31))
        let rows = CampaignEngine.comparisonRows([c], months: 12) { _ in "" }
        let row = rows.first { $0.label == "Slutdatum" }!
        let expected = sweFormatter.string(from: date(2026, 10, 31))
        XCTAssertEqual(row.cells[0].text, expected)
    }
}
