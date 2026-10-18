import Foundation

// MARK: - Scenarios

public enum RolePlayDifficulty: String, Codable, CaseIterable, Sendable {
    case easy, medium, hard

    public var label: String {
        switch self {
        case .easy: return "Nybörjare"
        case .medium: return "Van säljare"
        case .hard: return "Utmanande"
        }
    }
}

public struct RolePlayScenario: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let category: String
    public let difficultyHint: String
    /// Facts about the customer. Revealed progressively, only when the seller asks.
    public let persona: Persona
    public let openingLine: String

    public init(id: String, title: String, category: String, difficultyHint: String,
                persona: Persona, openingLine: String) {
        self.id = id
        self.title = title
        self.category = category
        self.difficultyHint = difficultyHint
        self.persona = persona
        self.openingLine = openingLine
    }
}

public struct Persona: Codable, Hashable, Sendable {
    public let name: String
    public let age: Int
    public let occupation: String
    /// What the customer can comfortably spend per month, SEK.
    public let budgetMonthlySEK: Double
    public let currentProvider: String
    public let dataNeedGB: Double
    public let wantsUnlimited: Bool
    public let familySize: Int
    public let painPoints: [String]
    public let hiddenMotivation: String
    /// Hard limits the seller must respect (e.g. "vägrar bindningstid").
    public let constraints: [String]

    public init(name: String, age: Int, occupation: String, budgetMonthlySEK: Double,
                currentProvider: String, dataNeedGB: Double, wantsUnlimited: Bool,
                familySize: Int, painPoints: [String], hiddenMotivation: String,
                constraints: [String]) {
        self.name = name
        self.age = age
        self.occupation = occupation
        self.budgetMonthlySEK = budgetMonthlySEK
        self.currentProvider = currentProvider
        self.dataNeedGB = dataNeedGB
        self.wantsUnlimited = wantsUnlimited
        self.familySize = familySize
        self.painPoints = painPoints
        self.hiddenMotivation = hiddenMotivation
        self.constraints = constraints
    }
}

// MARK: - Built-in scenarios

