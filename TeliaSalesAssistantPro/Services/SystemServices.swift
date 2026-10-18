import Foundation
import EventKit
import UserNotifications
import TeliaCore
import TeliaCore

// MARK: - EventKit (optional, requested only on use)

@MainActor
final class EventKitService: ObservableObject {
    @Published var authorizationDenied = false
    private let store = EKEventStore()

    /// Adds one event to the user's Apple Calendar. Permission is requested only here.
    func addToAppleCalendar(_ event: ScheduleEvent) async -> Bool {
        let granted = await withCheckedContinuation { continuation in
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
        authorizationDenied = !granted
        guard granted else { return false }

        let ekEvent = EKEvent(eventStore: store)
        ekEvent.title = event.title
        ekEvent.notes = event.notes
        ekEvent.location = event.location
        ekEvent.startDate = event.start
        ekEvent.endDate = event.end
        ekEvent.calendar = store.defaultCalendarForNewEvents
        do {
            try store.save(ekEvent, span: .thisEvent)
            return true
        } catch {
            return false
        }
    }
}

// MARK: - Notifications (opt-in reminders)

final class NotificationService {
    static let shared = NotificationService()

    func requestPermission() async -> Bool {
        let center = UNUserNotificationCenter.current()
        return await withCheckedContinuation { continuation in
            center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                continuation.resume(returning: granted)
            }
        }
    }

    /// Schedule a local reminder 30 minutes before a shift.
    func scheduleShiftReminder(for event: ScheduleEvent) {
        guard event.kind == .shift else { return }
        let content = UNMutableNotificationContent()
        content.title = event.title
        content.body = "Ditt pass börjar om 30 minuter. Kolla förberedelserna i appen."
        content.sound = .default

        let fireDate = event.start.addingTimeInterval(-30 * 60)
        guard fireDate > Date() else { return }
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: "shift-\(event.id.uuidString)", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    func cancelShiftReminder(for event: ScheduleEvent) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["shift-\(event.id.uuidString)"])
    }

    /// Opt-in reminder that a saved campaign is nearing its *verified* end date.
    /// Fires three days before the end date, morning local time; only campaigns
    /// with a published end date are meaningful to remind about.
    func scheduleCampaignExpiryReminder(for campaign: CampaignRecord) {
        guard let end = campaign.endDate else { return }
        let content = UNMutableNotificationContent()
        content.title = "Kampanj slutar snart"
        content.body = "\(campaign.title) har verifierat slutdatum \(Format.dayMonth.string(from: end)). Kontrollera telia.se innan du citerar den."
        content.sound = .default

        guard let fireDate = Calendar.current.date(byAdding: .day, value: -3, to: end),
              fireDate > Date() else { return }
        var components = Calendar.current.dateComponents([.year, .month, .day], from: fireDate)
        components.hour = 9
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: "campaign-\(campaign.id)", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    func cancelCampaignReminders(ids: [String]) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids.map { "campaign-\($0)" })
    }

    func cancelAll() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }
}
