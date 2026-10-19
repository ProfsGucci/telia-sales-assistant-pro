import SwiftUI
import UIKit
import TeliaCore

// MARK: - Detail

/// Dedicated route so related-product pushes never collide with the String
/// product destinations other screens register in the same stack.
struct CampaignProductRoute: Hashable {
    let productID: String
}

struct CampaignDetailView: View {
    @EnvironmentObject private var campaigns: CampaignStore
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var catalog: CatalogStore
    @EnvironmentObject private var appState: AppState

    let campaign: CampaignRecord

    @State private var compareIDs: [String] = []
    @State private var showCompare = false
    @State private var copied = false

    private var status: CampaignStatus { CampaignEngine.status(campaign) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.m) {
                headerCard
                pricingCard
                termsCard
                if !campaign.includedServices.isEmpty {
                    servicesCard
                }
                if !campaign.relatedProductIDs.isEmpty {
                    relatedCard
                }
                sourceCard
                footer
            }
            .padding(.horizontal, DS.Space.m)
            .padding(.bottom, DS.Space.xl)
        }
        .navigationTitle("Kampanj")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    campaigns.toggleFavorite(campaign.id)
                } label: {
                    Image(systemName: campaigns.isFavorite(campaign.id) ? "star.fill" : "star")
                }
                .accessibilityLabel(campaigns.isFavorite(campaign.id) ? "Ta bort favorit" : "Spara som favorit")
            }
        }
        .sheet(isPresented: $showCompare) {
            CampaignCompareView(ids: compareIDs)
        }
        .navigationDestination(for: CampaignProductRoute.self) { route in
            ProductDetailView(productID: route.productID)
        }
        .onAppear {
            campaigns.recordView(id: campaign.id)
            compareIDs = [campaign.id]
        }
    }

    // MARK: Header

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            HStack(spacing: DS.Space.s) {
                Image(systemName: campaign.category.symbolName)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(DS.heroGradient, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(campaign.title)
                        .font(.system(.headline, design: .rounded))
                    Text("\(campaign.category.displayName) · \(campaign.productName)")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            expiryLine
        }
        .padding(DS.Space.m)
        .card(gradient: true)
    }

    @ViewBuilder
    private var expiryLine: some View {
        switch status {
        case .expiresSoon(let days):
            Label(days <= 1 ? "Slutar idag enligt verifierat slutdatum" : "Slutar om \(days) dagar (\(Format.dayMonth.string(from: campaign.endDate ?? Date())))",
                  systemImage: "hourglass")
                .font(.system(.caption, design: .rounded).weight(.medium))
                .foregroundStyle(DS.warning)
        case .active:
            if let end = campaign.endDate {
                Label("Giltig t.o.m. \(Format.dayMonth.string(from: end)) enligt källan",
                      systemImage: "calendar")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(DS.positive)
            }
        case .noVerifiedEndDate:
            Label("Källan anger inget slutdatum – verifiera att kampanjen fortfarande gäller på telia.se",
                  systemImage: "questionmark.circle")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(.secondary)
        case .expired:
            Label("Kampanjen har utgått enligt verifierat slutdatum och kan inte längre citeras som aktuell",
                  systemImage: "xmark.circle")
                .font(.system(.caption, design: .rounded).weight(.medium))
                .foregroundStyle(DS.negative)
        }
    }

    // MARK: Pricing

    private var pricingCard: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            cardTitle("Priser", icon: "banknote")
            VStack(spacing: 0) {
                priceRow("Kampanjpris",
                         campaign.priceKind == .monthly
                         ? "\(Format.sekPlain(campaign.campaignPriceSEK)) / mån"
                         : "\(Format.sekPlain(campaign.campaignPriceSEK)) engångspris",
                         bold: true)
                if let ordinary = campaign.ordinaryPriceSEK {
                    priceRow("Ordinarie pris",
                             campaign.priceKind == .monthly
                             ? "\(Format.sekPlain(ordinary)) / mån"
                             : Format.sekPlain(ordinary))
                }
                if let saving = comparableSaving, saving > 0 {
                    priceRow("Besparing",
                             "−\(Format.sekPlain(saving)) \(campaign.priceKind == .monthly ? "/ mån" : "engångs")",
                             tint: DS.positive)
                }
                if let promo = campaign.promoMonths {
                    priceRow("Kampanjpris giltigt", "\(promo) mån")
                }
                if let after = campaign.priceAfterCampaignSEK {
                    priceRow("Pris efter kampanjen", "\(Format.sekPlain(after)) / mån")
                }
                if let binding = campaign.bindingMonths {
                    priceRow("Bindningstid", binding > 0 ? "\(binding) mån" : "Ingen")
                }
                if let value = campaign.oneTimeValueSEK {
                    priceRow("Ingående hårdvara", "värde \(Format.sekPlain(value))")
                }
                priceRow("Totalkostnad 12 mån",
                         CampaignEngine.totalCostSEK(campaign, months: 12).map { "\(Format.sekPlain($0))" } ?? "–")
                priceRow("Totalkostnad 24 mån",
                         CampaignEngine.totalCostSEK(campaign, months: 24).map { "\(Format.sekPlain($0))" } ?? "–")
            }
            if campaign.ordinaryPriceSEK == nil {
                Text("Ordinarie pris är inte publicerat i källan – därför visas ingen beräknad besparing.")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(DS.Space.m)
        .card()
    }

    private var comparableSaving: Double? {
        campaign.priceKind == .monthly
            ? CampaignEngine.monthlySavingSEK(campaign)
            : CampaignEngine.oneTimeSavingSEK(campaign)
    }

    private func cardTitle(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.system(.subheadline, design: .rounded).weight(.semibold))
    }

    @ViewBuilder
    private func priceRow(_ label: String, _ value: String, bold: Bool = false, tint: Color? = nil) -> some View {
        HStack {
            Text(label)
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(bold ? .subheadline : .body, design: .rounded).weight(bold ? .bold : .regular))
                .foregroundStyle(tint ?? DS.Purple.base)
        }
        .padding(.vertical, 7)
    }

    // MARK: Terms

    private var termsCard: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            cardTitle("Villkor", icon: "doc.text")
            VStack(alignment: .leading, spacing: DS.Space.s) {
                if let eligibility = campaign.eligibility {
                    termRow("Krav", eligibility)
                }
                if let exclusions = campaign.exclusions {
                    termRow("Undantas", exclusions)
                }
                if let terms = campaign.termsSummary {
                    termRow("Villkor", terms)
                }
                if let notes = campaign.notes {
                    termRow("Notering", notes)
                }
            }
        }
        .padding(DS.Space.m)
        .card()
    }

    private func termRow(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.system(.caption2, design: .rounded).weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.subheadline, design: .rounded))
        }
    }

    // MARK: Services

    private var servicesCard: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            cardTitle("Ingår", icon: "checkmark.seal")
            ForEach(campaign.includedServices, id: \.self) { service in
                HStack(alignment: .top, spacing: DS.Space.s) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(DS.positive)
                        .padding(.top, 3)
                    Text(service)
                        .font(.system(.subheadline, design: .rounded))
                }
            }
        }
        .padding(DS.Space.m)
        .card()
    }

    // MARK: Related products

    private var relatedCard: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            cardTitle("Relaterade produkter", icon: "cart")
            ForEach(campaign.relatedProductIDs, id: \.self) { productID in
                if let product = catalog.product(id: productID) {
                    NavigationLink(value: CampaignProductRoute(productID: productID)) {
                        HStack {
                            Text(product.name)
                                .font(.system(.subheadline, design: .rounded))
                                .foregroundStyle(.primary)
                            Spacer()
                            Text(Format.monthly(CostCalculator.currentMonthly(product)))
                                .font(.system(.caption, design: .rounded))
                                .foregroundStyle(DS.Purple.base)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(DS.Space.m)
        .card()
    }

    // MARK: Source & actions

    private var sourceCard: some View {
        VStack(alignment: .leading, spacing: DS.Space.m) {
            cardTitle("Källa & verifiering", icon: "link")
            VStack(alignment: .leading, spacing: DS.Space.s) {
                Text("Verifierad \(Format.dateTime.string(from: campaign.verifiedAt)) mot \(campaign.sourceName).")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
                if let url = URL(string: campaign.sourceURL) {
                    Link(destination: url) {
                        Label("Öppna originalerbjudandet på telia.se", systemImage: "safari")
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(BorderedProminentButtonStyle())
                    .tint(DS.Purple.base)
                }
                SecondaryButton(
                    title: copied ? "Kopierat!" : "Kopiera kundförklaring",
                    symbol: copied ? "checkmark" : "doc.on.doc"
                ) {
                    copyExplanation()
                }
                SecondaryButton(
                    title: "Jämför med andra kampanjer",
                    symbol: "square.split.2x1"
                ) {
                    compareIDs = [campaign.id]
                    for other in campaigns.favoriteCampaigns where other.id != campaign.id && compareIDs.count < 3 {
                        compareIDs.append(other.id)
                    }
                    showCompare = true
                }
                SecondaryButton(
                    title: "Öva med AI-coachen",
                    symbol: "bubble.left.and.text.bubble.right.fill"
                ) {
                    // Verified campaign facts travel with the question —
                    // the coach never invents terms. The user sends it.
                    Haptics.tap()
                    appState.coachSeed = "Hjälp mig förklara kampanjen \"\(campaign.title)\" för en kund: kampanjpris \(Int(campaign.campaignPriceSEK)) kr\(campaign.ordinaryPriceSEK != nil ? ", ordinarie \(Int(campaign.ordinaryPriceSEK!)) kr" : "")\(campaign.bindingMonths != nil ? ", bindningstid \(campaign.bindingMonths!) mån" : ""). Ge mig en kort kundförklaring, vanliga invändningar och svar, samt en rimlig följdfråga. Använd bara verifierade villkor — påtala om något är oklart."
                    appState.selectedTab = .coach
                }
            }
        }
        .padding(DS.Space.m)
        .card()
    }

    private var footer: some View {
        Text("Appen kan inte aktivera kampanjen eller reservera lager – avsluta alltid i Telias egna kanaler. Ej en officiell Telia-app.")
            .font(.system(.caption2, design: .rounded))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.top, DS.Space.s)
    }

    /// Plain-Swedish summary a seller can paste into notes or messages.
    private func copyExplanation() {
        var lines: [String] = []
        lines.append("\(campaign.title) (Telia)")
        lines.append(campaign.priceKind == .monthly
                     ? "Kampanjpris: \(Format.sekPlain(campaign.campaignPriceSEK)) kr/mån"
                     : "Kampanjpris: \(Format.sekPlain(campaign.campaignPriceSEK)) kr engångspris")
        if let ordinary = campaign.ordinaryPriceSEK {
            lines.append("Ordinarie pris: \(Format.sekPlain(ordinary)) kr\(campaign.priceKind == .monthly ? "/mån" : "")")
        }
        if let promo = campaign.promoMonths {
            lines.append("Gäller i \(promo) mån" + (campaign.priceAfterCampaignSEK.map { ", därefter \(Format.sekPlain($0)) kr/mån" } ?? ""))
        }
        if let binding = campaign.bindingMonths, binding > 0 {
            lines.append("Bindningstid: \(binding) mån")
        }
        if let end = campaign.endDate {
            lines.append("Slutdatum enligt telia.se: \(Format.dayMonth.string(from: end))")
        } else {
            lines.append("Slutdatum: ej angivet – kontrollera telia.se")
        }
        if let eligibility = campaign.eligibility {
            lines.append("Krav: \(eligibility)")
        }
        lines.append("Källa: \(campaign.sourceURL) (verifierad \(Format.dayMonth.string(from: campaign.verifiedAt)))")
        UIPasteboard.general.string = lines.joined(separator: "\n")
        withAnimation(.easeOut(duration: 0.2)) { copied = true }
        Task {
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            await MainActor.run { withAnimation(.easeOut(duration: 0.2)) { copied = false } }
        }
    }
}

// MARK: - Compare

struct CampaignCompareView: View {
    @EnvironmentObject private var campaigns: CampaignStore
    @Environment(\.dismiss) private var dismiss

    let ids: [String]

    @State private var months = 24

    private var records: [CampaignRecord] {
        ids.prefix(3).compactMap { campaigns.campaign(id: $0) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.m) {
                    horizonPicker
                    compareGrid
                    hint
                }
                .padding(.horizontal, DS.Space.m)
                .padding(.bottom, DS.Space.xl)
            }
            .background(Color(.systemBackground))
            .navigationTitle("Jämför kampanjer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Klar") { dismiss() }
                }
            }
        }
    }

    private var horizonPicker: some View {
        Picker("Beräkningsperiod", selection: $months) {
            Text("12 mån").tag(12)
            Text("24 mån").tag(24)
        }
        .pickerStyle(.segmented)
    }

    private var compareGrid: some View {
        let rows = CampaignEngine.comparisonRows(records, months: months) { Format.sekPlain($0) }
        return VStack(alignment: .leading, spacing: 0) {
            // Header row: campaign titles
            HStack(alignment: .top, spacing: DS.Space.s) {
                Text("")
                    .frame(width: 92, alignment: .leading)
                ForEach(records) { record in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(record.title)
                            .font(.system(.caption, design: .rounded).weight(.semibold))
                            .lineLimit(3)
                        Text(record.productName)
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.bottom, DS.Space.s)
            Divider()
            ForEach(rows) { row in
                VStack(spacing: 0) {
                    HStack(alignment: .top, spacing: DS.Space.s) {
                        Text(row.label)
                            .font(.system(.caption2, design: .rounded).weight(.medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 92, alignment: .leading)
                        ForEach(Array(row.cells.enumerated()), id: \.offset) { index, cell in
                            Text(cell.text ?? "–")
                                .font(.system(.caption, design: .rounded).weight(cell.text == nil ? .regular : .medium))
                                .foregroundStyle(cell.text == nil ? Color.secondary : Color.primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .multilineTextAlignment(.leading)
                        }
                    }
                    .padding(.vertical, 8)
                    Divider()
                }
            }
        }
        .padding(DS.Space.m)
        .card()
    }

    private var hint: some View {
        Text("– betyder att uppgiften inte finns i den verifierade källan. Totalkostnaden räknar in publicerat pris efter kampanjperiod när det finns.")
            .font(.system(.caption2, design: .rounded))
            .foregroundStyle(.secondary)
    }
}
