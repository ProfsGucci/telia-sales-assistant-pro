import Foundation
import CryptoKit
import AuthenticationServices
import UIKit
import TeliaCore

// MARK: - OAuth (Google & Microsoft) with PKCE
//
// REAL OAuth flows — no fake login screens. Both providers require the app
// owner to register an application and supply its client ID:
//
//   Google:  Google Cloud Console → APIs & Services → Credentials →
//            OAuth client ID (iOS) with bundle id `se.sthlm.teliacoachpro`
//            and redirect scheme `se.sthlm.teliacoachpro.oauth`. Enable the
//            Google Calendar API. Paste the client ID in the app
//            (Inställningar → Kalendrar).
//   Microsoft: Azure Portal → Microsoft Entra ID → App registrations →
//            New registration (public client/native + redirect URI
//            `se.sthlm.teliacoachpro.oauth:/oauth`). Delegated permission
//            `Calendars.Read` (+ `offline_access`).
//
// Until a client ID is configured, the UI labels the provider
// "Kräver konfiguration" and refuses to connect — it is never shown as
// operational. Client IDs are user settings, NOT compiled into the binary,
// and no client secrets are used or stored (public PKCE clients don't need
// one). See docs/CALENDAR-SETUP.md.

// MARK: Token model

struct OAuthToken: Codable {
    var accessToken: String
    var refreshToken: String?
    var expiresAt: Date

    var isExpired: Bool { Date() >= expiresAt }
}

enum OAuthError: LocalizedError {
    case notConfigured
    case cancelled
    case invalidResponse
    case authFailed(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Leverantören är inte konfigurerad (client ID saknas)."
        case .cancelled:
            return "Inloggningen avbröts."
        case .invalidResponse:
            return "Oväntat svar från leverantören."
        case .authFailed(let m):
            return "Inloggningen misslyckades: \(m)"
        }
    }
}

// MARK: PKCE

enum PKCE {
    /// base64url (RFC 7636 §Appendix B) — no padding, URL-safe chars.
    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func make() -> (verifier: String, challenge: String) {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let verifier = base64URL(Data(bytes))
        let challenge = base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
        return (verifier, challenge)
    }
}

// MARK: Web auth presentation anchor

final class WebAuthAnchor: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first ?? ASPresentationAnchor()
    }
}

// MARK: OAuth client

/// One OAuth client for a provider (public PKCE client, no secret).
struct OAuthClient {
    let provider: CalendarProvider
    let clientID: String
    let authorizeEndpoint: String
    let tokenEndpoint: String
    let scopes: String
    /// Extra authorize query parameters (e.g. Google's access_type).
    var extraAuthParams: [String: String] = [:]

    static let redirectURI = "se.sthlm.teliacoachpro.oauth:/oauth"
    static let callbackScheme = "se.sthlm.teliacoachpro.oauth"

    static func google(clientID: String) -> OAuthClient {
        OAuthClient(
            provider: .google,
            clientID: clientID,
            authorizeEndpoint: "https://accounts.google.com/o/oauth2/v2/auth",
            tokenEndpoint: "https://oauth2.googleapis.com/token",
            scopes: "https://www.googleapis.com/auth/calendar.readonly",
            extraAuthParams: ["access_type": "offline", "prompt": "consent"]
        )
    }

    static func microsoft(clientID: String) -> OAuthClient {
        OAuthClient(
            provider: .outlook,
            clientID: clientID,
            authorizeEndpoint: "https://login.microsoftonline.com/common/oauth2/v2.0/authorize",
            tokenEndpoint: "https://login.microsoftonline.com/common/oauth2/v2.0/token",
            scopes: "Calendars.Read offline_access"
        )
    }

    // MARK: Keychain persistence

    private var keychain: KeychainStore {
        KeychainStore(service: "se.sthlm.teliacoachpro.calendar", account: "oauth-\(provider.rawValue)")
    }

    func storedToken() -> OAuthToken? {
        guard let data = keychain.load() else { return nil }
        return try? JSONDecoder().decode(OAuthToken.self, from: data)
    }

