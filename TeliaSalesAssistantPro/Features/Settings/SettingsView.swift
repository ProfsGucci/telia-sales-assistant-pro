import SwiftUI
import UniformTypeIdentifiers
import TeliaCore

struct SettingsView: View {
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var catalog: CatalogStore
    @EnvironmentObject private var campaigns: CampaignStore
    @EnvironmentObject private var chat: ChatStore
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var progress: ProgressStore
    @EnvironmentObject private var learning: LearningStore
    @EnvironmentObject private var schedule: ScheduleStore

    @State private var apiKey = ""
    @State private var testingConnection = false
    @State private var testResult: String?
    @State private var importReport: PriceImportReport?
    @State private var showImportReport = false
    @State private var importError: String?
    @State private var showImportError = false
    @State private var showImporter = false
    @State private var confirmDeleteAll = false

    private let keychain = KeychainService()

    var body: some View {
        Form {
            appearanceSection
            calendarsSection
            priceSection
            campaignSection
            aiSection
            reminderSection
            dataSection
            privacySection
            aboutSection
        }
        .navigationTitle("Inställningar")
        .scrollContentBackground(.hidden)
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json, .commaSeparatedText]) { result in
            switch result {
            case .success(let url):
                guard url.startAccessingSecurityScopedResource() else { return }
                defer { url.stopAccessingSecurityScopedResource() }
                if let data = try? Data(contentsOf: url) {
                    let outcome = catalog.importFile(data: data, filename: url.lastPathComponent)
                    switch outcome {
                    case .success(let report):
                        importReport = report
                        showImportReport = true
                    case .failure(let error):
                        importError = error.localizedDescription
                        showImportError = true
                    }
                }
            case .failure(let error):
                importError = error.localizedDescription
            }
        }
        .sheet(item: $exportPayload) { payload in
            ActivityShareView(url: payload.url)
        }
        .alert("Import klar", isPresented: $showImportReport) {
            Button("OK") { importReport = nil }
        } message: {
            if let report = importReport {
                Text("\(report.importedCount) produkter importerade från \(report.source). \(report.errors.isEmpty ? "" : "\(report.skippedCount) rader hoppades över.")")
            }
        }
        .alert("Importfel", isPresented: $showImportError) {
            Button("OK") { importError = nil }
        } message: {
            Text(importError ?? "")
        }
        .confirmationDialog("Radera all data?", isPresented: $confirmDeleteAll, titleVisibility: .visible) {
            Button("Radera allt (kan inte ångras)", role: .destructive) {
                deleteEverything()
            }
        } message: {
            Text("Konversationer, anteckningar, passdata och importerad prisdata tas bort permanent.")
        }
        .onAppear {
            apiKey = keychain.getAIKey() ?? ""
        }
    }

    private struct ExportPayload: Identifiable {
        let url: URL
        var id: String { url.absoluteString }
    }
    @State private var exportPayload: ExportPayload?

    // MARK: Sections

    private var appearanceSection: some View {
        Section("Utseende") {
            Picker("Tema", selection: Binding(
                get: { settings.data.theme },
                set: { settings.data.theme = $0 }
            )) {
                ForEach(ThemePreference.allCases, id: \.self) { preference in
                    Text(preference.label).tag(preference)
                }
            }
            .pickerStyle(.segmented)
            NavigationLink {
                BackgroundSettingsView()
            } label: {
                Label("Bakgrund", systemImage: "paintpalette.fill")
            }
        }
    }

    private var priceSection: some View {
        Section {
            Toggle("Uppdatera automatiskt vid öppning", isOn: Binding(
                get: { settings.data.autoRefreshOnOpen },
                set: { settings.data.autoRefreshOnOpen = $0 }
            ))
            TextField("Prisfeed-URL (https://…)", text: Binding(
                get: { settings.data.priceFeedURL },
                set: { settings.data.priceFeedURL = $0 }
            ))
            .keyboardType(.URL)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            Stepper("Markera data som åldrad efter \(settings.data.staleAfterDays) dagar", value: Binding(
                get: { settings.data.staleAfterDays },
                set: { settings.data.staleAfterDays = $0 }
            ), in: 1...90)
            Button {
                Task { await catalog.refreshFromFeed(urlString: settings.data.priceFeedURL) }
            } label: {
                Label("Uppdatera nu", systemImage: "arrow.clockwise")
            }
            .disabled(settings.data.priceFeedURL.isEmpty || catalog.isRefreshing)
            Button {
                catalog.resetToSeed()
            } label: {
                Label("Återställ inbyggd katalog", systemImage: "arrow.counterclockwise")
            }
        } header: {
            Text("Prisdata")
        } footer: {
            Text("Feed-formatet är samma JSON som appen exporterar. HTML-skrapning av telia.se görs inte – det är opålitligt. Senast uppdaterad: \(catalog.lastUpdated.map { Format.dateTime.string(from: $0) } ?? "aldrig").")
        }
    }

    private var aiSection: some View {
        Section {
            TextField("Server-URL (https://…)", text: Binding(
                get: { settings.data.aiBaseURL },
                set: { settings.data.aiBaseURL = $0 }
            ))
            .keyboardType(.URL)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            TextField("Modell", text: Binding(
                get: { settings.data.aiModel },
                set: { settings.data.aiModel = $0 }
            ))
            .autocorrectionDisabled()
            Toggle("Kräv API-nyckel", isOn: Binding(
                get: { settings.data.aiUsesKey },
                set: { settings.data.aiUsesKey = $0 }
            ))
            if settings.data.aiUsesKey {
                SecureField("API-nyckel (sparas i Keychain)", text: $apiKey)
                    .onChange(of: apiKey) { newValue in
                        keychain.saveAIKey(newValue)
                    }
            }
            Button {
                testConnection()
            } label: {
                HStack {
                    Label("Testa anslutningen", systemImage: "bolt.horizontal")
                    if testingConnection { Spacer(); ProgressView() }
                }
            }
            .disabled(testingConnection)
            if let testResult {
                Text(testResult)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(testResult.contains("Kunde") ? .red : .green)
            }
        } header: {
            Text("AI-backend")
        } footer: {
            Text("Peka på en OpenAI-kompatibel server, t.ex. den medföljande proxyn (backend/openai-proxy) där API-nyckeln bor på servern. Lämna tomt för demoläge. Nyckeln lagras i enhetens Keychain, aldrig i filer.")
        }
    }

    private func testConnection() {
        guard let url = URL(string: settings.data.aiBaseURL), url.scheme == "https" else {
            testResult = "Ange en giltig https-adress."
            return
        }
        testingConnection = true
        testResult = nil
        let service = RemoteCoachService(baseURL: url, model: settings.data.aiModel, apiKey: settings.data.aiUsesKey ? keychain.getAIKey() : nil)
        Task {
            do {
                let reply = try await service.reply(
                    to: "Svara med ett ord: hej",
                    history: [],
                    catalog: catalog.products,
                    campaigns: []
                ) { _ in }
                await MainActor.run {
                    testResult = reply.text.isEmpty ? "Servern svarade men utan text." : "Anslutningen fungerar."
                    testingConnection = false
                }
            } catch {
                await MainActor.run {
                    testResult = "Kunde inte ansluta: \(error.localizedDescription)"
                    testingConnection = false
                }
            }
        }
    }

    private var reminderSection: some View {
        Section {
            Toggle("Påminnelser före pass", isOn: Binding(
                get: { settings.data.remindersEnabled },
                set: { enabled in
                    settings.data.remindersEnabled = enabled
                    if enabled {
                        Task {
                            let granted = await NotificationService.shared.requestPermission()
                            if !granted {
                                await MainActor.run { settings.data.remindersEnabled = false }
                            }
                        }
                    }
                }
            ))
            Toggle("Påminn när sparade kampanjer slutar", isOn: Binding(
                get: { settings.data.campaignNotificationsEnabled },
                set: { enabled in
                    settings.data.campaignNotificationsEnabled = enabled
                    if enabled {
                        Task {
                            let granted = await NotificationService.shared.requestPermission()
                            if !granted {
                                await MainActor.run { settings.data.campaignNotificationsEnabled = false }
                            } else {
                                campaigns.scheduleFavoriteExpiryNotifications(settings: settings.data)
                            }
                        }
                    } else {
                        campaigns.scheduleFavoriteExpiryNotifications(settings: settings.data)
                    }
                }
            ))
        } header: {
            Text("Notiser")
        } footer: {
            Text("Lokala notiser 30 minuter före pass, om iOS tillåter. Kampanjpåminnelser skickas tre dagar innan en stjärnmärkt kampanjs verifierade slutdatum – bara sådana är meningsfulla. Inga push-notiser skickas från någon server.")
        }
    }

    private var campaignSection: some View {
        Section {
            TextField("Kampanjfeed-URL (https://…)", text: Binding(
                get: { settings.data.campaignFeedURL },
                set: { settings.data.campaignFeedURL = $0 }
            ))
            .keyboardType(.URL)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            Button {
                Task {
                    do {
                        try await campaigns.refresh(feedURL: settings.data.campaignFeedURL)
                        campaigns.scheduleFavoriteExpiryNotifications(settings: settings.data)
                    } catch {
                        campaigns.noteRefreshFailure((error as? LocalizedError)?.errorDescription ?? String(describing: error))
                    }
                }
            } label: {
                Label("Uppdatera kampanjer nu", systemImage: "arrow.clockwise")
            }
            .disabled(settings.data.campaignFeedURL.isEmpty || campaigns.isRefreshing)
        } header: {
            Text("Kampanjdata")
        } footer: {
            Text("Kampanjerna verifieras manuellt mot offentliga sidor på telia.se och publiceras som JSON. Appen hämtar den publika listan vid öppning – HTML-skrapning av telia.se görs inte. Senast hämtat: \(campaigns.data.lastRefresh.map { Format.dateTime.string(from: $0) } ?? "aldrig").")
        }
    }

    private var dataSection: some View {
        Section {
            Button {
                if let data = DataStore.exportAll() {
                    let url = FileManager.default.temporaryDirectory
                        .appendingPathComponent("tsap-export-\(Int(Date().timeIntervalSince1970)).json")
                    try? data.write(to: url, options: .atomic)
                    exportPayload = ExportPayload(url: url)
                }
            } label: {
                Label("Exportera all data (JSON)", systemImage: "square.and.arrow.up")
            }
            Button {
                showImporter = true
            } label: {
                Label("Importera prislista (JSON/CSV)", systemImage: "square.and.arrow.down")
            }
            Button(role: .destructive) {
                confirmDeleteAll = true
            } label: {
                Label("Radera all data…", systemImage: "trash")
            }
        } header: {
            Text("Data")
        } footer: {
            Text("Exporten innehåller konversationer, anteckningar, passdata, mål och träningshistorik – bra för backup eller flytt. All data lagras lokalt i appens dokumentmapp.")
        }
    }

    private var privacySection: some View {
        Section("Integritet") {
            VStack(alignment: .leading, spacing: DS.Space.s) {
                bullet("All lokal data (konversationer, anteckningar, resultat) lagras i appens dokumentmapp och lämnar aldrig enheten.")
                bullet("I demoläge skickas ingenting till någon server.")
                bullet("Med konfigurerad AI-backend skickas din fråga + relevant produktdata till den servern. Inga personnummer, betalningsuppgifter eller kundregister hanteras.")
                bullet("Ingen analys, ingen spårning, inga tredjeparts-SDK:er.")
            }
        }
    }

    private var aboutSection: some View {
        Section("Om appen") {
            VStack(alignment: .leading, spacing: DS.Space.l) {
                HStack(spacing: DS.Space.m) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(DS.Surface.heroGradient)
                            .frame(width: 52, height: 52)
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                            )
                        Image(systemName: "bubble.left.and.text.bubble.right.fill")
                            .font(.system(.title3, design: .rounded))
                            .foregroundStyle(.white)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Telia Sales Assistant Pro")
                            .font(.system(.headline, design: .rounded))
                        Text("Version 1.2 (3) · Update 1.2 BETA")
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text("Made by Kevork Khagadurian")
                        .font(.system(.subheadline, design: .rounded).weight(.bold))
                        .foregroundStyle(DS.Purple.base)
                    Text("Personligt säljverktyg för egen utveckling. Inte en officiell Telia-produkt och inte kopplad till Telias system. Priser och kampanjer läses från offentliga sidor på telia.se – verifiera alltid mot källan.")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, DS.Space.s)
        }
    }

    /// Deletes persisted files and resets every in-memory store so the app
    /// returns to its first-launch state without restarting.
    private func deleteEverything() {
        chat.deleteAll()
        library.data = LibraryData()
        progress.entries = []
        progress.goals = Goals()
        learning.data = LearningData()
        schedule.events = []
        schedule.tasks = []
        catalog.resetToSeed()
        settings.data = SettingsData()
        keychain.deleteAIKey()
        DataStore.deleteEverything()
    }

    private func bullet(_ text: String) -> some View {
        Label(text, systemImage: "checkmark.circle")
            .labelStyle(ManualBulletStyle(color: .green))
            .font(.system(.caption, design: .rounded))
    }
}

// MARK: - Share sheet wrapper

struct ActivityShareView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
