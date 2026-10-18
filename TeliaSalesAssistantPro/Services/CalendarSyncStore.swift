import Foundation
import EventKit
import SwiftUI
import TeliaCore

// MARK: - Calendar sync orchestration
//
// One place that owns imported events and per-provider sync state.
//
// Synchronization model (honest description):
// - Periodic + manual refresh (on app becoming active, throttled to 15 min,
//   and via the refresh button). NOT real-time push.
// - Imported events are READ-ONLY in the app; the provider is the source of
//   truth. Refreshes upsert by provider identity — no duplicates.
// - Events deleted or deselected at the source disappear on next refresh.
//
// Sync window: one month back to three months ahead — enough for planning
// without pulling a user's entire history.

@MainActor
final class CalendarSyncStore: ObservableObject {

    @Published private(set) var externalEvents: [ExternalEventRecord] {
        didSet { DataStore.save(externalEvents) }
    }

    /// Providers currently syncing (drives refresh spinners).
    @Published private(set) var syncing: Set<CalendarProvider> = []
    /// Last error per provider, shown in the provider sheet.
    @Published private(set) var lastErrors: [CalendarProvider: String] = [:]
    /// Calendar lists per provider (id + display name), loaded on connect
    /// and refresh. No event data — just calendars the user can pick.
    @Published private(set) var availableCalendars: [CalendarProvider: [ProviderCalendar]] = [:]

    struct ProviderCalendar: Identifiable, Hashable {
        let id: String
        let name: String
        var provider: CalendarProvider?
        var tintHex: String?
    }

    private let apple = AppleCalendarService.shared

    init() {
        self.externalEvents = DataStore.load([ExternalEventRecord].self) ?? []
    }

    // MARK: Settings conveniences

    /// The settings store is injected once at app startup. SettingsStore
    /// does not reference back, so a strong reference is cycle-free.
    private var settings: SettingsStore!

    func inject(settings: SettingsStore) {
        self.settings = settings
    }

    var googleClient: OAuthClient { .google(clientID: settings.data.googleClientID) }
    var microsoftClient: OAuthClient { .microsoft(clientID: settings.data.microsoftClientID) }

