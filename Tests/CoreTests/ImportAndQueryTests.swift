import XCTest
@testable import TeliaCore

final class ImportAndQueryTests: XCTestCase {

    func csv(_ content: String) -> Data { Data(content.utf8) }

    // MARK: - CSV import

    func testCSVParsesFullRow() throws {
        let csvText = """
        name,kind,category,monthlyPrice,ordinaryPrice,bindingMonths,campaignMonths,dataGB,unlimitedData,speedMbit,sourceUrl,sourceName,verifiedAt,verification,notes,services,tags
        Mobil 30 GB,mobilePlan,Surf,349,,0,,30,no,,https://www.telia.se/test,telia.se,2026-10-18,verified,"En notis","Fri surf inom Sverige",mobil;surf
        """
        let (snapshot, report) = try PriceImport.parseCSV(csv(csvText))
        XCTAssertEqual(report.importedCount, 1)
        XCTAssertEqual(report.skippedCount, 0)
        let p = try XCTUnwrap(snapshot.products.first)
        XCTAssertEqual(p.name, "Mobil 30 GB")
        XCTAssertEqual(p.kind, .mobilePlan)
        XCTAssertEqual(p.monthlyPriceSEK, 349)
        XCTAssertEqual(p.dataGB, 30)
        XCTAssertEqual(p.verification, .verified)
        XCTAssertEqual(p.sourceURL, "https://www.telia.se/test")
        XCTAssertEqual(p.eligibilityNotes, "En notis")
        XCTAssertEqual(p.includedServices, ["Fri surf inom Sverige"])
        XCTAssertEqual(p.tags, ["mobil", "surf"])
    }

    func testCSVSwedishNumberFormat() throws {
        // Swedish decimal comma inside a quoted cell: "349,50" → 349.50
        let valid = "name,monthlyPrice,sourceUrl,verification\nTest,\"349,50\",https://x.se,unverified"
        let (snapshot, _) = try PriceImport.parseCSV(csv(valid))
        assertClose(snapshot.products.first?.monthlyPriceSEK ?? 0, 349.5, accuracy: 0.001)
    }

    func testCSVSkipsRowsWithoutNameAndReports() throws {
        let csvText = """
        name,monthlyPrice
        ,100
        Valid Row,200
        """
        let (snapshot, report) = try PriceImport.parseCSV(csv(csvText))
        XCTAssertEqual(snapshot.products.count, 1)
        XCTAssertEqual(report.importedCount, 1)
        XCTAssertEqual(report.skippedCount, 1)
        XCTAssertTrue(report.errors.first?.contains("Rad 2") == true)
    }

    func testCSVDowngradesVerifiedWithoutSource() throws {
        let csvText = """
        name,monthlyPrice,verification
        Test,299,verified
        """
        let (snapshot, _) = try PriceImport.parseCSV(csv(csvText))
        XCTAssertEqual(snapshot.products.first?.verification, .imported)
    }

    func testJSONRoundTrip() throws {
        let plan = ProductRecord(
            id: "x", name: "X", kind: .broadband, category: "Fiber",
            monthlyPriceSEK: 379, ordinaryMonthlyPriceSEK: 599, bindingMonths: 12,
            campaignMonths: nil, cashPriceSEK: nil, speedMbit: 150,
            mandatoryCharges: [ChargeItem(name: "Faktura", amountSEK: 59, recurring: true)],
            sourceURL: "https://www.telia.se/bredband", verifiedAt: Date(), verification: .verified
        )
        let snapshot = CatalogSnapshot(products: [plan], generatedAt: Date(), sourceNote: "test")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(snapshot)

        let (parsed, report) = try PriceImport.parseJSON(data)
        XCTAssertEqual(report.importedCount, 1)
        XCTAssertEqual(parsed.products.first?.monthlyPriceSEK, 379)
        XCTAssertEqual(parsed.products.first?.mandatoryCharges.first?.amountSEK, 59)
    }

    func testUnsupportedFormatThrows() {
        XCTAssertThrowsError(try PriceImport.parse(data: Data("x".utf8), filename: "file.txt"))
    }

    // MARK: - Query

