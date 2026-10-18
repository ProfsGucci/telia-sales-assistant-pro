import SwiftUI
import EventKit
import TeliaCore

// MARK: - Anslutna kalendrar (provider management)
//
// Honest state model:
// - Apple Kalender: fully functional via EventKit (system permission).
// - Google/Outlook: REAL OAuth + REST clients — but they require the app
//   owner's own client ID (Settings fields below). Until configured they
//   are shown as "Kräver konfiguration" and cannot connect. No fake logins.

struct CalendarProvidersView: View {
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var calendarSync: CalendarSyncStore

    var body: some View {
        List {
            Section {
                Toggle("Synka när appen öppnas", isOn: Binding(
                    get: { settings.data.calendarSyncOnOpen },
                    set: { settings.data.calendarSyncOnOpen = $0 }
                ))
            } footer: {
                Text("Importerade kalendrar uppdateras med jämna mellanrum (tidigast var 15:e minut) och manuellt via uppdateringsknappen — det är ingen realtidssynkronisering.Importerade händelser är skrivskyddade; originalet finns kvar hos leverantören.")
            }

            ForEach(CalendarProvider.allCases) { provider in
                ProviderSection(provider: provider)
            }

            Section {
                Text("Kalenderinnehåll lämnar aldrig enheten i onödan: appen hämtar händelser direkt från respektive leverantör till din telefon. Token lagras i enhetens Keychain. Se docs/CALENDAR-SETUP.md för exakt konfiguration av Google och Microsoft.")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Kalendrar")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await calendarSync.syncAll(force: true) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .accessibilityLabel("Uppdatera alla kalendrar")
            }
        }
    }
}

// MARK: One provider

private struct ProviderSection: View {
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var calendarSync: CalendarSyncStore

    let provider: CalendarProvider

    private var connected: Bool { calendarSync.isConnected(provider) }
    private var enabled: Bool { calendarSync.isEnabled(provider) }
    private var configured: Bool { calendarSync.isConfigured(provider) }
    private var syncing: Bool { calendarSync.syncing.contains(provider) }

