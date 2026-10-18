import Foundation

/// Verifies price freshness, campaign validity, and detects price changes between snapshots.
public enum PriceVerification {

    // MARK: - Freshness

    public enum Freshness: String, Codable, Sendable {
        case fresh
        case aging
        case stale
        case unknown

        public var label: String {
            switch self {
            case .fresh: return "Aktuell data"
            case .aging: return "Bör verifieras"
            case .stale: return "Gammal data"
            case .unknown: return "Okänd ålder"
            }
        }
    }

    /// Freshness is judged on `verifiedAt`. Data with no verification date is `unknown`.
    public static func freshness(
        of product: ProductRecord,
        now: Date = Date(),
        agingDays: Int = 7,
        staleDays: Int = 30
    ) -> Freshness {
        guard let verified = product.verifiedAt else { return .unknown }
        let days = daysBetween(verified, now)
        if days < 0 { return .unknown }
        if days <= agingDays { return .fresh }
        if days <= staleDays { return .aging }
        return .stale
    }

    static func daysBetween(_ a: Date, _ b: Date, calendar: Calendar = .current) -> Int {
        let start = calendar.startOfDay(for: a)
        let end = calendar.startOfDay(for: b)
        return calendar.dateComponents([.day], from: start, to: end).day ?? 0
    }

    // MARK: - Campaign status

    public enum CampaignStatus: String, Codable, Sendable {
        case activeCampaign
        case endsSoon
        case noCampaign
        case expired

        public var label: String {
            switch self {
            case .activeCampaign: return "Kampanj"
            case .endsSoon: return "Kampanj – snart slut"
            case .noCampaign: return "Ordinarie pris"
            case .expired: return "Kampanjen har upphört"
            }
        }
    }

    public static func campaignStatus(
        _ product: ProductRecord,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> CampaignStatus {
        if let end = product.campaignEnd {
            if let start = product.campaignStart, now < start { return .expired }
            if now > end { return .expired }
            let daysLeft = daysBetween(now, end, calendar: calendar)
            if daysLeft <= 14 { return .endsSoon }
            return .activeCampaign
        }
        if product.hasCampaign { return .activeCampaign }
        return .noCampaign
    }

    /// Whether the product may be presented as an active offer right now.
    /// Expired promotions must never be presented as active.
    public static func isActiveOffer(_ product: ProductRecord, now: Date = Date()) -> Bool {
        if product.verification == .expired { return false }
        return campaignStatus(product, now: now) != .expired
    }

    // MARK: - Change detection

    public enum ChangeField: String, Codable, Sendable {
        case monthlyPrice
        case ordinaryPrice
        case upfrontCost
        case bindingMonths
        case added
        case removed
    }

    public struct PriceChange: Codable, Hashable, Identifiable, Sendable {
        public var id: String { "\(productId)-\(field.rawValue)-\(Int(detectedAt.timeIntervalSince1970))" }
        public let productId: String
        public let productName: String
        public let field: ChangeField
        public let oldValue: String
        public let newValue: String
        public let detectedAt: Date
    }

    /// Diff two product lists and return human-readable changes.
    public static func diff(
        old: [ProductRecord],
        new: [ProductRecord],
        detectedAt: Date = Date()
    ) -> [PriceChange] {
        var changes: [PriceChange] = []
        let oldByID = Dictionary(uniqueKeysWithValues: old.map { ($0.id, $0) })

        for product in new {
            if let before = oldByID[product.id] {
                if let oldP = before.monthlyPriceSEK, let newP = product.monthlyPriceSEK, oldP != newP {
                    changes.append(PriceChange(
                        productId: product.id, productName: product.name,
                        field: .monthlyPrice,
                        oldValue: sekw(oldP), newValue: sekw(newP), detectedAt: detectedAt
                    ))
                }
                if let oldP = before.ordinaryMonthlyPriceSEK, let newP = product.ordinaryMonthlyPriceSEK, oldP != newP {
                    changes.append(PriceChange(
                        productId: product.id, productName: product.name,
                        field: .ordinaryPrice,
                        oldValue: sekw(oldP), newValue: sekw(newP), detectedAt: detectedAt
                    ))
                }
                if let oldP = before.upfrontCostSEK, let newP = product.upfrontCostSEK, oldP != newP {
                    changes.append(PriceChange(
                        productId: product.id, productName: product.name,
                        field: .upfrontCost,
                        oldValue: sekw(oldP), newValue: sekw(newP), detectedAt: detectedAt
                    ))
                }
                if before.bindingMonths != product.bindingMonths {
                    changes.append(PriceChange(
                        productId: product.id, productName: product.name,
                        field: .bindingMonths,
                        oldValue: bindingLabel(before.bindingMonths),
                        newValue: bindingLabel(product.bindingMonths),
                        detectedAt: detectedAt
                    ))
                }
            } else {
                changes.append(PriceChange(
                    productId: product.id, productName: product.name,
                    field: .added,
                    oldValue: "—", newValue: product.monthlyPriceSEK.map(sekw) ?? "ny",
                    detectedAt: detectedAt
                ))
            }
        }

        let newIDs = Set(new.map(\.id))
        for product in old where !newIDs.contains(product.id) {
            changes.append(PriceChange(
                productId: product.id, productName: product.name,
                field: .removed,
                oldValue: product.monthlyPriceSEK.map(sekw) ?? "—", newValue: "—",
                detectedAt: detectedAt
            ))
        }
        return changes
    }

    static func sekw(_ value: Double) -> String {
        let rounded = value.rounded()
        if rounded == value { return "\(Int(rounded)) kr" }
        return String(format: "%.2f kr", value)
    }

    static func bindingLabel(_ months: Int?) -> String {
        guard let m = months, m > 0 else { return "Ingen bindningstid" }
        return "\(m) mån"
    }
}
