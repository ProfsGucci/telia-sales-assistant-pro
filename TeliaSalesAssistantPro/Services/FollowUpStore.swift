import Foundation
import SwiftUI
import TeliaCore

// MARK: - Follow-up store (Check Later Customer)
//
// Persists follow-up records on-device only (app documents directory).
// No sync, no export, no AI access — see FollowUpModels' privacy note.

@MainActor
final class FollowUpStore: ObservableObject {
    @Published var records: [FollowUpRecord] {
        didSet {
            DataStore.save(records)
            // Keep local reminders in sync with the data (idempotent full
            // reschedule — never duplicates). No-op when reminders are off.
            FollowUpNotificationService.shared.reschedule(
                records: records,
                enabled: remindersEnabled
            )
        }
    }

    /// Injected at app startup; nil-safe so the store works in previews.
    private var settingsStore: SettingsStore?
    private var remindersEnabled: Bool {
        settingsStore?.data.followUpRemindersEnabled ?? false
    }

    func inject(settings: SettingsStore) {
        self.settingsStore = settings
    }

    init() {
        self.records = DataStore.load([FollowUpRecord].self) ?? []
    }

    // MARK: CRUD

    /// Validation failure with a user-friendly Swedish message.
    struct ValidationError: Error {
        let message: String
    }

    /// Validates the personnummer and adds the record. Returns a friendly
    /// error when validation fails. Never mutates digits silently.
    func add(personnummer: String, name: String, reason: String, dueDate: Date) -> Result<FollowUpRecord, ValidationError> {
        guard let normalized = Personnummer.validate(personnummer) else {
            return .failure(ValidationError(message: "Ogiltigt personnummer. Kontrollera siffrorna (ÅÅÅÅMMDD-XXXX)."))
        }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            return .failure(ValidationError(message: "Namn måste fyllas i."))
        }
        let trimmedReason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedReason.isEmpty else {
            return .failure(ValidationError(message: "Anledning måste fyllas i."))
        }
        let record = FollowUpRecord(
            personnummer: normalized.digits12,
            name: trimmedName,
            reason: trimmedReason,
            dueDate: dueDate
        )
        records.append(record)
        return .success(record)
    }

    func update(_ record: FollowUpRecord) {
        guard let index = records.firstIndex(where: { $0.id == record.id }) else { return }
        records[index] = record
    }

    func delete(_ record: FollowUpRecord) {
        records.removeAll { $0.id == record.id }
    }

    func deleteAll() {
        records.removeAll()
    }

    // MARK: Status actions

    func markCompleted(_ record: FollowUpRecord) {
        var copy = record
        copy.completedAt = Date()
        update(copy)
    }

    func reopen(_ record: FollowUpRecord) {
        var copy = record
        copy.completedAt = nil
        update(copy)
    }

    func reschedule(_ record: FollowUpRecord, to date: Date) {
        var copy = record
        copy.dueDate = date
        copy.completedAt = nil // rescheduling an old follow-up reopens it
        update(copy)
    }

    /// Duplicate warning (same identity, still open) — surfaced before save.
    func hasOpenDuplicate(personnummer: String) -> Bool {
        FollowUpEngine.hasOpenDuplicate(personnummer: personnummer, in: records)
    }
}
