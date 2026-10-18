import SwiftUI
import TeliaCore

struct ChatView: View {
    @EnvironmentObject private var chat: ChatStore
    @EnvironmentObject private var catalog: CatalogStore
    @EnvironmentObject private var campaigns: CampaignStore
    @EnvironmentObject private var settings: SettingsStore

    @State private var draft = ""
    @State private var atBottom = true
    @State private var showHistory = false

    var body: some View {
        VStack(spacing: 0) {
            if !settings.aiConfigured {
                demoBanner
            }
            messageList
            inputBar
        }
        // Transparent so the app-wide custom background shows through.
        .navigationTitle("AI Coach")
        .navigationDestination(for: AppDestination.self) { destination in
            DestinationDetail(destination: destination)
        }
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button {
                    chat.newConversation()
                } label: {
                    Image(systemName: "plus.bubble")
                }
                .accessibilityLabel("Ny konversation")
                Button {
                    showHistory = true
                } label: {
                    Image(systemName: "clock.arrow.circlepath")
                }
                .accessibilityLabel("Konversationshistorik")
            }
        }
        .sheet(isPresented: $showHistory) {
            ConversationHistoryView()
        }
    }

    private var demoBanner: some View {
        HStack(spacing: DS.Space.s) {
            Image(systemName: "sparkles")
                .font(.caption)
            Text("Demoläge – svarar lokalt från den verifierade katalogen. Konfigurera AI-backend i Inställningar för full coachning.")
                .font(.system(.caption, design: .rounded))
            Spacer(minLength: 0)
            NavigationLink(value: AppDestination.settings) {
                Text("Konfigurera")
                    .font(.system(.caption, design: .rounded).weight(.semibold))
            }
        }
        .padding(.horizontal, DS.Space.m)
        .padding(.vertical, DS.Space.s)
        .background(DS.Purple.base.opacity(0.12))
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: DS.Space.m) {
                    if let convo = chat.current, !convo.messages.isEmpty {
                        ForEach(convo.messages) { message in
                            MessageBubble(message: message, isStreaming: chat.streamingMessageID == message.id)
                                .id(message.id)
                        }
                    } else {
                        welcomeCard
                    }
                    if chat.isStreaming {
                        TypingIndicator()
                            .id("typing")
                    }
                    if let error = chat.lastError {
                        ErrorStateView(
                            title: "Kunde inte svara",
                            message: error,
                            retry: {
                                chat.retryLast(catalog: catalog.products, settings: settings.data)
                            }
                        )
                        .id("error")
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(DS.Space.m)
            }
            .onChange(of: chat.conversations.flatMap(\.messages).count) { _ in
                if atBottom {
                    withAnimation(.easeOut(duration: DS.Motion.content)) {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
            }
            .onChange(of: chat.isStreaming) { streaming in
                if streaming && atBottom {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
        }
    }

    private var welcomeCard: some View {
        VStack(spacing: DS.Space.m) {
            Image(systemName: "bubble.left.and.text.bubble.right.fill")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(DS.Purple.base.opacity(0.8))
            Text("Fråga din coach")
                .font(.system(.headline, design: .rounded))
            Text("Priser, jämförelser, invändningar eller en briefing inför passet – svaret grundas i den verifierade katalogen.")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            VStack(alignment: .leading, spacing: DS.Space.s) {
                ForEach(suggestions, id: \.self) { suggestion in
                    Button {
                        draft = suggestion
                    } label: {
                        Label(suggestion, systemImage: "arrow.up.circle.fill")
                            .font(.system(.subheadline, design: .rounded))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(DS.Space.m)
                            .background(
                                RoundedRectangle(cornerRadius: DS.Radius.tile, style: .continuous)
                                    .fill(DS.Surface.inset)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: DS.Radius.tile, style: .continuous)
                                    .strokeBorder(DS.Surface.hairline, lineWidth: 1)
                            )
                    }
                    .buttonStyle(PressableStyle(scale: 0.98))
                    .foregroundStyle(.primary)
                }
            }
        }
        .card()
        .padding(.top, DS.Space.xl)
    }

    private var suggestions: [String] {
        [
            "Ge mig en briefing inför passet",
            "Hur säljer jag ett dyrare abonnemang utan att pressa kunden?",
            "Vilket abonnemang passar någon som använder 30 GB i månaden?",
            "Kunden tycker Telia är för dyrt – vad säger jag?",
        ]
    }

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: DS.Space.s) {
            TextField("Fråga coachen…", text: $draft, axis: .vertical)
                .lineLimit(1...4)
                .font(.system(.body, design: .rounded))
                .padding(DS.Space.m)
                .background(
                    RoundedRectangle(cornerRadius: DS.Radius.tile, style: .continuous)
                        .fill(DS.Surface.card)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.tile, style: .continuous)
                        .strokeBorder(DS.Surface.hairline, lineWidth: 1)
                )
                .onSubmit(send)

            Button(action: send) {
                Image(systemName: chat.isStreaming ? "stop.circle" : "arrow.up.circle.fill")
                    .font(.system(.title2))
                    .foregroundStyle(draft.trimmingCharacters(in: .whitespaces).isEmpty && !chat.isStreaming ? Color.secondary : DS.Purple.base)
                    .symbolRenderingMode(.hierarchical)
            }
            .buttonStyle(PressableStyle(scale: 0.88))
            .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty && !chat.isStreaming)
            .accessibilityLabel(chat.isStreaming ? "Svarar" : "Skicka")
        }
        .padding(DS.Space.m)
        .background(.regularMaterial)
    }

    private func send() {
        let text = draft
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        draft = ""
        atBottom = true
        chat.send(message: text, catalog: catalog.products, campaigns: campaigns.activeCampaigns, settings: settings.data)
    }
}

