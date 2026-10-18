import SwiftUI
import TeliaCore

// MARK: - Playbook

struct PlaybookView: View {
    @EnvironmentObject private var catalog: CatalogStore

    @State private var query = ""

    private var entries: [PlaybookEntry] {
        let all = AppContent.playbook.entries
        let filtered = query.isEmpty ? all : all.filter { entry in
            let haystack = ([entry.title, entry.summary] + entry.guidance).joined(separator: " ").lowercased()
            return query.lowercased()
                .split(separator: " ")
                .contains { haystack.contains($0) }
        }
        return filtered
    }

    private struct PlaybookGroup: Identifiable {
        let section: PlaybookSection
        let entries: [PlaybookEntry]
        var id: String { section.rawValue }
    }

    private var grouped: [PlaybookGroup] {
        PlaybookSection.allCases.compactMap { section in
            let matching = entries.filter { $0.section == section }
            return matching.isEmpty ? nil : PlaybookGroup(section: section, entries: matching)
        }
    }

    var body: some View {
        List {
            ForEach(grouped) { group in
                Section {
                    ForEach(group.entries) { entry in
                        playbookRow(entry)
                    }
                } header: {
                    Label(group.section.displayName, systemImage: group.section.symbolName)
                }
            }
        }
        .searchable(text: $query, prompt: "Sök i säljmanus")
        .navigationDestination(for: String.self) { productID in
            ProductDetailView(productID: productID)
        }
        .scrollContentBackground(.hidden)
        .navigationTitle("Säljmanus")
    }

    private func playbookRow(_ entry: PlaybookEntry) -> some View {
        NavigationLink {
            PlaybookEntryView(entry: entry)
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.title)
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                Text(entry.summary)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }
}

// MARK: - Entry detail

struct PlaybookEntryView: View {
    let entry: PlaybookEntry

    @EnvironmentObject private var catalog: CatalogStore
    @EnvironmentObject private var library: LibraryStore
    @State private var showScriptEditor = false

    var body: some View {
        ScrollView {
            VStack(spacing: DS.Space.m) {
                SectionCard(title: "Sammanfattning", symbol: entry.section.symbolName) {
                    Text(entry.summary)
                        .font(.system(.subheadline, design: .rounded))
                }

                if let objection = entry.objection {
                    objectionCard(objection)
                }

                if !entry.guidance.isEmpty {
                    SectionCard(title: "Så gör du", symbol: "checkmark.seal") {
                        VStack(alignment: .leading, spacing: DS.Space.s) {
                            ForEach(entry.guidance, id: \.self) { line in
                                Label(line, systemImage: "circle.fill")
                                    .labelStyle(ManualBulletStyle())
                                    .font(.system(.subheadline, design: .rounded))
                            }
                        }
                    }
                }

                let related = entry.relatedProductIds.compactMap { catalog.product(id: $0) }
                if !related.isEmpty {
                    SectionCard(title: "Verifierade produkter", symbol: "cart") {
                        VStack(spacing: 0) {
                            ForEach(related) { product in
                                NavigationLink(value: product.id) {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(product.name)
                                                .font(.system(.subheadline, design: .rounded).weight(.medium))
                                                .foregroundStyle(.primary)
                                            Text(Format.monthly(CostCalculator.currentMonthly(product)))
                                                .font(.system(.caption, design: .rounded))
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        VerificationBadge(status: product.verification, freshness: PriceVerification.freshness(of: product))
                                    }
                                    .padding(.vertical, DS.Space.s)
                                }
                                .buttonStyle(PressableStyle(scale: 0.98))
                            }
                        }
                    }
                }

                PrimaryButton(title: "Spara som manus", symbol: "square.and.arrow.down") {
                    showScriptEditor = true
                }
            }
            .padding(DS.Space.m)
        }
        // Transparent so the app-wide premium canvas shows through.
        .navigationTitle(entry.title)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showScriptEditor) {
            ScriptEditorView(script: SavedScript(
                title: entry.title,
                body: ([entry.summary] + entry.guidance).joined(separator: "\n\n"),
                linkedProductId: entry.relatedProductIds.first
            ))
        }
        .navigationDestination(for: String.self) { productID in
            ProductDetailView(productID: productID)
        }
    }

    private func objectionCard(_ objection: ObjectionGuide) -> some View {
        VStack(spacing: DS.Space.m) {
            SectionCard(title: "Vad kunden menar", symbol: "thought.bubble") {
                Text(objection.whatTheyMean)
                    .font(.system(.subheadline, design: .rounded))
            }
            SectionCard(title: "Klargörande fråga", symbol: "questionmark.bubble") {
                Text(objection.clarifyingQuestion)
                    .font(.system(.subheadline, design: .rounded).italic())
            }
            SectionCard(title: "Empatiskt svar", symbol: "heart.text.square") {
                Text("“\(objection.empatheticResponse)”")
                    .font(.system(.subheadline, design: .rounded))
            }
            SectionCard(title: "Nästa steg", symbol: "arrow.right.circle") {
                Text(objection.nextStep)
                    .font(.system(.subheadline, design: .rounded))
            }
            SectionCard(title: "Vanliga misstag", symbol: "exclamationmark.triangle") {
                VStack(alignment: .leading, spacing: DS.Space.s) {
                    ForEach(objection.commonMistakes, id: \.self) { mistake in
                        Label(mistake, systemImage: "xmark")
                            .labelStyle(ManualBulletStyle(color: .red))
                            .font(.system(.subheadline, design: .rounded))
                    }
                }
            }
        }
    }
}

/// Bullet-style label rendering without the default icon sizing.
struct ManualBulletStyle: LabelStyle {
    var color: Color = DS.Purple.base

    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .top, spacing: DS.Space.s) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
                .padding(.top, 6)
            configuration.title
        }
    }
}

// MARK: - Script editor

struct ScriptEditorView: View {
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.dismiss) private var dismiss

    @State var script: SavedScript
    @State private var confirmDelete = false

    init(script: SavedScript) {
        _script = State(initialValue: script)
    }

    private var isNew: Bool {
        !library.data.scripts.contains { $0.id == script.id }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Titel") {
                    TextField("Titel", text: $script.title)
                }
                Section("Manus") {
                    TextEditor(text: $script.body)
                        .frame(minHeight: 220)
                        .font(.system(.subheadline, design: .rounded))
                }
                Section {
                    Button(role: .destructive) {
                        confirmDelete = true
                    } label: {
                        Label("Radera manuset", systemImage: "trash")
                    }
                    .disabled(isNew)
                }
            }
            .navigationTitle(isNew ? "Nytt manus" : "Redigera manus")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Avbryt") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Spara") {
                        var toSave = script
                        toSave.updatedAt = Date()
                        library.upsert(script: toSave)
                        dismiss()
                    }
                    .disabled(script.title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .confirmationDialog("Radera manuset?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Radera", role: .destructive) {
                    library.deleteScript(id: script.id)
                    dismiss()
                }
            }
        }
    }
}
