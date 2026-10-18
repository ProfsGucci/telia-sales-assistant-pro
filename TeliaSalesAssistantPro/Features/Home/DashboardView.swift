import SwiftUI
import TeliaCore

// MARK: - Card registry

enum DashboardCard: String, CaseIterable, Identifiable {
    case shift, search, quickActions, productShortcuts, checklist, goals, campaigns, featured, coach, tip, quiz, recents, scripts, reminders, freshness, training

    var id: String { rawValue }

    var title: String {
        switch self {
        case .shift: return "Dagens fokus"
        case .search: return "Snabb prisök"
        case .quickActions: return "Snabbåtgärder"
        case .productShortcuts: return "Produktgenvägar"
        case .checklist: return "Dagens förberedelser"
        case .goals: return "Dagens mål"
        case .campaigns: return "Kampanj Center"
        case .featured: return "Utvald kampanj"
        case .coach: return "AI Coach"
        case .tip: return "Dagens säljtips"
        case .quiz: return "Snabbquiz"
        case .recents: return "Senast visade"
        case .scripts: return "Sparade manus"
        case .reminders: return "Kommande"
        case .freshness: return "Prisdata"
        case .training: return "Träning"
        }
    }

    static let defaultOrder: [String] = DashboardCard.allCases.map(\.rawValue)
}

// MARK: - Dashboard

struct DashboardView: View {
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var catalog: CatalogStore
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var schedule: ScheduleStore
    @EnvironmentObject private var progress: ProgressStore
    @EnvironmentObject private var learning: LearningStore
    @EnvironmentObject private var appState: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var appeared = false
    @State private var showCustomize = false

    private var orderedCards: [DashboardCard] {
        let order = settings.data.dashboardOrder
        let all = DashboardCard.allCases
        let known = order.compactMap { raw in all.first { $0.rawValue == raw } }
        let missing = all.filter { card in !order.contains(card.rawValue) }
        return (known + missing).filter { !settings.data.hiddenDashboardCards.contains($0.rawValue) }
    }

    private var hour: Int { Calendar.current.component(.hour, from: Date()) }
    private var greeting: String {
        switch hour {
        case 5..<10: return "God morgon"
        case 10..<13: return "Hej"
        case 13..<18: return "God eftermiddag"
        default: return "God kväll"
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: DS.Space.m) {
                header
                ForEach(Array(orderedCards.enumerated()), id: \.element.rawValue) { index, card in
                    cardView(card)
                        .opacity(appeared || reduceMotion ? 1 : 0)
                        .offset(y: appeared || reduceMotion ? 0 : 14)
                        .animation(DS.Motion.entrance(reduceMotion, index: index), value: appeared)
                }
                footer
            }
            .padding(.horizontal, DS.Space.m)
            .padding(.bottom, DS.Space.xl)
        }
        // ScrollView is transparent by default — the app-wide BackgroundLayer shows through.
        .navigationTitle(greeting)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showCustomize = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }
                .accessibilityLabel("Anpassa hem")
            }
        }
        .sheet(isPresented: $showCustomize) {
            DashboardCustomizeView()
                .presentationDetents([.medium, .large])
        }
        .navigationDestination(for: String.self) { productID in
            ProductDetailView(productID: productID)
        }
        .navigationDestination(for: AppDestination.self) { destination in
            DestinationDetail(destination: destination)
        }
        .onAppear { _ = appState; appeared = true }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(Date(), style: .date)
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(.secondary)
            HStack {
                Text("Telia Sales Assistant")
                    .font(.system(.largeTitle, design: .rounded).weight(.bold))
                Spacer()
                NavigationLink(value: AppDestination.settings) {
                    Image(systemName: "gearshape.fill")
                        .font(.system(.body))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.top, DS.Space.s)
    }

    @ViewBuilder
    private func cardView(_ card: DashboardCard) -> some View {
        switch card {
        case .shift: ShiftCard()
        case .search: QuickSearchCard()
        case .quickActions: QuickActionsCard()
        case .productShortcuts: ProductShortcutsCard()
        case .checklist: ChecklistCard()
        case .goals: GoalsCard()
        case .campaigns: CampaignsCard()
        case .featured: FeaturedCampaignCard()
        case .coach: CoachShortcutCard()
        case .tip: TipCard()
        case .quiz: MiniQuizCard()
        case .recents: RecentProductsCard()
        case .scripts: ScriptsCard()
        case .reminders: RemindersCard()
        case .freshness: FreshnessCard()
        case .training: TrainingCard()
        }
    }

    private var footer: some View {
        VStack(spacing: 6) {
            Text("Made by Kevork Khagadurian")
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(.tertiary)
            Text("Personligt verktyg – inte en officiell Telia-app")
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(.secondary)
            Text("Priser verifierade mot telia.se \(catalog.lastUpdated.map { Format.relativeDays($0) } ?? "aldrig"). Kontrollera alltid källan vid osäkerhet.")
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, DS.Space.l)
    }
}

