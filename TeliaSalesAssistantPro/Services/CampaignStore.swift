import Foundation
import TeliaCore

// MARK: - Campaign data (cache + favorites + recents)

struct CampaignData: Codable, Equatable {
    var campaigns: [CampaignRecord] = []
    var lastRefresh: Date?
    var lastRefreshFailed: Bool = false
    var favorites: Set<String> = []
    var recentIDs: [RecentCampaign] = []

    static func == (lhs: CampaignData, rhs: CampaignData) -> Bool {
        lhs.campaigns.map(\.id) == rhs.campaigns.map(\.id)
            && lhs.lastRefresh == rhs.lastRefresh
            && lhs.lastRefreshFailed == rhs.lastRefreshFailed
            && lhs.favorites == rhs.favorites
            && lhs.recentIDs.map(\.id) == rhs.recentIDs.map(\.id)
    }
}

struct RecentCampaign: Codable, Equatable, Identifiable {
    let id: String
    let viewedAt: Date
}

// MARK: - Feed file format (same shape as CampaignSeed.json)

struct CampaignFeedFile: Codable {
    let campaigns: [CampaignRecord]
    let generatedAt: Date?
    let sourceNote: String?
    let schemaVersion: Int?

    init(campaigns: [CampaignRecord], generatedAt: Date? = nil, sourceNote: String? = nil, schemaVersion: Int? = 1) {
        self.campaigns = campaigns
        self.generatedAt = generatedAt
        self.sourceNote = sourceNote
        self.schemaVersion = schemaVersion
    }
}

// MARK: - Store

/// Kampanj Center store. Loads the bundled verified seed on first launch,
/// then tries to refresh from a JSON feed (default: the project's published
/// seed on GitHub). On failure the cache is kept and flagged — data is never
/// silently stale and never silently dropped.
@MainActor
final class CampaignStore: ObservableObject {

    @Published var data: CampaignData {
        didSet { DataStore.save(data) }
    }

    /// True while a feed refresh is in flight (drives progress UI).
    @Published var isRefreshing = false

    /// Non-nil when the last refresh failed; drives the prominent freshness warning.
    @Published var lastRefreshError: String?

    init() {
        if let cached = DataStore.load(CampaignData.self), !cached.campaigns.isEmpty {
            self.data = cached
        } else if let seeded = CampaignStore.loadBundledSeed() {
            self.data = CampaignData(
                campaigns: seeded,
                lastRefresh: nil,
                lastRefreshFailed: false
            )
        } else {
            self.data = CampaignData()
        }
    }

    // MARK: Seed

    static func loadBundledSeed() -> [CampaignRecord]? {
        guard let url = Bundle.main.url(forResource: "CampaignSeed", withExtension: "json"),
              let raw = try? Data(contentsOf: url) else { return nil }
        do {
            let file = try DataStore.decoder.decode(CampaignFeedFile.self, from: raw)
            return file.campaigns
        } catch {
            return nil
        }
    }

    // MARK: Accessors

    /// Active campaigns sorted by relevance (expiring first).
    var activeCampaigns: [CampaignRecord] {
        CampaignEngine.sort(CampaignEngine.activeCampaigns(data.campaigns), by: .relevance)
    }

    func campaign(id: String) -> CampaignRecord? {
        data.campaigns.first { $0.id == id }
    }

    var favoriteCampaigns: [CampaignRecord] {
        activeCampaigns.filter { data.favorites.contains($0.id) }
    }

    var recentCampaigns: [CampaignRecord] {
        data.recentIDs
            .compactMap { recent in campaign(id: recent.id) }
            .filter { CampaignEngine.status($0).isActive }
    }

    func isFavorite(_ id: String) -> Bool {
        data.favorites.contains(id)
    }

    func toggleFavorite(_ id: String) {
        if data.favorites.contains(id) {
            data.favorites.remove(id)
        } else {
            data.favorites.insert(id)
        }
    }

