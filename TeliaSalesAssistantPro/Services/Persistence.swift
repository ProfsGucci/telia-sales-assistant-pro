import Foundation
import SwiftUI
import TeliaCore

/// JSON-file persistence in the app's Documents directory. Atomic writes, ISO8601 dates.
/// Everything stays on-device by default; see docs/PRIVACY.md.
enum DataStore {

    static var baseURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TeliaSalesAssistant", isDirectory: true)
    }

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    static func url<T>(for type: T.Type) -> URL {
        baseURL.appendingPathComponent("\(String(describing: type)).json")
    }

    static func load<T: Decodable>(_ type: T.Type) -> T? {
        let fileURL = url(for: type)
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? decoder.decode(T.self, from: data)
    }

    @discardableResult
    static func save<T: Encodable>(_ value: T) -> Bool {
        let fileURL = url(for: T.self)
        do {
            try FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)
            let data = try encoder.encode(value)
            try data.write(to: fileURL, options: .atomic)
            return true
        } catch {
            NSLog("DataStore save \(String(describing: T.self)) failed: \(error.localizedDescription)")
            return false
        }
    }

    static func remove<T: Encodable>(_ type: T.Type) {
        try? FileManager.default.removeItem(at: url(for: type))
    }

    static func deleteEverything() {
        try? FileManager.default.removeItem(at: baseURL)
    }

    /// Export every persisted JSON file as a single envelope the user can save or share.
    static func exportAll() -> Data? {
        struct ExportEnvelope: Codable {
            var exportedAt: Date
            var files: [String: Data]
        }
        var files: [String: Data] = [:]
        if let urls = try? FileManager.default.contentsOfDirectory(at: baseURL, includingPropertiesForKeys: nil) {
            for url in urls where url.pathExtension == "json" {
                if let data = try? Data(contentsOf: url) {
                    files[url.lastPathComponent] = data
                }
            }
        }
        let envelope = ExportEnvelope(exportedAt: Date(), files: files)
        return try? encoder.encode(envelope)
    }
}

// MARK: - User preferences

enum ThemePreference: String, Codable, CaseIterable {
    case system, light, dark

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    var label: String {
        switch self {
        case .system: return "System"
        case .light: return "Ljust"
        case .dark: return "Mörkt"
        }
    }
}

struct SettingsData: Codable, Equatable {
    var theme: ThemePreference = .system
    var autoRefreshOnOpen: Bool = true
    var priceFeedURL: String = ""
    var aiBaseURL: String = ""
    var aiModel: String = "gpt-4o-mini"
    var aiUsesKey: Bool = false
    var staleAfterDays: Int = 7
    var dashboardOrder: [String] = DashboardCard.defaultOrder
    var hiddenDashboardCards: Set<String> = []
    var remindersEnabled: Bool = false
    var background: BackgroundPreference = .default
    /// Opt-in notifications for saved campaigns nearing a verified expiry.
    var campaignNotificationsEnabled: Bool = false
    /// JSON feed with verified campaign records. Defaults to the project's
    /// published seed so campaign data can update without scraping telia.se.
    var campaignFeedURL: String = SettingsData.defaultCampaignFeedURL

    // MARK: External calendars (1.4)
    // Client IDs are the user's OWN app registrations (never compiled into
    // the binary). See docs/CALENDAR-SETUP.md.
    var googleClientID: String = ""
    var microsoftClientID: String = ""
    var appleCalendarsEnabled: Bool = false
    var selectedAppleCalendarIDs: Set<String> = []
    var googleCalendarsEnabled: Bool = false
    var selectedGoogleCalendarIDs: Set<String> = []
    var outlookCalendarsEnabled: Bool = false
    var selectedOutlookCalendarIDs: Set<String> = []
    /// provider rawValue → last successful sync date.
    var calendarLastSync: [String: Date] = [:]
    /// Refresh imported calendars when the app becomes active (throttled).
    var calendarSyncOnOpen: Bool = true
    /// Opt-in local reminders for customer follow-ups (privacy-safe text).
    var followUpRemindersEnabled: Bool = false

    /// Raw GitHub URL of the bundled seed in the public repository.
    static let defaultCampaignFeedURL =
        "https://raw.githubusercontent.com/ProfsGucci/telia-sales-assistant-pro/main/TeliaSalesAssistantPro/Resources/CampaignSeed.json"

