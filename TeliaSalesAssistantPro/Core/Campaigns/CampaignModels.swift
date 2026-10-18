import Foundation

// MARK: - Campaign categories

public enum CampaignCategory: String, Codable, CaseIterable, Sendable, Identifiable {
    case mobilabonnemang
    case familjeabonnemang
    case iphone
    case samsung
    case otherSmartphones = "andra_smartphones"
    case tablets
    case bredband
    case tvStreaming = "tv_streaming"
    case accessories
    case bundles
    case other

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .mobilabonnemang: return "Mobilabonnemang"
        case .familjeabonnemang: return "Familjeabonnemang"
        case .iphone: return "iPhone"
        case .samsung: return "Samsung"
        case .otherSmartphones: return "Andra smartphones"
        case .tablets: return "Surfplattor & enheter"
        case .bredband: return "Bredband"
        case .tvStreaming: return "TV & streaming"
        case .accessories: return "Tillbehör"
        case .bundles: return "Paket & kombinationer"
        case .other: return "Övriga erbjudanden"
        }
    }

    public var symbolName: String {
        switch self {
        case .mobilabonnemang: return "antenna.radiowaves.left.and.right"
        case .familjeabonnemang: return "person.2.fill"
        case .iphone: return "iphone.gen3"
        case .samsung: return "rectangle.and.hand.point.up.left.fill"
        case .otherSmartphones: return "smartphone"
        case .tablets: return "ipad.landscape"
        case .bredband: return "wifi.router"
        case .tvStreaming: return "tv.fill"
        case .accessories: return "headphones"
        case .bundles: return "shippingbox.fill"
        case .other: return "tag.fill"
        }
    }
}

// MARK: - Price kinds

/// Distinguishes a discounted monthly price from a one-time discount price.
/// Never mix these when computing savings.
public enum CampaignPriceKind: String, Codable, Sendable {
    case monthly
    case oneTime
}

// MARK: - Campaign record

/// A source-verified Telia campaign, kept separate from ordinary product
/// records. Campaigns may reference products via `relatedProductIDs`.
public struct CampaignRecord: Codable, Hashable, Identifiable, Sendable {

    public var id: String
    public var title: String
    public var productName: String
    public var category: CampaignCategory
    public var priceKind: CampaignPriceKind
    /// Campaign price in SEK — monthly or one-time depending on `priceKind`.
    public var campaignPriceSEK: Double
    /// Ordinary price in the SAME price kind, when published.
    public var ordinaryPriceSEK: Double?
    /// Contract binding in months, when published.
    public var bindingMonths: Int?
    /// How many months the campaign price applies, when published.
    public var promoMonths: Int?
    /// Price after the campaign period, when published.
    public var priceAfterCampaignSEK: Double?
    /// Documented value of included hardware (e.g. a router on the house).
    public var oneTimeValueSEK: Double?
    public var includedServices: [String]
    public var eligibility: String?
    public var exclusions: String?
    public var termsSummary: String?
    public var startDate: Date?
    /// Verified campaign end date. Nil means the source publishes no end date.
    public var endDate: Date?
    public var sourceURL: String
    public var sourceName: String
    /// When this record was last successfully verified against the source.
    public var verifiedAt: Date
    public var imageURL: String?
    public var relatedProductIDs: [String]
    public var notes: String?

    public init(
        id: String,
        title: String,
        productName: String,
        category: CampaignCategory,
        priceKind: CampaignPriceKind,
        campaignPriceSEK: Double,
        ordinaryPriceSEK: Double? = nil,
        bindingMonths: Int? = nil,
        promoMonths: Int? = nil,
        priceAfterCampaignSEK: Double? = nil,
        oneTimeValueSEK: Double? = nil,
        includedServices: [String] = [],
        eligibility: String? = nil,
        exclusions: String? = nil,
        termsSummary: String? = nil,
        startDate: Date? = nil,
        endDate: Date? = nil,
        sourceURL: String,
        sourceName: String,
        verifiedAt: Date,
        imageURL: String? = nil,
        relatedProductIDs: [String] = [],
        notes: String? = nil
    ) {
        self.id = id
        self.title = title
        self.productName = productName
        self.category = category
        self.priceKind = priceKind
        self.campaignPriceSEK = campaignPriceSEK
        self.ordinaryPriceSEK = ordinaryPriceSEK
        self.bindingMonths = bindingMonths
        self.promoMonths = promoMonths
        self.priceAfterCampaignSEK = priceAfterCampaignSEK
        self.oneTimeValueSEK = oneTimeValueSEK
        self.includedServices = includedServices
        self.eligibility = eligibility
        self.exclusions = exclusions
        self.termsSummary = termsSummary
        self.startDate = startDate
        self.endDate = endDate
        self.sourceURL = sourceURL
        self.sourceName = sourceName
        self.verifiedAt = verifiedAt
        self.imageURL = imageURL
        self.relatedProductIDs = relatedProductIDs
        self.notes = notes
    }
}

// MARK: - Status