// MARK: - Cards

// MARK: - Circular quick-action tile (NavigationLink flavour)

private struct QuickActionLink: View {
    let destination: AppDestination
    let icon: String
    let label: String
    var tint: Color = DS.Purple.base

    var body: some View {
        NavigationLink(value: destination) {
            VStack(spacing: DS.Space.s) {
                Image(systemName: icon)
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                    .foregroundStyle(tint)
                    .frame(width: 54, height: 54)
                    .background(Circle().fill(tint.opacity(0.13)))
                    .overlay(Circle().strokeBorder(DS.Surface.hairline, lineWidth: 1))
                Text(label)
                    .font(.system(.caption2, design: .rounded).weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(PressableStyle(scale: 0.92))
        .accessibilityLabel(label)
    }
}

/// Quick Actions — the fastest paths through a busy shift.
private struct QuickActionsCard: View {
    @State private var showFollowUpAdd = false

    var body: some View {
        SectionCard(title: "Snabbåtgärder", symbol: "bolt.fill") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 68), spacing: DS.Space.m)], spacing: DS.Space.l) {
                QuickActionLink(destination: .products, icon: "cart.fill", label: "Produkter")
                QuickActionLink(destination: .campaign, icon: "tag.fill", label: "Kampanjer", tint: DS.Orange.base)
                QuickActionLink(destination: .coach, icon: "bubble.left.and.text.bubble.right.fill", label: "AI Coach")
                QuickActionLink(destination: .calendar, icon: "calendar", label: "Schema", tint: .blue)
                QuickActionLink(destination: .roleplay, icon: "theatermasks.fill", label: "Rollspel", tint: DS.Orange.base)
                QuickActionLink(destination: .library, icon: "bookmark.fill", label: "Bibliotek")
                Button {
                    Haptics.tap()
                    showFollowUpAdd = true
                } label: {
                    VStack(spacing: DS.Space.s) {
                        Image(systemName: "person.crop.circle.badge.clock")
                            .font(.system(.title3, design: .rounded).weight(.semibold))
                            .foregroundStyle(DS.Purple.base)
                            .frame(width: 54, height: 54)
                            .background(Circle().fill(DS.Purple.base.opacity(0.13)))
                            .overlay(Circle().strokeBorder(DS.Surface.hairline, lineWidth: 1))
                        Text("Kolla senare")
                            .font(.system(.caption2, design: .rounded).weight(.medium))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(PressableStyle(scale: 0.92))
                .accessibilityLabel("Ny kund att kolla senare")
            }
        }
        .sheet(isPresented: $showFollowUpAdd) {
            FollowUpQuickAddSheet()
        }
    }
}

/// Product Shortcuts — jumps straight into the catalogue with a search seed.
private struct ProductShortcutsCard: View {
    @EnvironmentObject private var appState: AppState

    private struct Shortcut {
        let label: String
        let icon: String
        let seed: String
        let tint: Color
    }

    private let shortcuts: [Shortcut] = [
        Shortcut(label: "Mobil", icon: "antenna.radiowaves.left.and.right", seed: "mobil", tint: DS.Purple.base),
        Shortcut(label: "Telefoner", icon: "iphone.gen3", seed: "iphone", tint: DS.Orange.base),
        Shortcut(label: "Samsung", icon: "smartphone", seed: "samsung", tint: DS.Purple.base),
        Shortcut(label: "Bredband", icon: "wifi.router", seed: "bredband", tint: .blue),
        Shortcut(label: "TV", icon: "tv.fill", seed: "tv", tint: DS.Orange.base),
        Shortcut(label: "Fiber", icon: "bolt.fill", seed: "fiber", tint: DS.Purple.base),
    ]