    func recordView(id: String) {
        data.recentIDs.removeAll { $0.id == id }
        data.recentIDs.insert(RecentCampaign(id: id, viewedAt: Date()), at: 0)
        if data.recentIDs.count > 20 {
            data.recentIDs = Array(data.recentIDs.prefix(20))
        }
    }

    // MARK: Freshness

    /// Days since the newest verifiedAt among records (nil when empty).
    var newestVerification: Date? {
        data.campaigns.map(\.verifiedAt).max()
    }

    var isStale: Bool {
        guard let newest = newestVerification else { return true }
        return Date().timeIntervalSince(newest) / 86_400 > 7
    }

    // MARK: Refresh

    /// Fetches the campaign feed and merges it safely into the cache.
    /// Throws on any failure — the caller keeps showing cached data and warns.
    @discardableResult
    func refresh(feedURL: String) async throws -> CampaignDiff {
        guard !isRefreshing else { throw CampaignFeedError.alreadyRunning }
        isRefreshing = true
        defer { isRefreshing = false }
        guard let url = URL(string: feedURL), url.scheme == "https" || url.scheme == "file" else {
            throw CampaignFeedError.badURL
        }
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (raw, response): (Data, URLResponse)
        do {
            (raw, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw CampaignFeedError.network(error.localizedDescription)
        }
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw CampaignFeedError.server(http.statusCode)
        }
        let file: CampaignFeedFile
        do {
            file = try DataStore.decoder.decode(CampaignFeedFile.self, from: raw)
        } catch {
            throw CampaignFeedError.decode(error.localizedDescription)
        }
        guard !file.campaigns.isEmpty else {
            throw CampaignFeedError.empty
        }

        let diff = CampaignEngine.diff(old: data.campaigns, new: file.campaigns)
        data.campaigns = CampaignEngine.merge(cached: data.campaigns, incoming: file.campaigns)
        data.lastRefresh = Date()
        data.lastRefreshFailed = false
        lastRefreshError = nil
        return diff
    }

    /// Marks the cache as served-after-failed-refresh (prominent warning).
    func noteRefreshFailure(_ message: String) {
        data.lastRefreshFailed = true
        lastRefreshError = message
    }

    func clearRefreshFailure() {
        data.lastRefreshFailed = false
        lastRefreshError = nil
    }

    /// Campaigns a favorite-expiry notification is meaningful for:
    /// favorites with a *verified* end date that is still in the future.
    var notifiableFavorites: [CampaignRecord] {
        favoriteCampaigns.filter { record in
            guard let end = record.endDate else { return false }
            return end > Date()
        }
    }

    /// (Re)schedules opt-in expiry reminders for favorites with verified end
    /// dates and clears stale ones. Only meaningful campaigns get a reminder.
    func scheduleFavoriteExpiryNotifications(settings: SettingsData) {
        guard settings.campaignNotificationsEnabled else {
            NotificationService.shared.cancelCampaignReminders(ids: Array(data.favorites))
            return
        }
        let notifiableIDs = Set(notifiableFavorites.map(\.id))
        // Cancel reminders for favorites without verified end dates.
        let staleIDs = data.favorites.filter { !notifiableIDs.contains($0) }
        if !staleIDs.isEmpty {
            NotificationService.shared.cancelCampaignReminders(ids: Array(staleIDs))
        }
        for campaign in notifiableFavorites {
            NotificationService.shared.scheduleCampaignExpiryReminder(for: campaign)
        }
    }
}

// MARK: - Errors

enum CampaignFeedError: LocalizedError {
    case badURL
    case alreadyRunning
    case network(String)
    case server(Int)
    case decode(String)
    case empty

    var errorDescription: String? {
        switch self {
        case .badURL: return "Ogiltig kampanjkälla."
        case .alreadyRunning: return "En uppdatering pågår redan."
        case .network(let m): return "Nätverksfel vid hämtning av kampanjer: \(m)"
        case .server(let code): return "Kampanjkällan svarade \(code)."
        case .decode(let m): return "Kunde inte läsa kampanjdata: \(m)"
        case .empty: return "Kampanjkällan innehöll inga kampanjer."
        }
    }
}
