import SwiftUI
import Charts
import TeliaCore

struct ProgressDashboardView: View {
    @EnvironmentObject private var progress: ProgressStore
    @EnvironmentObject private var learning: LearningStore
    @EnvironmentObject private var catalog: CatalogStore

    @State private var showLogSheet = false
    @State private var editingEntry: SalesEntry?

    private var last14Days: [DayAggregate] {
        let cal = Calendar.current
        return (0..<14).reversed().compactMap { offset in
            guard let day = cal.date(byAdding: .day, value: -offset, to: Date()) else { return nil }
            return ProgressEngine.aggregate(entries: progress.entries, on: day, calendar: cal)
        }
    }

    var body: some View {
        List {
            Section {
                todaySummary
            }
            Section("Senaste 14 dagar") {
                salesChart
                    .listRowSeparator(.hidden)
                    .padding(.vertical, DS.Space.s)
            }
            Section("Träning") {
                trainingSummary
            }
            insightsSection
            entriesSection
        }
        .scrollContentBackground(.hidden) // let the app-wide background show through
        .navigationTitle("Min utveckling")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    editingEntry = nil
                    showLogSheet = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Logga pass")
            }
        }
        .sheet(isPresented: $showLogSheet) {
            LogEntrySheet(entry: nil)
        }
        .sheet(item: $editingEntry) { entry in
            LogEntrySheet(entry: entry)
        }
        .navigationDestination(for: AppDestination.self) { destination in
            DestinationDetail(destination: destination)
        }
    }

    // MARK: Today

    private var todaySummary: some View {
        let today = ProgressEngine.aggregate(entries: progress.entries, on: Date(), calendar: Calendar.current)
        return VStack(spacing: DS.Space.m) {
            HStack(spacing: DS.Space.m) {
                RingGauge(
                    progress: progress.goals.dailySales > 0 ? Double(today.sales) / Double(progress.goals.dailySales) : 0,
                    title: "Affärer idag",
                    detail: "\(today.sales) av \(progress.goals.dailySales) i mål"
                )
                RingGauge(
                    progress: progress.goals.dailyCustomers > 0 ? Double(today.customers) / Double(progress.goals.dailyCustomers) : 0,
                    title: "Kunder",
                    detail: "\(today.customers) hjälpta",
                    color: .blue
                )
                RingGauge(
                    progress: progress.goals.weeklySales > 0 ? Double(weekSales) / Double(progress.goals.weeklySales) : 0,
                    title: "Vecka",
                    detail: "\(weekSales) av \(progress.goals.weeklySales)",
                    color: .pink
                )
            }
            .listRowSeparator(.hidden)
            HStack(spacing: DS.Space.m) {
                StatTile(value: "\(today.devices)", label: "enheter", symbol: "iphone.gen3")
                StatTile(value: "\(today.plans)", label: "abonnemang", symbol: "antenna.radiowaves.left.and.right")
                StatTile(value: "\(today.accessories)", label: "tillbehör", symbol: "headphones")
                StatTile(value: "\(today.broadbandTV)", label: "bredband/TV", symbol: "wifi.router")
            }
            .listRowSeparator(.hidden)
        }
    }

    private var weekSales: Int {
        let cal = Calendar.current
        let weekStart = cal.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
        return progress.entries
            .filter { $0.date >= weekStart }
            .reduce(0) { $0 + $1.completedSales }
    }

    // MARK: Charts

    private var salesChart: some View {
        Chart(last14Days) { day in
            BarMark(
                x: .value("Dag", Format.dayShort.string(from: day.date)),
                y: .value("Affärer", day.sales)
            )
            .foregroundStyle(DS.Purple.base.gradient)
            .cornerRadius(3)
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: 3)) { _ in
                AxisGridLine().foregroundStyle(.clear)
                AxisValueLabel()
                    .font(.system(.caption2, design: .rounded))
            }
        }
        .frame(height: 170)
        .accessibilityLabel("Stapeldiagram med försäljning de senaste 14 dagarna")
    }

    private var trainingSummary: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            HStack {
                Label("Streak: \(learning.streak) dagar", systemImage: "flame.fill")
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(.orange)
                Spacer()
                NavigationLink(value: AppDestination.academy) {
                    Text("Fortsätt träna")
                        .font(.system(.caption, design: .rounded).weight(.semibold))
                }
            }
            let answers = learning.data.answers.count
            let correct = learning.data.answers.filter(\.correct).count
            Text("\(learning.completedLessonIDs.count) lektioner · \(answers) quizfrågor (\(answers > 0 ? Int(Double(correct) / Double(answers) * 100) : 0)% rätt)")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Insights

    private var insightsSection: some View {
        Section("Förslag & trender") {
            let insights = InsightsEngine.suggestions(
                entries: progress.entries,
                goals: progress.goals,
                calendar: Calendar.current,
                learningAnswers: learning.data.answers
            )
            if insights.isEmpty {
                Text("Logga ett pass för att få personliga förslag.")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(insights) { insight in
                    HStack(alignment: .top, spacing: DS.Space.m) {
                        Image(systemName: insight.symbol)
                            .font(.system(.body, design: .rounded))
                            .foregroundStyle(DS.Purple.base)
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(insight.title)
                                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            Text(insight.detail)
                                .font(.system(.caption, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    // MARK: Entries

    private var entriesSection: some View {
        Section("Registrerade pass") {
            if progress.entries.isEmpty {
                Text("Inga inmatningar ännu. Allt du loggar stannar i telefonen – appen hittar bara på siffror du själv skrivit.")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(progress.entries.sorted { $0.date > $1.date }) { entry in
                    Button {
                        editingEntry = entry
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(Format.dayMonth.string(from: entry.date))
                                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                                .foregroundStyle(.primary)
                            Text("\(entry.completedSales) affärer · \(entry.customersAssisted) kunder · \(entry.devicesSold) enheter · \(entry.mobilePlansSold) abonnemang")
                                .font(.system(.caption, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete { offsets in
                    let sorted = progress.entries.sorted { $0.date > $1.date }
                    for index in offsets {
                        progress.deleteEntry(id: sorted[index].id)
                    }
                }
            }
        }
    }
}

// MARK: - Log entry sheet

struct LogEntrySheet: View {
    let entry: SalesEntry?

    @EnvironmentObject private var progress: ProgressStore
    @Environment(\.dismiss) private var dismiss

    @State private var date = Date()
    @State private var customers = 0
    @State private var sales = 0
    @State private var devices = 0
    @State private var plans = 0
    @State private var accessories = 0
    @State private var broadbandTV = 0
    @State private var services = 0
    @State private var revenue = ""
    @State private var notes = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Pass") {
                    DatePicker("Datum", selection: $date, displayedComponents: .date)
                }
                Section("Kunder & affärer") {
                    Stepper("Hjälpta kunder: \(customers)", value: $customers, in: 0...999)
                    Stepper("Färdiga affärer: \(sales)", value: $sales, in: 0...999)
                }
                Section("Vad såldes") {
                    Stepper("Enheter: \(devices)", value: $devices, in: 0...999)
                    Stepper("Abonnemang: \(plans)", value: $plans, in: 0...999)
                    Stepper("Tillbehör: \(accessories)", value: $accessories, in: 0...999)
                    Stepper("Bredband & TV: \(broadbandTV)", value: $broadbandTV, in: 0...999)
                    Stepper("Övriga tjänster: \(services)", value: $services, in: 0...999)
                }
                Section("Valfritt") {
                    TextField("Omsättning (kr, om din butik mäter det)", text: $revenue)
                        .keyboardType(.numberPad)
                    TextField("Anteckningar", text: $notes)
                }
                Section {
                    Text("Bara siffror du skriver in används – appen uppskattar eller hittar aldrig på försäljningsdata.")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(entry == nil ? "Logga pass" : "Redigera pass")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Avbryt") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Spara") {
                        let toSave = SalesEntry(
                            id: entry?.id ?? UUID(),
                            date: date,
                            customersAssisted: customers,
                            completedSales: sales,
                            devicesSold: devices,
                            mobilePlansSold: plans,
                            accessoriesSold: accessories,
                            broadbandTVSold: broadbandTV,
                            extraServicesSold: services,
                            revenueSEK: Double(revenue.replacingOccurrences(of: ",", with: ".")),
                            notes: notes
                        )
                        progress.upsert(toSave)
                        Haptics.success()
                        dismiss()
                    }
                }
            }
            .onAppear {
                if let entry {
                    date = entry.date
                    customers = entry.customersAssisted
                    sales = entry.completedSales
                    devices = entry.devicesSold
                    plans = entry.mobilePlansSold
                    accessories = entry.accessoriesSold
                    broadbandTV = entry.broadbandTVSold
                    services = entry.extraServicesSold
                    revenue = entry.revenueSEK.map { String(format: "%.0f", $0) } ?? ""
                    notes = entry.notes
                }
            }
        }
    }
}
