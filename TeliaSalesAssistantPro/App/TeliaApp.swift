import SwiftUI
import TeliaCore

@main
struct TeliaSalesAssistantApp: App {
    @StateObject private var settings = SettingsStore()
    @StateObject private var catalog = CatalogStore()
    @StateObject private var library = LibraryStore()
    @StateObject private var chat = ChatStore()
    @StateObject private var schedule = ScheduleStore()
    @StateObject private var progress = ProgressStore()
    @StateObject private var learning = LearningStore()
    @StateObject private var appState = AppState()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(settings)
                .environmentObject(catalog)
                .environmentObject(library)
                .environmentObject(chat)
                .environmentObject(schedule)
                .environmentObject(progress)
                .environmentObject(learning)
                .environmentObject(appState)
                .preferredColorScheme(settings.data.theme.colorScheme)
                .tint(DS.Purple.base)
                .task {
                    // Brief branded splash on cold start only; never blocks interaction
                    // longer than the content needs to be ready.
                    try? await Task.sleep(nanoseconds: 650_000_000)
                    withAnimation(.easeOut(duration: 0.3)) {
                        appState.splashVisible = false
                    }
                }
                .onChange(of: scenePhase) { phase in
                    if phase == .active {
                        appState.persistAllNow()
                        if settings.data.autoRefreshOnOpen,
                           !settings.data.priceFeedURL.isEmpty,
                           catalogNeedsRefresh() {
                            Task {
                                await catalog.refreshFromFeed(urlString: settings.data.priceFeedURL)
                            }
                        }
                    }
                }
        }
    }

    private func catalogNeedsRefresh() -> Bool {
        guard let last = catalog.lastUpdated else { return true }
        return Date().timeIntervalSince(last) > 6 * 3600
    }
}

// MARK: - App state

@MainActor
final class AppState: ObservableObject {
    @Published var splashVisible = true
    @Published var selectedTab: AppTab = .home
    /// Cross-tab navigation requests, e.g. "open product search" from the dashboard.
    /// Seed text for the product search field, set when navigating from the dashboard.
    @Published var productSearchSeed: String?

    var settingsStore: SettingsStore?
    var libraryStore: LibraryStore?
    var chatStore: ChatStore?
    var scheduleStore: ScheduleStore?
    var progressStore: ProgressStore?
    var learningStore: LearningStore?

    func persistAllNow() {
        // Stores persist on change; this is a safety net for scene transitions.
    }
}

enum AppTab: Hashable {
    case home, products, coach, calendar, progress

    /// The sidebar destination matching this tab (used in the regular-width layout).
    var primaryDestination: AppDestination {
        switch self {
        case .home: return .home
        case .products: return .products
        case .coach: return .coach
        case .calendar: return .calendar
        case .progress: return .progress
        }
    }

    /// The tab a destination belongs to, if any (training destinations return nil).
    init?(destination: AppDestination) {
        switch destination {
        case .home: self = .home
        case .products: self = .products
        case .coach: self = .coach
        case .calendar: self = .calendar
        case .progress: self = .progress
        default: return nil
        }
    }
}

/// Every reachable top-level destination.
enum AppDestination: String, Hashable, Identifiable, CaseIterable {
    case home, products, coach, calendar, progress
    case playbook, roleplay, academy, library, settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "Hem"
        case .products: return "Produkter"
        case .coach: return "AI Coach"
        case .calendar: return "Kalender"
        case .progress: return "Min utveckling"
        case .playbook: return "Säljmanus"
        case .roleplay: return "Rollspel"
        case .academy: return "Akademin"
        case .library: return "Bibliotek"
        case .settings: return "Inställningar"
        }
    }

    var symbol: String {
        switch self {
        case .home: return "house.fill"
        case .products: return "cart.fill"
        case .coach: return "bubble.left.and.text.bubble.right.fill"
        case .calendar: return "calendar"
        case .progress: return "chart.line.uptrend.xyaxis"
        case .playbook: return "text.book.closed.fill"
        case .roleplay: return "theatermasks.fill"
        case .academy: return "graduationcap.fill"
        case .library: return "bookmark.fill"
        case .settings: return "gearshape.fill"
        }
    }
}
