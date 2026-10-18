import Foundation

/// Search, filtering, sorting and grounded retrieval over the catalog.
public enum CatalogQuery {

    public struct Filters: Equatable, Sendable {
        public var kinds: Set<ProductKind>
        public var brands: Set<String>
        public var maxMonthlySEK: Double?
        public var minMonthlySEK: Double?
        public var onlyFavorites: Bool
        public var onlyVerified: Bool
        public var onlyUnbound: Bool
        public var requireUnlimitedData: Bool

        public init(
            kinds: Set<ProductKind> = [],
            brands: Set<String> = [],
            maxMonthlySEK: Double? = nil,
            minMonthlySEK: Double? = nil,
            onlyFavorites: Bool = false,
            onlyVerified: Bool = false,
            onlyUnbound: Bool = false,
            requireUnlimitedData: Bool = false
        ) {
            self.kinds = kinds
            self.brands = brands
            self.maxMonthlySEK = maxMonthlySEK
            self.minMonthlySEK = minMonthlySEK
            self.onlyFavorites = onlyFavorites
            self.onlyVerified = onlyVerified
            self.onlyUnbound = onlyUnbound
            self.requireUnlimitedData = requireUnlimitedData
        }

        public var isActive: Bool {
            !kinds.isEmpty || !brands.isEmpty || maxMonthlySEK != nil || minMonthlySEK != nil
                || onlyFavorites || onlyVerified || onlyUnbound || requireUnlimitedData
        }
    }

    public enum Sort: String, CaseIterable, Sendable {
        case relevance, nameAsc, priceAsc, priceDesc, dataDesc
    }

    // MARK: - Search

    public static func search(
        _ products: [ProductRecord],
        query: String,
        filters: Filters = Filters(),
        sort: Sort = .relevance,
        now: Date = Date()
    ) -> [ProductRecord] {
        let active = products.filter { PriceVerification.isActiveOffer($0, now: now) }
        let filtered = active.filter { p in
            if !filters.kinds.isEmpty && !filters.kinds.contains(p.kind) { return false }
            if !filters.brands.isEmpty {
                guard let b = p.brand, filters.brands.contains(b) else { return false }
            }
            if let max = filters.maxMonthlySEK {
                guard let m = CostCalculator.currentMonthly(p), m <= max else { return false }
            }
            if let min = filters.minMonthlySEK {
                guard let m = CostCalculator.currentMonthly(p), m >= min else { return false }
            }
            if filters.onlyVerified && p.verification != .verified { return false }
            if filters.onlyUnbound && !p.isUnbound { return false }
            if filters.requireUnlimitedData && !p.unlimitedData { return false }
            return true
        }

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return sortResults(filtered, by: sort, query: nil)
        }
        let terms = tokenize(trimmed)
        let scored = filtered.map { p -> (ProductRecord, Int) in
            var score = 0
            let nameTokens = tokenize(p.name)
            for term in terms {
                if p.name.lowercased().contains(term) { score += 10 }
                for t in nameTokens where t == term { score += 6 }
                if p.category.lowercased().contains(term) { score += 3 }
                if p.brand?.lowercased().contains(term) == true { score += 4 }
                if p.dataLabel.lowercased().contains(term) { score += 3 }
                if p.tags.contains(where: { $0.lowercased().contains(term) }) { score += 2 }
                if p.includedServices.contains(where: { $0.lowercased().contains(term) }) { score += 2 }
                if p.kind.rawValue.lowercased().contains(term) { score += 1 }
            }
            return (p, score)
        }
        .filter { $0.1 > 0 }

        if sort == .relevance {
            return scored.sorted { $0.1 > $1.1 }.map(\.0)
        }
        return sortResults(scored.map(\.0), by: sort, query: nil)
    }

    static func sortResults(_ products: [ProductRecord], by sort: Sort, query: String?) -> [ProductRecord] {
        switch sort {
        case .relevance:
            return products
        case .nameAsc:
            return products.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .priceAsc:
            return products.sorted { (CostCalculator.currentMonthly($0) ?? .infinity) < (CostCalculator.currentMonthly($1) ?? .infinity) }
        case .priceDesc:
            return products.sorted { (CostCalculator.currentMonthly($0) ?? -.infinity) > (CostCalculator.currentMonthly($1) ?? -.infinity) }
        case .dataDesc:
            return products.sorted { ($0.unlimitedData ? .infinity : ($0.dataGB ?? 0)) > ($1.unlimitedData ? .infinity : ($1.dataGB ?? 0)) }
        }
    }

    public static func tokenize(_ text: String) -> [String] {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 2 }
    }

    // MARK: - Retrieval for the AI coach (grounding)

    /// Lightweight retrieval: scores products against a free-text message and returns the
    /// top matches. Used to ground the AI coach and the role-play engine in real catalog data.
    public static func retrieve(
        message: String,
        in products: [ProductRecord],
        topK: Int = 3
    ) -> [ProductRecord] {
        let terms = tokenize(message)
        guard !terms.isEmpty else { return [] }

        // Numeric intent: "30 GB i månaden" → match plans at or above that data.
        var gbIntent: Double?
        if let regex = gbRegex,
           let r = regex.firstMatch(in: message, range: NSRange(message.startIndex..., in: message)),
           let range = Range(r.range, in: message) {
            let numberString = String(message[range]).filter { $0.isNumber }
            gbIntent = Double(numberString)
        }

        var best: [(ProductRecord, Int)] = []
        for p in products {
            guard PriceVerification.isActiveOffer(p) else { continue }
            var score = 0
            let haystack = ([p.name, p.category, p.brand ?? "", p.dataLabel]
                            + p.includedServices + p.tags + p.highlights)
                .joined(separator: " ").lowercased()
            for term in terms where haystack.contains(term) { score += 2 }
            if terms.contains(where: { p.name.lowercased().contains($0) }) { score += 5 }
            if let gb = gbIntent {
                if p.unlimitedData { score += 2 }
                else if let data = p.dataGB, data >= gb { score += 4 }
            }
            if score > 0 { best.append((p, score)) }
        }
        return best
            .sorted { $0.1 > $1.1 }
            .prefix(topK)
            .map(\.0)
    }

    static let gbRegex = try? NSRegularExpression(pattern: #"(\d+)\s*(gb|gig)"#, options: [.caseInsensitive])

    /// Recommend plans for a stated monthly data usage.
    public static func recommend(
        dataGB: Double,
        in products: [ProductRecord]
    ) -> [ProductRecord] {
        let plans = products.filter { $0.kind == .mobilePlan && PriceVerification.isActiveOffer($0) }
        let bounded = plans
            .filter { p in
                guard let gb = p.dataGB else { return false }
                return gb >= dataGB
            }
            .sorted { (CostCalculator.currentMonthly($0) ?? .infinity) < (CostCalculator.currentMonthly($1) ?? .infinity) }
        let unlimitedCheapest = plans
            .filter { $0.unlimitedData }
            .sorted { (CostCalculator.currentMonthly($0) ?? .infinity) < (CostCalculator.currentMonthly($1) ?? .infinity) }
        var result: [ProductRecord] = []
        for p in bounded.prefix(2) where !result.contains(p) { result.append(p) }
        for p in unlimitedCheapest.prefix(1) where !result.contains(p) { result.append(p) }
        return result
    }

    /// Distinct brands in the catalogue, for filter chips.
    public static func brands(in products: [ProductRecord]) -> [String] {
        Array(Set(products.compactMap(\.brand))).sorted()
    }
}