public enum RolePlayCatalog {
    public static let scenarios: [RolePlayScenario] = [
        RolePlayScenario(
            id: "student",
            title: "Budgetmedveten student",
            category: "Mobilabonnemang",
            difficultyHint: "Fokus: kartlägg behov, hitta rimlig prisnivå, nämn ungdomsrabatten under 28 år.",
            persona: Persona(
                name: "Elias", age: 22, occupation: "Studerande",
                budgetMonthlySEK: 200, currentProvider: "Hallon",
                dataNeedGB: 15, wantsUnlimited: false, familySize: 1,
                painPoints: ["Surfen tar slut varje månad", "Tycker Telia låter dyrt"],
                hiddenMotivation: "Vill helst inte binda sig; skulle kunna byta om totalkostnaden är tydlig.",
                constraints: ["Ingen bindningstid", "Max 250 kr/mån"]
            ),
            openingLine: "Hej! Jag pluggar och mitt abonnemang tar slut på surfen hela tiden. Men jag har hört att ni är ganska dyra?"
        ),
        RolePlayScenario(
            id: "family",
            title: "Familj med flera abonnemang",
            category: "Familj",
            difficultyHint: "Fokus: räkna på extra användare, en faktura, värdet av obegränsad surf för alla.",
            persona: Persona(
                name: "Sara", age: 41, occupation: "Sjuksköterska",
                budgetMonthlySEK: 1200, currentProvider: "Blandat (Telia + Tele2)",
                dataNeedGB: 30, wantsUnlimited: true, familySize: 4,
                painPoints: ["Fyra olika fakturor", "Barnen streamar på mobilt nät"],
                hiddenMotivation: "Vill förenkla vardagen och ha koll på kostnaden.",
                constraints: ["Vill se totalkostnad innan beslut"]
            ),
            openingLine: "Hej! Vi är fyra personer i familjen med fyra olika abonnemang. Det känns kaos – kan ni hjälpa mig strukturera det?"
        ),
        RolePlayScenario(
            id: "upgrader",
            title: "Kund som ska uppgradera mobilen",
            category: "Mobil + abonnemang",
            difficultyHint: "Fokus: bindningstidens koppling till enhetspris, kontantpris vs avbetalning, totalkostnad.",
            persona: Persona(
                name: "Oskar", age: 34, occupation: "Utvecklare",
                budgetMonthlySEK: 800, currentProvider: "Telia",
                dataNeedGB: 50, wantsUnlimited: true, familySize: 1,
                painPoints: ["Batteriet räcker inte en dag", "Vet inte om avbetalning lönar sig"],
                hiddenMotivation: "Vill ha en bra telefon utan att betala allt på en gång.",
                constraints: []
            ),
            openingLine: "Hej, jag har haft samma telefon i fyra år. Den håller på att dö. Hur funkar det om jag köper en ny hos er?"
        ),
        RolePlayScenario(
            id: "competitor",
            title: "Kunden jämför med konkurrent",
            category: "Invändningar",
            difficultyHint: "Fokus: håll det rent om konkurrenten, fråga vad kunden värdesätter.",
            persona: Persona(
                name: "Birgitta", age: 58, occupation: "Lärare",
                budgetMonthlySEK: 300, currentProvider: "Telenor",
                dataNeedGB: 8, wantsUnlimited: false, familySize: 2,
                painPoints: ["Telenor erbjuder 199 kr/mån med 10 GB"],
                hiddenMotivation: "Vill egentligen ha bättre täckning på landstället.",
                constraints: []
            ),
            openingLine: "Telenor erbjuder mig 10 GB för 199 i månaden. Varför skulle jag byta till er?"
        ),
        RolePlayScenario(
            id: "wifi",
            title: "Kund med dåligt Wi-Fi hemma",
            category: "Bredband",
            difficultyHint: "Fokus: fiber vs 5G-bredband, hastighetsbehov, samlingsrabatt.",
            persona: Persona(
                name: "Johan", age: 47, occupation: "Arkitekt",
                budgetMonthlySEK: 500, currentProvider: "Inget (grannens nät)",
                dataNeedGB: 0, wantsUnlimited: false, familySize: 3,
                painPoints: ["Wi-Fi-räckvidden räcker inte", "Jobbar hemma med stora filer"],
                hiddenMotivation: "Vill ha stabilt nät för jobbet och streaming på kvällarna.",
                constraints: ["Bor i lägenhet – ingen fiber draggen än"]
            ),
            openingLine: "Hej! Wi-Fi:t hemma är hemskt. Filmen buffrar och jobbfilerna tar evigheter. Vad kan ni erbjuda?"
        ),
        RolePlayScenario(
            id: "streamer",
            title: "Kunden betalar för streaming separat",
            category: "TV & Streaming",
            difficultyHint: "Fokus: samla streaming i abonnemanget, räkna på besparing, kombinera med samlingsrabatt.",
            persona: Persona(
                name: "Amanda", age: 29, occupation: "Grafisk designer",
                budgetMonthlySEK: 700, currentProvider: "Tele2",
                dataNeedGB: 40, wantsUnlimited: true, familySize: 2,
                painPoints: ["Betalar Netflix + HBO separat", "Surfen räcker inte"],
                hiddenMotivation: "Vill sänka totalkostnaden för streaming och surf.",
                constraints: []
            ),
            openingLine: "Jag betalar redan för Netflix och HBO varje månad, och ändå tar surfen slut. Det känns dumt?"
        ),
        RolePlayScenario(
            id: "binding-hater",
            title: "Kund som ogillar bindningstid",
            category: "Invändningar",
            difficultyHint: "Fokus: vara transparent om bindning, visa obundna alternativ, förklara varför vissa erbjudanden har bindning.",
            persona: Persona(
                name: "Peter", age: 39, occupation: "Kock",
                budgetMonthlySEK: 400, currentProvider: "Comviq",
                dataNeedGB: 25, wantsUnlimited: false, familySize: 1,
                painPoints: ["Har blivit bränd av bindningstid innan"],
                hiddenMotivation: "Vill ha flexibilitet men skulle acceptera bindning om mervärdet är tydligt.",
                constraints: ["Skeptisk till allt med bindningstid"]
            ),
            openingLine: "Innan vi börjar: jag vägrar binda upp mig. Har blivit lurad förr. Finns det något utan bindningstid?"
        ),
        RolePlayScenario(
            id: "unsure",
            title: "Kund som inte vet vad den behöver",
            category: "Mobilabonnemang",
            difficultyHint: "Fokus: öppna frågor, lyssna, sammanfatta behov innan du föreslår något.",
            persona: Persona(
                name: "Fatima", age: 63, occupation: "Pensionär",
                budgetMonthlySEK: 250, currentProvider: "Telia kontantkort",
                dataNeedGB: 3, wantsUnlimited: false, familySize: 2,
                painPoints: ["Vet inte hur mycket surf hon använder", "Barnbarnen säger att hon borde skaffa 'riktigt' abonnemang"],
                hiddenMotivation: "Vill ha något enkelt och tryggt, inte billigast.",
                constraints: ["Vill inte ha krångel"]
            ),
            openingLine: "Hej... mina barnbarn säger jag borde sluta med kontantkort. Men jag fattar inte skillnaden på alla dessa abonnemang. Kan du förklara?"
        )
    ]
}

