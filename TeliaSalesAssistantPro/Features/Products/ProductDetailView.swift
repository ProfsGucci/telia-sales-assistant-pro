import SwiftUI
import TeliaCore

struct ProductDetailView: View {
    let productID: String

    @EnvironmentObject private var catalog: CatalogStore
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.openURL) private var openURL

    private var product: ProductRecord? {
        catalog.product(id: productID)
    }

    var body: some View {
        Group {
            if let product = product {
                content(product)
            } else {
                EmptyStateView(
                    symbol: "questionmark.folder",
                    title: "Produkten hittades inte",
                    message: "Prisdata kan ha uppdaterats. Gå tillbaka och sök igen."
                )
                .padding()
            }
        }
        .navigationTitle(product?.name ?? "Produkt")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if let p = product { library.recordView(productID: p.id) }
        }
    }

    @ViewBuilder
    private func content(_ product: ProductRecord) -> some View {
        ScrollView {
            VStack(spacing: DS.Space.m) {
                priceCard(product)
                factsCard(product)
                if !product.includedServices.isEmpty { servicesCard(product) }
                if !product.highlights.isEmpty { highlightsCard(product) }
                if !product.mandatoryCharges.isEmpty { chargesCard(product) }
                if product.eligibilityNotes != nil { termsCard(product) }
                sourceCard(product)
                actionsCard(product)
            }
            .padding(.horizontal, DS.Space.m)
            .padding(.bottom, DS.Space.xl)
        }
        // Transparent so the app-wide premium canvas shows through.
    }

    private func priceCard(_ product: ProductRecord) -> some View {
        SectionCard(title: "Pris", symbol: "banknote") {
            VStack(alignment: .leading, spacing: DS.Space.m) {
                PriceText(
                    monthly: CostCalculator.currentMonthly(product),
                    ordinary: product.ordinaryMonthlyPriceSEK,
                    large: true
                )
                HStack(spacing: DS.Space.s) {
                    CampaignBadge(status: PriceVerification.campaignStatus(product))
                    Chip(text: product.isUnbound ? "Ingen bindningstid" : "\(product.bindingMonths ?? 0) mån bindning", color: .blue)
                    if let upfront = product.upfrontCostSEK, upfront > 0 {
                        Chip(text: "Start \(Int(upfront)) kr", color: .orange)
                    } else if product.kind == .mobilePlan || product.kind == .broadband {
                        Chip(text: "0 kr startavgift online", color: .green)
                    }
                }
                if product.hasCampaign, let months = product.campaignMonths {
                    Label("Kampanjpris i \(months) månader, därefter \(Format.monthly(CostCalculator.monthlyAfterCampaign(product)))",
                          systemImage: "clock")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                if let cash = product.cashPriceSEK {
                    Label("Kontantpris: \(Format.sekPlain(cash))", systemImage: "banknote")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                if let months = product.campaignMonths, product.hasCampaign {
                    totalPreview(product, campaignMonths: months)
                } else if product.kind == .mobilePlan || product.kind == .broadband || product.kind == .tvPackage {
                    totalPreview(product, campaignMonths: 0)
                }
            }
        }
    }

    private func totalPreview(_ product: ProductRecord, campaignMonths: Int) -> some View {
        Group {
            if let result = CostCalculator.planTotal(product, months: 24) {
                VStack(alignment: .leading, spacing: 4) {
                    Divider()
                    HStack {
                        Text("Totalt 24 mån")
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        Spacer()
                        Text(Format.sekPlain(result.totalSEK))
                            .font(.system(.subheadline, design: .rounded).weight(.bold))
                    }
                    Text("Snitt \(Format.sekPlain(result.monthlyAverageSEK))/mån inkl. engångskostnader")
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func factsCard(_ product: ProductRecord) -> some View {
        SectionCard(title: "Fakta", symbol: "info.circle") {
            VStack(spacing: DS.Space.s) {
                factRow("Kategori", product.kind.displayName)
                if !product.dataLabel.isEmpty { factRow("Surf", product.dataLabel) }
                if let speed = product.speedMbit { factRow("Hastighet", "Upp till \(Int(speed)) Mbit/s") }
                if let brand = product.brand { factRow("Märke", brand) }
                factRow("Bindningstid", product.isUnbound ? "Ingen" : "\(product.bindingMonths ?? 0) månader")
                if let verified = product.verifiedAt {
                    factRow("Verifierad", Format.dayMonth.string(from: verified))
                }
            }
        }
    }

    private func factRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(.subheadline, design: .rounded).weight(.medium))
        }
    }

    private func servicesCard(_ product: ProductRecord) -> some View {
        SectionCard(title: "Ingår", symbol: "checkmark.seal") {
            VStack(alignment: .leading, spacing: DS.Space.s) {
                ForEach(product.includedServices, id: \.self) { service in
                    HStack(alignment: .top, spacing: DS.Space.s) {
                        Image(systemName: "checkmark")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(DS.Purple.base)
                            .padding(.top, 2)
                        Text(service)
                            .font(.system(.subheadline, design: .rounded))
                    }
                }
            }
        }
    }

    private func highlightsCard(_ product: ProductRecord) -> some View {
        SectionCard(title: "Bra att veta", symbol: "sparkles") {
            VStack(alignment: .leading, spacing: DS.Space.s) {
                ForEach(product.highlights, id: \.self) { highlight in
                    Label(highlight, systemImage: "star.leadinghalf.filled")
                        .font(.system(.subheadline, design: .rounded))
                }
            }
        }
    }

    private func chargesCard(_ product: ProductRecord) -> some View {
        SectionCard(title: "Avgifter", symbol: "doc.text") {
            VStack(spacing: DS.Space.s) {
                ForEach(product.mandatoryCharges) { charge in
                    HStack {
                        Text(charge.name)
                            .font(.system(.subheadline, design: .rounded))
                        Spacer()
                        Text(charge.recurring ? "\(Int(charge.amountSEK)) kr/faktura" : "\(Int(charge.amountSEK)) kr engångs")
                            .font(.system(.subheadline, design: .rounded).weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func termsCard(_ product: ProductRecord) -> some View {
        SectionCard(title: "Villkor", symbol: "text.page") {
            Text(product.eligibilityNotes ?? "")
                .font(.system(.subheadline, design: .rounded))
        }
    }

    private func sourceCard(_ product: ProductRecord) -> some View {
        SectionCard(title: "Källa & verifiering", symbol: "link") {
            VStack(alignment: .leading, spacing: DS.Space.m) {
                HStack {
                    VerificationBadge(status: product.verification, freshness: PriceVerification.freshness(of: product))
                    Spacer()
                }
                if let verified = product.verifiedAt {
                    Text("Senast verifierad \(Format.dateTime.string(from: verified))")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                if product.verification != .verified {
                    Text("Priset är inte verifierat. Kontrollera källan innan du citerar det till kunder.")
                        .font(.system(.caption, design: .rounded).weight(.medium))
                        .foregroundStyle(.orange)
                }
                if let urlString = product.sourceURL, let url = URL(string: urlString) {
                    Button {
                        openURL(url)
                    } label: {
                        Label(product.sourceName ?? "Öppna källan på telia.se", systemImage: "safari")
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: DS.Radius.tile, style: .continuous)
                                    .fill(DS.Purple.base.opacity(0.12))
                            )
                    }
                    .buttonStyle(PressableStyle())
                }
            }
        }
    }

    private func actionsCard(_ product: ProductRecord) -> some View {
        HStack(spacing: DS.Space.m) {
            Button {
                library.toggleFavorite(product.id)
                Haptics.tap()
            } label: {
                VStack(spacing: 6) {
                    Image(systemName: library.isFavorite(product.id) ? "heart.fill" : "heart")
                        .font(.system(.body))
                    Text("Favorit")
                        .font(.system(.caption2, design: .rounded))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, DS.Space.m)
                .background(
                    RoundedRectangle(cornerRadius: DS.Radius.tile, style: .continuous)
                        .fill(DS.Surface.inset)
                )
                .foregroundStyle(library.isFavorite(product.id) ? .pink : Color.primary)
            }
            .buttonStyle(PressableStyle())

            Button {
                catalog.toggleCompare(product.id)
                Haptics.tap()
            } label: {
                VStack(spacing: 6) {
                    Image(systemName: catalog.compareIDs.contains(product.id) ? "checkmark.square.fill" : "square.split.2x1")
                        .font(.system(.body))
                        .foregroundStyle(DS.Purple.base)
                    Text("Jämför")
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(.primary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, DS.Space.m)
                .background(
                    RoundedRectangle(cornerRadius: DS.Radius.tile, style: .continuous)
                        .fill(DS.Surface.inset)
                )
            }
            .buttonStyle(PressableStyle())
        }
    }
}