    var sampleCatalog: [ProductRecord] {
        [
            ProductRecord(id: "a", name: "Mobil 10 GB", kind: .mobilePlan, category: "Surf",
                          monthlyPriceSEK: 299, dataGB: 10,
                          sourceURL: "https://x.se", verifiedAt: Date(), verification: .verified,
                          tags: ["mobil"]),
            ProductRecord(id: "b", name: "Obegränsad", kind: .mobilePlan, category: "Obegränsad",
                          monthlyPriceSEK: 499, unlimitedData: true,
                          sourceURL: "https://x.se", verifiedAt: Date(), verification: .verified,
                          tags: ["mobil", "obegraensad"]),
            ProductRecord(id: "c", name: "Obegränsad Plus Netflix", kind: .mobilePlan, category: "Plus",
                          monthlyPriceSEK: 629, ordinaryMonthlyPriceSEK: 699, bindingMonths: 24,
                          campaignMonths: 12, unlimitedData: true,
                          sourceURL: "https://x.se", verifiedAt: Date(), verification: .verified,
                          tags: ["netflix"]),
            ProductRecord(id: "d", name: "Bredband via 5G", kind: .broadband, category: "5G",
                          monthlyPriceSEK: 249, ordinaryMonthlyPriceSEK: 399, bindingMonths: 24,
                          campaignMonths: 24,
                          sourceURL: "https://x.se", verifiedAt: Date(), verification: .verified,
                          tags: ["bredband"]),
        ]
    }

    func testSearchFindsByName() {
        let hits = CatalogQuery.search(sampleCatalog, query: "obegränsad")
        XCTAssertTrue(hits.contains { $0.id == "b" || $0.id == "c" })
        XCTAssertFalse(hits.contains { $0.id == "d" })
    }

    func testSearchSwedishWords() {
        let hits = CatalogQuery.search(sampleCatalog, query: "netflix abonnemang")
        XCTAssertTrue(hits.contains { $0.id == "c" })
    }

    func testFilterByKindAndPrice() {
        var filters = CatalogQuery.Filters()
        filters.kinds = [.broadband]
        let hits = CatalogQuery.search(sampleCatalog, query: "", filters: filters)
        XCTAssertEqual(hits.map(\.id), ["d"])

        filters = CatalogQuery.Filters()
        filters.maxMonthlySEK = 300
        let cheap = CatalogQuery.search(sampleCatalog, query: "", filters: filters)
        XCTAssertEqual(cheap.map(\.id), ["a", "d"], "249 and 299 are both under 300")
    }

    func testFilterUnboundAndUnlimited() {
        var f = CatalogQuery.Filters()
        f.onlyUnbound = true
        f.requireUnlimitedData = true
        let hits = CatalogQuery.search(sampleCatalog, query: "", filters: f)
        XCTAssertEqual(hits.map(\.id), ["b"])
    }

    func testSortByPrice() {
        let asc = CatalogQuery.search(sampleCatalog, query: "", sort: .priceAsc)
        XCTAssertEqual(asc.first?.id, "d", "249 is the cheapest")
        let desc = CatalogQuery.search(sampleCatalog, query: "", sort: .priceDesc)
        XCTAssertEqual(desc.first?.id, "c", "629 is the priciest")
    }

    func testExpiredCampaignsExcludedFromSearch() {
        let cal = Calendar.current
        let expired = ProductRecord(
            id: "e", name: "Gammal kampanj", kind: .mobilePlan, category: "Kampanj",
            monthlyPriceSEK: 199, ordinaryMonthlyPriceSEK: 399,
            campaignStart: cal.date(byAdding: .day, value: -90, to: Date()),
            campaignEnd: cal.date(byAdding: .day, value: -30, to: Date()),
            sourceURL: "https://x.se", verifiedAt: Date(), verification: .verified
        )
        let hits = CatalogQuery.search([expired] + sampleCatalog, query: "gammal")
        XCTAssertFalse(hits.contains { $0.id == "e" }, "Expired promotions must never be shown as active offers")
    }

    // MARK: - Retrieval & recommendations

    func testRetrieveWithGBIntent() {
        let hits = CatalogQuery.retrieve(message: "Vilket abonnemang passar någon som använder 30 GB i månaden?", in: sampleCatalog, topK: 3)
        XCTAssertTrue(hits.contains { $0.id == "b" || $0.id == "c" }, "Unlimited plans should rank for 30 GB usage")
    }

    func testRecommendFor30GBPrefersBoundedThenUnlimited() {
        let recs = CatalogQuery.recommend(dataGB: 30, in: sampleCatalog)
        XCTAssertFalse(recs.isEmpty)
        XCTAssertTrue(recs.contains { $0.unlimitedData })
    }

    func testRetrieveByName() {
        let hits = CatalogQuery.retrieve(message: "Vad kostar bredband via 5g?", in: sampleCatalog)
        XCTAssertEqual(hits.first?.id, "d")
    }
}
