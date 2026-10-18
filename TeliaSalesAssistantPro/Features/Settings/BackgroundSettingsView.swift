import SwiftUI
import PhotosUI
import TeliaCore

// MARK: - Background settings

struct BackgroundSettingsView: View {
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var photoItem: PhotosPickerItem?
    @State private var importError: String?

    private var preference: BackgroundPreference { settings.data.background }

    var body: some View {
        List {
            Section {
                preview
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            } footer: {
                Text("Förhandsgranskningen visar hur bakgrunden ligger bakom appens riktiga kort. Ändringen gäller direkt i hela appen.")
            }

            presetSection

            Section {
                ColorPicker("Solid färg", selection: solidBinding, supportsOpacity: false)
            } header: {
                Text("Egen färg")
            } footer: {
                Text("Väljer du en egen färg används den som lugn, enfärgad bakgrund.")
            }

            photoSection

            adjustSection

            resetSection
        }
        .navigationTitle("Bakgrund")
        .navigationBarTitleDisplayMode(.inline)
        .scrollContentBackground(.hidden)
    }

    // MARK: Preview

    /// A miniature of the real UI so the effect is judged behind genuine cards.
    private var preview: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            HStack {
                Image(systemName: "tag.fill")
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(DS.heroGradient, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Så ser korten ut")
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    Text("Läsbarhet behålls genom att korten ligger på egna ytor")
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(DS.Space.m)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                    .fill(DS.Surface.inset)
            )
            Text("Made by Kevork Khagadurian")
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(.secondary)
                .padding(.top, 2)
        }
        .padding(DS.Space.m)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.card + 4, style: .continuous)
                .fill(Color(.systemGroupedBackground).opacity(0.5))
        )
        .padding(DS.Space.s)
    }

    // MARK: Presets

    private var presetSection: some View {
        Section("Förinställda bakgrunder") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: DS.Space.s)], spacing: DS.Space.s) {
                presetButton(id: nil, name: "Standard", colors: ["systemBackground"])
                ForEach(BackgroundPresets.all) { preset in
                    presetButton(id: preset.id, name: preset.name, colors: preset.colors)
                }
            }
            .padding(.vertical, 4)
            .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
        }
    }

    private func presetButton(id: String?, name: String, colors: [String]) -> some View {
        Button {
            setPreference { p in
                if let id {
                    p.kind = .preset
                    p.presetID = id
                } else {
                    p.kind = .systemDefault
                    p.presetID = nil
                }
            }
        } label: {
            VStack(spacing: 6) {
                swatch(colors: colors, active: isActive(presetID: id))
                    .frame(height: 56)
                Text(name)
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Bakgrund: \(name)")
    }

    private func isActive(presetID: String?) -> Bool {
        presetID == nil ? preference.kind == .systemDefault
                        : preference.kind == .preset && preference.presetID == presetID
    }

    @ViewBuilder
    private func swatch(colors: [String], active: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        if colors == ["systemBackground"] {
            ZStack {
                Color(.systemBackground)
                LinearGradient(
                    colors: [DS.Purple.light.opacity(0.22), DS.Purple.deep.opacity(0.14)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
            }
            .clipShape(shape)
            .overlay(shape.strokeBorder(active ? DS.Purple.base : .clear, lineWidth: 2))
        } else {
            gradient(for: colors)
                .clipShape(shape)
                .overlay(shape.strokeBorder(active ? DS.Purple.base : .clear, lineWidth: 2))
        }
    }

    private func gradient(for hexes: [String]) -> some View {
        LinearGradient(
            colors: hexes.compactMap { Color(hex: $0) },
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    }

    // MARK: Photo

    private var photoSection: some View {
        Section {
            PhotosPicker(selection: $photoItem, matching: .images) {
                Label("Välj bild från bilder", systemImage: "photo.on.rectangle.angled")
            }
            if preference.kind == .photo, let fileName = preference.fileName {
                if let image = BackgroundStore.loadPhoto(fileName: fileName) {
                    HStack {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 56, height: 56)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .blur(radius: preference.blur * 8)
                        Text("Nuvarande bild")
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Label("Bilden kunde inte läsas – välj en ny", systemImage: "exclamationmark.triangle")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(DS.warning)
                }
            }
            if let importError {
                Text(importError)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(DS.negative)
            }
        } header: {
            Text("Egen bild")
        } footer: {
            Text("Bilden kopieras till appens egna lagring och lämnar aldrig enheten. Ingen behörighet till hela bildbiblioteket begärs – du väljer en enskild bild. För stora bilder skalas ned automatiskt.")
        }
        .onChange(of: photoItem) { item in
            guard let item else { return }
            Task {
                do {
                    guard let data = try await item.loadTransferable(type: Data.self) else {
                        throw BackgroundImportError.notAnImage
                    }
                    let fileName = try BackgroundStore.importPhoto(data)
                    let oldFile = settings.data.background.fileName
                    setPreference { p in
                        p.kind = .photo
                        p.fileName = fileName
                    }
                    if let oldFile, oldFile != fileName {
                        BackgroundStore.deletePhoto(fileName: oldFile)
                    }
                    importError = nil
                } catch {
                    importError = (error as? LocalizedError)?.errorDescription ?? "Bilden kunde inte importeras."
                }
            }
        }
    }

    // MARK: Adjustments

    private var adjustSection: some View {
        Section {
            if preference.kind == .photo {
                VStack(alignment: .leading, spacing: 6) {
                    LabeledContent("Oskärpa") {
                        Text("\(Int(preference.blur * 100)) %")
                            .foregroundStyle(.secondary)
                            .font(.system(.caption, design: .rounded))
                    }
                    Slider(value: blurBinding, in: 0...1)
                        .accessibilityLabel("Oskärpa")
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                LabeledContent("Intensitet") {
                    Text("\(Int(preference.intensity * 100)) %")
                        .foregroundStyle(.secondary)
                        .font(.system(.caption, design: .rounded))
                }
                Slider(value: intensityBinding, in: 0...1)
                    .accessibilityLabel("Intensitet")
            }
        } header: {
            Text("Justering")
        } footer: {
            Text(preference.kind == .photo
                 ? "Oskärpa gör bilden mjukare bakom innehållet. Intensitet sänker bakgrunden mot appens standardfärg – använd den om texten känns svår att läsa."
                 : "Intensitet sänker bakgrunden mot appens standardfärg – använd den om texten känns svår att läsa.")
        }
    }

    private var resetSection: some View {
        Section {
            Button(role: .destructive) {
                let oldFile = settings.data.background.fileName
                setPreference { p in
                    p = BackgroundPreference.default
                }
                if let oldFile {
                    BackgroundStore.deletePhoto(fileName: oldFile)
                }
            } label: {
                Label("Återställ till standard", systemImage: "arrow.counterclockwise")
            }
        } footer: {
            Text("Återställ tar bort den importerade bilden ur appens lagring och återgår till standardbakgrunden.")
        }
    }

    // MARK: Bindings

    private var blurBinding: Binding<Double> {
        Binding(
            get: { settings.data.background.blur },
            set: { value in setPreference { $0.blur = value } }
        )
    }

    private var intensityBinding: Binding<Double> {
        Binding(
            get: { settings.data.background.intensity },
            set: { value in setPreference { $0.intensity = value } }
        )
    }

    private var solidBinding: Binding<Color> {
        Binding(
            get: {
                Color(hex: settings.data.background.hex ?? "") ?? DS.Purple.base
            },
            set: { color in
                if let hex = hexString(from: color) {
                    setPreference { $0.kind = .solid; $0.hex = hex }
                }
            }
        )
    }

    private func hexString(from color: Color) -> String? {
        let ui = UIColor(color)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        guard a > 0.99 else { return nil } // no opacity in hex
        return String(format: "%02lX%02lX%02lX",
                      lround(Double(r) * 255),
                      lround(Double(g) * 255),
                      lround(Double(b) * 255))
    }

    /// One mutation point so every change animates consistently and persists.
    private func setPreference(_ mutate: (inout BackgroundPreference) -> Void) {
        var preference = settings.data.background
        mutate(&preference)
        preference.blur = preference.blur.clampedToUnit()
        preference.intensity = preference.intensity.clampedToUnit()
        settings.data.background = preference
    }
}
