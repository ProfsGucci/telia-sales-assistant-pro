import SwiftUI
import TeliaCore

struct CalendarView: View {
    @EnvironmentObject private var schedule: ScheduleStore

    @State private var mode: CalMode = .month
    @State private var selectedDate = Date()
    @State private var displayedMonth: Date = Date()
    @State private var editorEvent: ScheduleEvent?
    @State private var showEditor = false

    enum CalMode: String, CaseIterable, Identifiable {
        case month = "Månad"
        case week = "Vecka"
        case upcoming = "Kommande"
        var id: String { rawValue }
    }

    private let cal = CalendarEngine.workCalendar()

    var body: some View {
        VStack(spacing: 0) {
            Picker("Vy", selection: $mode) {
                ForEach(CalMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .padding(DS.Space.m)

            ScrollView {
                VStack(spacing: DS.Space.m) {
                    switch mode {
                    case .month: monthView
                    case .week: weekView
                    case .upcoming: upcomingView
                    }
                }
                .padding(.horizontal, DS.Space.m)
                .padding(.bottom, DS.Space.xl)
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Kalender")
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button {
                    selectedDate = Date()
                    displayedMonth = Date()
                } label: {
                    Text("Idag")
                }
                Button {
                    editorEvent = nil
                    showEditor = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Ny händelse")
            }
        }
        .sheet(isPresented: $showEditor) {
            EventEditorView(existing: editorEvent, initialDate: selectedDate)
        }
    }

    // MARK: Month

    private var monthView: some View {
        VStack(spacing: DS.Space.m) {
            monthHeader
            MonthGrid(
                month: displayedMonth,
                selectedDate: $selectedDate,
                events: schedule.events,
                calendar: cal
            )
            dayDetail
        }
    }

    private var monthHeader: some View {
        HStack {
            Button {
                changeMonth(-1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color(.tertiarySystemFill)))
            }
            .buttonStyle(PressableStyle(scale: 0.9))
            Spacer()
            VStack(spacing: 0) {
                Text(monthTitle)
                    .font(.system(.headline, design: .rounded))
                Text(String(cal.component(.year, from: displayedMonth)))
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                changeMonth(1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.body.weight(.semibold))
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color(.tertiarySystemFill)))
            }
            .buttonStyle(PressableStyle(scale: 0.9))
        }
        .padding(.horizontal, DS.Space.xs)
    }

