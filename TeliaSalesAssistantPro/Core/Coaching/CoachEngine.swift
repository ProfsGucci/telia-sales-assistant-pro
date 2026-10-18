import Foundation

// MARK: - Conversation models

public struct ChatCitation: Codable, Hashable, Identifiable, Sendable {
    public var id: String { productId }
    public let productId: String
    public let productName: String
    public let sourceURL: String?
    public let priceSEK: Double?
    public let verifiedAt: Date?

    public init(productId: String, productName: String, sourceURL: String?, priceSEK: Double?, verifiedAt: Date?) {
        self.productId = productId
        self.productName = productName
        self.sourceURL = sourceURL
        self.priceSEK = priceSEK
        self.verifiedAt = verifiedAt
    }
}

public enum MessageRole: String, Codable, Sendable {
    case user
    case assistant
    case system
}

public struct ChatMessage: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public let role: MessageRole
    public var text: String
    public let date: Date
    public var citations: [ChatCitation]
    /// True when the assistant message could not be delivered and can be retried.
    public var failed: Bool
    /// True when this reply was produced locally by the demo engine.
    public var isDemo: Bool
    public var saved: Bool

    public init(id: UUID = UUID(), role: MessageRole, text: String, date: Date = Date(),
                citations: [ChatCitation] = [], failed: Bool = false, isDemo: Bool = false, saved: Bool = false) {
        self.id = id
        self.role = role
        self.text = text
        self.date = date
        self.citations = citations
        self.failed = failed
        self.isDemo = isDemo
        self.saved = saved
    }
}