    var body: some View {
        SectionCard(title: "Produktgenvägar", symbol: "square.grid.2x2.fill") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 68), spacing: DS.Space.m)], spacing: DS.Space.l) {
                ForEach(shortcuts, id: \.label) { shortcut in
                    Button {
                        Haptics.tap()
                        appState.productSearchSeed = shortcut.seed
                        appState.selectedTab = .products
                    } label: {
                        VStack(spacing: DS.Space.s) {
                            Image(systemName: shortcut.icon)
                                .font(.system(.title3, design: .rounded).weight(.semibold))
                                .foregroundStyle(shortcut.tint)
                                .frame(width: 54, height: 54)
                                .background(Circle().fill(shortcut.tint.opacity(0.13)))
                                .overlay(Circle().strokeBorder(DS.Surface.hairline, lineWidth: 1))
                            Text(shortcut.label)
                                .font(.system(.caption2, design: .rounded).weight(.medium))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PressableStyle(scale: 0.92))
                    .accessibilityLabel("Sök \(shortcut.label)")
                }
            }
        }
    }
}

/// DS 2.0 hero card: the day at a glance on a dark premium surface.
private struct ShiftCard: View {
    @EnvironmentObject private var schedule: ScheduleStore
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var progress: ProgressStore

    private var nextShift: ScheduleEvent? {
        CalendarEngine.nextShift(from: schedule.events, after: Date(), calendar: CalendarEngine.workCalendar())
    }

    private var checklistCount: Int { library.data.checklistItems.count }
    private var doneCount: Int { library.completedTodayCount() }

    private var todaySales: Int {
        ProgressEngine.aggregate(entries: progress.entries, on: Date(), calendar: Calendar.current).sales
    }

    /// Short human countdown to the shift, e.g. "3 h" or "2 d".
    private var countdown: String {
        guard let shift = nextShift else { return "–" }
        let seconds = shift.start.timeIntervalSinceNow
        guard seconds > 0 else { return "nu" }
        let hours = seconds / 3600
        if hours < 1 { return "<1 h" }
        if hours < 48 { return "\(Int(hours.rounded())) h" }
        return "\(Int((hours / 24).rounded())) d"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.l) {
            HStack(alignment: .top, spacing: DS.Space.m) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("DAGENS FOKUS")
                        .font(.system(.caption2, design: .rounded).weight(.bold))
                        .kerning(1.4)
                        .foregroundStyle(DS.Orange.light)
                    if let shift = nextShift {
                        Text(shift.title)
                            .font(DS.Typo.title)
                            .foregroundStyle(.white)
                            .lineLimit(2)
                        Text("\(Format.dayMonth.string(from: shift.start)) · \(Format.time.string(from: shift.start))–\(Format.time.string(from: shift.end))")
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(Color.white.opacity(0.75))
                    } else {
                        Text("Inget pass inplanerat")
                            .font(DS.Typo.title)
                            .foregroundStyle(.white)
                        Text("Lägg till ditt nästa pass i kalendern så hjälper appen dig förbereda.")
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(Color.white.opacity(0.75))
                    }
                }
                Spacer(minLength: DS.Space.s)
                Image(systemName: "bag.fill")
                    .font(.system(.title3, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.9))
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Color.white.opacity(0.10)))
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
            }

            HStack(spacing: DS.Space.m) {
                HeroStat(value: "\(doneCount)/\(checklistCount)", label: "Checklista", symbol: "checklist")
                HeroStat(value: "\(todaySales)", label: "Affärer idag", symbol: "target", tint: DS.Purple.light)
                HeroStat(value: countdown, label: "Till passet", symbol: "clock")
            }

            HStack {
                if let shift = nextShift, !shift.location.isEmpty {
                    Label(shift.location, systemImage: "mappin.and.ellipse")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.7))
                }
                Spacer()
                NavigationLink(value: AppDestination.calendar) {
                    Text(nextShift == nil ? "Planera pass" : "Öppna kalendern")
                        .font(.system(.footnote, design: .rounded).weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, DS.Space.l)
                        .padding(.vertical, DS.Space.s + 2)
                        .background(Capsule().fill(Color.white.opacity(0.14)))
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
                }
                .buttonStyle(PressableStyle())
            }
        }
        .heroCard()
    }
}

private struct QuickSearchCard: View {
    @EnvironmentObject private var catalog: CatalogStore
    @EnvironmentObject private var appState: AppState
    @State private var query = ""

