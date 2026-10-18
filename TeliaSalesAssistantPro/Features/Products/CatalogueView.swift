import SwiftUI
import TeliaCore

struct CatalogueView: View {
    @EnvironmentObject private var catalog: CatalogStore
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var appState: AppState

    @State private var query = ""
    @State private var filters = CatalogQuery.Filters()
    @State private var sort: CatalogQuery.Sort = .relevance
    @State private var showGrid = true
    @State private var showFilters = false

    private var results: [ProductRecord] {
        CatalogQuery.search(catalog.products, query: query, filters: filters, sort: sort)
    }

    var body: some View {
        List {
            if !catalog.compareIDs.isEmpty {
                Section {
                    compareBar
                }
            }
            Section {
                if results.isEmpty {
                    emptyState
                } else {
                    cardsSection(results)
                }
            } header: {
                Text("\(results.count) produkter")
            }
        }
        .listStyle(.insetGrouped)
        .searchable(text: $query, prompt: "Sök produkt, priser, streaming…")
        .navigationTitle("Produkter")
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { showGrid.toggle() }
                } label: {
                    Image(systemName: showGrid ? "list.bullet" : "square.grid.2x2")
                }
                .accessibilityLabel(showGrid ? "Vy: lista" : "Vy: rutnät")

                Menu {
                    Picker("Sortering", selection: $sort) {
                        Text("Relevans").tag(CatalogQuery.Sort.relevance)
                        Text("Namn A–Ö").tag(CatalogQuery.Sort.nameAsc)
                        Text("Pris lägst").tag(CatalogQuery.Sort.priceAsc)
                        Text("Pris högst").tag(CatalogQuery.Sort.priceDesc)
                        Text("Mest surf").tag(CatalogQuery.Sort.dataDesc)
                    }
                    Button {
                        showFilters = true
                    } label: {
                        Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
                    }
                    NavigationLink(value: AppDestination.settings) {
                        Label("Importera priser", systemImage: "square.and.arrow.down")
                    }
                } label: {
                    Image(systemName: filters.isActive ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                }
            }
        }
        .sheet(isPresented: $showFilters) {
            FilterSheet(filters: $filters)
                .presentationDetents([.medium, .large])
        }
        .navigationDestination(for: String.self) { productID in
            ProductDetailView(productID: productID)
        }
        .navigationDestination(for: CompareRoute.self) { _ in
            CompareView()
        }
        .navigationDestination(for: AppDestination.self) { destination in
            DestinationDetail(destination: destination)
        }
        .onAppear {
            if let seed = appState.productSearchSeed, !seed.isEmpty {
                query = seed
                appState.productSearchSeed = nil
            }
        }
        .refreshable {
            if !settings_feedURL.isEmpty {
                await catalog.refreshFromFeed(urlString: settings_feedURL)
            }
        }
    }

    private var settings_feedURL: String {
        // Local read to avoid an extra store dependency in this view's refreshable.
        DataStore.load(SettingsData.self)?.priceFeedURL ?? ""
    }

    private var compareBar: some View {
        HStack {
            Label("\(catalog.compareIDs.count) valda att jämföra", systemImage: "square.split.2x1")
                .font(.system(.subheadline, design: .rounded).weight(.medium))
            Spacer()
            NavigationLink(value: CompareRoute()) {
                Text("Jämför")
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .padding(.horizontal, DS.Space.l)
                    .padding(.vertical, DS.Space.s)
                    .background(Capsule().fill(DS.Purple.base))
                    .foregroundStyle(.white)
            }
            .buttonStyle(PressableStyle())
        }
    }

    @ViewBuilder
    private func cardsSection(_ products: [ProductRecord]) -> some View {
        if showGrid {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 155), spacing: DS.Space.m)], spacing: DS.Space.m) {
                ForEach(products) { product in
                    NavigationLink(value: product.id) {
                        ProductGridCell(product: product, isFavorite: library.isFavorite(product.id))
                    }
                    .buttonStyle(PressableStyle(scale: 0.97))
                }
            }
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 4, leading: DS.Space.m, bottom: 4, trailing: DS.Space.m))
        } else {
            ForEach(products) { product in
                NavigationLink(value: product.id) {
                    ProductRow(product: product, isFavorite: library.isFavorite(product.id))
                }
                .buttonStyle(PressableStyle(scale: 0.98))
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button {
                        library.toggleFavorite(product.id)
                    } label: {
                        Label("Favorit", systemImage: library.isFavorite(product.id) ? "heart.slash" : "heart")
                    }
                    .tint(.pink)
                    Button {
                        catalog.toggleCompare(product.id)
                    } label: {
                        Label("Jämför", systemImage: "square.split.2x1")
                    }
                    .tint(DS.Purple.base)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack {
            if filters.isActive || !query.isEmpty {
                EmptyStateView(
                    symbol: "magnifyingglass",
                    title: "Inga träffar",
                    message: "Prova ett annat sökord eller rensa filtren.",
                    actionTitle: "Rensa filter",
                    action: {
                        filters = CatalogQuery.Filters()
                        query = ""
                    }
                )
                .listRowSeparator(.hidden)
            } else {
                EmptyStateView(
                    symbol: "cart",
                    title: "Katalogen är tom",
                    message: "Importera en prislista eller återställ den inbyggda katalogen i Inställningar.",
                    actionTitle: "Återställ inbyggd data",
                    action: { catalog.resetToSeed() }
                )
                .listRowSeparator(.hidden)
            }
        }
    }
}

