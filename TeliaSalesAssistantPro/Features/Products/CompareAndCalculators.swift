import SwiftUI
import TeliaCore

// MARK: - Compare view

struct CompareView: View {
    @EnvironmentObject private var catalog: CatalogStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var months = 24

    var body: some View {
        ScrollView {
            VStack(spacing: DS.Space.m) {
                if catalog.compareProducts.isEmpty {
                    EmptyStateView(
                        symbol: "square.split.2x1",
                        title: "Inget valt att jämföra",
                        message: "Välj upp till tre produkter i katalogen – svep i listvyn eller använd knapparna på produktsidan."
                    )
                } else {
                    picker
                    table
                }
            }
            .padding(DS.Space.m)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Jämför")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var picker: some View {
        SectionCard(title: "Tidshorisont", symbol: "calendar") {
            Picker("Månader", selection: $months) {
                Text("12 mån").tag(12)
                Text("24 mån").tag(24)
                Text("36 mån").tag(36)
            }
            .pickerStyle(.segmented)
        }
    }

    private var rows: [(String, (ProductRecord) -> String)] {
        [
            ("Pris nu", { Format.monthly(CostCalculator.currentMonthly($0)) }),
            ("Efter kampanj", { Format.monthly(CostCalculator.monthlyAfterCampaign($0)) }),
            ("Bindningstid", { $0.isUnbound ? "Ingen" : "\($0.bindingMonths ?? 0) mån" }),
            ("Surf", { $0.dataLabel.isEmpty ? "—" : $0.dataLabel }),
            ("Hastighet", { $0.speedMbit.map { "Upp till \(Int($0)) Mbit/s" } ?? "—" }),
            ("Startkostnad", { $0.upfrontCostSEK.map { "\(Int($0)) kr" } ?? "0 kr" }),
            ("Totalt \(months) mån", { p in
                CostCalculator.planTotal(p, months: months).map { Format.sekPlain($0.totalSEK) } ?? "—"
            }),
            ("Snitt/mån", { p in
                CostCalculator.planTotal(p, months: months).map { Format.sekPlain($0.monthlyAverageSEK) } ?? "—"
            }),
            ("Verifiering", { $0.verification.label }),
        ]
    }

    private var table: some View {
        VStack(spacing: DS.Space.m) {
            ForEach(catalog.compareProducts) { product in
                SectionCard(title: product.name, symbol: product.kind.symbolName) {
                    VStack(spacing: DS.Space.s) {
                        ForEach(rows, id: \.0) { label, value in
                            HStack {
                                Text(label)
                                    .font(.system(.subheadline, design: .rounded))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(value(product))
                                    .font(.system(.subheadline, design: .rounded).weight(
                                        label.hasPrefix("Totalt") ? .bold : .regular
                                    ))
                            }
                        }
                        HStack {
                            Spacer()
                            Button {
                                withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.8)) {
                                    catalog.toggleCompare(product.id)
                                }
                            } label: {
                                Label("Ta bort", systemImage: "trash")
                                    .font(.system(.caption, design: .rounded).weight(.medium))
                            }
                            .buttonStyle(PressableStyle())
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Calculators

struct CalculatorsView: View {
    var body: some View {
        List {
            Section("Räkna på") {
                NavigationLink {
                    PlanTotalCalculator()
                } label: {
                    Label("Abonnemangskostnad över tid", systemImage: "calendar.badge.clock")
                }
                NavigationLink {
                    DeviceCalculator()
                } label: {
                    Label("Mobil + avbetalning", systemImage: "iphone.gen3")
                }
                NavigationLink {
                    FamilyCalculator()
                } label: {
                    Label("Familjeabonnemang", systemImage: "person.2")
                }
                NavigationLink {
                    CampaignCalculator()
                } label: {
                    Label("Pris efter kampanj", systemImage: "sparkles")
                }
            }
            Section {
                Text("Alla beräkningar visar antaganden och steg. Priser kommer ur den verifierade katalogen – inga påhittade siffror.")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Kalkylator")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Plan total

struct PlanTotalCalculator: View {
    @EnvironmentObject private var catalog: CatalogStore

    @State private var selectedID: String = ""
    @State private var months = 24

    private var plans: [ProductRecord] {
        catalog.products.filter { $0.kind == .mobilePlan || $0.kind == .broadband || $0.kind == .tvPackage }
    }
    private var plan: ProductRecord? { plans.first { $0.id == selectedID } ?? plans.first }

    var body: some View {
        ScrollView {
            VStack(spacing: DS.Space.m) {
                SectionCard(title: "Val", symbol: "slider.horizontal.3") {
                    Picker("Produkt", selection: $selectedID) {
                        ForEach(plans) { p in
                            Text(p.name).tag(p.id)
                        }
                    }
                    .pickerStyle(.menu)
                    Stepper("Tidshorisont: \(months) månader", value: $months, in: 1...48)
                }
                if let plan, let result = CostCalculator.planTotal(plan, months: months) {
                    resultCard(result)
                } else {
                    EmptyStateView(
                        symbol: "questionmark",
                        title: "Välj en produkt",
                        message: "Inga produkter med pris hittades i katalogen."
                    )
                }
            }
            .padding(DS.Space.m)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Abonnemang över tid")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if selectedID.isEmpty { selectedID = plans.first?.id ?? "" }
        }
    }

    @ViewBuilder
    private func resultCard(_ result: CostCalculator.CostResult) -> some View {
        SectionCard(title: "Beräkning", symbol: "plus.forwardslash.minus") {
            VStack(alignment: .leading, spacing: DS.Space.s) {
                ForEach(result.lines) { line in
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(line.label)
                                .font(.system(.subheadline, design: .rounded))
                            if line.recurring, let m = line.months {
                                Text("\(Int(line.amountSEK)) kr × \(m) mån")
                                    .font(.system(.caption2, design: .rounded))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Text(line.recurring
                             ? Format.sekPlain(line.amountSEK * Double(line.months ?? months))
                             : Format.sekPlain(line.amountSEK))
                            .font(.system(.subheadline, design: .rounded).weight(.medium))
                    }
                }
                Divider()
                HStack {
                    Text("Totalt \(result.months) månader")
                        .font(.system(.subheadline, design: .rounded).weight(.bold))
                    Spacer()
                    Text(Format.sekPlain(result.totalSEK))
                        .font(.system(.title3, design: .rounded).weight(.bold))
                }
                Text("Månadskostnad nu: \(Format.monthly(result.monthlyNowSEK)) · efter kampanjperioden: \(Format.monthly(result.monthlyAfterCampaignSEK)) · engångskostnader: \(Format.sekPlain(result.oneTimeTotalSEK))")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Device + plan

struct DeviceCalculator: View {
    @EnvironmentObject private var catalog: CatalogStore

    @State private var deviceID: String = ""
    @State private var planID: String = ""
    @State private var quotedMonthly: Double = 0
    @State private var upfront: Double = 0

    private var devices: [ProductRecord] { catalog.products.filter { $0.kind == .device } }
    private var plans: [ProductRecord] { catalog.products.filter { $0.kind == .mobilePlan && $0.unlimitedData } }

    private var device: ProductRecord? { devices.first { $0.id == deviceID } ?? devices.first }
    private var plan: ProductRecord? { plans.first { $0.id == planID } ?? plans.first }

    var body: some View {
        ScrollView {
            VStack(spacing: DS.Space.m) {
                SectionCard(title: "Val", symbol: "iphone.gen3") {
                    Picker("Enhet", selection: $deviceID) {
                        ForEach(devices) { d in Text(d.name).tag(d.id) }
                    }
                    Picker("Abonnemang", selection: $planID) {
                        ForEach(plans) { p in Text(p.name).tag(p.id) }
                    }
                    .pickerStyle(.menu)
                    if let device {
                        HStack {
                            Text("Citerad månadskostnad (enhet + abonnemang)")
                                .font(.system(.subheadline, design: .rounded))
                            Spacer()
                            TextField("kr", value: $quotedMonthly, format: .number)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 90)
                                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        }
                        if let cash = device.cashPriceSEK {
                            Text("Kontantpris: \(Format.sekPlain(cash)) — jämför med avbetalningens totalkostnad.")
                                .font(.system(.caption, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                if let device, let plan, quotedMonthly > 0,
                   let result = CostCalculator.deviceWithPlan(
                       devicePriceSEK: device.cashPriceSEK ?? quotedMonthly * 24,
                       plan: plan,
                       quotedBundleMonthlySEK: quotedMonthly,
                       months: 24,
                       upfrontSEK: upfront
                   ) {
                    SectionCard(title: "Beräkning (24 mån)", symbol: "plus.forwardslash.minus") {
                        VStack(alignment: .leading, spacing: DS.Space.s) {
                            ForEach(result.lines) { line in
                                HStack {
                                    Text(line.label)
                                        .font(.system(.subheadline, design: .rounded))
                                    Spacer()
                                    Text(line.recurring ? "\(Int(line.amountSEK)) kr/mån × \(line.months ?? 24)" : Format.sekPlain(line.amountSEK))
                                        .font(.system(.subheadline, design: .rounded).weight(.medium))
                                }
                            }
                            Divider()
                            HStack {
                                Text("Totalt")
                                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                                Spacer()
                                Text(Format.sekPlain(result.totalSEK))
                                    .font(.system(.title3, design: .rounded).weight(.bold))
                            }
                            if let cash = device.cashPriceSEK {
                                Label("Kontant betalning hade kostat \(Format.sekPlain(cash)) för enheten (plus abonnemanget).", systemImage: "banknote")
                                    .font(.system(.caption, design: .rounded))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } else {
                    SectionCard(title: "Så funkar det", symbol: "info.circle") {
                        Text("Välj enhet och abonnemang och skriv in det månad pris som citeras i kassasystemet. Appen delar upp kostnaden på abonnemang och enhet, och räknar ut totalkostnaden under 24 månader.")
                            .font(.system(.subheadline, design: .rounded))
                    }
                }
            }
            .padding(DS.Space.m)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Mobil + avbetalning")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if deviceID.isEmpty { deviceID = devices.first?.id ?? "" }
            if planID.isEmpty { planID = plans.first?.id ?? "" }
        }
    }
}

// MARK: - Family

struct FamilyCalculator: View {
    @EnvironmentObject private var catalog: CatalogStore

    @State private var mainID: String = ""
    @State private var extraUsers = 3
    @State private var extraPrice = 175.0
    @State private var extraOrdinary = 239.0
    @State private var campaignMonths = 12

    private var mains: [ProductRecord] {
        catalog.products.filter { $0.kind == .mobilePlan && $0.unlimitedData }
    }
    private var addOn: ProductRecord? { catalog.products.first { $0.kind == .familyAddOn } }
    private var main: ProductRecord? { mains.first { $0.id == mainID } ?? mains.first }

    var body: some View {
        ScrollView {
            VStack(spacing: DS.Space.m) {
                SectionCard(title: "Familjen", symbol: "person.2") {
                    Picker("Huvudabonnemang", selection: $mainID) {
                        ForEach(mains) { m in Text(m.name).tag(m.id) }
                    }
                    .pickerStyle(.menu)
                    Stepper("Extra användare: \(extraUsers)", value: $extraUsers, in: 0...9)
                    Stepper("Kampanjpris extra användare: \(Int(extraPrice)) kr", value: $extraPrice, in: 0...500, step: 5)
                    Stepper("Ordinarie pris extra användare: \(Int(extraOrdinary)) kr", value: $extraOrdinary, in: 0...500, step: 5)
                    if let addOn {
                        Text("Katalogen säger: \(addOn.name) \(Format.monthly(CostCalculator.currentMonthly(addOn))) (ord. \(Format.monthly(addOn.ordinaryMonthlyPriceSEK)))")
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
                if let main, let result = CostCalculator.familyTotal(
                    main: main,
                    extraUsers: extraUsers,
                    extraUserMonthlySEK: extraPrice,
                    extraUserOrdinarySEK: extraOrdinary,
                    extraUserCampaignMonths: campaignMonths
                ) {
                    SectionCard(title: "Resultat", symbol: "equal") {
                        VStack(spacing: DS.Space.s) {
                            resultRow("Huvudabonnemang", Format.monthly(result.mainMonthlySEK))
                            resultRow("Extra användare (\(result.extraUsers) st)", "\(Int(result.extraUserMonthlySEK)) kr/mån each")
                            Divider()
                            resultRow("Totalt nu", Format.monthly(result.monthlyNowSEK))
                            resultRow("Efter kampanj (\(result.extraUserCampaignMonths) mån)", Format.monthly(result.monthlyAfterCampaignSEK))
                            resultRow("Per person (nu, \(result.extraUsers + 1) pers.)", "\(Int(result.monthlyPerPersonSEK)) kr/mån")
                        }
                    }
                    SectionCard(title: "Så presenterar du det", symbol: "bubble.left") {
                        Text("“Ni är \(result.extraUsers + 1) personer. Idag kostar det \(Int(result.monthlyNowSEK)) kr totalt per månad – alla med obegränsad surf och allt på en faktura. Per person blir det \(Int(result.monthlyPerPersonSEK)) kr. Kampanjpriset på extra användare gäller i \(result.extraUserCampaignMonths) månader, därefter \(Int(result.monthlyAfterCampaignSEK)) kr totalt.”")
                            .font(.system(.subheadline, design: .rounded))
                    }
                }
            }
            .padding(DS.Space.m)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Familjekalkyl")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if mainID.isEmpty { mainID = mains.first?.id ?? "" }
        }
    }

    private func resultRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
        }
    }
}

// MARK: - Campaign end

struct CampaignCalculator: View {
    @EnvironmentObject private var catalog: CatalogStore

    private var campaignProducts: [ProductRecord] {
        catalog.products.filter { $0.hasCampaign }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: DS.Space.m) {
                if campaignProducts.isEmpty {
                    EmptyStateView(
                        symbol: "sparkles",
                        title: "Inga aktiva kampanjer",
                        message: "Katalogen innehåller inga produkter med kampanjpris just nu."
                    )
                } else {
                    ForEach(campaignProducts) { product in
                        campaignCard(product)
                    }
                }
            }
            .padding(DS.Space.m)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Pris efter kampanj")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func campaignCard(_ product: ProductRecord) -> some View {
        if let now = CostCalculator.currentMonthly(product),
           let after = CostCalculator.monthlyAfterCampaign(product) {
            SectionCard(title: product.name, symbol: "sparkles") {
                VStack(alignment: .leading, spacing: DS.Space.s) {
                    HStack {
                        PriceText(monthly: now, ordinary: product.ordinaryMonthlyPriceSEK)
                        Spacer()
                        Chip(text: product.isUnbound ? "Obundet" : "\(product.bindingMonths ?? 0) mån bindning", color: .blue)
                    }
                    Label("Efter kampanjen: \(Format.monthly(after)) — en ökning med \(Int(after - now)) kr/mån", systemImage: "arrow.up.right")
                        .font(.system(.subheadline, design: .rounded).weight(.medium))
                        .foregroundStyle(.orange)
                    if let months = product.campaignMonths {
                        Label("Kampanjpriset gäller i \(months) månader från köpet", systemImage: "clock")
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    Text("Säg alltid till kunden både priserna och hur länge rabatten gäller – det är lag och rådgivning i ett.")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
