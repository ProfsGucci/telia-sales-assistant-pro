import SwiftUI
import TeliaCore

// MARK: - Check Later Customer (snabba uppföljningar)
//
// Design goals:
// - EXAKT fyra obligatoriska fält: personnummer, namn, anledning, datum.
// - Öppnas som ett snabbt sheet direkt från Schema och dashboard.
// - Personnummer maskeras i listor (visas bara vid tryck på ögat) och lämnar
//   ALDRIG enheten — ingen AI, ingen synk, inga loggar.

// MARK: Quick-add sheet

struct FollowUpQuickAddSheet: View {
    @EnvironmentObject private var followUps: FollowUpStore
    @Environment(\.dismiss) private var dismiss

    @State private var personnummer = ""
    @State private var name = ""
    @State private var reason = ""
    @State private var dueDate = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
    @State private var validationError: String?
    @State private var showDuplicateConfirm = false
    @FocusState private var focusedField: Field?

    enum Field: Hashable {
        case personnummer, name, reason
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Personnummer")
                            .font(.system(.caption, design: .rounded).weight(.semibold))
                            .foregroundStyle(.secondary)
                        TextField("ÅÅÅÅMMDD-XXXX", text: $personnummer)
                            .keyboardType(.numbersAndPunctuation)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($focusedField, equals: .personnummer)
                            .onSubmit { focusedField = .name }
                        if let validationError {
                            Label(validationError, systemImage: "exclamationmark.circle")
                                .font(.system(.caption, design: .rounded))
                                .foregroundStyle(DS.negative)
                                .transition(.opacity)
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Namn")
                            .font(.system(.caption, design: .rounded).weight(.semibold))
                            .foregroundStyle(.secondary)
                        TextField("Kundens namn", text: $name)
                            .textInputAutocapitalization(.words)
                            .focused($focusedField, equals: .name)
                            .onSubmit { focusedField = .reason }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Anledning att kolla senare")
                            .font(.system(.caption, design: .rounded).weight(.semibold))
                            .foregroundStyle(.secondary)
                        TextField("t.ex. Kolla kampanj, jämför abonnemang", text: $reason, axis: .vertical)
                            .lineLimit(2...4)
                            .focused($focusedField, equals: .reason)
                    }

                    DatePicker(
                        "Datum att kolla",
                        selection: $dueDate,
                        displayedComponents: [.date]
                    )
                    .environment(\.locale, Locale(identifier: "sv_SE"))
                } header: {
                    Text("Ny uppföljning")
                } footer: {
                    Text("Personnumret stannar på enheten — det skickas aldrig till AI eller tjänster. Kontrollera att din arbetsgivares regler tillåter att kunduppgifter sparas i appen.")
                }
            }
            .navigationTitle("Kolla senare")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Avbryt") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Spara") { save() }
                        .font(.system(.subheadline, design: .rounded).weight(.bold))
                        .disabled(personnummer.isEmpty || name.isEmpty || reason.isEmpty)
                }
            }
            .alert("Möjlig dubblett", isPresented: $showDuplicateConfirm) {
                Button("Spara ändå") { save(force: true) }
                    .keyboardShortcut(.defaultAction)
                Button("Avbryt", role: .cancel) {}
            } message: {
                Text("Det finns redan en pågående uppföljning för det här personnumret. Vill du spara en till?")
            }
            .onAppear { focusedField = .personnummer }
        }
        .presentationDetents([.large])
    }

    private func save(force: Bool = false) {
        withAnimation(.easeInOut(duration: DS.Motion.tap)) {
            validationError = nil
        }
        guard !force else {
            commitSave()
            return
        }
        // Duplicate check runs BEFORE validation errors are shown so a
        // well-formed repeat gets the friendly warning first.
        if Personnummer.isValid(personnummer), followUps.hasOpenDuplicate(personnummer: personnummer) {
            showDuplicateConfirm = true
            return
        }
        commitSave()
    }

    private func commitSave() {
        let result = followUps.add(
            personnummer: personnummer,
            name: name,
            reason: reason,
            dueDate: dueDate
        )
        switch result {
        case .success:
            Haptics.tap()
            dismiss()
        case .failure(let error):
            withAnimation(.easeInOut(duration: DS.Motion.tap)) {
                validationError = error.message
            }
        }
    }
}

// MARK: Follow-up list (dashboard)

