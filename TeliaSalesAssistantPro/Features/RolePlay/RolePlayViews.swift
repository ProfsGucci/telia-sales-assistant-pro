import SwiftUI
import TeliaCore

// MARK: - Home

struct RolePlayHomeView: View {
    @State private var difficulty: RolePlayDifficulty = .medium
    @State private var category: String = "Alla"

    private var categories: [String] {
        ["Alla"] + Array(Set(RolePlayCatalog.scenarios.map(\.category))).sorted()
    }

    private var scenarios: [RolePlayScenario] {
        category == "Alla"
            ? RolePlayCatalog.scenarios
            : RolePlayCatalog.scenarios.filter { $0.category == category }
    }

    var body: some View {
        List {
            Section {
                Picker("Svårighetsgrad", selection: $difficulty) {
                    ForEach(RolePlayDifficulty.allCases, id: \.self) { level in
                        Text(level.label).tag(level)
                    }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
            }
            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: DS.Space.s) {
                        ForEach(categories, id: \.self) { cat in
                            Button {
                                withAnimation(.easeInOut(duration: DS.Motion.reveal)) { category = cat }
                            } label: {
                                Chip(text: cat, color: DS.Purple.base, filled: category == cat)
                            }
                            .buttonStyle(PressableStyle())
                        }
                    }
                }
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 4, leading: DS.Space.m, bottom: 4, trailing: DS.Space.m))
            }
            Section {
                ForEach(scenarios) { scenario in
                    NavigationLink {
                        RolePlaySessionView(scenario: scenario, difficulty: difficulty)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(scenario.title)
                                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            Text(scenario.difficultyHint)
                                .font(.system(.caption, design: .rounded))
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                            Chip(text: scenario.category, color: DS.Purple.base)
                        }
                        .padding(.vertical, 2)
                    }
                }
            } header: {
                Text("Scenarier (\(scenarios.count))")
            }
        }
        .navigationTitle("Rollspel")
    }
}

// MARK: - Session

struct RolePlaySessionView: View {
    let scenario: RolePlayScenario
    let difficulty: RolePlayDifficulty

    @EnvironmentObject private var catalog: CatalogStore
    @State private var session: RolePlaySession?
    @State private var draft = ""
    @State private var result: RolePlayResult?
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            if let session {
                transcript(session)
                if result == nil {
                    inputBar
                }
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(scenario.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if session != nil && result == nil {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Avsluta") { scoreSession() }
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                }
            }
        }
        .onAppear {
            if session == nil {
                session = RolePlaySession(scenario: scenario, difficulty: difficulty, catalog: catalog.products)
            }
        }
        .sheet(item: $result) { result in
            RolePlayResultView(result: result, scenario: scenario)
        }
    }

    private func transcript(_ session: RolePlaySession) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: DS.Space.m) {
                    infoCard
                    ForEach(session.turns) { turn in
                        HStack(alignment: .top, spacing: DS.Space.s) {
                            if turn.isCustomer {
                                Image(systemName: "person.crop.circle.fill")
                                    .font(.system(.title2))
                                    .foregroundStyle(.secondary)
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                Text(turn.isCustomer ? scenario.persona.name : "Du")
                                    .font(.system(.caption2, design: .rounded).weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Text(turn.text)
                                    .font(.system(.subheadline, design: .rounded))
                                    .padding(DS.Space.m)
                                    .background(
                                        RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                                            .fill(turn.isCustomer
                                                  ? AnyShapeStyle(Color(.secondarySystemGroupedBackground))
                                                  : AnyShapeStyle(DS.heroGradient))
                                    )
                                    .foregroundStyle(turn.isCustomer ? Color.primary : Color.white)
                            }
                            Spacer(minLength: 0)
                        }
                        .frame(maxWidth: .infinity, alignment: turn.isCustomer ? .leading : .trailing)
                        .id(turn.id)
                    }
                    Color.clear.frame(height: 1).id("rp-bottom")
                }
                .padding(DS.Space.m)
            }
            .onChange(of: session.turns.count) { _ in
                withAnimation(.easeOut(duration: DS.Motion.content)) {
                    proxy.scrollTo("rp-bottom", anchor: .bottom)
                }
            }
        }
    }

    private var infoCard: some View {
        SectionCard(title: "Scenario", symbol: "theatermasks.fill") {
            VStack(alignment: .leading, spacing: DS.Space.s) {
                Text("Du möter \(scenario.persona.name), \(scenario.persona.age) år.")
                    .font(.system(.subheadline, design: .rounded))
                Text("Kunden avslöjar bara det du frågar efter. Ställ öppna frågor, lyssna, och avsluta när behovet är klart.")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
                if !scenario.persona.constraints.isEmpty {
                    Label("Kundens begränsningar upptäcker du under samtalet", systemImage: "lock")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: DS.Space.s) {
            TextField("Svara kunden…", text: $draft, axis: .vertical)
                .lineLimit(1...4)
                .font(.system(.body, design: .rounded))
                .focused($inputFocused)
                .padding(DS.Space.m)
                .background(
                    RoundedRectangle(cornerRadius: DS.Radius.tile, style: .continuous)
                        .fill(Color(.secondarySystemGroupedBackground))
                )
                .onSubmit(send)
            Button(action: send) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(.title2))
                    .foregroundStyle(draft.trimmingCharacters(in: .whitespaces).isEmpty ? Color.secondary : DS.Purple.base)
            }
            .buttonStyle(PressableStyle(scale: 0.88))
            .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(DS.Space.m)
        .background(.regularMaterial)
    }

    private func send() {
        guard let session, !draft.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        let text = draft
        draft = ""
        session.sellerMessage(text)
        // Customer responds after a beat so the exchange feels like a conversation.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            _ = session.customerReply()
        }
    }

    private func scoreSession() {
        guard let session else { return }
        let scoring = RolePlayScorer.score(session)
        Haptics.success()
        result = scoring
    }
}

