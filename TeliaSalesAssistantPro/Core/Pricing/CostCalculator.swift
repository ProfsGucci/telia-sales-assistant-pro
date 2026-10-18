import Foundation

/// Pure, testable cost math. All amounts in SEK. Every function returns explicit
/// calculation lines so the UI can show its work ("Show assumptions and calculation steps").
public enum CostCalculator {

    // MARK: - Line items

    public struct CostLine: Hashable, Identifiable, Sendable {
        public var id: String { label }
        public let label: String
        public let amountSEK: Double
        /// True when the amount repeats every month of the horizon.
        public let recurring: Bool
        /// How many months the recurring amount runs (may be shorter than the horizon, e.g. campaign price).
        public let months: Int?

        public init(label: String, amountSEK: Double, recurring: Bool, months: Int? = nil) {
            self.label = label
            self.amountSEK = amountSEK
            self.recurring = recurring
            self.months = months
        }
    }

    public struct CostResult: Hashable, Sendable {
        public let lines: [CostLine]
        public let months: Int
        public let monthlyNowSEK: Double
        /// Monthly cost after any campaign period ends (equals monthlyNow when no campaign).
        public let monthlyAfterCampaignSEK: Double
        public let campaignMonths: Int
        public let oneTimeTotalSEK: Double
        public let totalSEK: Double

        public var monthlyAverageSEK: Double {
            months > 0 ? (totalSEK / Double(months)) : 0
        }
    }

    // MARK: - Helpers

    /// The recurring monthly charge right now: campaign price if present, otherwise ordinary.
    public static func currentMonthly(_ product: ProductRecord) -> Double? {
        if let m = product.monthlyPriceSEK { return m }
        return product.ordinaryMonthlyPriceSEK
    }

    /// The recurring monthly charge after any promotional period expires.
    public static func monthlyAfterCampaign(_ product: ProductRecord) -> Double? {
        product.ordinaryMonthlyPriceSEK ?? product.monthlyPriceSEK
    }

    /// Number of months the promotional price applies, counted from now.
    /// For a product with `campaignMonths` the window is that long; for one with only
    /// `campaignEnd`, the months until that date.
    public static func activeCampaignMonths(_ product: ProductRecord, from date: Date, calendar: Calendar = .current) -> Int {
        if let m = product.campaignMonths, m > 0 { return m }
        if let end = product.campaignEnd, let start = product.campaignStart, end > date {
            let days = calendar.dateComponents([.day], from: start, to: end).day ?? 0
            return max(1, Int(ceil(Double(days) / 30.0)))
        }
        return 0
    }

    // MARK: - Plan totals

    /// Total cost of a subscription over `months`, including one-time charges and
    /// recurring mandatory charges. Campaign pricing transitions to the ordinary price
    /// after the campaign window.
    public static func planTotal(
        _ product: ProductRecord,
        months: Int,
        at date: Date = Date(),
        calendar: Calendar = .current
    ) -> CostResult? {
        guard months > 0 else { return nil }
        guard let monthly = currentMonthly(product) else { return nil }

        let campaignMonths = activeCampaignMonths(product, from: date, calendar: calendar)
        let campaignRun = min(campaignMonths, months)
        let ordinary = monthlyAfterCampaign(product) ?? monthly
        let afterMonthly = max(ordinary, monthly)
        let fullPriceMonths = months - campaignRun

        var lines: [CostLine] = []
        if campaignRun > 0 {
            lines.append(CostLine(
                label: "\(product.name) – kampanjpris",
                amountSEK: monthly,
                recurring: true,
                months: campaignRun
            ))
        }
        if fullPriceMonths > 0 {
            lines.append(CostLine(
                label: campaignRun > 0 ? "\(product.name) – ordinarie pris efter kampanjen" : product.name,
                amountSEK: afterMonthly,
                recurring: true,
                months: fullPriceMonths
            ))
        }

        if let upfront = product.upfrontCostSEK, upfront > 0 {
            lines.append(CostLine(label: "Startavgift", amountSEK: upfront, recurring: false))
        }
        for charge in product.mandatoryCharges where charge.recurring {
            lines.append(CostLine(label: charge.name, amountSEK: charge.amountSEK, recurring: true, months: months))
        }
        for charge in product.mandatoryCharges where !charge.recurring {
            lines.append(CostLine(label: charge.name, amountSEK: charge.amountSEK, recurring: false))
        }

        let recurringTotal = monthly * Double(campaignRun) + afterMonthly * Double(fullPriceMonths)
        let chargeRecurring = product.mandatoryCharges.filter(\.recurring).reduce(0.0) { $0 + $1.amountSEK } * Double(months)
        let oneTime = (product.upfrontCostSEK ?? 0)
            + product.mandatoryCharges.filter { !$0.recurring }.reduce(0.0) { $0 + $1.amountSEK }

        let total = recurringTotal + chargeRecurring + oneTime

        return CostResult(
            lines: lines,
            months: months,
            monthlyNowSEK: monthly,
            monthlyAfterCampaignSEK: afterMonthly,
            campaignMonths: campaignRun,
            oneTimeTotalSEK: oneTime,
            totalSEK: total
        )
    }

