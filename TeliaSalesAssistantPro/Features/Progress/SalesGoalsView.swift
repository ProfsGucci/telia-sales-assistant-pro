import SwiftUI
import TeliaCore

// MARK: - Säljmål (Schema → Sales goals)
//
// Manual goals + automatic "how much per day" calculations. All numbers are
// entered by the user; the engine only divides what the user gave it.
// Day basis "Mina planerade pass" counts ONLY days that have shifts in the
// app's Schema — the app never assumes a working day.

struct SalesGoalsView: View {
    @EnvironmentObject private var goals: SalesGoalStore
    @EnvironmentObject private var schedule: ScheduleStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var editorGoal: SalesGoal?
    @State private var showEditor = false

    private var cal: Calendar { CalendarEngine.workCalendar() }

    /// All days (start-of-day) that have at least one shift — the realistic
    /// selling days for `.shiftDays` goals. Uses the same recurrence
    /// expansion as the calendar itself.
    private var shiftDays: [Date] {
        let horizon = cal.date(byAdding: .year, value: 1, to: Date()) ?? Date()
        var days = Set<Date>()
        for event in schedule.events where event.kind == .shift {
            let occurrences = CalendarEngine.occurrences(
                of: event, between: Date.distantPast, and: horizon, calendar: cal
            )
            for occurrence in occurrences {
                days.insert(cal.startOfDay(for: occurrence.start))
            }
        }
        return Array(days)
    }

    var body: some View {
        List {
            if goals.goals.isEmpty {
                Section {
                    EmptyStateView(
                        symbol: "target",
                        title: "Inga säljmål",
                        message: "Skapa ett mål så räknar appen ut hur mycket du behöver sälja per dag."
                    )
                    .listRowBackground(Color.clear)
                }
            }

            ForEach(goals.goals) { goal in
                let snapshot = SalesGoalEngine.snapshot(
                    goal: goal,
                    calendar: cal,
                    plannedShiftDates: goal.dayBasis == .shiftDays ? shiftDays : nil
                )
                SalesGoalCard(snapshot: snapshot) {
                    editorGoal = goal
                    showEditor = true
                } onDelete: {
                    withAnimation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.85)) {
                        goals.delete(goal)
                    }
                }
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 6, leading: DS.Space.m, bottom: 6, trailing: DS.Space.m))
            }
        }
        .scrollContentBackground(.hidden)
        .navigationTitle("Säljmål")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    editorGoal = nil
                    showEditor = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Nytt säljmål")
            }
        }
        .sheet(isPresented: $showEditor) {
            SalesGoalEditorSheet(existing: editorGoal)
        }
    }
}

// MARK: Goal card

private struct SalesGoalCard: View {
    let snapshot: SalesGoalSnapshot
    var onEdit: () -> Void = {}
    var onDelete: () -> Void = {}

    private var goal: SalesGoal { snapshot.goal }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.m) {
            header

            // Progress bar with spring fill.
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(DS.Surface.inset)
                    Capsule()
                        .fill(LinearGradient(colors: [DS.Purple.base, DS.Purple.light],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(8, geo.size.width * snapshot.progressFraction))
                }
            }
            .frame(height: 10)
            .accessibilityElement()
            .accessibilityLabel("Framsteg \(snapshot.progressPercent) procent")

            if let message = snapshot.message {
                Label(message, systemImage: statusSymbol)
                    .font(.system(.caption, design: .rounded).weight(.medium))
                    .foregroundStyle(statusColor)
            } else {
                numbersGrid
            }

            HStack(spacing: DS.Space.s) {
                Button {
                    onEdit()
                } label: {
                    Label("Redigera", systemImage: "pencil")
                        .font(.system(.caption, design: .rounded).weight(.semibold))
                }
                .buttonStyle(.bordered)
                .tint(DS.Purple.base)

                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label("Radera", systemImage: "trash")
                        .font(.system(.caption, design: .rounded).weight(.semibold))
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(DS.Space.l)
        .gloss(.subtle, tinted: false)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: DS.Space.m) {
            Image(systemName: goal.category.symbolName)
                .font(.system(.title3, design: .rounded))
                .foregroundStyle(DS.Purple.base)
                .frame(width: 42, height: 42)
                .background(Circle().fill(DS.Purple.base.opacity(0.12)))
            VStack(alignment: .leading, spacing: 3) {
                Text(goal.title)
                    .font(.system(.headline, design: .rounded))
                HStack(spacing: 6) {
                    Chip(text: goal.category.displayName, color: DS.Purple.base)
                    Chip(text: goal.dayBasis.displayName, color: .blue)
                    Text("\(snapshot.progressPercent)%")
                        .font(.system(.caption2, design: .rounded).weight(.bold))
                        .foregroundStyle(DS.Purple.base)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(Int(goal.actualProgress))/\(Int(goal.totalTarget))")
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .contentTransition(.numericInterpolation())
                    .animation(.spring(response: 0.4, dampingFraction: 0.85), value: goal.actualProgress)
                Text("klart")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var numbersGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: DS.Space.m) {
            numberCell(
                value: goal.category.isWholeUnit
                    ? "\(Int(snapshot.remaining))"
                    : SalesGoalEngine.formatNumber(snapshot.remaining, whole: false),
                label: "Kvar",
                tint: DS.Purple.base
            )
            numberCell(
                value: "\(snapshot.remainingDays)",
                label: "säljdagar kvar",
                tint: .blue
            )
            numberCell(
                value: perDayValue,
                label: perDayLabel,
                tint: DS.Orange.base
            )
        }
    }

    private var perDayValue: String {
        if goal.category.isWholeUnit {
            return snapshot.roundedUpPerDay > 0 ? "\(snapshot.roundedUpPerDay)" : "0"
        }
        return SalesGoalEngine.formatNumber(snapshot.requiredPerDay, whole: false)
    }

    private var perDayLabel: String {
        goal.category.isWholeUnit ? "att sälja/dag" : "kr/dag"
    }

    private func numberCell(value: String, label: String, tint: Color) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(.title2, design: .rounded).weight(.bold))
                .foregroundStyle(tint)
                .contentTransition(.numericInterpolation())
                .animation(.spring(response: 0.4, dampingFraction: 0.85), value: value)
            Text(label)
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DS.Space.s)
        .background(RoundedRectangle(cornerRadius: DS.Radius.tile, style: .continuous).fill(DS.Surface.inset))
    }

    private var statusSymbol: String {
        switch snapshot.status {
        case .completed: return "checkmark.seal.fill"
        case .exceeded: return "star.fill"
        case .noDaysRemaining: return "calendar.badge.exclamationmark"
        case .overdue: return "clock.badge.exclamationmark"
        case .notStarted, .inProgress: return "info.circle"
        }
    }

    private var statusColor: Color {
        switch snapshot.status {
        case .completed: return .green
        case .exceeded: return DS.Orange.base
        case .noDaysRemaining, .overdue: return DS.negative
        case .notStarted, .inProgress: return DS.Purple.base
        }
    }
}

