import Foundation

/// Imports price data the user is authorized to use: exported JSON snapshots,
/// remote feed JSON (same schema), or hand-maintained CSV price lists.
public enum PriceImportError: Error, Equatable, Sendable {
    case empty
    case malformedCSV(String)
    case malformedJSON(String)
    case missingRequiredField(String)
    case invalidNumber(field: String, value: String)
    case invalidDate(field: String, value: String)
    case unsupportedFormat
}

public struct PriceImportReport: Codable, Sendable {
    public let importedCount: Int
    public let skippedCount: Int
    public let errors: [String]
    public let source: String

    public init(importedCount: Int, skippedCount: Int, errors: [String], source: String) {
        self.importedCount = importedCount
        self.skippedCount = skippedCount
        self.errors = errors
        self.source = source
    }
}

public enum PriceImport {

    static let iso8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static let isoDay: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Europe/Stockholm")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    // MARK: - Entry point

    public static func parse(data: Data, filename: String) throws -> (CatalogSnapshot, PriceImportReport) {
        let lower = filename.lowercased()
        if lower.hasSuffix(".json") || looksLikeJSON(data) {
            return try parseJSON(data)
        }
        if lower.hasSuffix(".csv") || looksLikeCSV(data) {
            return try parseCSV(data)
        }
        throw PriceImportError.unsupportedFormat
    }

    static func looksLikeJSON(_ data: Data) -> Bool {
        if let s = String(data: data.prefix(64), encoding: .utf8) {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.hasPrefix("{") || t.hasPrefix("[")
        }
        return false
    }

    static func looksLikeCSV(_ data: Data) -> Bool {
        guard let s = String(data: data.prefix(512), encoding: .utf8) else { return false }
        return s.contains(",") && s.contains("\n")
    }

    // MARK: - JSON (same schema as SeedCatalog.json / app export)