    private enum CodingKeys: String, CodingKey {
        case theme, autoRefreshOnOpen, priceFeedURL, aiBaseURL, aiModel, aiUsesKey
        case staleAfterDays, dashboardOrder, hiddenDashboardCards, remindersEnabled
        case background, campaignNotificationsEnabled, campaignFeedURL
        case googleClientID, microsoftClientID
        case appleCalendarsEnabled, selectedAppleCalendarIDs
        case googleCalendarsEnabled, selectedGoogleCalendarIDs
        case outlookCalendarsEnabled, selectedOutlookCalendarIDs
        case calendarLastSync, calendarSyncOnOpen, followUpRemindersEnabled
    }

    /// Tolerant decoding: settings saved by earlier app versions — or with one
    /// corrupt individual field — keep loading (defaults fill only the bad
    /// fields) instead of the whole file being discarded. This is the root
    /// cause fix for backgrounds/settings "randomly resetting".
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        theme = (try? c.decodeIfPresent(ThemePreference.self, forKey: .theme)) ?? .system
        autoRefreshOnOpen = (try? c.decodeIfPresent(Bool.self, forKey: .autoRefreshOnOpen)) ?? true
        priceFeedURL = (try? c.decodeIfPresent(String.self, forKey: .priceFeedURL)) ?? ""
        aiBaseURL = (try? c.decodeIfPresent(String.self, forKey: .aiBaseURL)) ?? ""
        aiModel = (try? c.decodeIfPresent(String.self, forKey: .aiModel)) ?? "gpt-4o-mini"
        aiUsesKey = (try? c.decodeIfPresent(Bool.self, forKey: .aiUsesKey)) ?? false
        staleAfterDays = (try? c.decodeIfPresent(Int.self, forKey: .staleAfterDays)) ?? 7
        dashboardOrder = (try? c.decodeIfPresent([String].self, forKey: .dashboardOrder)) ?? DashboardCard.defaultOrder
        hiddenDashboardCards = (try? c.decodeIfPresent(Set<String>.self, forKey: .hiddenDashboardCards)) ?? []
        remindersEnabled = (try? c.decodeIfPresent(Bool.self, forKey: .remindersEnabled)) ?? false
        background = (try? c.decodeIfPresent(BackgroundPreference.self, forKey: .background)) ?? .default
        campaignNotificationsEnabled = (try? c.decodeIfPresent(Bool.self, forKey: .campaignNotificationsEnabled)) ?? false
        campaignFeedURL = (try? c.decodeIfPresent(String.self, forKey: .campaignFeedURL)) ?? SettingsData.defaultCampaignFeedURL
        googleClientID = (try? c.decodeIfPresent(String.self, forKey: .googleClientID)) ?? ""
        microsoftClientID = (try? c.decodeIfPresent(String.self, forKey: .microsoftClientID)) ?? ""
        appleCalendarsEnabled = (try? c.decodeIfPresent(Bool.self, forKey: .appleCalendarsEnabled)) ?? false
        selectedAppleCalendarIDs = (try? c.decodeIfPresent(Set<String>.self, forKey: .selectedAppleCalendarIDs)) ?? []
        googleCalendarsEnabled = (try? c.decodeIfPresent(Bool.self, forKey: .googleCalendarsEnabled)) ?? false
        selectedGoogleCalendarIDs = (try? c.decodeIfPresent(Set<String>.self, forKey: .selectedGoogleCalendarIDs)) ?? []
        outlookCalendarsEnabled = (try? c.decodeIfPresent(Bool.self, forKey: .outlookCalendarsEnabled)) ?? false
        selectedOutlookCalendarIDs = (try? c.decodeIfPresent(Set<String>.self, forKey: .selectedOutlookCalendarIDs)) ?? []
        calendarLastSync = (try? c.decodeIfPresent([String: Date].self, forKey: .calendarLastSync)) ?? [:]
        calendarSyncOnOpen = (try? c.decodeIfPresent(Bool.self, forKey: .calendarSyncOnOpen)) ?? true
        followUpRemindersEnabled = (try? c.decodeIfPresent(Bool.self, forKey: .followUpRemindersEnabled)) ?? false
    }

    init() {}
}

