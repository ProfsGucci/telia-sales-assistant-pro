import XCTest
@testable import TeliaCore

final class PricingTests: XCTestCase {

    static let iso = ISO8601DateFormatter()

    func makePlan(
        id: String = "p1", name: String = "Test 20 GB",
        monthly: Double?, ordinary: Double? = nil, upfront: Double? = nil,
        binding: Int? = 0, campaignMonths: Int? = nil,
        charges: [ChargeItem] = [], dataGB: Double? = 20
    ) -> ProductRecord {
        ProductRecord(
            id: id, name: name, kind: .mobilePlan, category: "Surf",
            monthlyPriceSEK: monthly, ordinaryMonthlyPriceSEK: ordinary,
            upfrontCostSEK: upfront, bindingMonths: binding,
            campaignMonths: campaignMonths, dataGB: dataGB,
            mandatoryCharges: charges,
            sourceURL: "https://www.telia.se/test", verifiedAt: Date(), verification: .verified
        )
    }

    // MARK: - Plan totals

    func testPlainPlanTotalOver12Months() {
        let plan = makePlan(monthly: 299)
        let result = CostCalculator.planTotal(plan, months: 12)!
        assertClose(result.totalSEK, 299 * 12)
        XCTAssertEqual(result.monthlyAfterCampaignSEK, 299)
        XCTAssertEqual(result.campaignMonths, 0)
        XCTAssertEqual(result.oneTimeTotalSEK, 0)
    }

    func testCampaignTransitionsToOrdinaryPrice() {
        // 599 first 12 months, 699 after, 24-month horizon.
        let plan = makePlan(monthly: 599, ordinary: 699, binding: 24, campaignMonths: 12)
        let result = CostCalculator.planTotal(plan, months: 24)!
        XCTAssertEqual(result.monthlyNowSEK, 599)
        XCTAssertEqual(result.monthlyAfterCampaignSEK, 699)
        XCTAssertEqual(result.campaignMonths, 12)
        assertClose(result.totalSEK, 599 * 12 + 699 * 12)
        // Lines expose both periods for the UI.
        XCTAssertEqual(result.lines.filter { $0.recurring }.count, 2)
        XCTAssertEqual(result.lines[0].months, 12)
        XCTAssertEqual(result.lines[1].months, 12)
    }

    func testCampaignClampedToHorizon() {
        let plan = makePlan(monthly: 379, ordinary: 599, binding: 12, campaignMonths: 12)
        let result = CostCalculator.planTotal(plan, months: 6)!
        XCTAssertEqual(result.campaignMonths, 6)
        assertClose(result.totalSEK, 379 * 6)
    }

    func testUpfrontAndChargesIncluded() {
        let plan = makePlan(
            monthly: 100, upfront: 300,
            charges: [
                ChargeItem(name: "Faktura papper", amountSEK: 59, recurring: true),
                ChargeItem(name: "Öppning", amountSEK: 195, recurring: false),
            ]
        )
        let result = CostCalculator.planTotal(plan, months: 3)!
        let expectedTotal: Double = 100 * 3 + 59 * 3 + 300 + 195
        assertClose(result.oneTimeTotalSEK, 495)
        assertClose(result.totalSEK, expectedTotal)
    }

    func testZeroMonthsReturnsNil() {
        XCTAssertNil(CostCalculator.planTotal(makePlan(monthly: 100), months: 0))
    }

    // MARK: - Installments & devices

    func testInstallmentMonthly() {
        assertClose(CostCalculator.installmentMonthly(devicePriceSEK: 16_495, months: 24)!,
                       16_495.0 / 24.0)
        assertClose(CostCalculator.installmentMonthly(devicePriceSEK: 16_495, months: 24, upfrontSEK: 1_495)!,
                       15_000.0 / 24.0)
        XCTAssertNil(CostCalculator.installmentMonthly(devicePriceSEK: 100, months: 0))
        XCTAssertNil(CostCalculator.installmentMonthly(devicePriceSEK: 100, months: 24, upfrontSEK: 200))
    }

    func testDeviceWithPlanSplitsDevicePortion() {
        // iPhone quote 649/mån with Obegränsad (499) → device = 150/mån.
        let plan = makePlan(id: "obg", name: "Obegränsad", monthly: 499, dataGB: nil)
        let result = CostCalculator.deviceWithPlan(
            devicePriceSEK: 16_495, plan: plan,
            quotedBundleMonthlySEK: 649, months: 24, upfrontSEK: 0
        )!
        XCTAssertEqual(result.lines[0].amountSEK, 499)
        XCTAssertEqual(result.lines[1].amountSEK, 150)
        assertClose(result.totalSEK, 649 * 24)
        assertClose(result.monthlyAverageSEK, 649)
    }

    // MARK: - Family

    func testFamilyTotal() {
        let main = makePlan(id: "plus", name: "Obegränsad Plus", monthly: 569, dataGB: nil)
        let result = CostCalculator.familyTotal(
            main: main, extraUsers: 3,
            extraUserMonthlySEK: 175, extraUserOrdinarySEK: 239,
            extraUserCampaignMonths: 12
        )!
        assertClose(result.monthlyNowSEK, 569 + 3 * 175)
        assertClose(result.monthlyAfterCampaignSEK, 569 + 3 * 239)
        assertClose(result.monthlyPerPersonSEK, (569 + 525) / 4)
    }

    // MARK: - Comparison

