import SwiftUI
import TeliaCore

// MARK: - Root

struct RootView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var appState: AppState

    var body: some View {
        ZStack {
            if horizontalSizeClass == .regular {
                SidebarRootView()
            } else {
                TabRootView()
            }
            if appState.splashVisible {
                SplashView()
                    .zIndex(10)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 1.03)))
            }
        }
    }
}

// MARK: - Splash

struct SplashView: View {
    var body: some View {
        VStack(spacing: DS.Space.m) {
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(DS.heroGradient)
                    .frame(width: 84, height: 84)
                    .shadow(color: DS.Purple.base.opacity(0.4), radius: 16, y: 6)
                Image(systemName: "bubble.left.and.text.bubble.right.fill")
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundStyle(.white)
            }
            Text("Telia Sales Assistant Pro")
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(.primary)
            Text("Personlig säljcoach")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
        .accessibilityHidden(true)
    }
}

// MARK: - iPhone: 5 tabs

struct TabRootView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        TabView(selection: $appState.selectedTab) {
            NavigationStack {
                DashboardView()
            }
            .tabItem { Label("Hem", systemImage: "house.fill") }
            .tag(AppTab.home)

            NavigationStack {
                CatalogueView()
            }
            .tabItem { Label("Produkter", systemImage: "cart.fill") }
            .tag(AppTab.products)

            NavigationStack {
                ChatView()
            }
            .tabItem { Label("AI Coach", systemImage: "bubble.left.and.text.bubble.right.fill") }
            .tag(AppTab.coach)

            NavigationStack {
                CalendarView()
            }
            .tabItem { Label("Kalender", systemImage: "calendar") }
            .tag(AppTab.calendar)

            NavigationStack {
                ProgressDashboardView()
            }
            .tabItem { Label("Min utveckling", systemImage: "chart.line.uptrend.xyaxis") }
            .tag(AppTab.progress)
        }
    }
}

// MARK: - iPad: sidebar + adaptive detail

struct SidebarRootView: View {
    @EnvironmentObject private var appState: AppState
    @State private var selection: AppDestination? = .home

    private let primary: [AppDestination] = [.home, .products, .coach, .calendar, .progress]
    private let secondary: [AppDestination] = [.playbook, .roleplay, .academy, .library, .settings]

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section("Arbetspass") {
                    ForEach(primary) { destination in
                        Label(destination.title, systemImage: destination.symbol)
                            .tag(destination)
                    }
                }
                Section("Träning") {
                    ForEach(secondary) { destination in
                        Label(destination.title, systemImage: destination.symbol)
                            .tag(destination)
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("Telia Coach")
        } detail: {
            NavigationStack {
                DestinationDetail(destination: selection ?? .home)
            }
        }
        .onChange(of: appState.selectedTab) { tab in
            // Honor cross-tab navigation requests from compact-era code paths.
            selection = tab.primaryDestination
        }
        .onChange(of: selection) { destination in
            // Keep tab state in sync so shared code paths behave the same in both layouts.
            if let destination, let tab = AppTab(destination: destination) {
                appState.selectedTab = tab
            }
        }
    }
}

// MARK: - Destination router

struct DestinationDetail: View {
    let destination: AppDestination

    var body: some View {
        switch destination {
        case .home: DashboardView()
        case .products: CatalogueView()
        case .coach: ChatView()
        case .calendar: CalendarView()
        case .progress: ProgressDashboardView()
        case .playbook: PlaybookView()
        case .roleplay: RolePlayHomeView()
        case .academy: AcademyView()
        case .library: LibraryView()
        case .settings: SettingsView()
        }
    }
}
