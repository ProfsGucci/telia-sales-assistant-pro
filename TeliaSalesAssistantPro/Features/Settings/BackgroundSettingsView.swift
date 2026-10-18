import SwiftUI
import PhotosUI
import TeliaCore

// MARK: - Background Studio (Settings → Bakgrund)

/// DS 2.2 (Update 1.3) — "Bakgrundsstudio".
///
/// Reliability contract:
/// - The preview renders through the exact same `BackgroundSurface` the app
///   uses, so preview == applied, always.
/// - Photo flow is pending→Apply/Cancel: the imported file is written first,
///   the preference is only changed on Apply, and Cancel deletes the pending
///   file. The active background is never deleted before a valid replacement
///   is in place.
/// - Every change persists immediately (SettingsStore saves on didSet); no
///   Apply needed for presets/solids/adjustments.
struct BackgroundSettingsView: View {
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Photo import state
    @State private var pickerItem: PhotosPickerItem?
    @State private var pendingPhoto: PendingPhoto?
    @State private var isImporting = false
    @State private var importError: String?
    @State private var failedData: Data?

    struct PendingPhoto: Identifiable {
        let id = UUID()
        let fileName: String
        let image: UIImage
    }

    private var preference: BackgroundPreference { settings.data.background }

    /// What the preview shows: the pending photo if one is being evaluated,
    /// otherwise the saved preference.
    private var previewPreference: BackgroundPreference {
        if let pending = pendingPhoto {
            var p = preference
            p.kind = .photo
            p.fileName = pending.fileName
            return p
        }
        return preference
    }

    var body: some View {
        List {
            Section {
                preview
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            } footer: {
                Text(pendingPhoto == nil
                     ? "Förhandsgranskningen visar hur bakgrunden ligger bakom appens riktiga kort. Ändringar förutom egna bilder gäller direkt i hela appen."
                     : "Granska den nya bilden och välj Använd för att aktivera den, eller Avbryt för att behålla nuvarande bakgrund.")
            }

            presetSection
            solidSection
            photoSection
            adjustSection
            resetSection
        }
        .navigationTitle("Bakgrundsstudio")
        .navigationBarTitleDisplayMode(.inline)
        .scrollContentBackground(.hidden)
    }

    // MARK: Live preview (shared renderer — identical to the applied result)