public enum CampaignStatus: Equatable, Sendable {
    /// End date in the future, further than `soonThresholdDays`.
    case active
    /// End date within `soonThresholdDays` of now.
    case expiresSoon(days: Int)
    /// Verified end date has passed — must never be presented as current.
    case expired
    /// No verified end date; treat as current but labelled accordingly.
    case noVerifiedEndDate

    public var isActive: Bool {
        switch self {
        case .expired: return false
        default: return true
        }
    }
}

// MARK: - Diff (changed / removed offers)

public struct CampaignDiff: Equatable, Sendable {
    public struct PriceChange: Equatable, Sendable, Identifiable {
        public let id: String
        public let title: String
        public let fromSEK: Double
        public let toSEK: Double
        public init(id: String, title: String, fromSEK: Double, toSEK: Double) {
            self.id = id
            self.title = title
            self.fromSEK = fromSEK
            self.toSEK = toSEK
        }
    }

    public let added: [CampaignRecord]
    public let removed: [CampaignRecord]
    public let priceChanges: [PriceChange]

    public var isEmpty: Bool { added.isEmpty && removed.isEmpty && priceChanges.isEmpty }
}

// MARK: - Engine

public enum CampaignEngine {

    public static let soonThresholdDays = 7

    // MARK: Status

    public static func status(
        _ campaign: CampaignRecord,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> CampaignStatus {
        guard let end = campaign.endDate else { return .noVerifiedEndDate }
        let startOfDayNow = calendar.startOfDay(for: now)
        let startOfDayEnd = calendar.startOfDay(for: end)
        if startOfDayEnd < startOfDayNow { return .expired }
        let days = calendar.dateComponents([.day], from: startOfDayNow, to: startOfDayEnd).day ?? 0
        if days <= soonThresholdDays { return .expiresSoon(days: max(0, days)) }
        return .active
    }

    // MARK: Savings (never invented, never cross-kind)

    /// Monthly saving in SEK — only for monthly campaigns with a published
    /// ordinary monthly price. One-time prices never produce a monthly saving.
    public static func monthlySavingSEK(_ campaign: CampaignRecord) -> Double? {
        guard campaign.priceKind == .monthly,
              let ordinary = campaign.ordinaryPriceSEK else { return nil }
        return ordinary - campaign.campaignPriceSEK
    }

    /// Saving in percent — only when both prices are monthly and comparable.
    public static func savingPercent(_ campaign: CampaignRecord) -> Double? {
        guard campaign.priceKind == .monthly,
              let ordinary = campaign.ordinaryPriceSEK,
              ordinary > 0 else { return nil }
        return (ordinary - campaign.campaignPriceSEK) / ordinary * 100
    }

    /// One-time saving in SEK — only for one-time campaigns with a published
    /// ordinary price.
    public static func oneTimeSavingSEK(_ campaign: CampaignRecord) -> Double? {
        guard campaign.priceKind == .oneTime,
              let ordinary = campaign.ordinaryPriceSEK else { return nil }
        return ordinary - campaign.campaignPriceSEK
    }

    /// Total cost over `months` months. Monthly campaigns multiply; one-time
    /// campaigns pay once regardless of horizon.
    public static func totalCostSEK(_ campaign: CampaignRecord, months: Int) -> Double? {
        switch campaign.priceKind {
        case .monthly:
            guard months > 0 else { return nil }
            var total = campaign.campaignPriceSEK * Double(months)
            if let after = campaign.priceAfterCampaignSEK, let promo = campaign.promoMonths, promo < months {
                // Replace the campaign price for the months after the promo
                // period with the published after-campaign price.
                total -= campaign.campaignPriceSEK * Double(months - promo)
                total += after * Double(months - promo)
            }
            return total
        case .oneTime:
            return campaign.campaignPriceSEK
        }
    }

    // MARK: Filtering & sorting

    public static func activeCampaigns(
        _ campaigns: [CampaignRecord],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [CampaignRecord] {
        campaigns.filter { status($0, now: now, calendar: calendar).isActive }
    }

    public static func filter(
        _ campaigns: [CampaignRecord],
        category: CampaignCategory?,
        query: String,
        maxMonthlySEK: Double?,
        needsVerificationOnly: Bool,
        staleAfterDays: Int,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [CampaignRecord] {
        campaigns.filter { campaign in
            guard status(campaign, now: now, calendar: calendar).isActive else { return false }
            if let category, campaign.category != category { return false }
            if let maxMonthlySEK {
                guard campaign.priceKind == .monthly, campaign.campaignPriceSEK <= maxMonthlySEK else { return false }
            }
            if needsVerificationOnly {
                let age = now.timeIntervalSince(campaign.verifiedAt) / 86_400
                guard age > Double(staleAfterDays) else { return false }
            }
            if !query.isEmpty {
                let haystack = ([campaign.title, campaign.productName, campaign.termsSummary ?? ""]
                                + campaign.includedServices)
                    .joined(separator: " ")
                    .lowercased()
                let matched = query.lowercased()
                    .split(separator: " ")
                    .contains { haystack.contains($0) }
                if !matched { return false }
            }
            return true
        }
    }

    public enum Sort: String, Codable, CaseIterable, Sendable {
        case relevance
        case expirySoonFirst
        case priceLowFirst
    }

    public static func sort(
        _ campaigns: [CampaignRecord],
        by sort: Sort,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [CampaignRecord] {
        switch sort {
        case .relevance:
            return campaigns.sorted { a, b in
                rank(a, now: now, calendar: calendar) < rank(b, now: now, calendar: calendar)
            }
        case .expirySoonFirst:
            return campaigns.sorted { a, b in
                (a.endDate ?? .distantFuture) < (b.endDate ?? .distantFuture)
            }
        case .priceLowFirst:
            return campaigns.sorted { $0.campaignPriceSEK < $1.campaignPriceSEK }
        }
    }

    private static func rank(_ c: CampaignRecord, now: Date, calendar: Calendar) -> Int {
        switch status(c, now: now, calendar: calendar) {
        case .expiresSoon: return 0
        case .active: return 1
        case .noVerifiedEndDate: return 2
        case .expired: return 3
        }
    }

    // MARK: Diff & dedupe

    /// Diff used when a refresh or import replaces the cached set, so removed
    /// or changed offers can be surfaced honestly.
    public static func diff(old: [CampaignRecord], new: [CampaignRecord]) -> CampaignDiff {
        let oldByID = Dictionary(uniqueKeysWithValues: old.map { ($0.id, $0) })
        let newByID = Dictionary(uniqueKeysWithValues: new.map { ($0.id, $0) })
        let added = new.filter { oldByID[$0.id] == nil }
        let removed = old.filter { newByID[$0.id] == nil }
        var changes: [CampaignDiff.PriceChange] = []
        for (_, fresh) in newByID {
            if let previous = oldByID[fresh.id],
               previous.campaignPriceSEK != fresh.campaignPriceSEK {
                changes.append(CampaignDiff.PriceChange(
                    id: fresh.id,
                    title: fresh.title,
                    fromSEK: previous.campaignPriceSEK,
                    toSEK: fresh.campaignPriceSEK
                ))
            }
        }
        return CampaignDiff(added: added, removed: removed, priceChanges: changes)
    }

    /// Safe merge for partial updates: keeps every valid cached record that the
    /// incoming set does not mention, so a failed/partial refresh can never
    /// silently drop campaigns.
    public static func merge(cached: [CampaignRecord], incoming: [CampaignRecord]) -> [CampaignRecord] {
        var byID = Dictionary(uniqueKeysWithValues: cached.map { ($0.id, $0) })
        for record in incoming where !record.title.isEmpty && record.campaignPriceSEK > 0 {
            byID[record.id] = record
        }
        return byID.values.sorted { $0.title < $1.title }
    }

    // MARK: Comparison

    public struct ComparisonCell: Equatable, Sendable {
        public let text: String?
        public init(_ text: String?) { self.text = text }
    }

    public struct ComparisonRow: Equatable, Sendable, Identifiable {
        public let label: String
        public let cells: [ComparisonCell]
        public var id: String { label }
    }

    /// Builds comparison rows for up to three campaigns. Missing values stay
    /// explicit ("–") rather than being invented or dropped.
    public static func comparisonRows(
        _ campaigns: [CampaignRecord],
        months: Int,
        formatter: (Double) -> String
    ) -> [ComparisonRow] {
        guard !campaigns.isEmpty else { return [] }

        func row(_ label: String, _ value: (CampaignRecord) -> String?) -> ComparisonRow {
            ComparisonRow(label: label, cells: campaigns.map { ComparisonCell(value($0)) })
        }

        var rows: [ComparisonRow] = []
        rows.append(row("Kategori") { $0.category.displayName })
        rows.append(row("Månadskostnad") { c in
            c.priceKind == .monthly ? formatter(c.campaignPriceSEK) : nil
        })
        rows.append(row("Engångspris") { c in
            c.priceKind == .oneTime ? formatter(c.campaignPriceSEK) : nil
        })
        rows.append(row("Ord. pris") { c in
            c.ordinaryPriceSEK.map(formatter)
        })
        rows.append(row("Månadsbesparing") { c in
            monthlySavingSEK(c).map(formatter)
        })
        rows.append(row("Engångsbesparing") { c in
            oneTimeSavingSEK(c).map(formatter)
        })
        rows.append(row("Totalt \(months) mån") { c in
            totalCostSEK(c, months: months).map(formatter)
        })
        rows.append(row("Kampanjpris giltigt") { c in
            c.promoMonths.map { "\($0) mån" }
        })
        rows.append(row("Pris efter kampanj") { c in
            c.priceAfterCampaignSEK.map(formatter)
        })
        rows.append(row("Bindningstid") { c in
            c.bindingMonths.map { "\($0) mån" }
        })
        rows.append(row("Ingår") { c in
            c.includedServices.isEmpty ? nil : c.includedServices.joined(separator: ", ")
        })
        rows.append(row("Villkor") { c in
            c.eligibility ?? c.exclusions
        })
        rows.append(row("Slutdatum") { c in
            guard let end = c.endDate else { return "Ej verifierat" }
            return Format.dayMonth.string(from: end)
        })
        return rows
    }
}