struct FollowUpListView: View {
    @EnvironmentObject private var followUps: FollowUpStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var searchText = ""
    @State private var filter: Filter = .open
    @State private var showAdd = false
    @State private var editing: FollowUpRecord?
    @State private var rescheduling: FollowUpRecord?
    @State private var revealedIDs: Set<UUID> = []

    enum Filter: String, CaseIterable, Identifiable {
        case open = "Aktiva"
        case completed = "Klara"
        case all = "Alla"
        var id: String { rawValue }
    }

    private var cal: Calendar { CalendarEngine.workCalendar() }

    var body: some View {
        List {
            Section {
                Picker("Filter", selection: $filter.animation(.easeInOut(duration: DS.Motion.content))) {
                    ForEach(Filter.allCases) { f in
                        Text(f.rawValue).tag(f)
                    }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
            }

            let groups = FollowUpEngine.group(
                FollowUpEngine.search(followUps.records, query: searchText),
                calendar: cal
            )

            switch filter {
            case .open:
                section("Försenade", records: groups.overdue, status: .overdue)
                section("Idag", records: groups.dueToday, status: .dueToday)
                section("Kommande", records: groups.upcoming, status: .upcoming)
                if groups.open.isEmpty && groups.completed.isEmpty {
                    emptyRow
                }
            case .completed:
                section("Klara", records: groups.completed, status: .completed)
                if groups.completed.isEmpty { emptyRow }
            case .all:
                section("Försenade", records: groups.overdue, status: .overdue)
                section("Idag", records: groups.dueToday, status: .dueToday)
                section("Kommande", records: groups.upcoming, status: .upcoming)
                section("Klara", records: groups.completed, status: .completed)
                if groups.isEmpty { emptyRow }
            }
        }
        .searchable(text: $searchText, prompt: "Sök på namn eller anledning")
        .navigationTitle("Kolla senare")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showAdd = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Ny uppföljning")
            }
        }
        .sheet(isPresented: $showAdd) {
            FollowUpQuickAddSheet()
        }
        .sheet(item: $editing) { record in
            FollowUpEditSheet(record: record)
        }
        .sheet(item: $rescheduling) { record in
            FollowUpRescheduleSheet(record: record)
        }
    }

    private var emptyRow: some View {
        Section {
            EmptyStateView(
                symbol: "person.crop.circle.badge.clock",
                title: "Inga uppföljningar",
                message: "Lägg till en kund att kolla senare med plus-knappen."
            )
            .listRowBackground(Color.clear)
        }
    }

    @ViewBuilder
    private func section(_ title: String, records: [FollowUpRecord], status: FollowUpStatus) -> some View {
        if !records.isEmpty {
            Section(title) {
                ForEach(records) { record in
                    FollowUpRow(
                        record: record,
                        status: status,
                        revealed: revealedIDs.contains(record.id)
                    ) {
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: DS.Motion.tap)) {
                            if revealedIDs.contains(record.id) {
                                revealedIDs.remove(record.id)
                            } else {
                                revealedIDs.insert(record.id)
                            }
                        }
                    } onEdit: {
                        editing = record
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        if record.isCompleted {
                            Button {
                                followUps.reopen(record)
                            } label: {
                                Label("Öppna igen", systemImage: "arrow.uturn.backward")
                            }
                            .tint(.blue)
                        } else {
                            Button {
                                Haptics.tap()
                                followUps.markCompleted(record)
                            } label: {
                                Label("Klar", systemImage: "checkmark.circle.fill")
                            }
                            .tint(.green)
                        }
                        Button(role: .destructive) {
                            followUps.delete(record)
                        } label: {
                            Label("Radera", systemImage: "trash")
                        }
                    }
                    .swipeActions(edge: .leading) {
                        Button {
                            rescheduling = record
                        } label: {
                            Label("Boka om", systemImage: "calendar.badge.clock")
                        }
                        .tint(DS.Purple.base)
                    }
                }
            }
        }
    }
}

// MARK: Row

private struct FollowUpRow: View {
    let record: FollowUpRecord
    let status: FollowUpStatus
    let revealed: Bool
    let onToggleReveal: () -> Void
    var onEdit: () -> Void = {}