/// Value type for programmatic navigation to the compare view.
struct CompareRoute: Hashable {}

// MARK: - Grid cell

struct ProductGridCell: View {
    let product: ProductRecord
    let isFavorite: Bool
    @EnvironmentObject private var catalog: CatalogStore

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            HStack {
                Image(systemName: product.kind.symbolName)
                    .font(.system(.title3, design: .rounded))
                    .foregroundStyle(DS.Purple.base)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(DS.Purple.base.opacity(0.12)))
                Spacer()
                if PriceVerification.campaignStatus(product) == .activeCampaign {
                    Image(systemName: "sparkles")
                        .font(.caption)
                        .foregroundStyle(.pink)
                }
            }
            Text(product.name)
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2, reservesSpace: true)
                .multilineTextAlignment(.leading)
            PriceText(monthly: CostCalculator.currentMonthly(product))
            HStack {
                if !product.dataLabel.isEmpty {
                    Text(product.dataLabel)
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VerificationBadge(
                    status: product.verification,
                    freshness: PriceVerification.freshness(of: product)
                )
            }
        }
        .padding(DS.Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                .strokeBorder(catalog.compareIDs.contains(product.id) ? DS.Purple.base : Color.primary.opacity(0.06), lineWidth: 1.5)
        )
    }
}

// MARK: - List row

struct ProductRow: View {
    let product: ProductRecord
    let isFavorite: Bool

    var body: some View {
        HStack(spacing: DS.Space.m) {
            Image(systemName: product.kind.symbolName)
                .font(.system(.title3, design: .rounded))
                .foregroundStyle(DS.Purple.base)
                .frame(width: 40, height: 40)
                .background(Circle().fill(DS.Purple.base.opacity(0.12)))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(product.name)
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if isFavorite {
                        Image(systemName: "heart.fill")
                            .font(.caption2)
                            .foregroundStyle(.pink)
                    }
                }
                HStack(spacing: 6) {
                    Text(product.kind.displayName)
                    if !product.dataLabel.isEmpty { Text("· \(product.dataLabel)") }
                }
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                PriceText(monthly: CostCalculator.currentMonthly(product))
                VerificationBadge(status: product.verification, freshness: PriceVerification.freshness(of: product))
            }
        }
        .contentShape(Rectangle())
    }
}

// MARK: - Filter sheet

struct FilterSheet: View {
    @Binding var filters: CatalogQuery.Filters
    @EnvironmentObject private var catalog: CatalogStore
    @Environment(\.dismiss) private var dismiss

    private var kinds: [ProductKind] { ProductKind.allCases }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.l) {
                    SectionCard(title: "Kategori", symbol: "square.grid.2x2") {
                        FlowChips(
                            items: kinds.map(\.displayName),
                            selected: kinds.filter { filters.kinds.contains($0) }.map(\.displayName)
                        ) { name, selected in
                            if let kind = kinds.first(where: { $0.displayName == name }) {
                                if selected { filters.kinds.insert(kind) } else { filters.kinds.remove(kind) }
                            }
                        }
                    }

                    SectionCard(title: "Pris per månad", symbol: "banknote") {
                        VStack(alignment: .leading, spacing: DS.Space.s) {
                            Toggle("Endast verifierade priser", isOn: $filters.onlyVerified)
                            Toggle("Endast utan bindningstid", isOn: $filters.onlyUnbound)
                            Toggle("Endast obegränsad surf", isOn: $filters.requireUnlimitedData)
                        }
                        .font(.system(.subheadline, design: .rounded))
                    }

                    SectionCard(title: "Maxpris", symbol: "arrow.down.to.line") {
                        Picker("Maxpris", selection: $maxPriceBinding) {
                            Text("Valfritt").tag(0)
                            Text("300 kr").tag(300)
                            Text("500 kr").tag(500)
                            Text("700 kr").tag(700)
                        }
                        .pickerStyle(.segmented)
                    }
                }
                .padding(DS.Space.m)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Filter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Rensa") { filters = CatalogQuery.Filters() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Klar") { dismiss() }
                }
            }
        }
    }

    private var maxPriceBinding: Binding<Int> {
        Binding<Int>(
            get: { Int(filters.maxMonthlySEK ?? 0) },
            set: { filters.maxMonthlySEK = $0 == 0 ? nil : Double($0) }
        )
    }
}

// MARK: - Flow chips (wrapping)

struct FlowChips: View {
    let items: [String]
    let selected: [String]
    let toggle: (String, Bool) -> Void

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: DS.Space.s)], alignment: .leading, spacing: DS.Space.s) {
            ForEach(items, id: \.self) { item in
                let isSelected = selected.contains(item)
                Button {
                    withAnimation(.easeInOut(duration: DS.Motion.reveal)) {
                        toggle(item, isSelected)
                    }
                } label: {
                    Chip(text: item, color: DS.Purple.base, filled: isSelected)
                }
                .buttonStyle(PressableStyle())
            }
        }
    }
}
