import Foundation
import EventKit
import TeliaCore

// MARK: - Apple Calendar (EventKit) read access
//
// Reads events from the user's Apple/iCloud calendars for the unified
// in-app calendar. Access is requested only when the user enables Apple
// Calendar in the app; denied access is handled gracefully (status shown,
// link to system Settings, app calendar keeps working without it).
//
// iOS 17 requires full-access for reading too; iOS 16 uses the legacy API.

@MainActor
final class AppleCalendarService: ObservableObject {

    static let shared = AppleCalendarService()

    private let store = EKEventStore()

    // MARK: Authorization

    var authorizationStatus: EKAuthorizationStatus { EKEventStore.authorizationStatus(for: .event) }

    var isAuthorized: Bool {
        let s = authorizationStatus
        if #available(iOS 17.0, *) {
            return s == .fullAccess || s == .authorized
        }
        return s == .authorized
    }

    var isDenied: Bool {
        let s = authorizationStatus
        return s == .denied || s == .restricted
    }

    /// Requests access (system prompt). Returns true when granted.
    func requestAccess() async -> Bool {
        let granted: Bool = await withCheckedContinuation { continuation in
            if #available(iOS 17.0, *) {
                store.requestFullAccessToEvents { granted, _ in
                    continuation.resume(returning: granted)
                }
            } else {
                store.requestAccess(to: .event) { granted, _ in
                    continuation.resume(returning: granted)
                }
            }
        }
        return granted
    }

    // MARK: Calendars

    /// Writable, subscribed and iCloud calendars that can contain events.
    func availableCalendars() -> [EKCalendar] {
        guard isAuthorized else { return [] }
        return store.calendars(for: .event)
            .filter { !$0.isImmutable }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    // MARK: Events

    /// Fetches Apple Calendar events in a window and maps them to the app's
    /// external-event model. Recurring events arrive already expanded by
    /// EventKit; time zones are handled by EventKit's Date conversion.
    func fetchEvents(from: Date, to: Date, calendarIDs: Set<String>) -> [ExternalEventRecord] {
        guard isAuthorized, !calendarIDs.isEmpty else { return [] }
        let selected = store.calendars(for: .event).filter { calendarIDs.contains($0.calendarIdentifier) }
        guard !selected.isEmpty else { return [] }
        let predicate = store.predicateForEvents(withStart: from, end: to, calendars: selected)
        let events = store.events(matching: predicate)
        return events.map { ek in
            ExternalEventRecord(
                provider: .apple,
                providerEventID: ek.eventIdentifier ?? ek.calendarItemIdentifier,
                providerCalendarID: ek.calendar?.calendarIdentifier ?? "",
                calendarName: ek.calendar?.title ?? "",
                title: ek.title ?? "(utan titel)",
                start: ek.startDate,
                end: ek.endDate,
                location: ek.location ?? "",
                isAllDay: ek.isAllDay,
                lastSynced: Date()
            )
        }
    }

    /// Re-fetches one EKEvent by identifier (for "open in Apple Calendar").
    func ekEvent(identifier: String) -> EKEvent? {
        store.event(withIdentifier: identifier)
    }
}