// MARK: Editor

struct SalesGoalEditorSheet: View {
    @EnvironmentObject private var goals: SalesGoalStore
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var category: SalesGoalCategory = .subscriptions
    @State private var dayBasis: SalesGoalDayBasis = .shiftDays
    @State private var totalText = ""
    @State private var progressText = ""
    @State private var startDate = Date()
    @State private var targetDate = Calendar.current.date(byAdding: .month, value: 1, to: Date()) ?? Date()
    @State private var error: String?
    @State private var existingID: UUID?

    private let numberFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: "sv_SE")
        f.isPartial = true
        return f
    }()

    init(existing: SalesGoal?) {
        if let g = existing {
            _title = State(initialValue: g.title)
            _category = State(initialValue: g.category)
            _dayBasis = State(initialValue: g.dayBasis)
            _totalText = State(initialValue: String(format: "%.0f", g.totalTarget))
            _progressText = State(initialValue: g.actualProgress > 0 ? String(format: "%.0f", g.actualProgress) : "")
            _startDate = State(initialValue: g.startDate)
            _targetDate = State(initialValue: g.targetDate)
            _existingID = State(initialValue: g.id)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Mål") {
                    TextField("t.ex. Oktober — abonnemang", text: $title)
                    Picker("Kategori", selection: $category) {
                        ForEach(SalesGoalCategory.allCases) { c in
                            Label(c.displayName, systemImage: c.symbolName).tag(c)
                        }
                    }
                    TextField(
                        category == .revenue ? "Totalt mål (kr)" : "Totalt mål (antal)",
                        text: $totalText
                    )
                    .keyboardType(category == .revenue ? .decimalPad : .numberPad)
                    TextField(
                        "Uppnått hittills (frivilligt)",
                        text: $progressText
                    )
                    .keyboardType(category == .revenue ? .decimalPad : .numberPad)
                }

                Section {
                    Picker("Dagsbas", selection: $dayBasis) {
                        ForEach(SalesGoalDayBasis.allCases) { b in
                            Text(b.displayName).tag(b)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                    Text(dayBasis.hint)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Hur räknas säljdagar?")
                }

                Section("Period") {
                    DatePicker("Startdatum", selection: $startDate, displayedComponents: [.date])
                        .environment(\.locale, Locale(identifier: "sv_SE"))
                    DatePicker("Måldatum", selection: $targetDate, in: startDate..., displayedComponents: [.date])
                        .environment(\.locale, Locale(identifier: "sv_SE"))
                }

                if let error {
                    Section {
                        Label(error, systemImage: "exclamationmark.circle")
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(DS.negative)
                    }
                }

                Section {
                    Text("Alla siffror kommer från det du skriver in — appen hittar aldrig på försäljning. Beräkningen: kvarvarande mål ÷ kvarvarande säljdagar.")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(existingID == nil ? "Nytt säljmål" : "Redigera mål")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Avbryt") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Spara") { save() }
                        .font(.system(.subheadline, design: .rounded).weight(.bold))
                        .disabled(title.isEmpty || totalText.isEmpty)
                }
            }
        }
    }

    private func save() {
        let total = Double(totalText.replacingOccurrences(of: ",", with: ".")) ?? Double(totalText) ?? -1
        let done = Double(progressText.replacingOccurrences(of: ",", with: ".")) ?? Double(progressText) ?? 0
        guard total > 0 else {
            error = "Totalt mål måste vara större än noll."
            return
        }
        guard done >= 0 else {
            error = "Uppnått kan inte vara negativt."
            return
        }
        guard targetDate > startDate else {
            error = "Måldatum måste ligga efter startdatum."
            return
        }
        let goal = SalesGoal(
            id: existingID ?? UUID(),
            title: title.trimmingCharacters(in: .whitespaces),
            category: category,
            totalTarget: total,
            actualProgress: max(0, done),
            startDate: startDate,
            targetDate: targetDate,
            dayBasis: dayBasis
        )
        goals.upsert(goal)
        Haptics.tap()
        dismiss()
    }
}