// MARK: - Session

public struct RolePlayTurn: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public let isCustomer: Bool
    public let text: String

    public init(isCustomer: Bool, text: String) {
        self.id = UUID()
        self.isCustomer = isCustomer
        self.text = text
    }
}

/// Drives one practice session. The customer reveals one new fact per relevant question,
/// objects with difficulty-dependent frequency, and decides at the end based on fit.
public final class RolePlaySession {
    public let scenario: RolePlayScenario
    public let difficulty: RolePlayDifficulty
    public private(set) var turns: [RolePlayTurn] = []
    public private(set) var revealedFacts: Set<String> = []

    /// Signals collected from the seller's messages for scoring.
    public private(set) var analysis = TurnAnalysis()

    public struct TurnAnalysis {
        public var openQuestions = 0
        public var closedQuestions = 0
        public var empathySignals = 0
        public var productMentions: Set<String> = []
        public var priceClaims: [Double] = []
        public var priceClaimsVerified = 0
        public var priceClaimsWrong = 0
        public var totalCostMentions = 0
        public var closingAttempts = 0
        public var pressureSignals = 0
        public var bindingTransparency = 0
        public var recommendations: Set<String> = []
    }

    private let catalog: [ProductRecord]

    public init(scenario: RolePlayScenario, difficulty: RolePlayDifficulty, catalog: [ProductRecord]) {
        self.scenario = scenario
        self.difficulty = difficulty
        self.catalog = catalog
        turns.append(RolePlayTurn(isCustomer: true, text: scenario.openingLine))
    }

    // MARK: Seller turn

    public func sellerMessage(_ text: String) {
        turns.append(RolePlayTurn(isCustomer: false, text: text))
        analyze(text)
    }

    func analyze(_ text: String) {
        let lower = text.lowercased()
        let words = lower.split(separator: " ").map(String.init)

        if text.contains("?") {
            let openStarters = ["vad", "hur", "varför", "berätta", "vilka", "vilket", "ber om", "how", "what", "why", "tell"]
            if words.first.map({ openStarters.contains($0) }) == true { analysis.openQuestions += 1 }
            else { analysis.closedQuestions += 1 }
        }

        let empathyWords = ["förstår", "bra att", "exakt", "håller med", "absolut", "precis", "kul att", "tack för", "i understand", "exactly"]
        analysis.empathySignals += empathyWords.filter { lower.contains($0) }.count

        let pressureWords = ["måste", "bör verkligen", "sista chansen", "nu eller aldrig", "skyll på", "du borde", "only today", "hurry"]
        analysis.pressureSignals += pressureWords.filter { lower.contains($0) }.count

        if lower.contains("total") || lower.contains("sammanlagt") || lower.contains("per månad") || lower.contains("totalkostnad") {
            analysis.totalCostMentions += 1
        }
        if lower.contains("bindningstid") || lower.contains("obundet") || lower.contains("binda") {
            analysis.bindingTransparency += 1
        }
        let closers = ["ska vi", "vill du att jag", "är du med", "teckna", "ska vi göra", "vill du ha", "boka", "signera"]
        if closers.contains(where: { lower.contains($0) }) { analysis.closingAttempts += 1 }

        for product in catalog {
            let name = product.name.lowercased()
            let tokens = CatalogQuery.tokenize(product.name)
            if lower.contains(name) || (tokens.count >= 2 && tokens.allSatisfy({ lower.contains($0) })) {
                analysis.productMentions.insert(product.name)
                if closers.contains(where: { lower.contains($0) }) { analysis.recommendations.insert(product.name) }
            }
        }

        // Price accuracy: find "N kr" claims and compare to the catalog.
        if let regex = try? NSRegularExpression(pattern: #"(\d{2,5})\s*(kr|kronor)"#) {
            let ns = lower as NSString
            var matches: [Double] = []
            regex.enumerateMatches(in: lower, range: NSRange(location: 0, length: ns.length)) { match, _, _ in
                guard let match, let r = Range(match.range(at: 1), in: lower),
                      let value = Double(lower[r]) else { return }
                matches.append(value)
            }
            let catalog = self.catalog
            for value in matches {
                analysis.priceClaims.append(value)
                let candidates = catalog.filter { p in
                    [CostCalculator.currentMonthly(p), p.ordinaryMonthlyPriceSEK, p.upfrontCostSEK]
                        .compactMap { $0 }
                        .contains { abs($0 - value) < 1 }
                }
                if candidates.isEmpty {
                    // 100 kr is also the samlingsrabatt.
                    if abs(value - 100) < 1 { analysis.priceClaimsVerified += 1 } else { analysis.priceClaimsWrong += 1 }
                } else {
                    analysis.priceClaimsVerified += 1
                }
            }
        }
    }

