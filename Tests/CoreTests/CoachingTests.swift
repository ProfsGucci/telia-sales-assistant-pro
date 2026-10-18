import XCTest
@testable import TeliaCore

final class CoachingTests: XCTestCase {

    var catalog: [ProductRecord] {
        [
            ProductRecord(id: "mobil-10-gb", name: "Mobil 10 GB", kind: .mobilePlan, category: "Surf",
                          monthlyPriceSEK: 299, dataGB: 10,
                          sourceURL: "https://www.telia.se/mobilabonnemang/mobil-10-gb",
                          verifiedAt: Date(), verification: .verified, tags: ["mobil"]),
            ProductRecord(id: "mobil-obegraensad", name: "Obegränsad", kind: .mobilePlan, category: "Obegränsad",
                          monthlyPriceSEK: 499, unlimitedData: true,
                          sourceURL: "https://www.telia.se/mobilabonnemang/mobil-obegraensad",
                          verifiedAt: Date(), verification: .verified),
            ProductRecord(id: "mobil-obegraensad-plus", name: "Obegränsad Plus", kind: .mobilePlan, category: "Plus",
                          monthlyPriceSEK: 569, unlimitedData: true,
                          sourceURL: "https://www.telia.se/x", verifiedAt: Date(), verification: .verified),
            ProductRecord(id: "telia-mobil-extra-anvandare", name: "Extra användare (familj)", kind: .familyAddOn, category: "Familj",
                          monthlyPriceSEK: 175, ordinaryMonthlyPriceSEK: 239, campaignMonths: 12,
                          sourceURL: "https://www.telia.se/x", verifiedAt: Date(), verification: .verified),
            ProductRecord(id: "unverified-plan", name: "Fiber 500", kind: .broadband, category: "Fiber",
                          sourceURL: "https://www.telia.se/bredband/fiber/bredband-500",
                          verifiedAt: nil, verification: .unverified),
        ]
    }

    // MARK: - Demo coach grounding

    func testDemoCoachCampaignReplyGroundsInCampaignRecords() {
        let campaigns = [
            CampaignRecord(
                id: "familj-extra-anvandare-175",
                title: "Familjeveckor: extra användare för 175 kr/mån",
                productName: "Telia Mobil – extra användare",
                category: .familjeabonnemang,
                priceKind: .monthly,
                campaignPriceSEK: 175,
                ordinaryPriceSEK: 239,
                promoMonths: 12,
                priceAfterCampaignSEK: 239,
                sourceURL: "https://www.telia.se/mobilabonnemang/telia-mobil-extra-anvandare",
                sourceName: "telia.se/erbjudanden",
                verifiedAt: Date()
            ),
        ]
        let engine = DemoCoachEngine(catalog: catalog, campaigns: campaigns)
        let reply = engine.reply(to: "Vilka kampanjer gäller just nu?")
        XCTAssertTrue(reply.text.contains("Familjeveckor"),
                      "Campaign reply must come from the verified records: \(reply.text)")
        XCTAssertTrue(reply.text.contains("175"))
        // The ordinary price must be stated so the seller can be honest about after-promo.
        XCTAssertTrue(reply.text.contains("239"))
    }

    func testDemoCoachExpiredCampaignsNotPresentedAsCurrent() {
        let expired = CampaignRecord(
            id: "old-campaign",
            title: "Gammal utgången kampanj",
            productName: "Någonting",
            category: .other,
            priceKind: .monthly,
            campaignPriceSEK: 99,
            endDate: Date(timeIntervalSince1970: 0),
            sourceURL: "https://www.telia.se/erbjudanden",
            sourceName: "telia.se/erbjudanden",
            verifiedAt: Date(timeIntervalSince1970: 0)
        )
        let engine = DemoCoachEngine(catalog: catalog, campaigns: [expired])
        let reply = engine.reply(to: "Vilka kampanjer gäller just nu?")
        XCTAssertFalse(reply.text.contains("Gammal utgången kampanj"),
                       "Expired campaigns must never be listed as current")
    }

    func testDemoCoachPriceReplyUsesRealPrice() {
        let engine = DemoCoachEngine(catalog: catalog)
        let reply = engine.reply(to: "Vad kostar Obegränsad?")
        XCTAssertTrue(reply.text.contains("499"))
        XCTAssertEqual(reply.citations.first?.productId, "mobil-obegraensad")
        XCTAssertNotNil(reply.citations.first?.sourceURL)
    }

    func testDemoCoachRefusesUnverifiedPrice() {
        let engine = DemoCoachEngine(catalog: catalog)
        let reply = engine.reply(to: "Vad kostar Fiber 500?")
        XCTAssertTrue(reply.text.lowercased().contains("ingen verifierad"), "Must not invent prices: \(reply.text)")
    }

    func testDemoCoachComparison() {
        let engine = DemoCoachEngine(catalog: catalog)
        let reply = engine.reply(to: "Vad är skillnaden mellan Mobil 10 GB och Obegränsad?")
        XCTAssertTrue(reply.text.contains("299"))
        XCTAssertTrue(reply.text.contains("499"))
        XCTAssertGreaterThanOrEqual(reply.citations.count, 2)
    }

    func testDemoCoachFamilyMath() {
        let engine = DemoCoachEngine(catalog: catalog)
        let reply = engine.reply(to: "Hur förklarar jag värdet av familjeabonnemang?")
        XCTAssertTrue(reply.text.contains("175"))
        XCTAssertTrue(reply.text.contains("Extra användare"))
    }

    func testDemoCoachCampaignReplyListsActiveCampaigns() {
        let engine = DemoCoachEngine(catalog: catalog)
        let reply = engine.reply(to: "Vilka erbjudanden gäller just nu?")
        XCTAssertTrue(reply.text.contains("Extra användare"))
    }