    func storeToken(_ token: OAuthToken) {
        if let data = try? JSONEncoder().encode(token) {
            keychain.save(data)
        }
    }

    func clearToken() {
        keychain.delete()
    }

    // MARK: Flows

    /// Runs the full authorization-code flow with PKCE:
    /// system browser (ASWebAuthenticationSession) → code → token exchange.
    @MainActor
    func authorize() async throws -> OAuthToken {
        guard !clientID.isEmpty else { throw OAuthError.notConfigured }

        let pkce = PKCE.make()
        var components = URLComponents(string: authorizeEndpoint)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: Self.redirectURI),
            URLQueryItem(name: "scope", value: scopes),
            URLQueryItem(name: "code_challenge", value: pkce.challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
        ] + extraAuthParams.map { URLQueryItem(name: $0.key, value: $0.value) }

        guard let authorizeURL = components.url else { throw OAuthError.invalidResponse }

        let returnedURL: URL
        do {
            returnedURL = try await ASWebAuthenticationSessionWrapper.run(
                url: authorizeURL,
                scheme: Self.callbackScheme
            )
        } catch {
            throw OAuthError.cancelled
        }

        guard let callbackComponents = URLComponents(url: returnedURL, resolvingAgainstBaseURL: false),
              let code = callbackComponents.queryItems?.first(where: { $0.name == "code" })?.value,
              !code.isEmpty
        else { throw OAuthError.invalidResponse }

        let token = try await exchangeCode(code, verifier: pkce.verifier)
        storeToken(token)
        return token
    }

    /// Exchanges the authorization code for tokens (no client secret —
    /// public PKCE client).
    func exchangeCode(_ code: String, verifier: String) async throws -> OAuthToken {
        var request = URLRequest(url: URL(string: tokenEndpoint)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = [
            "grant_type": "authorization_code",
            "code": code,
            "client_id": clientID,
            "code_verifier": verifier,
            "redirect_uri": Self.redirectURI,
        ]
        request.httpBody = body.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")" }
            .joined(separator: "&")
            .data(using: .utf8)
        return try await performTokenRequest(request)
    }

    /// Uses the refresh token to get a fresh access token. Throws when the
    /// user must re-authorize (expired/revoked consent).
    func refresh(_ token: OAuthToken) async throws -> OAuthToken {
        guard let refresh = token.refreshToken else { throw OAuthError.authFailed("Inloggningen har upphört — koppla upp igen.") }
        var request = URLRequest(url: URL(string: tokenEndpoint)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = [
            "grant_type": "refresh_token",
            "refresh_token": refresh,
            "client_id": clientID,
        ]
        request.httpBody = body.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")" }
            .joined(separator: "&")
            .data(using: .utf8)
        let refreshed = try await performTokenRequest(request, keepRefresh: refresh)
        storeToken(refreshed)
        return refreshed
    }

    /// Returns a valid access token, refreshing when needed.
    func validToken() async throws -> OAuthToken {
        guard !clientID.isEmpty else { throw OAuthError.notConfigured }
        guard let token = storedToken() else { throw OAuthError.authFailed("Ingen inloggning — koppla upp kontot.") }
        if token.isExpired {
            return try await refresh(token)
        }
        return token
    }

    private func performTokenRequest(_ request: URLRequest, keepRefresh: String? = nil) async throws -> OAuthToken {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw OAuthError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            // Never log the body — it can echo token material.
            throw OAuthError.authFailed("HTTP \(http.statusCode)")
        }
        struct TokenResponse: Decodable {
            let access_token: String
            let refresh_token: String?
            let expires_in: Int
        }
        guard let json = try? JSONDecoder().decode(TokenResponse.self, from: data) else {
            throw OAuthError.invalidResponse
        }
        return OAuthToken(
            accessToken: json.access_token,
            refreshToken: json.refresh_token ?? keepRefresh,
            expiresAt: Date().addingTimeInterval(TimeInterval(max(0, json.expires_in - 60)))
        )
    }
}