// MARK: - Result

struct RolePlayResultView: View {
    let result: RolePlayResult
    let scenario: RolePlayScenario

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var revealed = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: DS.Space.m) {
                    totalCard
                    ForEach(result.scores) { score in
                        scoreCard(score)
                    }
                    if !result.redFlags.isEmpty {
                        SectionCard(title: "Varningar", symbol: "exclamationmark.triangle.fill") {
                            VStack(alignment: .leading, spacing: DS.Space.s) {
                                ForEach(result.redFlags, id: \.self) { flag in
                                    Label(flag, systemImage: "xmark.octagon")
                                        .labelStyle(ManualBulletStyle(color: .red))
                                        .font(.system(.subheadline, design: .rounded))
                                }
                            }
                        }
                    }
                    if !result.strengths.isEmpty {
                        SectionCard(title: "Styrkor", symbol: "checkmark.seal.fill") {
                            VStack(alignment: .leading, spacing: DS.Space.s) {
                                ForEach(result.strengths, id: \.self) { strength in
                                    Label(strength, systemImage: "hand.thumbsup")
                                        .labelStyle(ManualBulletStyle(color: .green))
                                        .font(.system(.subheadline, design: .rounded))
                                }
                            }
                        }
                    }
                    SectionCard(title: "Förslag på formuleringar", symbol: "text.quote") {
                        VStack(alignment: .leading, spacing: DS.Space.s) {
                            ForEach(result.alternativePhrases, id: \.self) { phrase in
                                Text(phrase)
                                    .font(.system(.subheadline, design: .rounded).italic())
                            }
                        }
                    }
                    PrimaryButton(title: "Klar", symbol: "checkmark") {
                        dismiss()
                    }
                }
                .padding(DS.Space.m)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Utvärdering")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                // Animate score reveals once; instant under Reduce Motion.
                guard !reduceMotion else { return }
                withAnimation(.spring(response: 0.5, dampingFraction: 0.85).delay(0.1)) {
                    revealed = true
                }
            }
        }
    }

    private var totalCard: some View {
        SectionCard(title: "Totalpoäng", symbol: "star.circle.fill", gradient: true) {
            VStack(spacing: DS.Space.s) {
                Text("\(result.total) / \(result.maxTotal)")
                    .font(.system(.largeTitle, design: .rounded).weight(.bold))
                ProgressBar(
                    progress: result.maxTotal > 0 ? Double(result.total) / Double(result.maxTotal) : 0,
                    color: DS.Purple.base,
                    height: 10
                )
                Text(fitLabel)
                    .font(.system(.subheadline, design: .rounded))
            }
        }
    }

    private var fitLabel: String {
        switch result.fit {
        case .good: return "Rekommendationen matchade kundens behov – bra jobbat."
        case .okay: return "Rekommendationen var nära, men inte perfekt anpassad."
        case .poor: return "Rekommendationen utanför kundens behov eller budget."
        }
    }

    private func scoreCard(_ score: RolePlayScore) -> some View {
        SectionCard(title: score.dimension, symbol: "chart.bar.fill") {
            VStack(alignment: .leading, spacing: DS.Space.s) {
                HStack {
                    ProgressBar(
                        progress: revealed || reduceMotion ? Double(score.score) / 5.0 : 0,
                        color: score.score >= 4 ? .green : (score.score <= 2 ? .orange : DS.Purple.base),
                        height: 8
                    )
                    Text("\(score.score)/5")
                        .font(.system(.subheadline, design: .rounded).weight(.bold))
                        .frame(width: 40, alignment: .trailing)
                }
                Text(score.feedback)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
    }
}