    private var preview: some View {
        BackgroundSurface(preference: previewPreference)
            .frame(height: 210)
            .overlay(
                VStack(alignment: .leading, spacing: DS.Space.s) {
                    HStack {
                        Image(systemName: "sparkles")
                            .foregroundStyle(.white)
                            .frame(width: 34, height: 34)
                            .background(DS.heroGradient, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Så ser korten ut")
                                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            Text("Korten ligger på egna ytor – läsbarheten behålls")
                                .font(.system(.caption2, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(DS.Space.m)
                    .background(
                        RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                            .fill(DS.Surface.card)
                    )
                    Text("Made by Kevork Khagadurian")
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                }
                .padding(DS.Space.m)
            )
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card + 4, style: .continuous))
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
        .buttonStyle(GlossPressStyle())
        .accessibilityLabel("Bakgrund: \(name)")
        .accessibilityAddTraits(isActive(presetID: id) ? .isSelected : [])
    }

    private func isActive(presetID: String?) -> Bool {
        presetID == nil ? preference.kind == .systemDefault
                        : preference.kind == .preset && preference.presetID == presetID
    }

    @ViewBuilder
    private func swatch(colors: [String], active: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        ZStack {
            if colors == ["systemBackground"] {
                Color(.systemBackground)
                LinearGradient(
                    colors: [DS.Purple.light.opacity(0.22), DS.Purple.deep.opacity(0.14)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
            } else {
                LinearGradient(
                    colors: colors.compactMap { Color(hex: $0) },
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
            }
            if active {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .shadow(radius: 3)
            }
        }
        .clipShape(shape)
        .glossSelection(active, cornerRadius: 12)
    }

    // MARK: Solids

    /// Curated solid colors (DS 2.2): calm neutrals plus restrained accents.
    private static let solidSwatches: [(name: String, hex: String)] = [
        ("Kol", "1A1A1E"),
        ("Grafit", "2E2E38"),
        ("Varm vit", "F1EBE2"),
        ("Silver", "D9DDE3"),
        ("Djupblå", "0E3A5D"),
        ("Telia lila", "7538DB"),
        ("Telia orange", "F2732E"),
        ("Svart", "000000"),
    ]

    private var solidSection: some View {
        Section {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 64), spacing: DS.Space.s)], spacing: DS.Space.s) {
                ForEach(Self.solidSwatches, id: \.hex) { swatch in
                    solidButton(name: swatch.name, hex: swatch.hex)
                }
            }
            .padding(.vertical, 4)
            .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))

            ColorPicker("Egen färg", selection: solidBinding, supportsOpacity: false)
        } header: {
            Text("Enfärgad")
        } footer: {
            Text("Välj en kuraterad färg eller din egen med färgväljaren. Färgen används direkt.")
        }
    }

    private func solidButton(name: String, hex: String) -> some View {
        let active = preference.kind == .solid && preference.hex?.uppercased() == hex
        return Button {
            setPreference { p in
                p.kind = .solid
                p.hex = hex
            }
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(hex: hex) ?? .clear)
                    if active {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(hex == "F1EBE2" || hex == "D9DDE3" ? .black : .white)
                            .shadow(radius: 3)
                    }
                }
                .glossSelection(active, cornerRadius: 12)
                .frame(height: 48)
                Text(name)
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
        }
        .buttonStyle(GlossPressStyle())
        .accessibilityLabel("Färg: \(name)")
        .accessibilityAddTraits(active ? .isSelected : [])
    }

    // MARK: Photo (pending → Apply/Cancel)

    private var photoSection: some View {
        Section {
            if pendingPhoto == nil {
                PhotosPicker(selection: $pickerItem, matching: .images) {
                    Label(preference.kind == .photo ? "Ersätt bild" : "Välj bild från Bilder",
                          systemImage: "photo.on.rectangle.angled")
                }
                .disabled(isImporting)
            }

            if isImporting {
                HStack(spacing: DS.Space.s) {
                    ProgressView()
                    Text("Importerar och optimerar bild…")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }

            if let pending = pendingPhoto {
                VStack(alignment: .leading, spacing: DS.Space.s) {
                    HStack(spacing: DS.Space.m) {
                        Image(uiImage: pending.image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 64, height: 64)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Ny bild – granska i förhandsgranskningen")
                                .font(.system(.subheadline, design: .rounded).weight(.medium))
                            Text("Aktiveras först när du väljer Använd")
                                .font(.system(.caption2, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                    }
                    HStack(spacing: DS.Space.s) {
                        Button {
                            applyPendingPhoto()
                        } label: {
                            Label("Använd", systemImage: "checkmark")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(DS.Purple.base)
                        .accessibilityLabel("Använd nya bakgrundsbilden")

                        Button(role: .destructive) {
                            cancelPendingPhoto()
                        } label: {
                            Label("Avbryt", systemImage: "xmark")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityLabel("Avbryt och behåll nuvarande bakgrund")
                    }
                }
                .padding(.vertical, 4)
            } else if preference.kind == .photo, let fileName = preference.fileName {
                if let image = BackgroundStore.loadPhoto(fileName: fileName) {
                    HStack {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 56, height: 56)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Nuvarande bild")
                                .font(.system(.subheadline, design: .rounded).weight(.medium))
                            Text("Sparad i appens egna lagring")
                                .font(.system(.caption2, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Label("Bilden kunde inte läsas – välj en ny eller återställ", systemImage: "exclamationmark.triangle")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(DS.warning)
                }
            }

            if preference.kind == .photo && pendingPhoto == nil {
                Button(role: .destructive) {
                    removePhoto()
                } label: {
                    Label("Ta bort bild", systemImage: "trash")
                }
            }

            if let importError {
                VStack(alignment: .leading, spacing: DS.Space.xs) {
                    Label(importError, systemImage: "exclamationmark.triangle")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(DS.negative)
                    if failedData != nil {
                        Button {
                            retryImport()
                        } label: {
                            Label("Försök igen", systemImage: "arrow.clockwise")
                                .font(.system(.caption, design: .rounded).weight(.medium))
                        }
                    }
                }
            }
        } header: {
            Text("Egen bild")
        } footer: {
            Text("Bilden kopieras till appens egna lagring och lämnar aldrig enheten. Ingen behörighet till bildbiblioteket begärs – du väljer en enskild bild. Stora bilder skalas ned automatiskt.")
        }
        .onChange(of: pickerItem) { item in
            guard let item else { return }
            importPicked(item)
        }
    }

    private func importPicked(_ item: PhotosPickerItem) {
        isImporting = true
        importError = nil
        Task {
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    throw BackgroundImportError.notAnImage
                }
                let fileName = try BackgroundStore.importPhoto(data)
                guard let image = BackgroundStore.loadPhoto(fileName: fileName) else {
                    throw BackgroundImportError.notAnImage
                }
                pendingPhoto = PendingPhoto(fileName: fileName, image: image)
                failedData = nil
            } catch {
                // Keep the raw data (if we got that far) so Försök igen can
                // re-attempt the import without another picker round-trip.
                if let d = try? await item.loadTransferable(type: Data.self) {
                    failedData = d
                }
                importError = (error as? LocalizedError)?.errorDescription ?? "Bilden kunde inte importeras."
            }
            isImporting = false
            pickerItem = nil
        }
    }

    private func retryImport() {
        guard let data = failedData else { return }
        isImporting = true
        importError = nil
        Task { @MainActor in
            do {
                let fileName = try BackgroundStore.importPhoto(data)
                guard let image = BackgroundStore.loadPhoto(fileName: fileName) else {
                    throw BackgroundImportError.notAnImage
                }
                pendingPhoto = PendingPhoto(fileName: fileName, image: image)
                failedData = nil
            } catch {
                importError = (error as? LocalizedError)?.errorDescription ?? "Bilden kunde inte importeras."
            }
            isImporting = false
        }
    }

    /// Commit order (never delete the active image first):
    /// file already written → switch preference → delete superseded file.
    private func applyPendingPhoto() {
        guard let pending = pendingPhoto else { return }
        let oldFile = settings.data.background.fileName
        setPreference { p in
            p.kind = .photo
            p.fileName = pending.fileName
        }
        if let oldFile, oldFile != pending.fileName {
            BackgroundStore.deletePhoto(fileName: oldFile)
        }
        pendingPhoto = nil
    }

    /// Cancel: the pending file is not referenced by any preference yet, so it
    /// is safe to delete it and keep the current background untouched.
    private func cancelPendingPhoto() {
        if let pending = pendingPhoto {
            BackgroundStore.deletePhoto(fileName: pending.fileName)
        }
        pendingPhoto = nil
    }

    private func removePhoto() {
        let oldFile = settings.data.background.fileName
        setPreference { p in
            p = BackgroundPreference.default
        }
        if let oldFile {
            BackgroundStore.deletePhoto(fileName: oldFile)
        }
    }

    // MARK: Adjustments

    private var adjustSection: some View {
        Section {
            if preference.kind == .photo {
                Picker("Anpassning", selection: fitBinding) {
                    Text("Fyll (beskär)").tag(BackgroundPreference.PhotoFit.fill)
                    Text("Anpass (hel bild)").tag(BackgroundPreference.PhotoFit.fit)
                }
                .pickerStyle(.segmented)
                .accessibilityLabel("Hur bilden fyller skärmen")
            }

            if preference.kind == .photo {
                sliderRow(title: "Oskärpa", value: blurBinding)
                sliderRow(title: "Mörkning", value: dimmingBinding)
            }

            sliderRow(title: "Intensitet", value: intensityBinding)
        } header: {
            Text("Justering")
        } footer: {
            Text(preference.kind == .photo
                 ? "Fyll beskär bilden till skärmen, Anpass visar hela bilden. Oskärpa gör bilden mjukare. Mörkning lägger ett mörkt lager som garanterar läsbarhet. Intensitet sänker hela bakgrunden mot appens standardfärg."
                 : "Intensitet sänker bakgrunden mot appens standardfärg – använd den om texten känns svår att läsa.")
        }
    }

    private func sliderRow(title: String, value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            LabeledContent(title) {
                Text("\(Int(value.wrappedValue * 100)) %")
                    .foregroundStyle(.secondary)
                    .font(.system(.caption, design: .rounded))
            }
            Slider(value: value, in: 0...1)
                .accessibilityLabel(title)
        }
    }

    private var resetSection: some View {
        Section {
            Button(role: .destructive) {
                cancelPendingPhoto()
                removePhoto()
            } label: {
                Label("Återställ till standard", systemImage: "arrow.counterclockwise")
            }
        } footer: {
            Text("Återställ tar bort eventuell importerad bild ur appens lagring och återgår till standardbakgrunden. Övriga inställningar påverkas inte.")
        }
    }

    // MARK: Bindings

    private var fitBinding: Binding<BackgroundPreference.PhotoFit> {
        Binding(
            get: { settings.data.background.photoFit },
            set: { value in setPreference { $0.photoFit = value } }
        )
    }

    private var blurBinding: Binding<Double> {
        Binding(
            get: { settings.data.background.blur },
            set: { value in setPreference { $0.blur = value } }
        )
    }

    private var dimmingBinding: Binding<Double> {
        Binding(
            get: { settings.data.background.dimming },
            set: { value in setPreference { $0.dimming = value } }
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
        preference.dimming = preference.dimming.clampedToUnit()
        settings.data.background = preference
    }
}