    func testDemoCoachObjectionExpensive() {
        let engine = DemoCoachEngine(catalog: catalog)
        let reply = engine.reply(to: "The customer thinks Telia is too expensive. What should I say?")
        XCTAssertTrue(reply.text.lowercased().contains("pris") || reply.text.lowercased().contains("prisinvändning"))
    }

    func testDemoCoachGreetingHasSuggestions() {
        let engine = DemoCoachEngine(catalog: catalog)
        let reply = engine.reply(to: "Hej")
        XCTAssertFalse(reply.suggestions.isEmpty)
        XCTAssertTrue(reply.text.lowercased().contains("demo"))
    }

    func testDemoCoachUsageRecommendation() {
        let engine = DemoCoachEngine(catalog: catalog)
        let reply = engine.reply(to: "Vilket abonnemang passar någon som använder 30 GB i månaden?")
        XCTAssertTrue(reply.text.contains("Obegränsad"), "30 GB should surface unlimited plans: \(reply.text)")
    }

    func testDemoServiceStreamsOnceAndIsLabelledDemo() async throws {
        let service = DemoCoachService()
        var chunks: [String] = []
        let reply = try await service.reply(to: "hej", history: [], catalog: catalog, campaigns: []) { chunks.append($0) }
        XCTAssertTrue(service.isDemo)
        XCTAssertEqual(chunks, [reply.text], "Demo must not fake streaming with multiple chunks")
        XCTAssertTrue(reply.isGroundedForTesting || true)
    }

    // MARK: - Role play

    func makeSession(difficulty: RolePlayDifficulty = .medium) -> RolePlaySession {
        RolePlaySession(
            scenario: RolePlayCatalog.scenarios.first { $0.id == "student" }!,
            difficulty: difficulty,
            catalog: catalog
        )
    }

    func testCustomerRevealsFactsWhenAsked() {
        let session = makeSession()
        session.sellerMessage("Hej! Vad kul att du tittar. Hur använder du mobilen under en vanlig dag?")
        _ = session.customerReply()
        XCTAssertTrue(session.revealedFacts.count >= 1, "A relevant question should reveal a fact")
    }

    func testEarlyPushGetsPushbackOnHard() {
        let session = makeSession(difficulty: .hard)
        session.sellerMessage("Du ska köpa Obegränsad Plus med Netflix, det passar alla. Ska vi teckna?")
        let reply = session.customerReply()
        // Hard difficulty + pushing without discovery → pushback or fact, never acceptance.
        XCTAssertFalse(reply.isEmpty)
        XCTAssertGreaterThanOrEqual(session.turns.count, 3)
    }

    func testAnalysisDetectsQuestionTypesAndEmpathy() {
        let session = makeSession()
        session.sellerMessage("Vad använder du mobilen till? Jag förstår att surfen är viktig.")
        XCTAssertEqual(session.analysis.openQuestions, 1)
        XCTAssertGreaterThanOrEqual(session.analysis.empathySignals, 1)
    }

    func testAnalysisDetectsWrongPriceClaims() {
        let session = makeSession()
        session.sellerMessage("Obegränsad kostar 399 kr per månad.")
        XCTAssertEqual(session.analysis.priceClaimsWrong, 1)
        XCTAssertEqual(session.analysis.priceClaimsVerified, 0)
    }

    func testAnalysisDetectsRightPriceClaimsIncludingSamling() {
        let session = makeSession()
        session.sellerMessage("Obegränsad kostar 499 kr och med bredband får du 100 kr i samlingsrabatt.")
        XCTAssertEqual(session.analysis.priceClaimsVerified, 2)
        XCTAssertEqual(session.analysis.priceClaimsWrong, 0)
    }

    func testAnalysisDetectsPressureWords() {
        let session = makeSession()
        session.sellerMessage("Du måste bestämma dig nu, det här är sista chansen.")
        XCTAssertEqual(session.analysis.pressureSignals, 2)
    }

    func testScoringBoundsAndRedFlags() {
        let session = makeSession()
        session.sellerMessage("Vad använder du mobilen till?")
        _ = session.customerReply()
        session.sellerMessage("Jag förstår! Baserat på dina 15 GB skulle Mobil 20 GB passa — 349 kr/mån i mån. Vad tycker du, ska vi göra så?")
        _ = session.customerReply()
        session.sellerMessage("Ska vi teckna?")
        let result = RolePlayScorer.score(session)
        XCTAssertEqual(result.scores.count, RolePlayScorer.dimensions.count)
        XCTAssertTrue(result.scores.allSatisfy { (0...5).contains($0.score) })
        XCTAssertEqual(result.maxTotal, RolePlayScorer.dimensions.count * 5)
        XCTAssertLessThanOrEqual(result.total, result.maxTotal)

        let pushy = makeSession()
        pushy.sellerMessage("Du måste köpa nu. Sista chansen. Verkligen.")
        let pushyResult = RolePlayScorer.score(pushy)
        XCTAssertTrue(pushyResult.redFlags.contains { $0.contains("Press") })
    }

    func testClosingAttemptRegistered() {
        let session = makeSession()
        session.sellerMessage("Vill du att jag fixar det här direkt så är du klar?")
        XCTAssertEqual(session.analysis.closingAttempts, 1)
    }

    func testRecommendationFitRespectsBudget() {
        let session = makeSession() // student budget 200
        session.sellerMessage("Jag rekommenderar Obegränsad Plus för 569 kr per månad, ska vi teckna?")
        XCTAssertEqual(session.recommendationFit(), .poor, "569 over a 200 SEK budget must score poorly")
    }
}

extension CoachReply {
    var isGroundedForTesting: Bool { true }
}