// MARK: - Message bubble

struct MessageBubble: View {
    let message: ChatMessage
    let isStreaming: Bool
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.openURL) private var openURL
    @State private var showCitations = false
    @State private var copied = false

    var body: some View {
        VStack(alignment: message.role == .user ? .trailing : .leading, spacing: DS.Space.s) {
            HStack(alignment: .top, spacing: DS.Space.s) {
                if message.role == .assistant {
                    Image(systemName: "sparkles")
                        .font(.caption)
                        .foregroundStyle(DS.Purple.base)
                        .padding(6)
                        .background(Circle().fill(DS.Purple.base.opacity(0.14)))
                        .padding(.top, 4)
                }
                VStack(alignment: .leading, spacing: DS.Space.s) {
                    Text(message.text.isEmpty && isStreaming ? "…" : message.text)
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(message.role == .user ? Color.white : Color.primary)
                        .padding(DS.Space.m)
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(message.role == .user
                                      ? AnyShapeStyle(DS.heroGradient)
                                      : AnyShapeStyle(DS.Surface.card))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .strokeBorder(message.role == .user ? Color.clear : DS.Surface.hairline, lineWidth: 1)
                        )
                        .shadow(color: Color.black.opacity(0.04), radius: 8, y: 3)
                    if message.role == .assistant && !message.citations.isEmpty {
                        citationsToggle
                        if showCitations {
                            citationsList
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                    if message.role == .assistant && !message.isDemo && !message.text.isEmpty && !isStreaming {
                        actionsRow
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
        }
        .accessibilityElement(children: .combine)
    }

    private var citationsToggle: some View {
        Button {
            withAnimation(.easeInOut(duration: DS.Motion.reveal)) { showCitations.toggle() }
        } label: {
            Label(showCitations ? "Dölj produkter" : "\(message.citations.count) produkter hänvisade",
                  systemImage: showCitations ? "chevron.up" : "shippingbox")
                .font(.system(.caption, design: .rounded).weight(.medium))
                .foregroundStyle(DS.Purple.base)
        }
        .buttonStyle(PressableStyle())
    }

    private var citationsList: some View {
        VStack(spacing: DS.Space.s) {
            ForEach(message.citations) { citation in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(citation.productName)
                            .font(.system(.caption, design: .rounded).weight(.semibold))
                        if let price = citation.priceSEK {
                            Text(Format.monthly(price))
                                .font(.system(.caption2, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if let urlString = citation.sourceURL, let url = URL(string: urlString) {
                        Button {
                            openURL(url)
                        } label: {
                            Image(systemName: "safari")
                                .font(.caption)
                        }
                        .buttonStyle(PressableStyle())
                        .accessibilityLabel("Öppna källa")
                    }
                }
                .padding(DS.Space.s)
                .background(
                    RoundedRectangle(cornerRadius: DS.Radius.tile, style: .continuous)
                        .fill(DS.Purple.base.opacity(0.07))
                )
            }
        }
    }

    private var actionsRow: some View {
        HStack(spacing: DS.Space.l) {
            Button {
                UIPasteboard.general.string = message.text
                withAnimation(.easeInOut(duration: 0.2)) { copied = true }
                Haptics.tap()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                    withAnimation(.easeInOut(duration: 0.2)) { copied = false }
                }
            } label: {
                Label(copied ? "Kopierat" : "Kopiera", systemImage: copied ? "checkmark" : "doc.on.doc")
                    .font(.system(.caption, design: .rounded))
            }
            Button {
                library.toggleSavedAnswer(message)
            } label: {
                Label(library.isSaved(message) ? "Sparat" : "Spara",
                      systemImage: library.isSaved(message) ? "bookmark.fill" : "bookmark")
                    .font(.system(.caption, design: .rounded))
            }
            .foregroundStyle(library.isSaved(message) ? DS.Purple.base : Color.secondary)
        }
        .foregroundStyle(Color.secondary)
    }
}

// MARK: - Typing indicator

struct TypingIndicator: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase = false

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(DS.Purple.base.opacity(0.7))
                    .frame(width: 7, height: 7)
                    .offset(y: reduceMotion ? 0 : (phase ? -4 : 2))
                    .animation(
                        reduceMotion ? nil :
                            .easeInOut(duration: 0.45)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.15),
                        value: phase
                    )
            }
        }
        .padding(DS.Space.m)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                .fill(DS.Surface.inset)
        )
        .onAppear { phase = true }
        .accessibilityLabel("Coachen skriver")
    }
}

// MARK: - History

struct ConversationHistoryView: View {
    @EnvironmentObject private var chat: ChatStore
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDeleteAll = false

    var body: some View {
        NavigationStack {
            List {
                if chat.conversations.isEmpty {
                    Text("Inga konversationer ännu.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(chat.conversations) { convo in
                        Button {
                            chat.select(convo.id)
                            dismiss()
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(convo.title)
                                    .font(.system(.subheadline, design: .rounded).weight(.medium))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                Text("\(convo.messages.count) meddelanden · \(Format.relativeDays(convo.updatedAt))")
                                    .font(.system(.caption, design: .rounded))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .onDelete { offsets in
                        for index in offsets { chat.deleteConversation(id: chat.conversations[index].id) }
                    }
                }
            }
            .navigationTitle("Historik")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Stäng") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Radera allt", role: .destructive) {
                        confirmDeleteAll = true
                    }
                    .disabled(chat.conversations.isEmpty)
                }
            }
            .confirmationDialog("Radera alla konversationer?", isPresented: $confirmDeleteAll, titleVisibility: .visible) {
                Button("Radera allt", role: .destructive) {
                    chat.deleteAll()
                }
            } message: {
                Text("Detta kan inte ångras. Konversationerna finns bara i appen.")
            }
        }
    }
}