    private var results: [ProductRecord] {
        CatalogQuery.search(catalog.products, query: query).prefix(4).map { $0 }
    }

    var body: some View {
        SectionCard(title: "Snabb prisök", symbol: "magnifyingglass") {
            TextField("Abonnemang, telefon, bredband…", text: $query)
                .font(.system(.body, design: .rounded))
                .padding(DS.Space.m)
                .background(
                    RoundedRectangle(cornerRadius: DS.Radius.tile, style: .continuous)
                        .fill(DS.Surface.inset)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.tile, style: .continuous)
                        .strokeBorder(DS.Surface.hairline, lineWidth: 1)
                )
                .autocorrectionDisabled()
            if !query.isEmpty {
                VStack(spacing: 0) {
                    if results.isEmpty {
                        Text("Inga träffar")
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(.secondary)
                            .padding(.vertical, DS.Space.m)
                    } else {
                        ForEach(results) { product in
                            NavigationLink(value: product.id) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(product.name)
                                            .font(.system(.subheadline, design: .rounded).weight(.medium))
                                            .foregroundStyle(.primary)
                                        Text(product.kind.displayName)
                                            .font(.system(.caption, design: .rounded))
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    PriceText(monthly: CostCalculator.currentMonthly(product))
                                }
                                .padding(.vertical, DS.Space.s)
                            }
                            .buttonStyle(PressableStyle(scale: 0.98))
                            if product.id != results.last?.id { Divider() }
                        }
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
                .animation(.easeOut(duration: DS.Motion.reveal), value: query)
            }
        }
    }
}

private struct ChecklistCard: View {
    @EnvironmentObject private var library: LibraryStore
    @State private var newItemTitle = ""

    var body: some View {
        SectionCard(title: "Dagens förberedelser", symbol: "checklist") {
            VStack(spacing: DS.Space.s) {
                ForEach(library.data.checklistItems) { item in
                    HStack(spacing: DS.Space.m) {
                        CheckToggle(done: library.isDoneToday(item)) {
                            library.toggleChecklist(item)
                            if library.isDoneToday(item) { Haptics.success() }
                        }
                        Text(item.title)
                            .font(.system(.subheadline, design: .rounded))
                            .strikethrough(library.isDoneToday(item), color: .secondary)
                            .foregroundStyle(library.isDoneToday(item) ? Color.secondary : Color.primary)
                        Spacer()
                    }
                }
                HStack(spacing: DS.Space.s) {
                    TextField("Lägg till…", text: $newItemTitle)
                        .font(.system(.subheadline, design: .rounded))
                        .onSubmit {
                            let trimmed = newItemTitle.trimmingCharacters(in: .whitespaces)
                            guard !trimmed.isEmpty else { return }
                            library.addChecklistItem(title: trimmed)
                            newItemTitle = ""
                        }
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(DS.Purple.base)
                }
                .padding(.top, DS.Space.xs)
                ProgressBar(progress: library.data.checklistItems.isEmpty ? 0 : Double(library.completedTodayCount()) / Double(library.data.checklistItems.count))
            }
        }
    }
}

private struct GoalsCard: View {
    @EnvironmentObject private var progress: ProgressStore
    @EnvironmentObject private var learning: LearningStore

    var body: some View {
        let today = ProgressEngine.aggregate(entries: progress.entries, on: Date(), calendar: Calendar.current)
        let salesProgress = progress.goals.dailySales > 0
            ? Double(today.sales) / Double(progress.goals.dailySales) : 0
        let customersProgress = progress.goals.dailyCustomers > 0
            ? Double(today.customers) / Double(progress.goals.dailyCustomers) : 0
        let todayAnswers = learning.data.answers.filter { Calendar.current.isDateInToday($0.date) }.count
        let trainingProgress = progress.goals.dailyTrainingMinutes > 0
            ? min(1, Double(todayAnswers) / 10.0) : 0

        SectionCard(title: "Dagens mål", symbol: "target", glossy: true) {
            HStack(alignment: .top, spacing: DS.Space.m) {
                RingGauge(progress: salesProgress, title: "Affärer", detail: "\(today.sales) av \(progress.goals.dailySales)")
                RingGauge(progress: customersProgress, title: "Kunder", detail: "\(today.customers) av \(progress.goals.dailyCustomers)", color: .blue)
                RingGauge(progress: trainingProgress, title: "Träning", detail: "\(todayAnswers) quiz svar", color: .pink)
            }
        }
    }
}