    // MARK: Customer turn

    /// Generates the customer's next line, revealing information progressively,
    /// and appends it to the transcript.
    public func customerReply() -> String {
        let line = generateCustomerLine()
        turns.append(RolePlayTurn(isCustomer: true, text: line))
        return line
    }

    func generateCustomerLine() -> String {
        let unansweredPain = scenario.persona.painPoints.filter { !revealedFacts.contains($0) }
        let basicFacts: [String] = [
            "Jag använder nog runt \(Int(scenario.persona.dataNeedGB)) GB i månaden.",
            "Min budget ligger på runt \(Int(scenario.persona.budgetMonthlySEK)) kr i månaden totalt.",
            "Jag är \(scenario.persona.age) år och jobbar som \(scenario.persona.occupation).",
            "Idag har jag \(scenario.persona.currentProvider).",
            scenario.persona.hiddenMotivation,
        ]
        let unrevealedBasics = basicFacts.filter { !revealedFacts.contains($0) }

        // Did the seller just ask a question? Then answer/reveal one fact.
        let lastSeller = turns.last { !$0.isCustomer }?.text ?? ""
        let askedQuestion = lastSeller.contains("?")

        // Difficulty-scaled objections when the seller pushes products without discovery.
        let mentionedProducts = !analysis.productMentions.isEmpty
        let earlyPush = mentionedProducts && analysis.openQuestions < 2 && turns.filter { !$0.isCustomer }.count <= 2
        if earlyPush && difficulty != .easy && Int.random(in: 0...1) == 0 {
            return pushbackLine()
        }

        if askedQuestion {
            if let fact = unrevealedBasics.first {
                revealedFacts.insert(fact)
                return revealLine(for: fact)
            }
            if let pain = unansweredPain.first {
                revealedFacts.insert(pain)
                return "Det som stör mig mest? \(pain)."
            }
        } else {
            // No question: the customer expects the seller to engage.
            if difficulty == .hard && Int.random(in: 0...2) == 0 {
                return pushbackLine()
            }
            if let pain = unansweredPain.first, revealedFacts.count >= 1 {
                revealedFacts.insert(pain)
                return "En sak till – \(pain.lowercased())."
            }
        }

        if turns.filter { !$0.isCustomer }.count >= 4, analysis.closingAttempts == 0 {
            return "Så... vad föreslår du att jag gör? Jag vill gärna veta vad det skulle kosta."
        }
        if analysis.closingAttempts > 0 {
            return decisionLine()
        }
        return "Okej... kan du berätta lite mer?"
    }

    func revealLine(for fact: String) -> String {
        if fact.hasPrefix("Jag använder") || fact.hasPrefix("Min budget") {
            return "\(fact) Känner du till vad som skulle passa?"
        }
        return fact
    }

    func pushbackLine() -> String {
        let lines = [
            "Vänta lite – du föreslår saker innan du vet vad jag behöver. Kan vi börja om?",
            "Hmm, jag nämnde ju inte att jag ville ha den tjänsten. Vad kostar den per månad, egentligen?",
            "Jag blev lite tappad nu. Kan du förklara vad som gäller – även det som kostar extra?",
        ]
        return lines[turns.count % lines.count]
    }

