import Foundation

// MARK: - Product kinds

public enum ProductKind: String, Codable, CaseIterable, Sendable {
    case mobilePlan
    case familyAddOn
    case mobileBroadband
    case broadband
    case tvPackage
    case device
    case accessory
    case service
    case fee

    public var displayName: String {
        switch self {
        case .mobilePlan: return "Mobilabonnemang"
        case .familyAddOn: return "Familj / Extra användare"
        case .mobileBroadband: return "Mobilt bredband"
        case .broadband: return "Bredband"
        case .tvPackage: return "TV & Streaming"
        case .device: return "Mobiltelefon"
        case .accessory: return "Tillbehör"
        case .service: return "Tjänst"
        case .fee: return "Avgift"
        }
    }

    public var symbolName: String {
        switch self {
        case .mobilePlan: return "antenna.radiowaves.left.and.right"
        case .familyAddOn: return "person.2.fill"
        case .mobileBroadband: return "wifi.router"
        case .broadband: return "house.badge.wifi"
        case .tvPackage: return "tv.fill"
        case .device: return "iphone.gen3"
        case .accessory: return "headphones"
        case .service: return "shield.checkerboard"
        case .fee: return "doc.text.fill"
        }
    }
}

// MARK: - Verification

/// How trustworthy a piece of price data is. The app surfaces this on every price.
public enum VerificationStatus: String, Codable, CaseIterable, Sendable {
    /// Price read directly from an official Telia page by the person maintaining the data,
    /// or imported from a feed the user trusts. Shows date + source link.
    case verified
    /// Structure known from official sources but the price itself was not directly confirmed.
    case unverified
    /// A campaign whose promotional window has ended; must never be shown as an active offer.
    case expired
    /// Imported from a user-provided feed/CSV without a source URL.
    case imported

    public var label: String {
        switch self {
        case .verified: return "Verifierat"
        case .unverified: return "Overifierat"
        case .expired: return "Utgånget"
        case .imported: return "Importerat"
        }
    }
}

// MARK: - Charges

/// One line of cost attached to a product, e.g. startavgift or fakturaavgift.
public struct ChargeItem: Codable, Hashable, Identifiable, Sendable {
    public var id: String { name }
    public let name: String
    /// SEK per month when `recurring` is true, otherwise a one-time amount.
    public let amountSEK: Double
    public let recurring: Bool

    public init(name: String, amountSEK: Double, recurring: Bool) {
        self.name = name
        self.amountSEK = amountSEK
        self.recurring = recurring
    }
}

// MARK: - Product record

