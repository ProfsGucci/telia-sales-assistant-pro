import SwiftUI
import Combine
import TeliaCore

// MARK: - SettingsStore

@MainActor
final class SettingsStore: ObservableObject {
    @Published var data: SettingsData {
        didSet { DataStore.save(data) }
    }

    init() {
        self.data = DataStore.load(SettingsData.self) ?? SettingsData()
    }

    var aiConfigured: Bool { !data.aiBaseURL.isEmpty }
}

// MARK: - LibraryStore (favorites, recents, scripts, notes, saved answers, checklist)

struct LibraryData: Codable, Equatable {
    var favoriteProductIDs: Set<String> = []
    var recentProductIDs: [RecentProduct] = []
    var scripts: [SavedScript] = []
    var notes: [PersonalNote] = []
    var savedAnswers: [ChatMessage] = []
    var checklistItems: [ChecklistItem] = ChecklistItem.defaults
    var completedChecklist: [String: String] = [:] // itemId -> yyyy-MM-dd of completion
}

struct RecentProduct: Codable, Equatable, Identifiable {
    let id: String
    let viewedAt: Date
}

struct ChecklistItem: Codable, Equatable, Identifiable {
    let id: String
    let title: String
    var isDefault: Bool = true

    static let defaults: [ChecklistItem] = [
        ChecklistItem(id: "c1", title: "Kolla dagens erbjudanden på telia.se"),
        ChecklistItem(id: "c2", title: "Läs dagens säljtips"),
        ChecklistItem(id: "c3", title: "Räkna upp kassan"),
        ChecklistItem(id: "c4", title: "Sätt dagens mål"),
        ChecklistItem(id: "c5", title: "Kolla schema för dagen"),
    ]
}

@MainActor
final class LibraryStore: ObservableObject {
    @Published var data: LibraryData {
        didSet { trim(); DataStore.save(data) }
    }

    private let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    init() {
        self.data = DataStore.load(LibraryData.self) ?? LibraryData()
    }

    func isFavorite(_ id: String) -> Bool { data.favoriteProductIDs.contains(id) }

    func toggleFavorite(_ id: String) {
        if data.favoriteProductIDs.contains(id) {
            data.favoriteProductIDs.remove(id)
        } else {
            data.favoriteProductIDs.insert(id)
        }
    }

    func recordView(productID: String) {
        data.recentProductIDs.removeAll { $0.id == productID }
        data.recentProductIDs.insert(RecentProduct(id: productID, viewedAt: Date()), at: 0)
    }

    private func trim() {
        if data.recentProductIDs.count > 20 {
            data.recentProductIDs = Array(data.recentProductIDs.prefix(20))
        }
    }

    // Checklist
    func isDoneToday(_ item: ChecklistItem, now: Date = Date()) -> Bool {
        data.completedChecklist[item.id] == dayFormatter.string(from: now)
    }

    func toggleChecklist(_ item: ChecklistItem, now: Date = Date()) {
        if isDoneToday(item, now: now) {
            data.completedChecklist[item.id] = nil
        } else {
            data.completedChecklist[item.id] = dayFormatter.string(from: now)
        }
    }

    func addChecklistItem(title: String) {
        let item = ChecklistItem(id: UUID().uuidString, title: title, isDefault: false)
        data.checklistItems.append(item)
    }

    func removeChecklistItems(at offsets: IndexSet) {
        data.checklistItems.remove(atOffsets: offsets)
    }

    func completedTodayCount(now: Date = Date()) -> Int {
        data.checklistItems.filter { isDoneToday($0, now: now) }.count
    }

    // Scripts
    func upsert(script: SavedScript) {
        if let index = data.scripts.firstIndex(where: { $0.id == script.id }) {
            data.scripts[index] = script
        } else {
            data.scripts.insert(script, at: 0)
        }
    }

    func deleteScript(id: UUID) {
        data.scripts.removeAll { $0.id == id }
    }

    // Notes
    func upsert(note: PersonalNote) {
        if let index = data.notes.firstIndex(where: { $0.id == note.id }) {
            data.notes[index] = note
        } else {
            data.notes.insert(note, at: 0)
        }
    }

    func deleteNote(id: UUID) {
        data.notes.removeAll { $0.id == id }
    }

    // Saved answers
    func toggleSavedAnswer(_ message: ChatMessage) {
        if let index = data.savedAnswers.firstIndex(where: { $0.id == message.id }) {
            data.savedAnswers.remove(at: index)
        } else {
            var copy = message
            copy.saved = true
            data.savedAnswers.insert(copy, at: 0)
        }
    }

    func isSaved(_ message: ChatMessage) -> Bool {
        data.savedAnswers.contains { $0.id == message.id }
    }
}

