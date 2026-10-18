import SwiftUI
import TeliaCore

// MARK: - Kampanj Center (top level)

struct CampaignCenterView: View {
    @EnvironmentObject private var campaigns: CampaignStore
    @EnvironmentObject private var settings: SettingsStore

    @State private var query = ""
    @State private var category: CampaignCategory?
    @State private var sort: CampaignEngine.Sort = .relevance
    @State private var onlyNeedsVerification = false
    @State private var favoritesOnly = false
    @State private var compareIDs: [String] = []
    @State private var showCompare = false

    private var filtered: [CampaignRecord] {
        let base = favoritesOnly ? campaigns.favoriteCampaigns : campaigns.activeCampaigns
        return CampaignEngine.sort(
            CampaignEngine.filter(
                base,
                category: category,
                query: query,
                maxMonthlySEK: nil,
                needsVerificationOnly: onlyNeedsVerification,
                staleAfterDays: settings.data.staleAfterDays
            ),
            by: sort
        )
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: DS.Space.m) {
                freshnessBanner
                statsHeader
                filterBar
                if !favoritesOnly && !campaigns.recentCampaigns.isEmpty {
                    recentsSection
                }
                campaignList
                footer
            }
            .padding(.horizontal, DS.Space.m)
            .padding(.bottom, DS.Space.xl)
        }
        .navigationTitle("Kampanj Center")
        .toolbar { toolbarContent }
        .refreshable { await refresh() }
        .navigationDestination(for: CampaignRecord.self) { campaign in
            CampaignDetailView(campaign: campaign)
        }
        .sheet(isPresented: $showCompare) {
            CampaignCompareView(ids: compareIDs)
        }
        .task { await refreshIfNeededOnAppear() }
    }

    // MARK: Freshness

    @ViewBuilder
    private var freshnessBanner: some View {
        if campaigns.data.lastRefreshFailed, let message = campaigns.lastRefreshError {
            freshnessCard(
                icon: "wifi.exclamationmark",
                tint: DS.warning,
                title: "Kunde inte hämta nya kampanjer",
                detail: "\(message) Visar sparad data — kontrollera giltighet på telia.se innan du citerar."
            )
        } else if campaigns.isStale {
            freshnessCard(
                icon: "clock.badge.exclamationmark",
                tint: DS.warning,
                title: "Kampanjdata kan vara inaktuell",
                detail: "Senast verifierad \(campaigns.newestVerification.map { Format.dayMonth.string(from: $0) } ?? "aldrig"). Uppdatera eller kontrollera telia.se."
            )
        }
    }

    private func freshnessCard(icon: String, tint: Color, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: DS.Space.m) {
            Image(systemName: icon)
                .foregroundStyle(tint)
                .font(.system(size: 18, weight: .semibold))
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                Text(detail)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(DS.Space.m)
        .cardStyle()
    }

    // MARK: Header

    private var statsHeader: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(campaigns.activeCampaigns.count) aktiva kampanjer")
                        .font(.system(.title2, design: .rounded).weight(.bold))
                    Text("Verifierade mot telia.se \(campaigns.newestVerification.map { Format.dayMonth.string(from: $0) } ?? "–")")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Menu {
                    Picker("Sortering", selection: $sort) {
                        Text("Relevans").tag(CampaignEngine.Sort.relevance)
                        Text("Slutar snartast").tag(CampaignEngine.Sort.expirySoonFirst)
                        Text("Lägsta pris").tag(CampaignEngine.Sort.priceLowFirst)
                    }
                    Toggle("Bara favoriter", isOn: $favoritesOnly)
                    Toggle("Bara som behöver verifieras", isOn: $onlyNeedsVerification)
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(DS.Purple.base)
                }
                .accessibilityLabel("Filter och sortering")
            }
        }
        .padding(DS.Space.m)
        .cardStyle(gradient: true)
    }

    // MARK: Filters

    private var filterBar: some View {
        VStack(spacing: DS.Space.s) {
            HStack(spacing: DS.Space.s) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Sök kampanj, produkt eller tjänst", text: $query)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                if !query.isEmpty {
                    Button {
                        query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityLabel("Rensa sökning")
                }
            }
            .padding(DS.Space.s + 2)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DS.Space.s) {
                    chip(label: "Alla", icon: "sparkles", active: category == nil) {
                        category = nil
                    }
                    ForEach(CampaignCategory.allCases) { cat in
                        chip(label: cat.displayName, icon: cat.symbolName, active: category == cat) {
                            category = category == cat ? nil : cat
                        }
                    }
                }
            }
        }
    }

    private func chip(label: String, icon: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(label, systemImage: icon)
                .font(.system(.caption, design: .rounded).weight(active ? .semibold : .regular))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    active ? DS.Purple.base : Color(.secondarySystemGroupedBackground),
                    in: Capsule()
                )
                .foregroundStyle(active ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
    }

    // MARK: Sections

    private var recentsSection: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            sectionTitle("Senast visade", icon: "clock")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DS.Space.s) {
                    ForEach(campaigns.recentCampaigns.prefix(8)) { campaign in
                        NavigationLink(value: campaign) {
                            recentChip(campaign)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func recentChip(_ campaign: CampaignRecord) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(campaign.title)
                .font(.system(.caption, design: .rounded).weight(.medium))
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            Text(priceLabel(campaign))
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(DS.Purple.base)
        }
        .frame(width: 180, alignment: .leading)
        .padding(DS.Space.s)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var campaignList: some View {
        VStack(spacing: DS.Space.m) {
            if filtered.isEmpty {
                emptyState
            } else {
                ForEach(filtered) { campaign in
                    NavigationLink(value: campaign) {
                        CampaignCardView(
                            campaign: campaign,
                            isFavorite: campaigns.isFavorite(campaign.id),
                            isComparing: compareIDs.contains(campaign.id)
                        )
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button {
                            campaigns.toggleFavorite(campaign.id)
                        } label: {
                            Label(campaigns.isFavorite(campaign.id) ? "Ta bort favorit" : "Spara som favorit",
                                  systemImage: campaigns.isFavorite(campaign.id) ? "star.slash" : "star")
                        }
                        Button {
                            toggleCompare(campaign.id)
                        } label: {
                            Label(compareIDs.contains(campaign.id) ? "Ta bort ur jämförelse" : "Jämför (max 3)",
                  systemImage: "square.split.2x1")
                        }
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: DS.Space.s) {
            Image(systemName: "tag")
                .font(.system(size: 34))
                .foregroundStyle(.secondary)
            Text(favoritesOnly ? "Inga sparade favoriter ännu" : "Inga kampanjer matchar filtret")
                .font(.system(.headline, design: .rounded))
            Text(favoritesOnly
                 ? "Spara kampanjer du vill följa – stjärnmärk dem i listan eller på detaljsidan."
                 : "Prova att rensa sökningen eller välja en annan kategori.")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DS.Space.xl)
        .cardStyle()
    }

    private func sectionTitle(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.system(.subheadline, design: .rounded).weight(.semibold))
            .foregroundStyle(.secondary)
    }

    // MARK: Footer

    private var footer: some View {
        VStack(spacing: 6) {
            Text("Kampanjerna är verifierade mot offentliga sidor på telia.se. Appen kan inte aktivera kampanjer eller reservera lager – det görs i Telias egna kanaler.")
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Text("Ej en officiell Telia-app. Medarbetarerbjudanden ingår inte.")
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .padding(.top, DS.Space.s)
    }

    // MARK: Toolbar & actions

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            HStack(spacing: DS.Space.m) {
                if !compareIDs.isEmpty {
                    Button {
                        showCompare = true
                    } label: {
                        Image(systemName: "square.split.2x1.fill")
                            .overlay(alignment: .topTrailing) {
                                Text("\(compareIDs.count)")
                                    .font(.system(size: 9, weight: .bold))
                                    .padding(4)
                                    .background(DS.Purple.base, in: Circle())
                                    .foregroundStyle(.white)
                                    .offset(x: 8, y: -8)
                            }
                    }
                    .accessibilityLabel("Visa jämförelse (\(compareIDs.count) kampanjer)")
                }
                Button {
                    Task { await refresh() }
                } label: {
                    if campaigns.isRefreshing {
                        ProgressView()
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .disabled(campaigns.isRefreshing)
                .accessibilityLabel("Uppdatera kampanjer")
            }
        }
    }

    private func toggleCompare(_ id: String) {
        if let index = compareIDs.firstIndex(of: id) {
            compareIDs.remove(at: index)
        } else if compareIDs.count < 3 {
            compareIDs.append(id)
        }
    }

    private func refreshIfNeededOnAppear() async {
        guard settings.data.autoRefreshOnOpen,
              !settings.data.campaignFeedURL.isEmpty else { return }
        let last = campaigns.data.lastRefresh
        if last == nil || Date().timeIntervalSince(last!) > 15 * 60 {
            await refresh()
        }
    }

    private func refresh() async {
        do {
            try await campaigns.refresh(feedURL: settings.data.campaignFeedURL)
            campaigns.scheduleFavoriteExpiryNotifications(settings: settings.data)
        } catch {
            campaigns.noteRefreshFailure((error as? LocalizedError)?.errorDescription ?? String(describing: error))
        }
    }

    private func priceLabel(_ campaign: CampaignRecord) -> String {
        campaign.priceKind == .monthly
            ? "\(Format.sekPlain(campaign.campaignPriceSEK))/mån"
            : Format.sekPlain(campaign.campaignPriceSEK)
    }
}

// MARK: - Card

struct CampaignCardView: View {
    let campaign: CampaignRecord
    let isFavorite: Bool
    let isComparing: Bool

    private var status: CampaignStatus { CampaignEngine.status(campaign) }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            header
            priceRow
            if !campaign.includedServices.isEmpty {
                servicesRow
            }
            metaRow
        }
        .padding(DS.Space.m)
        .cardStyle(gradient: isComparing)
        .overlay(alignment: .topTrailing) { favoriteStar }
        .accessibilityElement(children: .combine)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: DS.Space.s) {
            Image(systemName: campaign.category.symbolName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(DS.Purple.base)
                .frame(width: 30, height: 30)
                .background(DS.Purple.base.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(campaign.title)
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                Text(campaign.category.displayName)
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 28)
        }
    }

    private var priceRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.s) {
            Text(campaign.priceKind == .monthly
                 ? "\(Format.sekPlain(campaign.campaignPriceSEK))/mån"
                 : "\(Format.sekPlain(campaign.campaignPriceSEK)) engångspris")
                .font(.system(.title3, design: .rounded).weight(.bold))
                .foregroundStyle(DS.Purple.base)
            if let ordinary = campaign.ordinaryPriceSEK {
                Text("ord. \(campaign.priceKind == .monthly ? "\(Format.sekPlain(ordinary))/mån" : Format.sekPlain(ordinary))")
                    .font(.system(.caption, design: .rounded))
                    .strikethrough()
                    .foregroundStyle(.secondary)
            }
            if let saving = comparableSaving, saving > 0 {
                Text("−\(Format.sekPlain(saving))")
                    .font(.system(.caption, design: .rounded).weight(.bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(DS.positive.opacity(0.14), in: Capsule())
                    .foregroundStyle(DS.positive)
            }
            Spacer()
            statusBadge
        }
    }

    private var comparableSaving: Double? {
        campaign.priceKind == .monthly
            ? CampaignEngine.monthlySavingSEK(campaign)
            : CampaignEngine.oneTimeSavingSEK(campaign)
    }

    private var statusBadge: some View {
        HStack(spacing: 4) {
            switch status {
            case .expiresSoon(let days):
                Image(systemName: "hourglass")
                Text(days <= 1 ? "slutar idag" : "slutar om \(days) dag")
            case .active:
                if let end = campaign.endDate {
                    Image(systemName: "calendar")
                    Text("t.o.m. \(Format.dayMonth.string(from: end))")
                } else {
                    Image(systemName: "checkmark.seal")
                    Text("aktiv")
                }
            case .noVerifiedEndDate:
                Image(systemName: "questionmark.circle")
                Text("slutdatum overifierat")
            case .expired:
                Image(systemName: "xmark.circle")
                Text("utgången")
            }
        }
        .font(.system(.caption2, design: .rounded).weight(.medium))
        .foregroundStyle(badgeTint)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(badgeTint.opacity(0.12), in: Capsule())
    }

    private var badgeTint: Color {
        switch status {
        case .expiresSoon: return DS.warning
        case .active: return DS.positive
        case .noVerifiedEndDate: return .secondary
        case .expired: return DS.negative
        }
    }

    private var favoriteStar: some View {
        Image(systemName: isFavorite ? "star.fill" : "")
            .font(.system(size: 13))
            .foregroundStyle(Color.yellow)
            .padding(DS.Space.s)
    }

    private var servicesRow: some View {
        Text(campaign.includedServices.joined(separator: " · "))
            .font(.system(.caption, design: .rounded))
            .foregroundStyle(.secondary)
            .lineLimit(2)
    }

    private var metaRow: some View {
        HStack(spacing: DS.Space.s) {
            Image(systemName: "checkmark.shield")
                .font(.system(size: 11))
            Text("Verifierad \(Format.dayMonth.string(from: campaign.verifiedAt)) · \(campaign.sourceName)")
                .lineLimit(1)
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
        }
        .font(.system(.caption2, design: .rounded))
        .foregroundStyle(.secondary)
    }
}
