import Foundation

// MARK: - Entries

/// One shift's self-reported numbers. Never fabricated — the user types every value.
public struct SalesEntry: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var date: Date
    public var customersAssisted: Int
    public var completedSales: Int
    public var devicesSold: Int
    public var mobilePlansSold: Int
    public var accessoriesSold: Int
    public var broadbandTVSold: Int
    public var extraServicesSold: Int
    /// Optional — some stores don't want revenue tracked.
    public var revenueSEK: Double?
    public var notes: String

    public init(id: UUID = UUID(), date: Date = Date(), customersAssisted: Int = 0,
                completedSales: Int = 0, devicesSold: Int = 0, mobilePlansSold: Int = 0,
                accessoriesSold: Int = 0, broadbandTVSold: Int = 0, extraServicesSold: Int = 0,
                revenueSEK: Double? = nil, notes: String = "") {
        self.id = id
        self.date = date
        self.customersAssisted = customersAssisted
        self.completedSales = completedSales
        self.devicesSold = devicesSold
        self.mobilePlansSold = mobilePlansSold
        self.accessoriesSold = accessoriesSold
        self.broadbandTVSold = broadbandTVSold
        self.extraServicesSold = extraServicesSold
        self.revenueSEK = revenueSEK
        self.notes = notes
    }
}

public struct Goals: Codable, Hashable, Sendable {
    public var dailySales: Int
    public var dailyCustomers: Int
    public var weeklySales: Int
    public var dailyTrainingMinutes: Int

    public init(dailySales: Int = 5, dailyCustomers: Int = 20, weeklySales: Int = 25,
                dailyTrainingMinutes: Int = 10) {
        self.dailySales = dailySales
        self.dailyCustomers = dailyCustomers
        self.weeklySales = weeklySales
        self.dailyTrainingMinutes = dailyTrainingMinutes
    }
}

// MARK: - Aggregation

public struct DayAggregate: Codable, Hashable, Identifiable, Sendable {
    public var id: Date { date }
    public let date: Date
    public let customers: Int
    public let sales: Int
    public let devices: Int
    public let plans: Int
    public let accessories: Int
    public let broadbandTV: Int
    public let services: Int
    public let revenue: Double

    /// Conversion computed strictly from entered data. No estimates.
    public var conversion: Double? {
        customers > 0 ? Double(sales) / Double(customers) : nil
    }
}

public enum ProgressEngine {

    public static func aggregate(
        entries: [SalesEntry],
        on date: Date,
        calendar: Calendar
    ) -> DayAggregate {
        let day = calendar.startOfDay(for: date)
        let matching = entries.filter { calendar.startOfDay(for: $0.date) == day }
        return reduce(entries: matching, date: day)
    }

    public static func weeklyAggregates(
        entries: [SalesEntry],
        endingOn date: Date,
        weeksBack: Int,
        calendar: Calendar
    ) -> [DayAggregate] {
        var results: [DayAggregate] = []
        for offset in stride(from: weeksBack - 1, through: 0, by: -1) {
            guard let weekEnd = calendar.date(byAdding: .weekOfYear, value: -offset, to: date) else { continue }
            let day = calendar.startOfDay(for: weekEnd)
            let matching = entries.filter { calendar.startOfDay(for: $0.date) == day }
            results.append(reduce(entries: matching, date: day))
        }
        return results
    }

    static func reduce(entries: [SalesEntry], date: Date) -> DayAggregate {
        DayAggregate(
            date: date,
            customers: entries.reduce(0) { $0 + $1.customersAssisted },
            sales: entries.reduce(0) { $0 + $1.completedSales },
            devices: entries.reduce(0) { $0 + $1.devicesSold },
            plans: entries.reduce(0) { $0 + $1.mobilePlansSold },
            accessories: entries.reduce(0) { $0 + $1.accessoriesSold },
            broadbandTV: entries.reduce(0) { $0 + $1.broadbandTVSold },
            services: entries.reduce(0) { $0 + $1.extraServicesSold },
            revenue: entries.reduce(0.0) { $0 + ($1.revenueSEK ?? 0) }
        )
    }