    var body: some View {
        Section {
            // Status row
            HStack(spacing: DS.Space.m) {
                Image(systemName: provider.symbolName)
                    .font(.system(.body, design: .rounded).weight(.semibold))
                    .foregroundStyle(Color(hex: provider.tintHex) ?? .secondary)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill((Color(hex: provider.tintHex) ?? .secondary).opacity(0.12)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(provider.displayName)
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    statusText
                }
                Spacer()
                if syncing {
                    ProgressView()
                }
            }

            // Client ID configuration (Google/Microsoft only)
            if provider == .google || provider == .outlook {
                clientIDField
            }

            // Connect / disconnect
            if provider == .apple {
                if enabled {
                    Button(role: .destructive) {
                        Task { await calendarSync.disconnect(provider) }
                    } label: {
                        Label("Koppla från Apple Kalender", systemImage: "minus.circle")
                    }
                } else {
                    Button {
                        Task { await calendarSync.connectApple() }
                    } label: {
                        Label("Anslut Apple Kalender", systemImage: "plus.circle")
                    }
                }
            } else if configured {
                if enabled {
                    Button(role: .destructive) {
                        calendarSync.disconnect(provider)
                    } label: {
                        Label("Koppla från", systemImage: "minus.circle")
                    }
                } else {
                    Button {
                        Task {
                            if provider == .google {
                                await calendarSync.connectGoogle()
                            } else {
                                await calendarSync.connectOutlook()
                            }
                        }
                    } label: {
                        Label("Logga in och anslut", systemImage: "person.badge.key")
                    }
                }
            }

            // Calendar selection
            if enabled, connected {
                calendarPicker
            }

            // Last synced + errors
            if let last = calendarSync.lastSynced(provider) {
                Text("Senast synkat: \(last.formatted(date: .abbreviated, time: .shortened))")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            if let error = calendarSync.lastErrors[provider] {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(DS.negative)
            }
        } footer: {
            footerText
        }
    }

    @ViewBuilder
    private var statusText: some View {
        if provider == .apple {
            Text(enabled ? "Ansluten (systembehörighet)" : "Ej ansluten")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(.secondary)
        } else if !configured {
            Label("Kräver konfiguration — fyll i ditt client ID", systemImage: "gear.badge.questionmark")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(DS.warning)
        } else {
            Text(enabled ? "Ansluten" : "Ej ansluten")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(.secondary)
        }
    }

    private var clientIDField: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(provider == .google ? "Google OAuth client ID" : "Microsoft (Azure) client ID")
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundStyle(.secondary)
            TextField("Ditt egna client ID från leverantören", text: clientIDBinding)
                .keyboardType(.asciiCapable)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.system(.caption, design: .rounded).monospaced())
            Text("Registrera appen hos Google/Microsoft enligt docs/CALENDAR-SETUP.md. ID:t sparas i appens inställningar — aldrig inbyggt i appen.")
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }

    private var clientIDBinding: Binding<String> {
        switch provider {
        case .google:
            return Binding(
                get: { settings.data.googleClientID },
                set: { settings.data.googleClientID = $0 }
            )
        case .outlook:
            return Binding(
                get: { settings.data.microsoftClientID },
                set: { settings.data.microsoftClientID = $0 }
            )
        case .apple:
            return Binding(get: { "" }, set: { _ in })
        }
    }

    @ViewBuilder
    private var calendarPicker: some View {
        let calendars = calendarSync.availableCalendars[provider] ?? []
        if !calendars.isEmpty {
            NavigationLink {
                CalendarPickerList(provider: provider)
            } label: {
                Label("Välj kalendrar (\(selectedCount(provider)) valda)", systemImage: "checklist")
            }
            Button {
                Task { await calendarSync.refreshCalendarLists(provider) }
            } label: {
                Label("Uppdatera kalenderlista", systemImage: "arrow.triangle.2.circlepath")
            }
        } else {
            Button {
                Task { await calendarSync.refreshCalendarLists(provider) }
            } label: {
                Label("Hämta kalendrar", systemImage: "arrow.triangle.2.circlepath")
            }
        }
    }

    private func selectedCount(_ provider: CalendarProvider) -> Int {
        switch provider {
        case .apple: return settings.data.selectedAppleCalendarIDs.count
        case .google: return settings.data.selectedGoogleCalendarIDs.count
        case .outlook: return settings.data.selectedOutlookCalendarIDs.count
        }
    }

    private var footerText: Text {
        switch provider {
        case .apple:
            return Text("Läser händelser från din Apple/iCloud-kalender via systemets behörighet. Du väljer vilka kalendrar som syns i appen.")
        case .google:
            return Text("Riktig Google-inloggning (OAuth med PKCE) som hämtar händelser via Google Calendar API, skrivskyddat. Kräver att appägaren registrerat en OAuth-klient — se docs/CALENDAR-SETUP.md.")
        case .outlook:
            return Text("Riktig Microsoft-inloggning (OAuth med PKCE) som hämtar händelser via Microsoft Graph, skrivskyddat. Kräver att appägaren registrerat en app i Azure — se docs/CALENDAR-SETUP.md.")
        }
    }
}

// MARK: Calendar multi-select

struct CalendarPickerList: View {
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var calendarSync: CalendarSyncStore

    let provider: CalendarProvider

    var body: some View {
        List {
            let calendars = calendarSync.availableCalendars[provider] ?? []
            if calendars.isEmpty {
                Text("Inga kalendrar hittades.")
                    .foregroundStyle(.secondary)
            }
            ForEach(calendars) { calendar in
                Button {
                    toggle(calendar.id)
                } label: {
                    HStack {
                        Text(calendar.name)
                            .foregroundStyle(.primary)
                        Spacer()
                        if isSelected(calendar.id) {
                            Image(systemName: "checkmark")
                                .foregroundStyle(DS.Purple.base)
                        }
                    }
                }
            }
        }
        .navigationTitle("Välj kalendrar")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func isSelected(_ id: String) -> Bool {
        switch provider {
        case .apple: return settings.data.selectedAppleCalendarIDs.contains(id)
        case .google: return settings.data.selectedGoogleCalendarIDs.contains(id)
        case .outlook: return settings.data.selectedOutlookCalendarIDs.contains(id)
        }
    }

    private func toggle(_ id: String) {
        switch provider {
        case .apple:
            if settings.data.selectedAppleCalendarIDs.contains(id) {
                settings.data.selectedAppleCalendarIDs.remove(id)
            } else {
                settings.data.selectedAppleCalendarIDs.insert(id)
            }
        case .google:
            if settings.data.selectedGoogleCalendarIDs.contains(id) {
                settings.data.selectedGoogleCalendarIDs.remove(id)
            } else {
                settings.data.selectedGoogleCalendarIDs.insert(id)
            }
        case .outlook:
            if settings.data.selectedOutlookCalendarIDs.contains(id) {
                settings.data.selectedOutlookCalendarIDs.remove(id)
            } else {
                settings.data.selectedOutlookCalendarIDs.insert(id)
            }
        }
    }
}