    func testComparisonRows() {
        let a = makePlan(id: "a", name: "A", monthly: 299)
        let b = makePlan(id: "b", name: "B", monthly: 379, ordinary: 599, binding: 12, campaignMonths: 12)
        let rows = CostCalculator.comparison([a, b], months: 12)
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0].totalSEK, 299 * 12)
        XCTAssertEqual(rows[1].totalSEK, 379 * 12) // campaign covers whole horizon
    }

    // MARK: - Freshness & campaigns

    func testFreshnessThresholds() {
        let cal = Calendar.current
        func planVerified(daysAgo: Int) -> ProductRecord {
            makePlan(monthly: 100, ordinary: nil).withVerifiedAt(cal.date(byAdding: .day, value: -daysAgo, to: Date())!)
        }
        XCTAssertEqual(PriceVerification.freshness(of: planVerified(daysAgo: 1)), .fresh)
        XCTAssertEqual(PriceVerification.freshness(of: planVerified(daysAgo: 10)), .aging)
        XCTAssertEqual(PriceVerification.freshness(of: planVerified(daysAgo: 40)), .stale)
        let neverVerified = ProductRecord(id: "nv", name: "NV", kind: .mobilePlan, category: "X",
                                          monthlyPriceSEK: 100, verifiedAt: nil, verification: .unverified)
        XCTAssertEqual(PriceVerification.freshness(of: neverVerified), .unknown)
    }

    func testCampaignStatusExpiry() {
        let cal = Calendar.current
        let expired = makePlan(monthly: 399, ordinary: 599)
            .withCampaignWindow(start: cal.date(byAdding: .day, value: -60, to: Date())!,
                                end: cal.date(byAdding: .day, value: -10, to: Date())!)
        XCTAssertEqual(PriceVerification.campaignStatus(expired), .expired)
        XCTAssertFalse(PriceVerification.isActiveOffer(expired))

        let endsSoon = makePlan(monthly: 399, ordinary: 599)
            .withCampaignWindow(start: cal.date(byAdding: .day, value: -30, to: Date())!,
                                end: cal.date(byAdding: .day, value: 5, to: Date())!)
        XCTAssertEqual(PriceVerification.campaignStatus(endsSoon), .endsSoon)
        XCTAssertTrue(PriceVerification.isActiveOffer(endsSoon))

        let active = makePlan(monthly: 379, ordinary: 599)
            .withCampaignWindow(start: cal.date(byAdding: .day, value: -10, to: Date())!,
                                end: cal.date(byAdding: .day, value: 60, to: Date())!)
        XCTAssertEqual(PriceVerification.campaignStatus(active), .activeCampaign)

        let plain = makePlan(monthly: 299)
        XCTAssertEqual(PriceVerification.campaignStatus(plain), .noCampaign)
    }

    // MARK: - Diff

    func testDiffDetectsChanges() {
        let old = [
            makePlan(id: "a", name: "A", monthly: 299),
            makePlan(id: "b", name: "B", monthly: 599, ordinary: 699, binding: 24),
            makePlan(id: "c", name: "C", monthly: 100),
        ]
        let new = [
            makePlan(id: "a", name: "A", monthly: 349),
            makePlan(id: "b", name: "B", monthly: 549, ordinary: 649, binding: 24),
            makePlan(id: "d", name: "D", monthly: 199),
        ]
        let changes = PriceVerification.diff(old: old, new: new)
        XCTAssertTrue(changes.contains { $0.productId == "a" && $0.field == .monthlyPrice && $0.oldValue == "299 kr" && $0.newValue == "349 kr" })
        XCTAssertTrue(changes.contains { $0.productId == "b" && $0.field == .ordinaryPrice })
        XCTAssertTrue(changes.contains { $0.productId == "d" && $0.field == .added })
        XCTAssertTrue(changes.contains { $0.productId == "c" && $0.field == .removed })
        XCTAssertFalse(changes.contains { $0.productId == "b" && $0.field == .monthlyPrice && $0.oldValue != "599 kr" })
    }
}

// Small test helpers for immutable records.
extension ProductRecord {
    func withVerifiedAt(_ date: Date) -> ProductRecord {
        ProductRecord(
            id: id, name: name, kind: kind, category: category, brand: brand,
            monthlyPriceSEK: monthlyPriceSEK, ordinaryMonthlyPriceSEK: ordinaryMonthlyPriceSEK,
            upfrontCostSEK: upfrontCostSEK, bindingMonths: bindingMonths,
            campaignMonths: campaignMonths, cashPriceSEK: cashPriceSEK, dataGB: dataGB,
            unlimitedData: unlimitedData, speedMbit: speedMbit,
            includedServices: includedServices, highlights: highlights,
            campaignStart: campaignStart, campaignEnd: campaignEnd,
            eligibilityNotes: eligibilityNotes, mandatoryCharges: mandatoryCharges,
            sourceURL: sourceURL, sourceName: sourceName,
            verifiedAt: date, verification: verification, tags: tags
        )
    }

    func withCampaignWindow(start: Date, end: Date) -> ProductRecord {
        ProductRecord(
            id: id, name: name, kind: kind, category: category, brand: brand,
            monthlyPriceSEK: monthlyPriceSEK, ordinaryMonthlyPriceSEK: ordinaryMonthlyPriceSEK,
            upfrontCostSEK: upfrontCostSEK, bindingMonths: bindingMonths,
            campaignMonths: campaignMonths, cashPriceSEK: cashPriceSEK, dataGB: dataGB,
            unlimitedData: unlimitedData, speedMbit: speedMbit,
            includedServices: includedServices, highlights: highlights,
            campaignStart: start, campaignEnd: end,
            eligibilityNotes: eligibilityNotes, mandatoryCharges: mandatoryCharges,
            sourceURL: sourceURL, sourceName: sourceName,
            verifiedAt: verifiedAt, verification: verification, tags: tags
        )
    }
}