/// Runs ASWebAuthenticationSession across an await. The session (and its
/// presentation anchor) MUST stay alive until the callback fires, so they
/// are retained statically and released when the flow completes.
@MainActor
enum ASWebAuthenticationSessionWrapper {
    private static var retainedSessions: [ASWebAuthenticationSession] = []
    private static var retainedAnchors: [WebAuthAnchor] = []

    static func run(url: URL, scheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            // One OAuth flow at a time: releasing ALL retained state from the
            // handler avoids capturing `session` inside its own declaration.
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: scheme) { callbackURL, error in
                Task { @MainActor in
                    retainedSessions.removeAll()
                    retainedAnchors.removeAll()
                    if let callbackURL {
                        continuation.resume(returning: callbackURL)
                    } else {
                        continuation.resume(throwing: error ?? OAuthError.cancelled)
                    }
                }
            }
            let anchor = WebAuthAnchor()
            session.presentationContextProvider = anchor
            session.prefersEphemeralWebBrowserSession = false
            retainedSessions.append(session)
            retainedAnchors.append(anchor)
            if !session.start() {
                retainedSessions.removeAll()
                retainedAnchors.removeAll()
                continuation.resume(throwing: OAuthError.cancelled)
            }
        }
    }
}

// MARK: - Google Calendar API (read-only)

enum GoogleCalendarAPI {

    struct CalendarListEntry: Decodable {
        let id: String
        let summary: String?
        let summaryOverride: String?
        let backgroundColor: String?
    }

    static func calendars(token: String) async throws -> [CalendarListEntry] {
        var request = URLRequest(url: URL(string: "https://www.googleapis.com/calendar/v3/users/me/calendarList")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw OAuthError.authFailed("Kunde inte hämta Google-kalendrar (HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)).")
        }
        struct List: Decodable { let items: [CalendarListEntry]? }
        return (try? JSONDecoder().decode(List.self, from: data))?.items ?? []
    }

    static func events(token: String,
                       calendarID: String,
                       from: Date,
                       to: Date) async throws -> [ExternalEventRecord] {
        var components = URLComponents(string: "https://www.googleapis.com/calendar/v3/calendars/\(calendarID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? calendarID)/events")!
        let iso = ISO8601DateFormatter()
        components.queryItems = [
            URLQueryItem(name: "timeMin", value: iso.string(from: from)),
            URLQueryItem(name: "timeMax", value: iso.string(from: to)),
            URLQueryItem(name: "singleEvents", value: "true"),   // expands recurrences
            URLQueryItem(name: "orderBy", value: "startTime"),
            URLQueryItem(name: "showDeleted", value: "false"),
            URLQueryItem(name: "maxResults", value: "500"),
        ]
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw OAuthError.authFailed("Kunde inte hämta Google-händelser (HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)).")
        }
        struct Event: Decodable {
            let id: String
            let status: String?
            let summary: String?
            let location: String?
            let start: When?
            let end: When?
            struct When: Decodable {
                let date: String?      // all-day: "2026-01-31"
                let dateTime: String?  // timed: RFC3339
            }
        }
        struct EventsPage: Decodable { let items: [Event]? }

        let page = (try? JSONDecoder().decode(EventsPage.self, from: data))?.items ?? []
        return page.compactMap { event in
            guard event.status != "cancelled" else { return nil }
            return ExternalEventRecordMapper.map(
                provider: .google,
                eventID: event.id,
                calendarID: calendarID,
                title: event.summary ?? "(utan titel)",
                location: event.location ?? "",
                startAllDay: event.start?.date,
                startDateTime: event.start?.dateTime,
                endAllDay: event.end?.date,
                endDateTime: event.end?.dateTime
            )
        }
    }
}

// MARK: - Microsoft Graph (Outlook / Microsoft 365) — read-only

enum MicrosoftCalendarAPI {

    struct GraphCalendar: Decodable {
        let id: String
        let name: String
    }

    static func calendars(token: String) async throws -> [GraphCalendar] {
        var request = URLRequest(url: URL(string: "https://graph.microsoft.com/v1.0/me/calendars")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw OAuthError.authFailed("Kunde inte hämta Outlook-kalendrar (HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)).")
        }
        struct List: Decodable { let value: [GraphCalendar]? }
        return (try? JSONDecoder().decode(List.self, from: data))?.value ?? []
    }