    public static func parseJSON(_ data: Data) throws -> (CatalogSnapshot, PriceImportReport) {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            let snapshot = try decoder.decode(CatalogSnapshot.self, from: data)
            let report = PriceImportReport(
                importedCount: snapshot.products.count,
                skippedCount: 0,
                errors: [],
                source: "JSON-fil"
            )
            return (snapshot, report)
        } catch {
            throw PriceImportError.malformedJSON(error.localizedDescription)
        }
    }

    // MARK: - CSV

    /// Expected CSV columns (header row required, order free, extra columns ignored):
    /// id,name,kind,category,monthlyPrice,ordinaryPrice,upfrontCost,bindingMonths,
    /// campaignMonths,dataGB,unlimitedData,speedMbit,services(;),sourceUrl,sourceName,
    /// verifiedAt(yyyy-MM-dd),verification,notes,tags(;)
    public static func parseCSV(_ data: Data) throws -> (CatalogSnapshot, PriceImportReport) {
        guard let text = String(data: data, encoding: .utf8) else {
            throw PriceImportError.malformedCSV("Filen är inte UTF-8-kodad")
        }
        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard lines.count >= 2 else { throw PriceImportError.malformedCSV("Filen saknar rader") }

        let header = splitCSV(lines[0]).map { $0.lowercased().trimmingCharacters(in: .whitespaces) }
        let required = ["name"]
        for field in required where !header.contains(field) {
            throw PriceImportError.missingRequiredField(field)
        }

        func col(_ name: String) -> Int? { header.firstIndex(of: name.lowercased()) }

        var products: [ProductRecord] = []
        var errors: [String] = []

        for (index, line) in lines.dropFirst().enumerated() {
            let rowNumber = index + 2
            let cells = splitCSV(line)
            func value(_ name: String) -> String? {
                guard let i = col(name), i < cells.count else { return nil }
                let v = cells[i].trimmingCharacters(in: .whitespaces)
                return v.isEmpty ? nil : v
            }
            guard let name = value("name") else {
                errors.append("Rad \(rowNumber): name saknas — raden hoppades över")
                continue
            }
            let id = value("id") ?? "csv-\(slug(name))"
            let kindRaw = value("kind")?.lowercased() ?? "mobileplan"
            let kind = ProductKind(rawValue: kindRaw) ?? .mobilePlan

            func number(_ field: String) throws -> Double? {
                guard let raw = value(field) else { return nil }
                let normalized = raw.replacingOccurrences(of: ",", with: ".")
                    .replacingOccurrences(of: "kr", with: "")
                    .replacingOccurrences(of: " ", with: "")
                guard let d = Double(normalized) else {
                    throw PriceImportError.invalidNumber(field: field, value: raw)
                }
                return d
            }
            func int(_ field: String) throws -> Int? {
                guard let d = try number(field) else { return nil }
                return Int(d.rounded())
            }
            func date(_ field: String) throws -> Date? {
                guard let raw = value(field) else { return nil }
                if let d = isoDay.date(from: raw) { return d }
                if let d = iso8601.date(from: raw) { return d }
                throw PriceImportError.invalidDate(field: field, value: raw)
            }

            do {
                let verificationRaw = value("verification")?.lowercased()
                let verification = VerificationStatus(rawValue: verificationRaw ?? "") ?? .imported
                let sourceURL = value("sourceurl") ?? value("url")
                // Records without a source URL can never be "verified".
                let effectiveVerification: VerificationStatus
                if verification == .verified && sourceURL == nil {
                    effectiveVerification = .imported
                } else {
                    effectiveVerification = verification
                }

                let product = ProductRecord(
                    id: id,
                    name: name,
                    kind: kind,
                    category: value("category") ?? kind.displayName,
                    brand: value("brand"),
                    monthlyPriceSEK: try number("monthlyprice"),
                    ordinaryMonthlyPriceSEK: try number("ordinaryprice"),
                    upfrontCostSEK: try number("upfrontcost"),
                    bindingMonths: try int("bindingmonths"),
                    campaignMonths: try int("campaignmonths"),
                    dataGB: try number("datagb"),
                    unlimitedData: ["1", "true", "ja", "yes"].contains((value("unlimiteddata") ?? "").lowercased()),
                    speedMbit: try number("speedmbit"),
                    includedServices: (value("services") ?? "").split(separator: ";").map(String.init),
                    highlights: [],
                    campaignStart: try date("campaignstart"),
                    campaignEnd: try date("campaignend"),
                    eligibilityNotes: value("notes"),
                    mandatoryCharges: [],
                    sourceURL: sourceURL,
                    sourceName: value("sourcename"),
                    verifiedAt: try date("verifiedat"),
                    verification: effectiveVerification,
                    tags: (value("tags") ?? "").split(separator: ";").map(String.init)
                )
                products.append(product)
            } catch let error as PriceImportError {
                errors.append("Rad \(rowNumber): \(error.localizedDescription)")
            }
        }

        guard !products.isEmpty else {
            throw PriceImportError.malformedCSV(errors.joined(separator: " ") )
        }
        let snapshot = CatalogSnapshot(
            products: products,
            generatedAt: Date(),
            sourceNote: "Importerad CSV-prislista"
        )
        let report = PriceImportReport(
            importedCount: products.count,
            skippedCount: errors.count,
            errors: errors,
            source: "CSV-fil"
        )
        return (snapshot, report)
    }

    /// Minimal CSV splitter that respects double quotes.
    static func splitCSV(_ line: String) -> [String] {
        var result: [String] = []
        var current = ""
        var inQuotes = false
        for ch in line {
            if ch == "\"" {
                inQuotes.toggle()
            } else if ch == "," && !inQuotes {
                result.append(current)
                current = ""
            } else {
                current.append(ch)
            }
        }
        result.append(current)
        return result
    }

    static func slug(_ s: String) -> String {
        let allowed = s.lowercased().replacingOccurrences(of: "å", with: "a")
            .replacingOccurrences(of: "ä", with: "a")
            .replacingOccurrences(of: "ö", with: "o")
        return allowed.map { ch -> Character in
            ("a"..."z").contains(String(ch)) || ("0"..."9").contains(String(ch)) ? ch : "-"
        }.reduce(into: "") { acc, ch in
            if ch == "-" && acc.hasSuffix("-") { return }
            acc.append(ch)
        }
    }
}

extension PriceImportError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .empty: return "Filen är tom"
        case .malformedCSV(let m): return "Ogiltig CSV: \(m)"
        case .malformedJSON(let m): return "Ogiltig JSON: \(m)"
        case .missingRequiredField(let f): return "Obligatoriskt fält saknas: \(f)"
        case .invalidNumber(let field, let value): return "Ogiltigt tal i \(field): \(value)"
        case .invalidDate(let field, let value): return "Ogiltigt datum i \(field): \(value)"
        case .unsupportedFormat: return "Formatet stöds inte (använd .json eller .csv)"
        }
    }
}