private struct CampaignsCard: View {
    @EnvironmentObject private var campaigns: CampaignStore

    private var top: CampaignRecord? {
        campaigns.activeCampaigns.first
    }

    private var endingSoon: CampaignRecord? {
        campaigns.activeCampaigns.first { campaign in
            if case .expiresSoon = CampaignEngine.status(campaign) { return true }
            return false
        }
    }

    private func endsInDays(_ campaign: CampaignRecord) -> Int? {
        if case .expiresSoon(let days) = CampaignEngine.status(campaign) { return days }
        return nil
    }

    var body: some View {
        SectionCard(title: "Kampanj Center", symbol: "tag.fill") {
            VStack(alignment: .leading, spacing: DS.Space.m) {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(campaigns.activeCampaigns.count)")
                        .font(DS.Typo.title)
                        .foregroundStyle(DS.Purple.base)
                    Text("aktiva kampanjer")
                        .font(.system(.subheadline, design: .rounded).weight(.medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("verifierade \(campaigns.newestVerification.map { Format.dayMonth.string(from: $0) } ?? "–")")
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                if let endingSoon {
                    campaignRow(
                        icon: "hourglass",
                        tint: DS.Orange.base,
                        title: endingSoon.title,
                        detail: (endsInDays(endingSoon) ?? 1) <= 1 ? "Slutar idag" : "Slutar om \(endsInDays(endingSoon) ?? 0) dagar"
                    )
                } else if let top {
                    campaignRow(
                        icon: "sparkles",
                        tint: DS.Purple.base,
                        title: top.title,
                        detail: top.priceKind == .monthly
                            ? "\(Format.sekPlain(top.campaignPriceSEK)) kr/mån"
                            : "\(Format.sekPlain(top.campaignPriceSEK)) kr engångspris"
                    )
                }

                NavigationLink(value: AppDestination.campaign) {
                    HStack {
                        Text("Öppna Kampanj Center")
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        Spacer()
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.system(.body))
                    }
                    .foregroundStyle(DS.Purple.base)
                    .padding(.vertical, DS.Space.s + 2)
                }
                .buttonStyle(PressableStyle(scale: 0.98))
            }
        }
    }

    private func campaignRow(icon: String, tint: Color, title: String, detail: String) -> some View {
        HStack(spacing: DS.Space.m) {
            Image(systemName: icon)
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 34, height: 34)
                .background(Circle().fill(tint.opacity(0.13)))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(.subheadline, design: .rounded).weight(.medium))
                    .lineLimit(1)
                Text(detail)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(DS.Space.m)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.tile, style: .continuous)
                .fill(DS.Surface.inset)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.tile, style: .continuous)
                .strokeBorder(DS.Surface.hairline, lineWidth: 1)
        )
    }
}

private struct FeaturedCampaignCard: View {
    @EnvironmentObject private var catalog: CatalogStore
    @EnvironmentObject private var library: LibraryStore

    private var featured: ProductRecord? {
        catalog.products
            .filter { PriceVerification.campaignStatus($0) == .activeCampaign }
            .sorted { ($0.kind == .mobilePlan ? 0 : 1) < ($1.kind == .mobilePlan ? 0 : 1) }
            .first
    }