    static func events(token: String,
                       calendarID: String,
                       from: Date,
                       to: Date) async throws -> [ExternalEventRecord] {
        let iso = ISO8601DateFormatter()
        var components = URLComponents(string: "https://graph.microsoft.com/v1.0/me/calendars/\(calendarID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? calendarID)/calendarview")!
        components.queryItems = [
            URLQueryItem(name: "startDateTime", value: iso.string(from: from)),
            URLQueryItem(name: "endDateTime", value: iso.string(from: to)),
        ]
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw OAuthError.authFailed("Kunde inte hämta Outlook-händelser (HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)).")
        }
        struct Event: Decodable {
            let id: String
            let subject: String?
            let location: Location?
            let isAllDay: Bool?
            let start: When?
            let end: When?
            struct Location: Decodable { let displayName: String? }
            struct When: Decodable {
                let dateTime: String?
                let timeZone: String?
            }
        }
        struct EventsPage: Decodable { let value: [Event]? }

        let page = (try? JSONDecoder().decode(EventsPage.self, from: data))?.value ?? []
        return page.compactMap { event in
            ExternalEventRecordMapper.map(
                provider: .outlook,
                eventID: event.id,
                calendarID: calendarID,
                title: event.subject ?? "(utan titel)",
                location: event.location?.displayName ?? "",
                startAllDay: nil,
                startDateTime: event.start?.dateTime,
                endAllDay: nil,
                endDateTime: event.end?.dateTime,
                timeZoneID: event.start?.timeZone,
                isAllDay: event.isAllDay ?? false
            )
        }
    }
}

// MARK: Shared date parsing (time-zone aware)

enum ExternalEventRecordMapper {

    /// Maps provider-specific date payloads to `ExternalEventRecord`.
    /// All-day events use midnight-to-midnight day spans; timed events are
    /// parsed as RFC 3339, falling back to the event's stated time zone
    /// (Graph returns local times without offsets).
    static func map(provider: CalendarProvider,
                    eventID: String,
                    calendarID: String,
                    calendarName: String = "",
                    title: String,
                    location: String,
                    startAllDay: String?,
                    startDateTime: String?,
                    endAllDay: String?,
                    endDateTime: String?,
                    timeZoneID: String? = nil,
                    isAllDay: Bool = false) -> ExternalEventRecord? {
        let dayFormatter = DateFormatter()
        dayFormatter.locale = Locale(identifier: "en_US_POSIX")
        dayFormatter.dateFormat = "yyyy-MM-dd"
        dayFormatter.timeZone = TimeZone(identifier: "Europe/Stockholm")

        let isoFractional = ISO8601DateFormatter()
        isoFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let iso = ISO8601DateFormatter()

        func parseWhen(allDay: String?, dateTime: String?, fallbackEnd: Bool) -> Date? {
            if let allDay, let d = dayFormatter.date(from: allDay) {
                return d
            }
            if let dateTime {
                if let d = isoFractional.date(from: dateTime) ?? iso.date(from: dateTime) {
                    return d
                }
                // Naive local time (Graph): apply the event's time zone.
                let naive = DateFormatter()
                naive.locale = Locale(identifier: "en_US_POSIX")
                naive.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
                naive.timeZone = TimeZone(identifier: timeZoneID ?? "") ?? .current
                if let d = naive.date(from: dateTime) {
                    return d
                }
            }
            return nil
        }

        guard let start = parseWhen(allDay: startAllDay, dateTime: startDateTime, fallbackEnd: false) else {
            return nil
        }
        var end = parseWhen(allDay: endAllDay, dateTime: endDateTime, fallbackEnd: true)
        if end == nil || end! < start {
            end = start.addingTimeInterval(isAllDay ? 86400 : 3600)
        }

        let allDayFlag = startAllDay != nil || isAllDay
        return ExternalEventRecord(
            provider: provider,
            providerEventID: eventID,
            providerCalendarID: calendarID,
            calendarName: calendarName,
            title: title,
            start: start,
            end: end!,
            location: location,
            isAllDay: allDayFlag
        )
    }
}