    // MARK: - Devices & installments

    /// Monthly installment for a device. `residual` is a final balloon payment if any.
    public static func installmentMonthly(
        devicePriceSEK: Double,
        months: Int,
        upfrontSEK: Double = 0,
        residualSEK: Double = 0
    ) -> Double? {
        guard months > 0, devicePriceSEK >= upfrontSEK else { return nil }
        let financed = devicePriceSEK - upfrontSEK - residualSEK
        guard financed >= 0 else { return nil }
        return financed / Double(months)
    }

    /// Device bought with a plan. The device monthly price Telia quotes with a 24-month
    /// binding already bundles plan + device; this computes the device-only portion and totals.
    public static func deviceWithPlan(
        devicePriceSEK: Double,
        plan: ProductRecord,
        quotedBundleMonthlySEK: Double,
        months: Int = 24,
        upfrontSEK: Double = 0
    ) -> CostResult? {
        guard months > 0, let planMonthly = currentMonthly(plan) else { return nil }
        let deviceMonthly = quotedBundleMonthlySEK - planMonthly
        guard deviceMonthly >= 0 else { return nil }
        var lines: [CostLine] = [
            CostLine(label: "Abonnemang (\(plan.name))", amountSEK: planMonthly, recurring: true, months: months),
            CostLine(label: "Enhet (avbetalning)", amountSEK: deviceMonthly, recurring: true, months: months),
        ]
        if upfrontSEK > 0 {
            lines.append(CostLine(label: "Kontantinsats", amountSEK: upfrontSEK, recurring: false))
        }
        let total = quotedBundleMonthlySEK * Double(months) + upfrontSEK
        return CostResult(
            lines: lines,
            months: months,
            monthlyNowSEK: quotedBundleMonthlySEK,
            monthlyAfterCampaignSEK: quotedBundleMonthlySEK,
            campaignMonths: 0,
            oneTimeTotalSEK: upfrontSEK,
            totalSEK: total
        )
    }

    // MARK: - Family plan

    public struct FamilyResult: Hashable, Sendable {
        public let mainMonthlySEK: Double
        public let extraUserMonthlySEK: Double
        public let extraUsers: Int
        public let extraUserCampaignMonths: Int
        public let extraUserOrdinarySEK: Double
        public let monthlyNowSEK: Double
        public let monthlyAfterCampaignSEK: Double
        public let monthlyPerPersonSEK: Double
    }

    /// Family plan cost: one main (huvud) subscription + N extra users.
    /// `extraUserOrdinarySEK` is the post-campaign price for an extra user.
    public static func familyTotal(
        main: ProductRecord,
        extraUsers: Int,
        extraUserMonthlySEK: Double,
        extraUserOrdinarySEK: Double,
        extraUserCampaignMonths: Int
    ) -> FamilyResult? {
        guard extraUsers >= 0,
              let mainMonthly = currentMonthly(main) else { return nil }
        let now = mainMonthly + Double(extraUsers) * extraUserMonthlySEK
        let after = mainMonthly + Double(extraUsers) * extraUserOrdinarySEK
        let people = Double(extraUsers + 1)
        return FamilyResult(
            mainMonthlySEK: mainMonthly,
            extraUserMonthlySEK: extraUserMonthlySEK,
            extraUsers: extraUsers,
            extraUserCampaignMonths: extraUserCampaignMonths,
            extraUserOrdinarySEK: extraUserOrdinarySEK,
            monthlyNowSEK: now,
            monthlyAfterCampaignSEK: after,
            monthlyPerPersonSEK: now / people
        )
    }

    // MARK: - Comparison

    public struct ComparisonRow: Hashable, Identifiable, Sendable {
        public var id: String { productId }
        public let productId: String
        public let name: String
        public let monthlySEK: Double?
        public let monthlyAfterCampaignSEK: Double?
        public let bindingMonths: Int?
        public let dataLabel: String
        public let totalSEK: Double?
        public let upfrontSEK: Double?
    }

    /// Side-by-side comparison over a shared horizon.
    public static func comparison(
        _ products: [ProductRecord],
        months: Int,
        at date: Date = Date()
    ) -> [ComparisonRow] {
        products.map { p in
            let total = planTotal(p, months: months, at: date)?.totalSEK
            return ComparisonRow(
                productId: p.id,
                name: p.name,
                monthlySEK: currentMonthly(p),
                monthlyAfterCampaignSEK: monthlyAfterCampaign(p),
                bindingMonths: p.bindingMonths,
                dataLabel: p.dataLabel,
                totalSEK: total,
                upfrontSEK: p.upfrontCostSEK
            )
        }
    }
}