    var body: some View {
        if let product = featured {
            SectionCard(title: "Utvald kampanj", symbol: "sparkles", glossy: true) {
                HStack(alignment: .top, spacing: DS.Space.m) {
                    Image(systemName: product.kind.symbolName)
                        .font(.system(.title2, design: .rounded))
                        .foregroundStyle(DS.Purple.base)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(DS.Purple.base.opacity(0.12)))
                    VStack(alignment: .leading, spacing: 6) {
                        Text(product.name)
                            .font(.system(.body, design: .rounded).weight(.semibold))
                        PriceText(monthly: product.monthlyPriceSEK, ordinary: product.ordinaryMonthlyPriceSEK)
                        if let note = product.eligibilityNotes {
                            Text(note)
                                .font(.system(.caption, design: .rounded))
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        HStack {
                            NavigationLink(value: product.id) {
                                Text("Visa detaljer")
                                    .font(.system(.footnote, design: .rounded).weight(.semibold))
                            }
                            Spacer()
                            FavoriteToggle(active: library.isFavorite(product.id)) {
                                library.toggleFavorite(product.id)
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct CoachShortcutCard: View {
    @EnvironmentObject private var settings: SettingsStore

    var body: some View {
        SectionCard(title: "AI Coach", symbol: "bubble.left.and.text.bubble.right.fill", gradient: true) {
            VStack(alignment: .leading, spacing: DS.Space.m) {
                Text(settings.aiConfigured
                     ? "Din coach är redo. Fråga om priser, invändningar eller be om en briefing."
                     : "Demoläge: svarar offline från den verifierade katalogen. Konfigurera en AI-backend i Inställningar för full coachning.")
                    .font(.system(.subheadline, design: .rounded))
                HStack(spacing: DS.Space.s) {
                    NavigationLink(value: AppDestination.coach) {
                        Text("Öppna coachen")
                            .font(.system(.footnote, design: .rounded).weight(.semibold))
                            .padding(.horizontal, DS.Space.l)
                            .padding(.vertical, DS.Space.s + 2)
                            .background(Capsule().fill(DS.Purple.base))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(PressableStyle())
                    Chip(text: settings.aiConfigured ? "AI aktiverad" : "Demoläge", color: .white.opacity(0.9))
                }
            }
        }
    }
}

private struct TipCard: View {
    @EnvironmentObject private var learning: LearningStore

    private var tip: SalesTip? {
        let tips = learning.content.tips
        guard !tips.isEmpty else { return nil }
        let day = Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 0
        return tips[day % tips.count]
    }

    var body: some View {
        if let tip = tip {
            SectionCard(title: "Dagens säljtips", symbol: "lightbulb.fill") {
                HStack(alignment: .top, spacing: DS.Space.m) {
                    Image(systemName: "lightbulb.fill")
                        .font(.system(.title3, design: .rounded))
                        .foregroundStyle(DS.Orange.base)
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(DS.Orange.base.opacity(0.13)))
                    VStack(alignment: .leading, spacing: DS.Space.s) {
                        Text(tip.text)
                            .font(.system(.subheadline, design: .rounded))
                        Chip(text: tip.category, color: DS.Orange.base)
                    }
                }
            }
        }
    }
}

private struct MiniQuizCard: View {
    @EnvironmentObject private var learning: LearningStore
    @State private var questions: [QuizQuestion] = []
    @State private var currentIndex = 0
    @State private var selected: Int? = nil

    private var allQuestions: [QuizQuestion] {
        learning.content.lessons.flatMap(\.quiz)
    }

    var body: some View {
        SectionCard(title: "Snabbquiz", symbol: "questionmark.bubble.fill") {
            if questions.isEmpty {
                Text("Testa dig själv på produktkunskap och säljteknik.")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(.secondary)
                PrimaryButton(title: "Starta quiz (3 frågor)", symbol: "play.fill") {
                    questions = Array(allQuestions.shuffled().prefix(3))
                    currentIndex = 0
                    selected = nil
                }
            } else if currentIndex < questions.count {
                let question = questions[currentIndex]
                VStack(alignment: .leading, spacing: DS.Space.m) {
                    Text("Fråga \(currentIndex + 1) av \(questions.count)")
                        .font(.system(.caption, design: .rounded).weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(question.prompt)
                        .font(.system(.body, design: .rounded).weight(.medium))
                    VStack(spacing: DS.Space.s) {
                        ForEach(Array(question.options.enumerated()), id: \.offset) { index, option in
                            let isCorrect = index == question.correctIndex
                            let isSelected = selected == index
                            Button {
                                guard selected == nil else { return }
                                withAnimation(.easeInOut(duration: DS.Motion.reveal)) { selected = index }
                                learning.recordAnswer(question: question, correct: isCorrect)
                            } label: {
                                HStack {
                                    Text(option)
                                        .font(.system(.subheadline, design: .rounded))
                                        .multilineTextAlignment(.leading)
                                    Spacer()
                                    if selected != nil {
                                        Image(systemName: isCorrect ? "checkmark.circle.fill" : (isSelected ? "xmark.circle.fill" : "circle"))
                                            .foregroundStyle(isCorrect ? .green : (isSelected ? .red : Color.secondary))
                                    }
                                }
                                .padding(DS.Space.m)
                                .background(
                                    RoundedRectangle(cornerRadius: DS.Radius.tile, style: .continuous)
                                        .fill(optionBackground(isCorrect: isCorrect, isSelected: isSelected))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: DS.Radius.tile, style: .continuous)
                                        .strokeBorder(borderColor(isCorrect: isCorrect, isSelected: isSelected), lineWidth: 1.5)
                                )
                            }
                            .buttonStyle(PressableStyle(scale: 0.98))
                            .foregroundStyle(.primary)
                        }
                    }
                    if selected != nil {
                        VStack(alignment: .leading, spacing: DS.Space.s) {
                            Text(question.explanation)
                                .font(.system(.caption, design: .rounded))
                                .foregroundStyle(.secondary)
                            PrimaryButton(title: currentIndex == questions.count - 1 ? "Klar" : "Nästa fråga", symbol: "arrow.right") {
                                currentIndex += 1
                                selected = nil
                            }
                        }
                        .transition(.opacity)
                    }
                }
            } else {
                VStack(spacing: DS.Space.s) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(.title))
                        .foregroundStyle(DS.Purple.base)
                    Text("Quiz klart – svaren sparades i Akademin.")
                        .font(.system(.subheadline, design: .rounded))
                    PrimaryButton(title: "Nytt quiz", symbol: "arrow.counterclockwise") {
                        questions = []
                    }
                }
            }
        }
        .onChange(of: questions) { _ in }
    }

    private func optionBackground(isCorrect: Bool, isSelected: Bool) -> Color {
        guard selected != nil else { return DS.Surface.inset }
        if isCorrect { return DS.Purple.base.opacity(0.14) }
        if isSelected { return Color.red.opacity(0.1) }
        return DS.Surface.inset
    }

    private func borderColor(isCorrect: Bool, isSelected: Bool) -> Color {
        guard selected != nil else { return .clear }
        if isCorrect { return DS.Purple.base }
        if isSelected { return .red.opacity(0.6) }
        return .clear
    }
}

private struct RecentProductsCard: View {
    @EnvironmentObject private var catalog: CatalogStore
    @EnvironmentObject private var library: LibraryStore

    var body: some View {
        let recents = library.data.recentProductIDs.prefix(5)
        if !recents.isEmpty {
            SectionCard(title: "Senast visade", symbol: "clock.arrow.circlepath") {
                VStack(spacing: 0) {
                    ForEach(Array(recents), id: \.id) { recent in
                        if let product = catalog.product(id: recent.id) {
                            NavigationLink(value: product.id) {
                                HStack {
                                    Text(product.name)
                                        .font(.system(.subheadline, design: .rounded))
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    PriceText(monthly: CostCalculator.currentMonthly(product))
                                }
                                .padding(.vertical, DS.Space.s)
                            }
                            .buttonStyle(PressableStyle(scale: 0.98))
                        }
                    }
                }
            }
        }
    }
}

private struct ScriptsCard: View {
    @EnvironmentObject private var library: LibraryStore

    var body: some View {
        if !library.data.scripts.isEmpty {
            SectionCard(title: "Sparade manus", symbol: "text.book.closed.fill") {
                VStack(spacing: 0) {
                    ForEach(library.data.scripts.prefix(3)) { script in
                        NavigationLink(value: AppDestination.library) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(script.title)
                                        .font(.system(.subheadline, design: .rounded).weight(.medium))
                                        .foregroundStyle(.primary)
                                    Text(Format.relativeDays(script.updatedAt))
                                        .font(.system(.caption, design: .rounded))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.vertical, DS.Space.s)
                        }
                        .buttonStyle(PressableStyle(scale: 0.98))
                    }
                }
            }
        }
    }
}

private struct RemindersCard: View {
    @EnvironmentObject private var schedule: ScheduleStore

    var body: some View {
        let upcoming = CalendarEngine.upcoming(from: schedule.events, after: Date(), limit: 3, calendar: CalendarEngine.workCalendar())
        let todayTasks = CalendarEngine.tasks(on: Date(), from: schedule.tasks, calendar: Calendar.current)
            .filter { !$0.done }
        SectionCard(title: "Kommande", symbol: "bell.fill") {
            VStack(alignment: .leading, spacing: DS.Space.s) {
                if upcoming.isEmpty && todayTasks.isEmpty {
                    Text("Inget planerat. Lägg till pass, träning eller påminnelser i kalendern.")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                ForEach(upcoming) { event in
                    HStack {
                        Image(systemName: event.kind.symbolName)
                            .foregroundStyle(DS.Purple.base)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(event.title)
                                .font(.system(.subheadline, design: .rounded).weight(.medium))
                            Text("\(Format.dayShort.string(from: event.start)) \(Format.time.string(from: event.start))")
                                .font(.system(.caption, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Chip(text: event.kind.displayName, color: DS.Purple.base)
                    }
                }
                ForEach(todayTasks.prefix(3)) { task in
                    HStack {
                        Image(systemName: "checklist")
                            .foregroundStyle(.orange)
                            .frame(width: 24)
                        Text(task.title)
                            .font(.system(.subheadline, design: .rounded))
                        Spacer()
                    }
                }
            }
        }
    }
}

private struct FreshnessCard: View {
    @EnvironmentObject private var catalog: CatalogStore
    @EnvironmentObject private var settings: SettingsStore

    var body: some View {
        SectionCard(title: "Prisdata", symbol: "checkmark.seal") {
            VStack(alignment: .leading, spacing: DS.Space.s) {
                HStack {
                    Chip(
                        text: catalog.freshnessNote,
                        color: catalog.lastUpdated == nil ? .red : .green
                    )
                    Spacer()
                }
                if let error = catalog.data.lastRefreshError {
                    Text("Senaste uppdatering misslyckades: \(error)")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.red)
                }
                Text("Källa: \(catalog.data.snapshot?.sourceNote ?? "ingen data")")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
        }
    }
}

private struct TrainingCard: View {
    var body: some View {
        SectionCard(title: "Träning", symbol: "graduationcap.fill") {
            VStack(spacing: DS.Space.m) {
                HStack(spacing: DS.Space.m) {
                    trainingLink(.playbook, title: "Säljmanus", subtitle: "Invändningar & manusscript")
                    trainingLink(.roleplay, title: "Rollspel", subtitle: "Öva på riktiga kunder")
                }
                HStack(spacing: DS.Space.m) {
                    trainingLink(.academy, title: "Akademin", subtitle: "Lektioner & flashcards")
                    trainingLink(.library, title: "Bibliotek", subtitle: "Anteckningar & ordlista")
                }
            }
        }
    }

    private func trainingLink(_ destination: AppDestination, title: String, subtitle: String) -> some View {
        NavigationLink(value: destination) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(DS.Space.m)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.tile, style: .continuous)
                    .fill(DS.Surface.inset)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.tile, style: .continuous)
                    .strokeBorder(DS.Surface.hairline, lineWidth: 1)
            )
        }
        .buttonStyle(PressableStyle(scale: 0.97))
    }
}

// MARK: - Customize sheet

struct DashboardCustomizeView: View {
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(orderedCards) { card in
                        Label(card.title, systemImage: "line.3.horizontal")
                            .foregroundStyle(.primary)
                    }
                    .onMove { from, to in
                        var order = settings.data.dashboardOrder
                        var cards = order.compactMap { raw in DashboardCard(rawValue: raw) }
                        cards.move(fromOffsets: from, toOffset: to)
                        order = cards.map(\.rawValue)
                        // Append any cards not present in the old order.
                        for missing in DashboardCard.allCases where !order.contains(missing.rawValue) {
                            order.append(missing.rawValue)
                        }
                        settings.data.dashboardOrder = order
                    }
                    .onDelete { offsets in
                        let cards = orderedCards
                        for index in offsets {
                            settings.data.hiddenDashboardCards.insert(cards[index].rawValue)
                        }
                    }
                } header: {
                    Text("Dra för att ordna, svep för att dölja")
                }
                if !settings.data.hiddenDashboardCards.isEmpty {
                    Section("Dolda kort") {
                        ForEach(Array(settings.data.hiddenDashboardCards).sorted(), id: \.self) { raw in
                            if let card = DashboardCard(rawValue: raw) {
                                Button {
                                    settings.data.hiddenDashboardCards.remove(raw)
                                } label: {
                                    Label(card.title, systemImage: "eye")
                                        .foregroundStyle(.primary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Anpassa hem")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) { EditButton() }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Klar") { dismiss() }
                }
            }
            .environment(\.editMode, .constant(.active))
        }
    }

    private var orderedCards: [DashboardCard] {
        let order = settings.data.dashboardOrder
        let all = DashboardCard.allCases
        let known = order.compactMap { raw in all.first { $0.rawValue == raw } }
        let missing = all.filter { !order.contains($0.rawValue) }
        return (known + missing).filter { !settings.data.hiddenDashboardCards.contains($0.rawValue) }
    }
}
