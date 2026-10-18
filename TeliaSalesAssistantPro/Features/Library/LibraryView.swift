import SwiftUI
import TeliaCore

struct LibraryView: View {
    @EnvironmentObject private var catalog: CatalogStore
    @EnvironmentObject private var library: LibraryStore

    @State private var section: LibSection = .favorites
    @State private var scriptEditor: ScriptEditorPayload?
    @State private var noteEditor: PersonalNote?
    @State private var showNewNote = false

    enum LibSection: String, CaseIterable, Identifiable {
        case favorites = "Favoriter"
        case recents = "Senast visade"
        case scripts = "Manus"
        case notes = "Anteckningar"
        case saved = "Sparade svar"
        case glossary = "Ordlista"
        case sources = "Källor"
        var id: String { rawValue }
    }

    var body: some View {
        List {
            Section {
                Picker("Avdelning", selection: $section) {
                    ForEach(LibSection.allCases) { s in
                        Text(s.rawValue).tag(s)
                    }
                }
                .pickerStyle(.menu)
                .listRowBackground(Color.clear)
            }
            Section {
                content
            }
        }
        .scrollContentBackground(.hidden)
        .navigationTitle("Bibliotek")
        .sheet(item: $scriptEditor) { payload in
            ScriptEditorView(script: payload.script)
        }
        .sheet(isPresented: $showNewNote) {
            NoteEditorView(note: nil)
        }
        .sheet(item: $noteEditor) { note in
            NoteEditorView(note: note)
        }
        .navigationDestination(for: String.self) { productID in
            ProductDetailView(productID: productID)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch section {
        case .favorites: favoritesList
        case .recents: recentsList
        case .scripts: scriptsList
        case .notes: notesList
        case .saved: savedList
        case .glossary: GlossaryView()
        case .sources: SourcesView()
        }
    }

    private var favoritesList: some View {
        let favorites = catalog.products.filter { library.isFavorite($0.id) }
        return Group {
            if favorites.isEmpty {
                Text("Inga favoriter än. Tryck på hjärtat på en produkt för att spara den här.")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(favorites) { product in
                    NavigationLink(value: product.id) {
                        ProductRow(product: product, isFavorite: true)
                    }
                }
            }
        }
    }

    private var recentsList: some View {
        Group {
            if library.data.recentProductIDs.isEmpty {
                Text("Produkter du öppnar hamnar här.")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(library.data.recentProductIDs) { recent in
                    if let product = catalog.product(id: recent.id) {
                        NavigationLink(value: product.id) {
                            HStack {
                                Text(product.name)
                                    .font(.system(.subheadline, design: .rounded))
                                    .foregroundStyle(.primary)
                                Spacer()
                                Text(Format.relativeDays(recent.viewedAt))
                                    .font(.system(.caption, design: .rounded))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }

    private var scriptsList: some View {
        Group {
            if library.data.scripts.isEmpty {
                Text("Spara manus från Säljmanus eller skriv egna.")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(library.data.scripts) { script in
                    Button {
                        scriptEditor = ScriptEditorPayload(script: script)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(script.title)
                                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                                .foregroundStyle(.primary)
                            Text(Format.relativeDays(script.updatedAt))
                                .font(.system(.caption, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete { offsets in
                    for index in offsets { library.deleteScript(id: library.data.scripts[index].id) }
                }
            }
            Button {
                scriptEditor = ScriptEditorPayload(script: SavedScript(title: "", body: ""))
            } label: {
                Label("Nytt manus", systemImage: "plus.circle.fill")
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(DS.Purple.base)
            }
        }
    }

    private var notesList: some View {
        Group {
            if library.data.notes.isEmpty {
                Text("Personliga träningsanteckningar – bara i din telefon.")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(library.data.notes) { note in
                    Button {
                        noteEditor = note
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(note.title)
                                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                                .foregroundStyle(.primary)
                            Text(note.body)
                                .font(.system(.caption, design: .rounded))
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                }
                .onDelete { offsets in
                    for index in offsets { library.deleteNote(id: library.data.notes[index].id) }
                }
            }
            Button {
                showNewNote = true
            } label: {
                Label("Ny anteckning", systemImage: "plus.circle.fill")
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(DS.Purple.base)
            }
        }
    }

    private var savedList: some View {
        Group {
            if library.data.savedAnswers.isEmpty {
                Text("Spara coachens svar med bokmärkesknappen i chatten.")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(library.data.savedAnswers) { message in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(message.text)
                            .font(.system(.subheadline, design: .rounded))
                        Text(Format.relativeDays(message.date))
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }
}

struct ScriptEditorPayload: Identifiable {
    let script: SavedScript
    var id: UUID { script.id }
}

// MARK: - Note editor

struct NoteEditorView: View {
    let note: PersonalNote?

    @EnvironmentObject private var library: LibraryStore
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var body_ = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Titel", text: $title)
                Section("Anteckning") {
                    TextEditor(text: $body_)
                        .frame(minHeight: 180)
                        .font(.system(.subheadline, design: .rounded))
                }
            }
            .navigationTitle(note == nil ? "Ny anteckning" : "Redigera")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Avbryt") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Spara") {
                        library.upsert(note: PersonalNote(
                            id: note?.id ?? UUID(),
                            title: title,
                            body: body_,
                            updatedAt: Date()
                        ))
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                if let note {
                    title = note.title
                    body_ = note.body
                }
            }
        }
    }
}

// MARK: - Glossary

struct GlossaryView: View {
    @State private var query = ""

    private var terms: [GlossaryTerm] {
        let all = AppContent.learning.glossary
        guard !query.isEmpty else { return all }
        return all.filter {
            $0.term.lowercased().contains(query.lowercased())
                || $0.definition.lowercased().contains(query.lowercased())
        }
    }

    var body: some View {
        VStack(spacing: DS.Space.m) {
            HStack(spacing: DS.Space.s) {
                Image(systemName: "magnifyingglass")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(.secondary)
                TextField("Sök i ordlistan", text: $query)
                    .font(.system(.subheadline, design: .rounded))
                    .autocorrectionDisabled()
                if !query.isEmpty {
                    Button {
                        query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(PressableStyle())
                    .accessibilityLabel("Rensa sökning")
                }
            }
            .padding(DS.Space.m)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.tile, style: .continuous)
                    .fill(Color(.tertiarySystemFill))
            )

            if terms.isEmpty {
                Text(query.isEmpty ? "Ordlistan är tom." : "Inga träffar på \(query).")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(terms) { term in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(term.term)
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        Text(term.definition)
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }
}

// MARK: - Sources

struct SourcesView: View {
    @EnvironmentObject private var catalog: CatalogStore
    @Environment(\.openURL) private var openURL

    private var sourceLinks: [(String, String)] {
        var seen = Set<String>()
        var links: [(String, String)] = []
        for product in catalog.products {
            guard let url = product.sourceURL, !seen.contains(url) else { continue }
            seen.insert(url)
            links.append((product.sourceName ?? product.name, url))
        }
        return links
    }

    var body: some View {
        Group {
            ForEach(sourceLinks, id: \.1) { name, url in
                Button {
                    if let link = URL(string: url) { openURL(link) }
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(name)
                                .font(.system(.subheadline, design: .rounded).weight(.medium))
                                .foregroundStyle(.primary)
                            Text(url)
                                .font(.system(.caption2, design: .rounded))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Image(systemName: "safari")
                            .font(.caption)
                            .foregroundStyle(DS.Purple.base)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Senast kontrollerad: \(catalog.lastUpdated.map { Format.dateTime.string(from: $0) } ?? "aldrig")")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
                Text(catalog.data.snapshot?.sourceNote ?? "")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
    }
}