    func isConfigured(_ provider: CalendarProvider) -> Bool {
        switch provider {
        case .apple: return true
        case .google: return !settings.data.googleClientID.trimmingCharacters(in: .whitespaces).isEmpty
        case .outlook: return !settings.data.microsoftClientID.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    func isEnabled(_ provider: CalendarProvider) -> Bool {
        switch provider {
        case .apple: return settings.data.appleCalendarsEnabled
        case .google: return settings.data.googleCalendarsEnabled
        case .outlook: return settings.data.outlookCalendarsEnabled
        }
    }

    func isConnected(_ provider: CalendarProvider) -> Bool {
        switch provider {
        case .apple: return apple.isAuthorized
        case .google: return googleClient.storedToken() != nil
        case .outlook: return microsoftClient.storedToken() != nil
        }
    }

    func lastSynced(_ provider: CalendarProvider) -> Date? {
        settings.data.calendarLastSync[provider.rawValue]
    }

    // MARK: Sync window

    var syncWindow: (from: Date, to: Date) {
        let cal = CalendarEngine.workCalendar()
        let now = Date()
        let from = cal.date(byAdding: .month, value: -1, to: now) ?? now
        let to = cal.date(byAdding: .month, value: 3, to: now) ?? now
        return (from, to)
    }

    // MARK: Public sync entry points

    /// Refreshes every enabled provider. Throttled unless `force`.
    func syncAllIfNeeded(force: Bool = false) {
        guard force || settings.data.calendarSyncOnOpen else { return }
        if !force, let last = settings.data.calendarLastSync.values.max(),
           Date().timeIntervalSince(last) < 15 * 60 {
            return
        }
        Task { await syncAll() }
    }

    func syncAll() async {
        async let a: Void = isEnabled(.apple) ? syncApple() : ()
        async let g: Void = isEnabled(.google) ? syncGoogle() : ()
        async let o: Void = isEnabled(.outlook) ? syncOutlook() : ()
        _ = await (a, g, o)
    }

    // MARK: Apple

    func connectApple() async {
        let granted = await apple.requestAccess()
        if granted {
            settings.data.appleCalendarsEnabled = true
            lastErrors[.apple] = nil
            await refreshCalendarLists(.apple)
            await syncApple()
        } else {
            settings.data.appleCalendarsEnabled = false
            lastErrors[.apple] = "Åtkomst till Apple Kalender nekades. Aktivera i Inställningar → Sekretess → Kalendrar."
        }
    }

    func syncApple() async {
        guard settings.data.appleCalendarsEnabled else { return }
        if apple.isDenied {
            lastErrors[.apple] = "Åtkomst till Apple Kalender har nekats i systeminställningarna."
            return
        }
        syncing.insert(.apple)
        defer { syncing.remove(.apple) }

        // EventKit's predicate fetch is fast for a ±few-months window and
        // runs on the main actor here (fetchEvents is MainActor-isolated —
        // no detached hop, which the concurrency checker would reject).
        let ids = settings.data.selectedAppleCalendarIDs
        let window = syncWindow
        let fetched = apple.fetchEvents(from: window.from, to: window.to, calendarIDs: ids)
        externalEvents = ExternalCalendarMerge.merge(existing: externalEvents, incoming: fetched, provider: .apple)
        noteSync(provider: .apple)
    }

    // MARK: Google

    func connectGoogle() async {
        do {
            guard isConfigured(.google) else { throw OAuthError.notConfigured }
            settings.data.googleCalendarsEnabled = true
            _ = try await googleClient.authorize()
            lastErrors[.google] = nil
            await refreshCalendarLists(.google)
            await syncGoogle()
        } catch {
            settings.data.googleCalendarsEnabled = false
            lastErrors[.google] = (error as? LocalizedError)?.errorDescription ?? "Kunde inte ansluta Google."
        }
    }

    func syncGoogle() async {
        // Capture selection BEFORE the (nonisolated) fetch closure so it
        // never touches MainActor-isolated state off the main actor.
        let selectedIDs = settings.data.selectedGoogleCalendarIDs
        await syncRemote(provider: .google, client: googleClient) { token, from, to in
            let lists = try await GoogleCalendarAPI.calendars(token: token)
            let selected = lists.filter { selectedIDs.contains($0.id) }
            var all: [ExternalEventRecord] = []
            for calendar in selected {
                let name = calendar.summaryOverride ?? calendar.summary ?? calendar.id
                let events = try await GoogleCalendarAPI.events(token: token, calendarID: calendar.id, from: from, to: to)
                all.append(contentsOf: events.map { r in
                    var copy = r
                    copy.calendarName = name
                    return copy
                })
            }
            return all
        }
    }

    // MARK: Outlook

    func connectOutlook() async {
        do {
            guard isConfigured(.outlook) else { throw OAuthError.notConfigured }
            settings.data.outlookCalendarsEnabled = true
            _ = try await microsoftClient.authorize()
            lastErrors[.outlook] = nil
            await refreshCalendarLists(.outlook)
            await syncOutlook()
        } catch {
            settings.data.outlookCalendarsEnabled = false
            lastErrors[.outlook] = (error as? LocalizedError)?.errorDescription ?? "Kunde inte ansluta Outlook."
        }
    }

    func syncOutlook() async {
        let selectedIDs = settings.data.selectedOutlookCalendarIDs
        await syncRemote(provider: .outlook, client: microsoftClient) { token, from, to in
            let lists = try await MicrosoftCalendarAPI.calendars(token: token)
            let selected = lists.filter { selectedIDs.contains($0.id) }
            var all: [ExternalEventRecord] = []
            for calendar in selected {
                let events = try await MicrosoftCalendarAPI.events(token: token, calendarID: calendar.id, from: from, to: to)
                all.append(contentsOf: events.map { r in
                    var copy = r
                    copy.calendarName = calendar.name
                    return copy
                })
            }
            return all
        }
    }

    /// Shared remote-sync path: valid token (refresh when needed) → fetch →
    /// merge → timestamp. Expired refresh tokens surface a reconnect message.
    private func syncRemote(provider: CalendarProvider,
                            client: OAuthClient,
                            fetch: @escaping (String, Date, Date) async throws -> [ExternalEventRecord]) async {
        syncing.insert(provider)
        defer { syncing.remove(provider) }
        do {
            let token = try await client.validToken()
            let window = syncWindow
            let fetched = try await fetch(token.accessToken, window.from, window.to)
            externalEvents = ExternalCalendarMerge.merge(existing: externalEvents, incoming: fetched, provider: provider)
            lastErrors[provider] = nil
            noteSync(provider: provider)
        } catch {
            lastErrors[provider] = (error as? LocalizedError)?.errorDescription ?? "Synkroniseringen misslyckades."
        }
    }

    // MARK: Calendar lists (for the picker)

    func refreshCalendarLists(_ provider: CalendarProvider) async {
        switch provider {
        case .apple:
            availableCalendars[.apple] = apple.availableCalendars().map {
                ProviderCalendar(id: $0.calendarIdentifier, name: $0.title)
            }
            // Default: select the user's default calendar on first connect.
            if settings.data.selectedAppleCalendarIDs.isEmpty,
               let def = apple.availableCalendars().first(where: { $0.allowsContentModifications }) {
                settings.data.selectedAppleCalendarIDs = [def.calendarIdentifier]
            }
        case .google:
            do {
                let token = try await googleClient.validToken()
                let lists = try await GoogleCalendarAPI.calendars(token: token.accessToken)
                availableCalendars[.google] = lists.map {
                    ProviderCalendar(id: $0.id, name: $0.summaryOverride ?? $0.summary ?? $0.id)
                }
                if settings.data.selectedGoogleCalendarIDs.isEmpty, let primary = lists.first(where: { $0.id.contains("@gmail.com") || $0.id == "primary" }) {
                    settings.data.selectedGoogleCalendarIDs = [primary.id]
                }
            } catch {
                lastErrors[.google] = (error as? LocalizedError)?.errorDescription ?? "Kunde inte hämta kalendrar."
            }
        case .outlook:
            do {
                let token = try await microsoftClient.validToken()
                let lists = try await MicrosoftCalendarAPI.calendars(token: token.accessToken)
                availableCalendars[.outlook] = lists.map {
                    ProviderCalendar(id: $0.id, name: $0.name)
                }
                if settings.data.selectedOutlookCalendarIDs.isEmpty, let first = lists.first {
                    settings.data.selectedOutlookCalendarIDs = [first.id]
                }
            } catch {
                lastErrors[.outlook] = (error as? LocalizedError)?.errorDescription ?? "Kunde inte hämta kalendrar."
            }
        }
    }

    // MARK: Disconnect

    func disconnect(_ provider: CalendarProvider) {
        switch provider {
        case .apple:
            settings.data.appleCalendarsEnabled = false
            settings.data.selectedAppleCalendarIDs = []
        case .google:
            googleClient.clearToken()
            settings.data.googleCalendarsEnabled = false
            settings.data.selectedGoogleCalendarIDs = []
        case .outlook:
            microsoftClient.clearToken()
            settings.data.outlookCalendarsEnabled = false
            settings.data.selectedOutlookCalendarIDs = []
        }
        // Imported events for that provider disappear immediately.
        externalEvents = externalEvents.filter { $0.provider != provider }
        availableCalendars[provider] = nil
        settings.data.calendarLastSync[provider.rawValue] = nil
        lastErrors[provider] = nil
    }

    // MARK: Helpers

    private func noteSync(provider: CalendarProvider) {
        settings.data.calendarLastSync[provider.rawValue] = Date()
    }

    /// Events (imported + app shifts) on one day, merged for the unified view.
    func externalEvents(on day: Date, calendar: Calendar) -> [ExternalEventRecord] {
        ExternalCalendarMerge.events(on: day, from: externalEvents, calendar: calendar)
    }

    func externalUpcoming(after date: Date, limit: Int = 20) -> [ExternalEventRecord] {
        ExternalCalendarMerge.upcoming(from: externalEvents, after: date, limit: limit)
    }
}