    var body: some View {
        Button(action: onEdit) {
            HStack(spacing: DS.Space.m) {
                Image(systemName: record.isCompleted ? "checkmark.circle.fill" : statusIcon)
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(record.isCompleted ? .green : statusColor)
                    .frame(width: 34)

                VStack(alignment: .leading, spacing: 3) {
                    Text(record.name)
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .foregroundStyle(.primary)
                    HStack(spacing: 6) {
                        Text(revealed
                             ? Personnummer.fullString(record.personnummer)
                             : Personnummer.maskedString(record.personnummer))
                            .font(.system(.caption, design: .rounded).monospaced())
                            .foregroundStyle(.secondary)
                        Button(action: onToggleReveal) {
                            Image(systemName: revealed ? "eye.slash" : "eye")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(revealed ? "Dölj personnummer" : "Visa personnummer")
                    }
                    Text(record.reason)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text(dateLabel)
                        .font(.system(.caption, design: .rounded).weight(.semibold))
                        .foregroundStyle(record.isCompleted ? .secondary : statusColor)
                    Chip(text: status.displayName, color: record.isCompleted ? .green : statusColor)
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }

    private var statusIcon: String {
        switch status {
        case .overdue: return "exclamationmark.circle.fill"
        case .dueToday: return "clock.fill"
        case .upcoming: return "calendar"
        case .completed: return "checkmark.circle.fill"
        }
    }

    private var statusColor: Color {
        switch status {
        case .overdue: return DS.negative
        case .dueToday: return DS.Orange.base
        case .upcoming: return DS.Purple.base
        case .completed: return .green
        }
    }

    private var dateLabel: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "sv_SE")
        formatter.dateFormat = "d MMM"
        return formatter.string(from: record.dueDate)
    }
}

// MARK: Edit sheet (same four fields)

struct FollowUpEditSheet: View {
    @EnvironmentObject private var followUps: FollowUpStore
    @Environment(\.dismiss) private var dismiss

    @State private var record: FollowUpRecord
    @State private var pnrText: String
    @State private var error: String?

    init(record: FollowUpRecord) {
        _record = State(initialValue: record)
        _pnrText = State(initialValue: Personnummer.fullString(record.personnummer))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Personnummer", text: $pnrText)
                        .keyboardType(.numbersAndPunctuation)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Namn", text: $record.name)
                        .textInputAutocapitalization(.words)
                    TextField("Anledning", text: $record.reason, axis: .vertical)
                        .lineLimit(2...4)
                    DatePicker("Datum att kolla", selection: $record.dueDate, displayedComponents: [.date])
                        .environment(\.locale, Locale(identifier: "sv_SE"))
                    if let error {
                        Label(error, systemImage: "exclamationmark.circle")
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(DS.negative)
                    }
                } footer: {
                    Text("Ändringar sparas direkt i appens lokala lagring.")
                }

                Section {
                    Button(role: .destructive) {
                        followUps.delete(record)
                        dismiss()
                    } label: {
                        Label("Radera uppföljning", systemImage: "trash")
                    }
                }
            }
            .navigationTitle("Redigera")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Avbryt") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Spara") { save() }
                        .font(.system(.subheadline, design: .rounded).weight(.bold))
                }
            }
        }
    }

    private func save() {
        guard let normalized = Personnummer.validate(pnrText) else {
            error = "Ogiltigt personnummer."
            return
        }
        record.personnummer = normalized.digits12
        guard !record.name.trimmingCharacters(in: .whitespaces).isEmpty else {
            error = "Namn måste fyllas i."
            return
        }
        guard !record.reason.trimmingCharacters(in: .whitespaces).isEmpty else {
            error = "Anledning måste fyllas i."
            return
        }
        followUps.update(record)
        Haptics.tap()
        dismiss()
    }
}

// MARK: Reschedule sheet

struct FollowUpRescheduleSheet: View {
    @EnvironmentObject private var followUps: FollowUpStore
    @Environment(\.dismiss) private var dismiss

    let record: FollowUpRecord
    @State private var date = Date()

    var body: some View {
        NavigationStack {
            VStack(spacing: DS.Space.l) {
                DatePicker("Nytt datum", selection: $date, displayedComponents: [.date])
                    .datePickerStyle(.graphical)
                    .environment(\.locale, Locale(identifier: "sv_SE"))
                    .frame(maxWidth: .infinity)

                PrimaryButton(title: "Boka om", symbol: "calendar.badge.clock") {
                    followUps.reschedule(record, to: date)
                    Haptics.tap()
                    dismiss()
                }
                .padding(.horizontal, DS.Space.l)

                Spacer()
            }
            .padding(.top, DS.Space.l)
            .navigationTitle("Boka om")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Avbryt") { dismiss() }
                }
            }
            .onAppear { date = record.dueDate }
        }
        .presentationDetents([.medium, .large])
    }
}
