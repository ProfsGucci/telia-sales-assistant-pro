import Foundation

// MARK: - Check Later Customer (follow-ups)
//
// PRIVACY: personnummer is highly sensitive personal data under Swedish/EU
// rules. Records live ONLY on the device (app documents directory), are
// never included in AI prompts, analytics, logs or exports, and are masked
// in list views. Deletion is a first-class action. See
// docs/DEBUG-REPORT-1.4.md for the full privacy analysis.

/// A "check later" customer follow-up. Exactly four user-entered fields —
/// personnummer, name, reason and due date — nothing else is required.
public struct FollowUpRecord: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    /// Normalized 12-digit personnummer (see `Personnummer`). Local only.
    public var personnummer: String
    public var name: String
    public var reason: String
    public var dueDate: Date
    public var createdAt: Date
    /// Set when the follow-up is done. Kept for history until deleted.
    public var completedAt: Date?

    public init(id: UUID = UUID(),
                personnummer: String,
                name: String,
                reason: String,
                dueDate: Date,
                createdAt: Date = Date(),
                completedAt: Date? = nil) {
        self.id = id
        self.personnummer = personnummer
        self.name = name
        self.reason = reason
        self.dueDate = dueDate
        self.createdAt = createdAt
        self.completedAt = completedAt
    }

    public var isCompleted: Bool { completedAt != nil }
}

public enum FollowUpStatus: String, Codable, CaseIterable, Sendable {
    case overdue, dueToday, upcoming, completed

    public var displayName: String {
        switch self {
        case .overdue: return "Försenad"
        case .dueToday: return "Idag"
        case .upcoming: return "Kommande"
        case .completed: return "Klar"
        }
    }
}

public enum FollowUpEngine {

    /// Status of one record on a given day (day-granular, calendar-aware).
    public static func status(of record: FollowUpRecord,
                              on date: Date = Date(),
                              calendar: Calendar = .current) -> FollowUpStatus {
        if record.isCompleted { return .completed }
        let due = calendar.startOfDay(for: record.dueDate)
        let today = calendar.startOfDay(for: date)
        if due < today { return .overdue }
        if due == today { return .dueToday }
        return .upcoming
    }

    /// Groups records into the four dashboard buckets, each sorted by due
    /// date (soonest first) then name.
    public struct Groups: Sendable {
        public let overdue: [FollowUpRecord]
        public let dueToday: [FollowUpRecord]
        public let upcoming: [FollowUpRecord]
        public let completed: [FollowUpRecord]

        public var open: [FollowUpRecord] { overdue + dueToday + upcoming }
        public var isEmpty: Bool {
            overdue.isEmpty && dueToday.isEmpty && upcoming.isEmpty && completed.isEmpty
        }
    }

    public static func group(_ records: [FollowUpRecord],
                             on date: Date = Date(),
                             calendar: Calendar = .current) -> Groups {
        var buckets: [FollowUpStatus: [FollowUpRecord]] = [:]
        for r in records {
            buckets[status(of: r, on: date, calendar: calendar), default: []].append(r)
        }
        func sort(_ list: [FollowUpRecord]) -> [FollowUpRecord] {
            list.sorted {
                $0.dueDate != $1.dueDate
                    ? $0.dueDate < $1.dueDate
                    : $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        }
        return Groups(
            overdue: sort(buckets[.overdue] ?? []),
            dueToday: sort(buckets[.dueToday] ?? []),
            upcoming: sort(buckets[.upcoming] ?? []),
            completed: sort(buckets[.completed] ?? [])
        )
    }

    /// Text search across name and reason (never personnummer — it must not
    /// be needlessly surfaced; searches stay non-sensitive).
    public static func search(_ records: [FollowUpRecord], query: String) -> [FollowUpRecord] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return records }
        return records.filter {
            $0.name.localizedCaseInsensitiveContains(q)
                || $0.reason.localizedCaseInsensitiveContains(q)
        }
    }

    /// True when an OPEN follow-up for the same person already exists — the
    /// UI uses this to warn (not block) about possible duplicates, without
    /// exposing the number itself.
    public static func hasOpenDuplicate(personnummer: String,
                                        in records: [FollowUpRecord]) -> Bool {
        guard let normalized = Personnummer.normalize(personnummer) else { return false }
        return records.contains {
            !$0.isCompleted && $0.personnummer == normalized.digits12
        }
    }

    // MARK: Local reminders (privacy-safe)

    /// Notification title — deliberately generic.
    public static let reminderTitle = "Kunduppföljning"

    /// Notification body text for a due date. NEVER includes names or
    /// personnummer — lock-screen previews must not leak customer data.
    public static func reminderBody(count: Int) -> String {
        switch count {
        case 0: return "Du har inga kunduppföljningar idag."
        case 1: return "Du har en kunduppföljning idag."
        default: return "Du har \(count) kunduppföljningar idag."
        }
    }
}