public struct Conversation: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public var title: String
    public var messages: [ChatMessage]
    public var createdAt: Date
    public var updatedAt: Date

    public init(id: UUID = UUID(), title: String, messages: [ChatMessage] = [],
                createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.title = title
        self.messages = messages
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - Service protocol

public struct CoachReply: Sendable {
    public let text: String
    public let citations: [ChatCitation]
    public let suggestions: [String]

    public init(text: String, citations: [ChatCitation] = [], suggestions: [String] = []) {
        self.text = text
        self.citations = citations
        self.suggestions = suggestions
    }
}

public protocol CoachService {
    var name: String { get }
    var isDemo: Bool { get }
    /// Produces one complete reply. `streamChunk` is called with text deltas when
    /// the backend genuinely streams; the demo engine calls it once.
    /// `campaigns` carries the currently cached Kampanj Center records so every
    /// campaign answer stays grounded in verified data.
    func reply(
        to message: String,
        history: [ChatMessage],
        catalog: [ProductRecord],
        campaigns: [CampaignRecord],
        streamChunk: @escaping (String) -> Void
    ) async throws -> CoachReply
}

public enum CoachError: LocalizedError, Equatable {
    case notConfigured
    case badURL
    case network(String)
    case server(Int)
    case rateLimited
    case cancelled
    case emptyResponse

    public var errorDescription: String? {
        switch self {
        case .notConfigured: return "Ingen AI-tjänst är konfigurerad."
        case .badURL: return "Ogiltig serveradress."
        case .network(let m): return "Nätverksfel: \(m)"
        case .server(let code): return "Servern svarade med felkod \(code)."
        case .rateLimited: return "För många förfrågningar – vänta en stund."
        case .cancelled: return "Avbruten."
        case .emptyResponse: return "Tomt svar från servern."
        }
    }
}

// MARK: - Demo coach (offline, grounded, clearly labelled)

/// A deterministic, fully local coach. It answers from the verified catalog only and
/// clearly labels itself as demo. It never invents prices: when it lacks data it says so
/// and points to the official source.
public struct DemoCoachEngine {
    public let catalog: [ProductRecord]
    /// Verified campaign records from Kampanj Center, when available. The demo
    /// coach answers campaign questions from these and never invents campaign
    /// prices, dates or terms.
    public let campaigns: [CampaignRecord]

    public init(catalog: [ProductRecord], campaigns: [CampaignRecord] = []) {
        self.catalog = catalog
        self.campaigns = campaigns
    }

    // MARK: Intent

    public enum Intent {
        case greeting
        case priceOf(ProductRecord)
        case compare([ProductRecord])
        case recommendForUsage([ProductRecord])
        case familyValue([ProductRecord])
        case campaigns([ProductRecord])
        case objectionExpensive
        case objectionBinding
        case objectionCompetitor
        case briefing
        case rolePlay
        case quiz
        case fallback
    }

    public func detectIntent(_ message: String) -> Intent {
        let m = message.lowercased()
        let swedish = m.contains("ä") || m.contains("å") || m.contains("ö")
            || m.contains(" abonnemang") || m.contains(" säljer") || m.contains(" kunden")
        let lang = swedish ? "sv" : "en"

        if isGreeting(m, lang: lang) { return .greeting }

        let retrieved = CatalogQuery.retrieve(message: message, in: catalog, topK: 3)
        let wantsComparison = m.contains("skillnad") || m.contains("jämför") || m.contains("compare")
            || m.contains("difference") || m.contains(" vs") || m.contains(" eller ")
        if wantsComparison, retrieved.count >= 2 { return .compare(Array(retrieved.prefix(3))) }

        if m.contains("familj") || m.contains("family") {
            let addOns = catalog.filter { $0.kind == .familyAddOn }
            let mains = catalog.filter { $0.kind == .mobilePlan && $0.unlimitedData }.prefix(1)
            if !addOns.isEmpty || !mains.isEmpty {
                return .familyValue(Array(mains) + Array(addOns.prefix(1)))
            }
        }

        if m.contains("kampanj") || m.contains("erbjudande") || m.contains("campaign")
            || m.contains("offer") || m.contains("rabatt") || m.contains("deal") {
            return .campaigns(activeCampaigns())
        }

        if m.contains("dyr") || m.contains("expensive") || m.contains("för mycket")
            || m.contains("billigare") || m.contains("too much") { return .objectionExpensive }
        if m.contains("bindningstid") || m.contains("bindning") || m.contains("contract")
            || m.contains("låst") { return .objectionBinding }
        if m.contains("tre ") || m.contains("tele2") || m.contains("telenor") || m.contains("comviq")
            || m.contains("hallon") || m.contains("competitor") || m.contains("konkurrent") {
            return .objectionCompetitor
        }
        if m.contains("role-play") || m.contains("roleplay") || m.contains("rollspel") { return .rolePlay }
        if m.contains("quiz") || m.contains("testa mig") || m.contains("fråga mig") { return .quiz }

        if let gb = dataIntentGB(m), gb > 0 {
            let recs = CatalogQuery.recommend(dataGB: gb, in: catalog)
            if !recs.isEmpty { return .recommendForUsage(recs) }
        }

        if m.contains("briefing") || m.contains("förbered") || m.contains("pass")
            || m.contains("shift") || m.contains("sammanfatt") { return .briefing }

        if let first = retrieved.first {
            let asksPrice = m.contains("pris") || m.contains("kostar") || m.contains("price")
                || m.contains("cost") || m.contains("hur mycket") || m.contains("mån")
            if asksPrice || retrieved.count == 1 { return .priceOf(first) }
        }

        if !retrieved.isEmpty { return .priceOf(retrieved[0]) }
        return .fallback
    }

    func isGreeting(_ m: String, lang: String) -> Bool {
        let words = Set(m.split(separator: " ").map(String.init))
        let greetings: Set<String> = ["hej", "hejsan", "hallå", "tja", "hej!", "hi", "hello", "hey", "godmorgon", "godkväll"]
        _ = lang
        return !words.isEmpty && words.subtracting(greetings).isEmpty
    }

    func dataIntentGB(_ m: String) -> Double? {
        guard let regex = try? NSRegularExpression(pattern: #"(\d+(?:[.,]\d+)?)\s*(gb|gig)"#, options: [.caseInsensitive]) else { return nil }
        guard let r = regex.firstMatch(in: m, range: NSRange(m.startIndex..., in: m)),
              let range = Range(r.range(at: 1), in: m) else { return nil }
        return Double(m[range].replacingOccurrences(of: ",", with: "."))
    }

    func activeCampaigns() -> [ProductRecord] {
        catalog.filter { PriceVerification.campaignStatus($0) == .activeCampaign || PriceVerification.campaignStatus($0) == .endsSoon }
            .prefix(6).map { $0 }
    }

    // MARK: Reply

    public func reply(to message: String) -> CoachReply {
        switch detectIntent(message) {
        case .greeting:
            return CoachReply(
                text: "Hej! Jag är din säljcoach i demoläge. Jag svarar utifrån den verifierade produktkatalogen – fråga mig om priser, jämförelser, invändningar eller be om en briefing inför passet.",
                suggestions: ["Ge mig en briefing inför passet", "Vilka kampanjer gäller just nu?", "Hur hanterar jag prisinvändningar?"]
            )

        case .priceOf(let p):
            return priceReply(p)

        case .compare(let products):
            return compareReply(products)

        case .recommendForUsage(let recs):
            return recommendationReply(recs)

        case .familyValue(let products):
            return familyReply(products)

        case .campaigns(let products):
            return campaignReply(products)

        case .objectionExpensive:
            return objectionExpensiveReply()

        case .objectionBinding:
            return objectionBindingReply()

        case .objectionCompetitor:
            return objectionCompetitorReply()

        case .briefing:
            return briefingReply()

        case .rolePlay:
            return CoachReply(
                text: "Rollspelet hittar du i fliken Rollspel – där kan du välja scenario, svårighetsgrad och produktkategori. Jag spelar kunden och poängsätter samtalet efteråt.",
                suggestions: ["Rollspel: budgetmedveten student", "Rollspel: familj med flera abonnemang"]
            )

        case .quiz:
            return CoachReply(
                text: "Quiz och lektioner hittar du i Akademin. Där kan jag även återkomma med flashcards efter spaced repetition – perfekt innan ett pass.",
                suggestions: ["Ge mig produktnyheter", "Vad är skillnaden på Obegränsad och Obegränsad Plus?"]
            )

        case .fallback:
            return CoachReply(
                text: "Jag är en lokal demoläge-coach och förstod inte riktigt. Prova att fråga om ett specifikt abonnemang, en jämförelse, en invändning eller be om en briefing. Konfigurerar du en AI-backend i Inställningar får du full coachning med fria följdfrågor.",
                suggestions: ["Briefing inför passet", "Vad kostar Obegränsad Plus?", "Hur säljer jag familjeabonnemang?"]
            )
        }
    }

    // MARK: Reply builders

    func priceReply(_ p: ProductRecord) -> CoachReply {
        guard let monthly = CostCalculator.currentMonthly(p) else {
            return CoachReply(
                text: "Jag har ingen verifierad prisinformation för \(p.name) just nu. Kontrollera alltid aktuellt pris på telia.se innan du citerar det till kunden.",
                citations: citation(for: p)
            )
        }
        var text = ""
        if PriceVerification.campaignStatus(p) == .activeCampaign, let ordinary = p.ordinaryMonthlyPriceSEK {
            text += "\(p.name) ligger just nu på kampanjpris \(intSEK(monthly)) kr/mån (ord. pris \(intSEK(ordinary)) kr/mån)."
        } else {
            text += "\(p.name) kostar \(intSEK(monthly)) kr/mån."
        }
        if let binding = p.bindingMonths, binding > 0 {
            text += " \(binding) mån bindningstid."
        } else if p.kind == .mobilePlan || p.kind == .broadband {
            text += " Ingen bindningstid."
        }
        if !p.dataLabel.isEmpty { text += " \(p.dataLabel).\(p.unlimitedData ? "" : "")" }
        if !p.includedServices.isEmpty {
            text += " Ingår: \(p.includedServices.joined(separator: ", "))."
        }
        if p.verification != .verified {
            text += "\n\nObservera: priset är markerat \(p.verification.label.lowercased()) – dubbelkolla källan."
        }
        return CoachReply(
            text: text,
            citations: citation(for: p),
            suggestions: ["Jämför med andra abonnemang", "Hur jag presenterar priset till kunden?"]
        )
    }

    func compareReply(_ products: [ProductRecord]) -> CoachReply {
        let rows = products.compactMap { p -> String? in
            guard let m = CostCalculator.currentMonthly(p) else { return nil }
            let data = p.dataLabel.isEmpty ? "—" : p.dataLabel
            let binding = p.isUnbound ? "obundet" : "\(p.bindingMonths ?? 0) mån"
            return "• \(p.name) – \(intSEK(m)) kr/mån, \(data), \(binding)"
        }
        let text = """
        Så här skiljer sig produkterna åt just nu:

        \(rows.joined(separator: "\n"))

        Tips i samtalet: utgå från kundens surfanvändning och vilket värde streaming, surfmängd eller obundenhet har för dem – inte från prislistan.
        """
        return CoachReply(
            text: text,
            citations: products.flatMap { citation(for: $0) },
            suggestions: ["Vilket passar en familj?", "Vilket är billigast per GB?"]
        )
    }

    func recommendationReply(_ recs: [ProductRecord]) -> CoachReply {
        let lines = recs.compactMap { p -> String? in
            guard let m = CostCalculator.currentMonthly(p) else { return nil }
            return "• \(p.name) – \(intSEK(m)) kr/mån (\(p.dataLabel.isEmpty ? "tjänst" : p.dataLabel))"
        }
        return CoachReply(
            text: """
            Utifrån surfbehovet skulle jag titta på:

            \(lines.joined(separator: "\n"))

            Kartlägg först: hur mycket surf använder kunden idag, streamar de på mobilt nät och reser de mycket? Obegränsad surf säljs bäst på trygghet – aldrig på gigabyte.
            """,
            citations: recs.flatMap { citation(for: $0) },
            suggestions: ["Hur frågar jag om surfvanor?", "Vad kostar obegränsad surf?"]
        )
    }

    func familyReply(_ products: [ProductRecord]) -> CoachReply {
        let main = products.first { $0.kind == .mobilePlan && $0.unlimitedData }
        let addOn = products.first { $0.kind == .familyAddOn } ?? catalog.first { $0.kind == .familyAddOn }
        var text = "Familjeabonnemang: köp ett Obegränsad Plus-abonnemang som huvudabonnemang och lägg till familjemedlemmar som extra användare."
        if let addOn, let addOnPrice = CostCalculator.currentMonthly(addOn) {
            text += " Extra användare kostar just nu \(intSEK(addOnPrice)) kr/mån per person"
            if let ordinary = addOn.ordinaryMonthlyPriceSEK, ordinary > addOnPrice {
                text += " (ord. \(intSEK(ordinary)) kr/mån)"
            }
            text += "."
        }
        if let main, let mainPrice = CostCalculator.currentMonthly(main) {
            text += " Huvudabonnemanget \(main.name) ligger på \(intSEK(mainPrice)) kr/mån."
            if let addOn, let addOnPrice = CostCalculator.currentMonthly(addOn) {
                let perPerson = (mainPrice + addOnPrice) / 2
                text += " För en familj på två blir det ca \(intSEK(perPerson)) kr/mån per person – ofta billigare än två separata abonnemang, och allt kommer på samma faktura."
            }
        }
        text += "\n\nSälj värdet: eget nummer och obegränsad surf var, en faktura, och enklare vardag. Undvik att pressa familjer som inte behöver obegränsat – räkna istället på deras faktiska behov."
        return CoachReply(
            text: text,
            citations: products.flatMap { citation(for: $0) },
            suggestions: ["Räkna på en familj med 4 personer", "Hur bemöter jag 'vi har redan egna abonnemang'?"]
        )
    }

    func campaignReply(_ products: [ProductRecord]) -> CoachReply {
        // Prefer the dedicated Kampanj Center records when they exist — they
        // carry verified prices, terms, end dates and source links.
        let now = Date()
        let activeCampaignRecords = CampaignEngine.activeCampaigns(campaigns, now: now)
        if !activeCampaignRecords.isEmpty {
            let lines = activeCampaignRecords.prefix(6).map { c in
                let price = c.priceKind == .monthly
                    ? "\(intSEK(c.campaignPriceSEK)) kr/mån"
                    : "\(intSEK(c.campaignPriceSEK)) kr engångspris"
                var line = "• \(c.title) – \(price)"
                if let saving = CampaignEngine.monthlySavingSEK(c), saving > 0 {
                    line += " (ord. \(intSEK(c.ordinaryPriceSEK ?? 0)) kr/mån)"
                }
                switch CampaignEngine.status(c, now: now) {
                case .expiresSoon(let days): line += ", slutar om \(days) dagar"
                case .active: if let end = c.endDate { line += ", t.o.m. \(Format.dayMonth.string(from: end))" }
                case .noVerifiedEndDate: line += ", slutdatum ej verifierat"
                case .expired: break
                }
                return line
            }
            let expiredNote = campaigns.contains { CampaignEngine.status($0, now: now) == .expired }
                ? "\nVissa tidigare kampanjer har utgått och visas inte längre som aktuella." : ""
            return CoachReply(
                text: """
                Aktuella kampanjer i Kampanj Center:

                \(lines.joined(separator: "\n"))

                Öppna Kampanj Center för fullständiga villkor, källor, jämförelser och verifieringstider.\(expiredNote)
                """,
                suggestions: ["Jämför bredbandskampanjer", "Hur hanterar jag prisinvändningar?", "Briefing inför passet"]
            )
        }
        guard !products.isEmpty else {
            return CoachReply(
                text: "Jag hittar inga aktiva kampanjer i katalogen just nu. Kontrollera telia.se/erbjudanden för aktuella erbjudanden – citera bara kampanjer du har sett i källan.",
                suggestions: ["Briefing inför passet", "Hur pratar jag om samlingsrabatt?"]
            )
        }
        let lines = products.map { p in
            let price = CostCalculator.currentMonthly(p).map { "\(intSEK($0)) kr/mån" } ?? "pris ej verifierat"
            let binding = p.isUnbound ? "obundet" : "\(p.bindingMonths ?? 0) mån bindning"
            return "• \(p.name) – \(price), \(binding)"
        }
        return CoachReply(
            text: """
            Aktiva kampanjer i den verifierade katalogen:

            \(lines.joined(separator: "\n"))

            Kom ihåg att redogöra för både kampanjpris och ordinarie pris – kunden har rätt att veta vad som gäller efter rabattperioden.
            """,
            citations: products.flatMap { citation(for: $0) },
            suggestions: ["Vad gäller för samlingsrabatt?", "Hur länge gäller kampanjerna?"]
        )
    }

    func objectionExpensiveReply() -> CoachReply {
        CoachReply(
            text: """
            Prisinvändning – tre steg som fungerar:

            1. Utforska först: "Vad jämför du med – är det totalkostnaden eller månadskostnaden som känns hög?"
            2.Ompröva värdet: visa exakt vad som ingår (surf, streaming, säkerhetstjänster, nät) och räkna på kundens nuvarande totalkostnad – många betalar redan för streaming och surf separat.
            3. Erbjud rätt alternativ: ett billigare abonnemang som passar deras behov är en bra affär – inte en förlust. Aldrig press, alltid transparens.

            Exempelfras: "Jag förstår att priset spelar roll. Låt oss titta på vad du faktiskt använder – då hittar vi rätt nivå, oavsett om det är billigare eller större."
            """,
            suggestions: ["Rollspel: kunden tycker Telia är dyrt", "Hur förklarar jag samlingsrabatt?"]
        )
    }

    func objectionBindingReply() -> CoachReply {
        CoachReply(
            text: """
            Bindningstidsinvändning:

            1. Klargör: "Vad är det med bindningstiden som oroar dig – flexibiliteten eller kostnaden?"
            2. Faktaplatser: flera abonnemang är helt obundna; där bindning finns följer oftast ett mervärde (t.ex. lägre enhetspris eller kampanjpris under 24 månader).
            3. Var ärlig: säg tydligt hur länge rabatten gäller och vad som händer efteråt. Transparent = trovärdig.

            Exempelfras: "De flesta av våra abonnemang har ingen bindningstid alls. När bindning finns är det för att rabatten ska räcka längre – och det säger jag gärna till dig exakt hur det fungerar."
            """,
            suggestions: ["Vilka abonnemang är obundna?", "Rollspel: kunden ogillar bindningstid"]
        )
    }

    func objectionCompetitorReply() -> CoachReply {
        CoachReply(
            text: """
            Konkurrentjämförelse – håll det rent:

            1. Aldrig diss på konkurrenten. Uppgradera istället: "Bra att du jämför – vad är det du värdesätter hos dem?"
            2. Skillnader som är ärliga: nätets täckning och utbyggnad, inkluderade säkerhetstjänster, möjlighet att samla tjänster och få rabatt, service i butik.
            3. Landning: "Om pris per GB är det viktigaste för dig finns det billigare alternativ – men om du värdesätter täckning när det verkligen gäller är det här ett bättre val."

            Lär dig aktuella skillnader i pris – men citera bara konkurrentpriser du har verifierat själv.
            """,
            suggestions: ["Rollspel: kunden jämför med en konkurrent", "Hur hanterar jag 'Telia är dyrast'?"]
        )
    }

    func briefingReply() -> CoachReply {
        let plans = catalog.filter { $0.kind == .mobilePlan && PriceVerification.isActiveOffer($0) }
        let unlimitedFrom = plans.filter { $0.unlimitedData }.compactMap { CostCalculator.currentMonthly($0) }.min()
        let cheapest = plans.compactMap { CostCalculator.currentMonthly($0) }.min()
        let campaignsCount = activeCampaigns().count
        var text = "Kort briefing inför passet:\n"
        if let cheapest {
            text += "• Mobilsurfer från \(intSEK(cheapest)) kr/mån.\n"
        }
        if let unlimitedFrom {
            text += "• Obegränsad surf från \(intSEK(unlimitedFrom)) kr/mån (kampanjpriser kan gälla).\n"
        }
        if let addOn = catalog.first(where: { $0.kind == .familyAddOn }), let p = CostCalculator.currentMonthly(addOn) {
            text += "• Extra användare (familj): \(intSEK(p)) kr/mån just nu.\n"
        }
        text += "• \(campaignsCount) aktiva kampanjer i katalogen.\n"
        text += "\nTre saker att ha fräscht: samlingsrabatt 100 kr/mån, vad som ingår i Obegränsad Plus (Cloud, streaming-alternativ, 1000 Mbit/s) och att startavgiften är 0 kr online. Kontrollera alltid dagens priser i källan vid osäkerhet."
        return CoachReply(
            text: text,
            citations: [],
            suggestions: ["Vilka kampanjer gäller?", "Ge mig en snabb quiz"]
        )
    }

    func citation(for p: ProductRecord) -> [ChatCitation] {
        [ChatCitation(
            productId: p.id,
            productName: p.name,
            sourceURL: p.sourceURL,
            priceSEK: CostCalculator.currentMonthly(p),
            verifiedAt: p.verifiedAt
        )]
    }

    func intSEK(_ v: Double) -> String {
        String(Int(v.rounded()))
    }
}

// MARK: - DemoCoachService

/// Conforms the engine to `CoachService` so the chat UI treats demo and remote identically.
public struct DemoCoachService: CoachService {
    public let name = "Demoläge (lokal)"
    public let isDemo = true

    public init() {}

    public func reply(
        to message: String,
        history: [ChatMessage],
        catalog: [ProductRecord],
        campaigns: [CampaignRecord],
        streamChunk: @escaping (String) -> Void
    ) async throws -> CoachReply {
        let engine = DemoCoachEngine(catalog: catalog, campaigns: campaigns)
        let reply = engine.reply(to: message)
        // The demo engine does not stream; deliver in one chunk and say so honestly.
        streamChunk(reply.text)
        return reply
    }
}