    private var monthTitle: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "sv_SE")
        formatter.dateFormat = "MMMM"
        formatter.calendar = cal
        return formatter.string(from: displayedMonth).capitalized
    }

    private func changeMonth(_ delta: Int) {
        withAnimation(.easeInOut(duration: DS.Motion.content)) {
            displayedMonth = cal.date(byAdding: .month, value: delta, to: displayedMonth) ?? displayedMonth
        }
    }

    // MARK: Week

    private var weekView: some View {
        VStack(spacing: DS.Space.m) {
            let weekDates = weekDates(containing: selectedDate)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DS.Space.s) {
                    ForEach(weekDates, id: \.self) { date in
                        let isToday = cal.isDateInToday(date)
                        let isSelected = cal.isDate(date, inSameDayAs: selectedDate)
                        Button {
                            withAnimation(.easeInOut(duration: DS.Motion.reveal)) { selectedDate = date }
                        } label: {
                            VStack(spacing: 4) {
                                Text(Format.weekdayLetter.string(from: date).uppercased())
                                    .font(.system(.caption2, design: .rounded).weight(.semibold))
                                Text("\(cal.component(.day, from: date))")
                                    .font(.system(.body, design: .rounded).weight(.semibold))
                                Circle()
                                    .fill(eventDotColor(date))
                                    .frame(width: 6, height: 6)
                                    .opacity(hasEvents(date) ? 1 : 0)
                            }
                            .frame(width: 52, height: 74)
                            .background(
                                RoundedRectangle(cornerRadius: DS.Radius.tile, style: .continuous)
                                    .fill(isSelected ? AnyShapeStyle(DS.heroGradient) : AnyShapeStyle(Color(.secondarySystemGroupedBackground)))
                            )
                            .foregroundStyle(isSelected ? .white : (isToday ? DS.Purple.base : Color.primary))
                        }
                        .buttonStyle(PressableStyle(scale: 0.93))
                    }
                }
                .padding(.horizontal, 2)
            }
            dayDetail
        }
    }

    private func weekDates(containing date: Date) -> [Date] {
        let start = cal.dateInterval(of: .weekOfYear, for: date)?.start ?? date
        return (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: start) }
    }

    // MARK: Upcoming

    private var upcomingView: some View {
        let upcoming = CalendarEngine.upcoming(from: schedule.events, after: Date(), limit: 20, calendar: cal)
        return Group {
            if upcoming.isEmpty {
                EmptyStateView(
                    symbol: "calendar.badge.clock",
                    title: "Inget kommande",
                    message: "Lägg till pass, utbildningar och påminnelser med plus-knappen."
                )
            } else {
                VStack(spacing: DS.Space.m) {
                    ForEach(upcoming) { event in
                        EventRow(event: event, calendar: cal) {
                            editorEvent = event
                            showEditor = true
                        }
                    }
                }
            }
        }
    }

    // MARK: Shared day detail

    private var dayDetail: some View {
        let events = CalendarEngine.events(on: selectedDate, from: schedule.events, calendar: cal)
        let tasks = CalendarEngine.tasks(on: selectedDate, from: schedule.tasks, calendar: cal)
        return VStack(spacing: DS.Space.m) {
            SectionCard(title: dayTitle, symbol: "calendar.day.timeline.left") {
                VStack(spacing: DS.Space.m) {
                    if events.isEmpty {
                        Text("Inga händelser.")
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(events) { event in
                            Button {
                                editorEvent = event
                                showEditor = true
                            } label: {
                                EventRowContent(event: event, calendar: cal)
                            }
                            .buttonStyle(PressableStyle(scale: 0.98))
                        }
                    }
                    taskSection(tasks: tasks)
                    Button {
                        editorEvent = nil
                        showEditor = true
                    } label: {
                        Label("Ny händelse denna dag", systemImage: "plus.circle.fill")
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            .foregroundStyle(DS.Purple.base)
                    }
                    .buttonStyle(PressableStyle())
                }
            }
        }
    }

    private func taskSection(tasks: [DayTask]) -> some View {
        Group {
            if !tasks.isEmpty {
                Divider()
                ForEach(tasks) { task in
                    HStack {
                        CheckToggle(done: task.done) {
                            schedule.toggleTask(task.id)
                        }
                        Text(task.title)
                            .font(.system(.subheadline, design: .rounded))
                            .strikethrough(task.done, color: .secondary)
                        Spacer()
                        Button {
                            schedule.deleteTask(id: task.id)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
        }
    }

    private var dayTitle: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "sv_SE")
        formatter.calendar = cal
        formatter.dateFormat = cal.isDateInToday(selectedDate) ? "'Idag' d MMMM" : "EEEE d MMMM"
        return formatter.string(from: selectedDate).capitalized
    }

    private func hasEvents(_ date: Date) -> Bool {
        !CalendarEngine.events(on: date, from: schedule.events, calendar: cal).isEmpty
    }

    private func eventDotColor(_ date: Date) -> Color {
        let events = CalendarEngine.events(on: date, from: schedule.events, calendar: cal)
        if events.contains(where: { $0.kind == .shift }) { return DS.Purple.base }
        return .blue
    }
}

// MARK: - Month grid

struct MonthGrid: View {
    let month: Date
    @Binding var selectedDate: Date
    let events: [ScheduleEvent]
    let calendar: Calendar

    private var grid: [Date] {
        CalendarEngine.monthGrid(containing: month, calendar: calendar)
    }

    private var weekdays: [String] {
        (0..<7).compactMap { offset -> String? in
            guard let weekday = calendar.date(byAdding: .day, value: offset, to: grid[0]) else { return nil }
            return Format.weekdayLetter.string(from: weekday).uppercased()
        }
    }

    var body: some View {
        VStack(spacing: DS.Space.s) {
            HStack {
                ForEach(weekdays, id: \.self) { day in
                    Text(day)
                        .font(.system(.caption2, design: .rounded).weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 6) {
                ForEach(grid, id: \.self) { date in
                    dayCell(date)
                }
            }
        }
    }

    @ViewBuilder
    private func dayCell(_ date: Date) -> some View {
        let inMonth = CalendarEngine.isSameMonth(date, month, calendar: calendar)
        let isSelected = calendar.isDate(date, inSameDayAs: selectedDate)
        let isToday = calendar.isDateInToday(date)
        let dayEvents = CalendarEngine.events(on: date, from: events, calendar: calendar)

        Button {
            withAnimation(.easeInOut(duration: DS.Motion.tap)) { selectedDate = date }
        } label: {
            VStack(spacing: 3) {
                Text("\(calendar.component(.day, from: date))")
                    .font(.system(.subheadline, design: .rounded).weight(isToday ? .bold : .regular))
                HStack(spacing: 2) {
                    ForEach(0..<min(3, dayEvents.count), id: \.self) { index in
                        Circle()
                            .fill(dayEvents[index].kind == .shift ? DS.Purple.base : Color.blue)
                            .frame(width: 5, height: 5)
                    }
                }
                .frame(height: 5)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? AnyShapeStyle(DS.heroGradient)
                          : AnyShapeStyle(inMonth ? Color(.secondarySystemGroupedBackground) : Color.clear))
            )
            .foregroundStyle(isSelected ? .white : (inMonth ? Color.primary : Color.secondary.opacity(0.5)))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(isToday && !isSelected ? DS.Purple.base.opacity(0.6) : .clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(PressableStyle(scale: 0.9))
        .accessibilityLabel(Text("\(calendar.component(.day, from: date)), \(dayEvents.count) händelser"))
    }
}

// MARK: - Event row

struct EventRow: View {
    let event: ScheduleEvent
    let calendar: Calendar
    var onEdit: () -> Void = {}

    var body: some View {
        Button(action: onEdit) {
            EventRowContent(event: event, calendar: calendar)
        }
        .buttonStyle(PressableStyle(scale: 0.98))
    }
}

struct EventRowContent: View {
    let event: ScheduleEvent
    let calendar: Calendar

    var body: some View {
        HStack(spacing: DS.Space.m) {
            Image(systemName: event.kind.symbolName)
                .font(.system(.body, design: .rounded))
                .foregroundStyle(DS.Purple.base)
                .frame(width: 38, height: 38)
                .background(RoundedRectangle(cornerRadius: 10).fill(DS.Purple.base.opacity(0.12)))
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(.primary)
                Text("\(Format.time.string(from: event.start))–\(Format.time.string(from: event.end))\(event.location.isEmpty ? "" : " · \(event.location)")")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if event.recurrence != .none {
                Image(systemName: "repeat")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Chip(text: event.kind.displayName, color: DS.Purple.base)
        }
        .padding(DS.Space.m)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.tile, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }
}

// MARK: - Editor

struct EventEditorView: View {
    let existing: ScheduleEvent?
    let initialDate: Date

    @EnvironmentObject private var schedule: ScheduleStore
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var kind: EventKind = .shift
    @State private var start = Date()
    @State private var durationHours = 8.0
    @State private var location = ""
    @State private var notes = ""
    @State private var recurrence: Recurrence = .none
    @State private var recurrenceEnd: Date = Date().addingTimeInterval(90 * 24 * 3600)
    @State private var hasRecurrenceEnd = false
    @State private var calendarExport = EventKitService()
    @State private var appleCalendarResult: String?
    @State private var confirmDelete = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Händelse") {
                    TextField("Titel (t.ex. Kvällspass Kista)", text: $title)
                    Picker("Typ", selection: $kind) {
                        ForEach(EventKind.allCases, id: \.self) { k in
                            Label(k.displayName, systemImage: k.symbolName).tag(k)
                        }
                    }
                    TextField("Plats (valfritt)", text: $location)
                }
                Section("Tid") {
                    DatePicker("Start", selection: $start, in: Date().addingTimeInterval(-86400 * 365)...)
                    Stepper("Längd: \(durationText)", value: $durationHours, in: 0.5...12, step: 0.5)
                }
                Section("Upprepning") {
                    Picker("Upprepas", selection: $recurrence) {
                        ForEach(Recurrence.allCases, id: \.self) { r in
                            Text(r.displayName).tag(r)
                        }
                    }
                    if recurrence != .none {
                        Toggle("Slutdatum", isOn: $hasRecurrenceEnd)
                        if hasRecurrenceEnd {
                            DatePicker("Upp till", selection: $recurrenceEnd, displayedComponents: .date)
                        }
                    }
                }
                Section("Förberedelser") {
                    TextEditor(text: $notes)
                        .frame(minHeight: 80)
                        .font(.system(.subheadline, design: .rounded))
                }
                Section {
                    Button {
                        Task {
                            let ok = await calendarExport.addToAppleCalendar(buildEvent())
                            appleCalendarResult = ok
                                ? "Tillagd i Apple Calendar."
                                : (calendarExport.authorizationDenied ? "Åtkomst nekad – kalendern fungerar ändå i appen." : "Kunde inte lägga till i Apple Calendar.")
                        }
                    } label: {
                        Label("Lägg även i Apple Calendar", systemImage: "calendar.badge.plus")
                    }
                    if let appleCalendarResult {
                        Text(appleCalendarResult)
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Apple Calendar (valfritt)")
                } footer: {
                    Text("Appen ber om åtkomst först när du trycker. Allt fungerar även utan Apple Calendar.")
                }
                if existing != nil {
                    Section {
                        Button(role: .destructive) {
                            confirmDelete = true
                        } label: {
                            Label("Radera händelsen", systemImage: "trash")
                        }
                    }
                }
            }
            .navigationTitle(existing == nil ? "Ny händelse" : "Redigera")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Avbryt") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Spara") {
                        let event = buildEvent()
                        schedule.upsert(event)
                        if settings.data.remindersEnabled && event.kind == .shift {
                            NotificationService.shared.scheduleShiftReminder(for: event)
                        }
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .confirmationDialog("Radera händelsen?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Radera", role: .destructive) {
                    if let existing { schedule.deleteEvent(id: existing.id) }
                    dismiss()
                }
            }
            .onAppear {
                if let existing {
                    title = existing.title
                    kind = existing.kind
                    start = existing.start
                    durationHours = max(0.5, existing.end.timeIntervalSince(existing.start) / 3600)
                    location = existing.location
                    notes = existing.notes
                    recurrence = existing.recurrence
                    if let end = existing.recurrenceEnd {
                        hasRecurrenceEnd = true
                        recurrenceEnd = end
                    }
                } else {
                    start = CalendarEngine.workCalendar().startOfDay(for: initialDate).addingTimeInterval(9 * 3600)
                }
            }
        }
    }

    private var durationText: String {
        let hours = Int(durationHours)
        let minutes = Int((durationHours - Double(hours)) * 60)
        if minutes > 0 { return "\(hours) h \(minutes) min" }
        return "\(hours) h"
    }

    private func buildEvent() -> ScheduleEvent {
        ScheduleEvent(
            id: existing?.id ?? UUID(),
            title: title.trimmingCharacters(in: .whitespaces),
            kind: kind,
            start: start,
            end: start.addingTimeInterval(durationHours * 3600),
            notes: notes,
            location: location,
            recurrence: recurrence,
            recurrenceEnd: hasRecurrenceEnd ? recurrenceEnd : nil
        )
    }
}