    public static func trend(
        values: [Double]
    ) -> Double? {
        guard values.count >= 4 else { return nil }
        let half = values.count / 2
        let older = values.prefix(half).reduce(0, +) / Double(half)
        let newer = values.suffix(half).reduce(0, +) / Double(half)
        guard older > 0 else { return newer > 0 ? 1 : nil }
        return (newer - older) / older
    }
}

// MARK: - Insights

public enum InsightsEngine {

    public struct Insight: Hashable, Identifiable, Sendable {
        public var id: String { title }
        public let title: String
        public let detail: String
        public let symbol: String
    }

    /// Rule-based, personal, honest suggestions from the entered data only.
    public static func suggestions(
        entries: [SalesEntry],
        goals: Goals,
        calendar: Calendar,
        learningAnswers: [QuizAnswerRecord]
    ) -> [Insight] {
        var insights: [Insight] = []
        let last14 = entries.filter {
            guard let cutoff = calendar.date(byAdding: .day, value: -14, to: Date()) else { return false }
            return $0.date >= cutoff
        }

        let totalCustomers = last14.reduce(0) { $0 + $1.customersAssisted }
        let totalSales = last14.reduce(0) { $0 + $1.completedSales }
        let totalAccessories = last14.reduce(0) { $0 + $1.accessoriesSold }
        let totalBroadband = last14.reduce(0) { $0 + $1.broadbandTVSold }
        let totalDevices = last14.reduce(0) { $0 + $1.devicesSold }

        if !last14.isEmpty {
            if totalCustomers > 0 {
                let conversion = Double(totalSales) / Double(totalCustomers)
                insights.append(Insight(
                    title: String(format: "Konversion %.0f%% (14 dagar)", conversion * 100),
                    detail: "Baserat på dina egna registreringar: \(totalSales) affärer av \(totalCustomers) hjälpta kunder. Jämför med hur det kännes i butik – siffran är bara sann om dina inmatningar är det.",
                    symbol: "percent"
                ))
            }
            if totalDevices > 0 && totalAccessories < totalDevices / 2 {
                insights.append(Insight(
                    title: "Tillbehörsmöjlighet",
                    detail: "Du har sålt \(totalDevices) enheter men bara \(totalAccessories) tillbehör. Nästa pass: fråga varje enhetskund om skydd, laddare eller hörlurar – ett naturligt 'bekvämlighetsval', inte ett push.",
                    symbol: "headphones"
                ))
            }
            if totalBroadband == 0 {
                insights.append(Insight(
                    title: "Bredband i samtalet",
                    detail: "Inga bredbands-/TV-affärer på 14 dagar. Öva på bredbandsargumentationen i Akademin och nämn samlingsrabatten (100 kr/mån) när du träffar obegränsade kunder.",
                    symbol: "wifi.router"
                ))
            }
            let trend = ProgressEngine.trend(values: last14.sorted { $0.date < $1.date }.map { Double($0.completedSales) })
            if let t = trend, abs(t) > 0.15 {
                insights.append(Insight(
                    title: t > 0 ? "Uppåtgående trend" : "Nedåtgående trend",
                    detail: t > 0
                        ? "Dina affärer per pass ökar jämfört med förra veckan. Fundera på vad du gör annorlunda och fortsätt med det."
                        : "Affärerna per pass har sjunkit. Prioritera kartläggningsfrågor (se Rollspel) innan du föreslår produkter.",
                    symbol: t > 0 ? "arrow.up.right" : "arrow.down.right"
                ))
            }
        } else {
            insights.append(Insight(
                title: "Börja logga ditt pass",
                detail: "Registrera kunder och affärer efter varje pass – då får du riktiga trender istället för gissningar. Allt stannar i telefonen.",
                symbol: "square.and.pencil"
            ))
        }

        let weak = LearningEngine.weakTopics(from: learningAnswers)
        if let worst = weak.first {
            insights.append(Insight(
                title: "Repetera: \(worst.topic)",
                detail: "Din träffsäkerhet på \(worst.topic) är \(Int(worst.accuracy * 100))%. En snabb lektion + flashcards tar ca 5 minuter.",
                symbol: "brain.head.profile"
            ))
        }
        _ = goals
        return insights
    }
}
