import Foundation
import UserNotifications
import UIKit
import TeliaCore

// MARK: - Follow-up local reminders
//
// Opt-in. The notification TEXT is deliberately generic ("Du har N
// kunduppföljningar idag") — never names, never personnummer — because
// lock-screen previews must not leak customer data. Identifiers are opaque
// (no customer data in the identifier either).

@MainActor
final class FollowUpNotificationService: ObservableObject {

    static let shared = FollowUpNotificationService()

    /// Drives the UI: unknown / denied / granted.
    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined

    private let center = UNUserNotificationCenter.current()

    func refreshAuthorizationStatus() {
        center.getNotificationSettings { [weak self] settings in
            Task { @MainActor in
                self?.authorizationStatus = settings.authorizationStatus
            }
        }
    }

    /// Requests permission (system prompt). Returns true when granted.
    @discardableResult
    func requestPermission() async -> Bool {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            await MainActor.run { self.refreshAuthorizationStatus() }
            return granted
        } catch {
            return false
        }
    }

    /// (Re)schedules one reminder per upcoming due date at 09:00 local time.
    /// Content = total count for that day, so nothing identifies a customer.
    func reschedule(records: [FollowUpRecord], enabled: Bool) {
        // Clear everything first — rescheduling is idempotent, so repeated
        // calls never create duplicates.
        center.removeAllPendingNotificationRequests()
        guard enabled else { return }

        let cal = CalendarEngine.workCalendar()
        let groups = FollowUpEngine.group(records, calendar: cal)
        let open = groups.open

        // Group open follow-ups by due day (counts only).
        var byDay: [Date: Int] = [:]
        for record in open {
            let day = cal.startOfDay(for: record.dueDate)
            byDay[day, default: 0] += 1
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "sv_SE")
        formatter.calendar = cal

        for (day, count) in byDay {
            guard day >= cal.startOfDay(for: Date()) else { continue } // overdue handled in-app

            var comps = cal.dateComponents([.year, .month, .day], from: day)
            comps.hour = 9
            comps.minute = 0

            let content = UNMutableNotificationContent()
            content.title = FollowUpEngine.reminderTitle
            content.body = FollowUpEngine.reminderBody(count: count)
            content.sound = .default

            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            // Opaque identifier: date + count only.
            let id = "followup-\(formatter.string(from: day))-\(count)"
            let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
            center.add(request)
        }
    }

}