public struct ProductRecord: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let kind: ProductKind
    /// Sub-group used for filter chips, e.g. "Obegränsad Plus", "Ungdom", "5G-bredband".
    public let category: String
    public let brand: String?

    /// Current monthly price in SEK (promotional price when a campaign is active).
    public let monthlyPriceSEK: Double?
    /// Ordinary monthly price in SEK, when the product is currently discounted.
    public let ordinaryMonthlyPriceSEK: Double?
    /// One-time start/upfront cost in SEK. Telia states startavgift is free online.
    public let upfrontCostSEK: Double?
    /// Months of commitment, 0 or nil = no binding.
    public let bindingMonths: Int?
    /// Months the promotional price applies before it returns to `ordinaryMonthlyPriceSEK`.
    public let campaignMonths: Int?
    /// Full cash price for devices (device-only purchase, no plan).
    public let cashPriceSEK: Double?

    public let dataGB: Double?
    public let unlimitedData: Bool
    public let speedMbit: Double?
    public let includedServices: [String]
    public let highlights: [String]

    public let campaignStart: Date?
    public let campaignEnd: Date?
    public let eligibilityNotes: String?
    public let mandatoryCharges: [ChargeItem]

    public let sourceURL: String?
    public let sourceName: String?
    /// When this record was last confirmed against the source.
    public let verifiedAt: Date?
    public let verification: VerificationStatus
    public let tags: [String]

    public init(
        id: String,
        name: String,
        kind: ProductKind,
        category: String,
        brand: String? = nil,
        monthlyPriceSEK: Double? = nil,
        ordinaryMonthlyPriceSEK: Double? = nil,
        upfrontCostSEK: Double? = nil,
        bindingMonths: Int? = nil,
        campaignMonths: Int? = nil,
        cashPriceSEK: Double? = nil,
        dataGB: Double? = nil,
        unlimitedData: Bool = false,
        speedMbit: Double? = nil,
        includedServices: [String] = [],
        highlights: [String] = [],
        campaignStart: Date? = nil,
        campaignEnd: Date? = nil,
        eligibilityNotes: String? = nil,
        mandatoryCharges: [ChargeItem] = [],
        sourceURL: String? = nil,
        sourceName: String? = nil,
        verifiedAt: Date? = nil,
        verification: VerificationStatus = .unverified,
        tags: [String] = []
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.category = category
        self.brand = brand
        self.monthlyPriceSEK = monthlyPriceSEK
        self.ordinaryMonthlyPriceSEK = ordinaryMonthlyPriceSEK
        self.upfrontCostSEK = upfrontCostSEK
        self.bindingMonths = bindingMonths
        self.campaignMonths = campaignMonths
        self.cashPriceSEK = cashPriceSEK
        self.dataGB = dataGB
        self.unlimitedData = unlimitedData
        self.speedMbit = speedMbit
        self.includedServices = includedServices
        self.highlights = highlights
        self.campaignStart = campaignStart
        self.campaignEnd = campaignEnd
        self.eligibilityNotes = eligibilityNotes
        self.mandatoryCharges = mandatoryCharges
        self.sourceURL = sourceURL
        self.sourceName = sourceName
        self.verifiedAt = verifiedAt
        self.verification = verification
        self.tags = tags
    }

    public enum CodingKeys: String, CodingKey {
        case id, name, kind, category, brand
        case monthlyPriceSEK, ordinaryMonthlyPriceSEK, upfrontCostSEK
        case bindingMonths, campaignMonths, cashPriceSEK
        case dataGB, unlimitedData, speedMbit
        case includedServices, highlights
        case campaignStart, campaignEnd, eligibilityNotes, mandatoryCharges
        case sourceURL, sourceName, verifiedAt, verification, tags
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        kind = try c.decode(ProductKind.self, forKey: .kind)
        category = try c.decode(String.self, forKey: .category)
        brand = try c.decodeIfPresent(String.self, forKey: .brand)
        monthlyPriceSEK = try c.decodeIfPresent(Double.self, forKey: .monthlyPriceSEK)
        ordinaryMonthlyPriceSEK = try c.decodeIfPresent(Double.self, forKey: .ordinaryMonthlyPriceSEK)
        upfrontCostSEK = try c.decodeIfPresent(Double.self, forKey: .upfrontCostSEK)
        bindingMonths = try c.decodeIfPresent(Int.self, forKey: .bindingMonths)
        campaignMonths = try c.decodeIfPresent(Int.self, forKey: .campaignMonths)
        cashPriceSEK = try c.decodeIfPresent(Double.self, forKey: .cashPriceSEK)
        dataGB = try c.decodeIfPresent(Double.self, forKey: .dataGB)
        unlimitedData = try c.decodeIfPresent(Bool.self, forKey: .unlimitedData) ?? false
        speedMbit = try c.decodeIfPresent(Double.self, forKey: .speedMbit)
        includedServices = try c.decodeIfPresent([String].self, forKey: .includedServices) ?? []
        highlights = try c.decodeIfPresent([String].self, forKey: .highlights) ?? []
        campaignStart = try c.decodeIfPresent(Date.self, forKey: .campaignStart)
        campaignEnd = try c.decodeIfPresent(Date.self, forKey: .campaignEnd)
        eligibilityNotes = try c.decodeIfPresent(String.self, forKey: .eligibilityNotes)
        mandatoryCharges = try c.decodeIfPresent([ChargeItem].self, forKey: .mandatoryCharges) ?? []
        sourceURL = try c.decodeIfPresent(String.self, forKey: .sourceURL)
        sourceName = try c.decodeIfPresent(String.self, forKey: .sourceName)
        verifiedAt = try c.decodeIfPresent(Date.self, forKey: .verifiedAt)
        verification = try c.decodeIfPresent(VerificationStatus.self, forKey: .verification) ?? .unverified
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
    }

    public var hasCampaign: Bool {
        guard let ordinary = ordinaryMonthlyPriceSEK, let current = monthlyPriceSEK else { return false }
        return current < ordinary
    }

    /// True when the product is free to combine: no binding period.
    public var isUnbound: Bool { (bindingMonths ?? 0) == 0 }

    public var dataLabel: String {
        if unlimitedData { return "Obegränsad surf" }
        guard let gb = dataGB else { return "" }
        return gb.truncatingRemainder(dividingBy: 1) == 0
            ? "\(Int(gb)) GB"
            : String(format: "%.1f GB", gb)
    }
}

// MARK: - Catalog snapshot

public struct CatalogSnapshot: Codable, Sendable {
    public var products: [ProductRecord]
    public var generatedAt: Date
    /// Human note about where this data came from, shown in the app.
    public var sourceNote: String
    public var schemaVersion: Int

    public init(
        products: [ProductRecord],
        generatedAt: Date,
        sourceNote: String,
        schemaVersion: Int = 1
    ) {
        self.products = products
        self.generatedAt = generatedAt
        self.sourceNote = sourceNote
        self.schemaVersion = schemaVersion
    }

    public func product(id: String) -> ProductRecord? {
        products.first { $0.id == id }
    }
}
