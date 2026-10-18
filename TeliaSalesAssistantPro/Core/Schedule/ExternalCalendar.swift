import Foundation

// MARK: - External calendar events (Apple / Google / Outlook)
//
// Data model + merge engine for imported calendar events. The app layer
// owns the actual network/EventKit code; everything here is the testable
// core: identity, de-duplication and provider metadata.
//
// Imported events are READ-ONLY in the app. The provider stays the source
// of truth; refreshes update or remove imported events rather than
// duplicating them. Sync is periodic/manual — never claimed as real-time.

public enum CalendarProvider: String, Codable, CaseIterable, Identifiable, Sendable {
    case apple, google, outlook

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .apple: return "Apple Kalender"
        case .google: return "Google Calendar"
        case .outlook: return "Outlook / Microsoft 365"
        }
    }

    /// SF Symbol name for provider badges.
    public var symbolName: String {
        switch self {
        case .apple: return "apple.logo"
        case .google: return "g.circle.fill"
        case .outlook: return "envelope.fill"
        }
    }

    /// Restrained brand-ish tint (hex) used for badges — not loud.
    public var tintHex: String {
        switch self {
        case .apple: return "8E8E93" // system gray
        case .google: return "4285F4" // Google blue
        case .outlook: return "0364B8" // Outlook blue
        }
    }
}

/// One event imported from an external provider. Identity at the source is
/// (provider, providerEventID, providerCalendarID) — refreshes upsert on
/// that key so edited events update in place and removed events disappear,
/// without ever duplicating.
public struct ExternalEventRecord: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var provider: CalendarProvider
    public var providerEventID: String
    public var providerCalendarID: String
    public var calendarName: String
    public var title: String
    public var start: Date
    public var end: Date
    public var location: String
    public var isAllDay: Bool
    public var lastSynced: Date

    public init(id: UUID = UUID(),
                provider: CalendarProvider,
                providerEventID: String,
                providerCalendarID: String,
                calendarName: String = "",
                title: String,
                start: Date,
                end: Date,
                location: String = "",
                isAllDay: Bool = false,
                lastSynced: Date = Date()) {
        self.id = id
        self.provider = provider
        self.providerEventID = providerEventID
        self.providerCalendarID = providerCalendarID
        self.calendarName = calendarName
        self.title = title
        self.start = start
        self.end = end
        self.location = location
        self.isAllDay = isAllDay
        self.lastSynced = lastSynced
    }

    public var sourceKey: String { "\(provider.rawValue):\(providerCalendarID):\(providerEventID)" }
}

public enum ExternalCalendarMerge {

    /// Merges one provider's incoming snapshot into the stored records.
    ///
    /// Rules:
    /// - Existing record with the same source key → updated in place
    ///   (keeps its UUID, so SwiftUI list identity is stable).
    /// - New events → appended.
    /// - Stored records of this provider that are NOT in the incoming
    ///   snapshot → deleted (the event was deleted or deselected at the
    ///   source).
    /// - Other providers' records are never touched.
    public static func merge(existing: [ExternalEventRecord],
                             incoming: [ExternalEventRecord],
                             provider: CalendarProvider,
                             now: Date = Date()) -> [ExternalEventRecord] {
        let incomingByKey = Dictionary(
            incoming.map { ($0.sourceKey, $0) },
            uniquingKeysWith: { a, _ in a }
        )

        var result: [ExternalEventRecord] = []
        var seenKeys = Set<String>()

        for record in existing {
            if record.provider != provider {
                // Another provider — pass through untouched.
                result.append(record)
                continue
            }
            if let updated = incomingByKey[record.sourceKey] {
                // Update in place, keeping the stable local UUID.
                var copy = updated
                copy.id = record.id
                copy.lastSynced = now
                result.append(copy)
                seenKeys.insert(record.sourceKey)
            }
            // else: not in the snapshot anymore → dropped (deleted at source).
        }

        // Brand-new events, in the incoming order.
        for event in incoming where !seenKeys.contains(event.sourceKey) {
            var copy = event
            copy.lastSynced = now
            result.append(copy)
        }

        return result
    }

    /// Events overlapping a day, for the unified calendar day view.
    public static func events(on day: Date,
                              from records: [ExternalEventRecord],
                              calendar: Calendar) -> [ExternalEventRecord] {
        let interval = calendar.dateInterval(of: .day, for: day) ?? DateInterval(start: day, duration: 86400)
        return records
            .filter { $0.end > interval.start && $0.start < interval.end }
            .sorted { $0.start < $1.start }
    }

    /// Upcoming events strictly after a date, soonest first.
    public static func upcoming(from records: [ExternalEventRecord],
                                after date: Date,
                                limit: Int = 20) -> [ExternalEventRecord] {
        records
            .filter { $0.end >= date }
            .sorted { $0.start < $1.start }
            .prefix(limit)
            .map { $0 }
    }

    /// Overlap detection for the conflict note: two imported events that
    /// intersect in time.
    public static func hasConflict(_ a: ExternalEventRecord, _ b: ExternalEventRecord) -> Bool {
        a.id != b.id && a.start < b.end && b.start < a.end
    }
}