// MARK: - CatalogStore

struct CatalogData: Codable, Equatable {
    var snapshot: CatalogSnapshot?
    var changes: [PriceVerification.PriceChange] = []
    var lastRefreshAt: Date?
    var lastRefreshError: String?
}

@MainActor
final class CatalogStore: ObservableObject {
    @Published private(set) var data: CatalogData
    @Published var compareIDs: [String] = []
    @Published private(set) var isRefreshing = false

    let seedLoadedAt: Date

    init() {
        if let saved = DataStore.load(CatalogData.self) {
            self.data = saved
            self.seedLoadedAt = saved.snapshot?.generatedAt ?? Date()
        } else if let seed = CatalogStore.loadSeed() {
            self.data = CatalogData(snapshot: seed, changes: [], lastRefreshAt: nil, lastRefreshError: nil)
            self.seedLoadedAt = seed.generatedAt
            DataStore.save(data)
        } else {
            self.data = CatalogData()
            self.seedLoadedAt = Date()
        }
    }

    static func loadSeed() -> CatalogSnapshot? {
        guard let url = Bundle.main.url(forResource: "SeedCatalog", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? DataStore.decoder.decode(CatalogSnapshot.self, from: data)
    }

    // MARK: Accessors

    var products: [ProductRecord] { data.snapshot?.products ?? [] }

    func product(id: String) -> ProductRecord? {
        products.first { $0.id == id }
    }

    var lastUpdated: Date? {
        data.lastRefreshAt ?? data.snapshot?.generatedAt
    }

    var freshnessNote: String {
        guard let date = lastUpdated else { return "Ingen prisdata" }
        return "Prisdata kontrollerad \(Format.relativeDays(date))"
    }

    // MARK: Compare

    var compareProducts: [ProductRecord] {
        compareIDs.compactMap { product(id: $0) }
    }

    func toggleCompare(_ id: String) {
        if let index = compareIDs.firstIndex(of: id) {
            compareIDs.remove(at: index)
        } else {
            guard compareIDs.count < 3 else { return }
            compareIDs.append(id)
        }
    }

    // MARK: Import & refresh

    func applyImport(_ snapshot: CatalogSnapshot, source: String) {
        let changes = PriceVerification.diff(old: products, new: snapshot.products)
        data.snapshot = snapshot
        data.changes = changes + data.changes
        data.lastRefreshAt = Date()
        data.lastRefreshError = nil
        DataStore.save(data)
    }

    func importFile(data: Data, filename: String) -> Result<PriceImportReport, PriceImportError> {
        do {
            let (snapshot, report) = try PriceImport.parse(data: data, filename: filename)
            applyImport(snapshot, source: report.source)
            return .success(report)
        } catch let error as PriceImportError {
            data.lastRefreshError = error.localizedDescription
            return .failure(error)
        } catch {
            data.lastRefreshError = error.localizedDescription
            return .failure(.malformedJSON(error.localizedDescription))
        }
    }

    /// Fetches a JSON feed (same schema as the app export / seed) over HTTPS.
    func refreshFromFeed(urlString: String) async {
        guard let url = URL(string: urlString), url.scheme == "https" else {
            data.lastRefreshError = "Ogiltig eller icke-HTTPS-adress."
            return
        }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            var request = URLRequest(url: url, timeoutInterval: 20)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            let (bytes, response) = try await URLSession.shared.bytes(for: request)
            guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
                throw CoachError.server((response as? HTTPURLResponse)?.statusCode ?? -1)
            }
            let content = try await bytes.lines.reduce(into: "") { $0 += $0 + "\n" }
            guard let feedData = content.data(using: .utf8) else { throw CoachError.emptyResponse }
            let (snapshot, _) = try PriceImport.parseJSON(feedData)
            applyImport(snapshot, source: "Feed: \(url.host ?? url.absoluteString)")
        } catch {
            data.lastRefreshError = error.localizedDescription
        }
    }

    /// Reverts to the bundled seed snapshot.
    func resetToSeed() {
        if let seed = CatalogStore.loadSeed() {
            applyImport(seed, source: "Inbyggd data")
        }
    }
}

// MARK: - Content loading

enum AppContent {
    static let learning: LearningContent = {
        guard let url = Bundle.main.url(forResource: "LearningContent", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let content = try? DataStore.decoder.decode(LearningContent.self, from: data) else {
            return LearningContent(lessons: [], glossary: [], tips: [])
        }
        return content
    }()

    static let playbook: PlaybookContent = {
        guard let url = Bundle.main.url(forResource: "PlaybookContent", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let content = try? DataStore.decoder.decode(PlaybookContent.self, from: data) else {
            return PlaybookContent(entries: [])
        }
        return content
    }()
}