    func decisionLine() -> String {
        let fit = recommendationFit()
        switch fit {
        case .good:
            return "Det låter rimligt det. Jag litar på att du har räknat rätt – låt oss göra så."
        case .okay:
            return "Kanske det. Kan jag få tänka på det tills imorgon? Jag vill jämföra totalkostnaden i fred och ro."
        case .poor:
            return "Tack för hjälpen, men det här känns inte rätt för mig just nu. Jag går hem och funderar."
        }
    }

    public enum Fit: String, Codable, Sendable { case good, okay, poor }

    /// How well the seller's final recommendation matches the persona's needs.
    public func recommendationFit() -> Fit {
        guard !analysis.recommendations.isEmpty else { return .poor }
        let persona = scenario.persona
        var score = 0
        for name in analysis.recommendations {
            guard let product = catalog.first(where: { $0.name == name }) else { continue }
            if let price = CostCalculator.currentMonthly(product) {
                if price <= persona.budgetMonthlySEK { score += 2 }
                else if price <= persona.budgetMonthlySEK * 1.2 { score += 1 }
                else if price > persona.budgetMonthlySEK * 1.5 { score -= 3 }
                else { score -= 1 }
            }
            if persona.wantsUnlimited && product.unlimitedData { score += 2 }
            if product.isUnbound && persona.constraints.contains(where: { $0.lowercased().contains("bindning") }) { score += 2 }
            if let gb = product.dataGB, gb >= persona.dataNeedGB, !persona.wantsUnlimited { score += 1 }
        }
        if analysis.priceClaimsWrong > 0 { score -= 2 }
        if analysis.pressureSignals > 0 { score -= 3 }
        if score >= 4 { return .good }
        if score >= 1 { return .okay }
        return .poor
    }
}

// MARK: - Scoring

public struct RolePlayScore: Codable, Hashable, Sendable {
    public let dimension: String
    /// 0...5
    public let score: Int
    public let feedback: String
}

public struct RolePlayResult: Codable, Hashable, Sendable, Identifiable {
    public var id: String { "result-\(total)-\(maxTotal)-\(scores.count)" }
    public let scores: [RolePlayScore]
    public let total: Int
    public let maxTotal: Int
    public let strengths: [String]
    public let improvements: [String]
    public let alternativePhrases: [String]
    public let fit: RolePlaySession.Fit
    public let redFlags: [String]
}

public enum RolePlayScorer {

    public static let dimensions = [
        "Kartläggningsfrågor", "Lyssnande & empati", "Produktkunskap", "Prisaccuracy",
        "Värdeförklaring", "Invändningshantering", "Totalkostnad-transparens", "Avslutsteknik", "Kundanpassning"
    ]

    public static func score(_ session: RolePlaySession) -> RolePlayResult {
        let a = session.analysis
        let sellerTurns = session.turns.filter { !$0.isCustomer }.count
        let persona = session.scenario.persona

        func clamp(_ v: Int) -> Int { max(0, min(5, v)) }

        let discovery = clamp(a.openQuestions - a.closedQuestions / 2 + (a.openQuestions >= 3 ? 1 : 0))
        let listening = clamp(a.empathySignals - (a.pressureSignals * 2) + (a.openQuestions >= 1 ? 1 : 0))
        let knowledge = clamp(a.productMentions.count + (a.priceClaimsVerified > 0 ? 1 : 0) - (sellerTurns == 0 ? 5 : 0))
        let accuracy = clamp(a.priceClaims.isEmpty ? 2 : (a.priceClaimsVerified * 5) / max(1, a.priceClaims.count) - a.priceClaimsWrong)
        let value = clamp(a.totalCostMentions + (a.productMentions.count >= 1 ? 2 : 0))
        let objections = clamp(session.revealedFacts.count >= 2 ? 3 : 1) - clamp(a.pressureSignals)
        let transparency = clamp(a.bindingTransparency + a.totalCostMentions + (a.priceClaimsWrong == 0 ? 1 : 0))
        let closing = clamp(a.closingAttempts >= 1 ? 4 : 0) + clamp(a.openQuestions >= 2 ? 1 : 0)
        let fit = session.recommendationFit()
        let suitability: Int
        switch fit {
        case .good: suitability = clamp(3 + (a.priceClaimsWrong == 0 ? 1 : 0) + (a.pressureSignals == 0 ? 1 : 0))
        case .okay: suitability = 3
        case .poor: suitability = sellerTurns >= 3 ? 1 : 0
        }

        var scores: [RolePlayScore] = []
        scores.append(RolePlayScore(dimension: "Kartläggningsfrågor", score: discovery,
            feedback: discovery >= 4 ? "Du ställde bra öppna frågor innan du föreslog något." : "Ställ fler öppna frågor (vad/hur/berätta) – de ger dig kundens behov utan att du gissar."))
        scores.append(RolePlayScore(dimension: "Lyssnande & empati", score: clamp(listening),
            feedback: listening >= 3 ? "Kunden kände sig hörd – du bekräftade och byggde vidare." : "Bekräfta kundens känsla med 'jag förstår' innan du svarar innehåll."))
        scores.append(RolePlayScore(dimension: "Produktkunskap", score: clamp(knowledge),
            feedback: knowledge >= 3 ? "Du använde konkreta produkter som lösningar." : "Koppla kundens behov till specifika produkter – det gör rådet handlingsbart."))
        scores.append(RolePlayScore(dimension: "Prisaccuracy", score: clamp(accuracy),
            feedback: a.priceClaimsWrong == 0 ? "Inga felaktiga priser i samtalet – bra." : "Du citerade priser som inte finns i katalogen. Kontrollera alltid källan innan du citerar."))
        scores.append(RolePlayScore(dimension: "Värdeförklaring", score: clamp(value),
            feedback: value >= 3 ? "Du förklarade värdet, inte bara priset." : "Förklara vad kunden får för pengarna – vad ingår, vad händer efter kampanjen."))
        scores.append(RolePlayScore(dimension: "Invändningshantering", score: clamp(max(1, objections)),
            feedback: objections >= 3 ? "Du hanterade invändningar utan att bli defensiv." : "Möt invändningar med nyfikenhet: 'vad är det som gör att du känner så?'"))
        scores.append(RolePlayScore(dimension: "Totalkostnad-transparens", score: clamp(transparency),
            feedback: transparency >= 3 ? "Du var tydlig med totalkostnad och bindning." : "Redovisa alltid månadskostnad, kampanjperiodens längd och vad som gäller efteråt."))
        scores.append(RolePlayScore(dimension: "Avslutsteknik", score: clamp(closing),
            feedback: a.closingAttempts >= 1 ? "Du bad om affären – lagom mjukt." : "Våga fråga om beslutet när behovet är klart: 'Ska vi göra så?'"))
        scores.append(RolePlayScore(dimension: "Kundanpassning", score: clamp(suitability),
            feedback: fit == .good ? "Rekommendationen matchade kundens budget och behov." : "Rekommendationen utanför kundens behov – anpassa förslag till det kartlagda behovet (\(persona.name)s budget och begränsningar)."))

        let total = scores.reduce(0) { $0 + $1.score }
        let strengths = scores.filter { $0.score >= 4 }.map { $0.dimension }
        let improvements = scores.filter { $0.score <= 2 }.map { $0.dimension }

        var redFlags: [String] = []
        if a.pressureSignals > 0 { redFlags.append("Pressande formuleringar upptäckta – det skadar förtroende och är aldrig okej.") }
        if a.priceClaimsWrong > 0 { redFlags.append("Felaktiga prisuppgifter i samtalet.") }

        let alternatives = [
            "Istället för att direkt föreslå: 'Vad är viktigast för dig i ett abonnemang – surfen, priset eller flexibiliteten?'",
            "Innan du citerar pris: 'Det beror på vad du behöver – får jag fråga lite först?'",
            "När du föreslår: 'Baserat på det du berättat skulle jag titta på X – vill du att jag räknar på totalkostnaden?'",
            "Vid osäkerhet om pris: 'Låt mig dubbelkolla exakt pris i systemet så du får rätt siffra.'",
        ]

        return RolePlayResult(
            scores: scores,
            total: total,
            maxTotal: dimensions.count * 5,
            strengths: strengths,
            improvements: improvements,
            alternativePhrases: alternatives,
            fit: fit,
            redFlags: redFlags
        )
    }
}
