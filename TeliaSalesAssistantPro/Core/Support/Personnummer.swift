import Foundation

// MARK: - Swedish personal identity number (personnummer)
//
// Used ONLY for the local "Check Later Customer" follow-up feature.
// A normalized personnummer is stored on-device in the app's own documents
// directory and is NEVER sent to any AI model, third-party service,
// analytics or log. See docs/DEBUG-REPORT-1.4.md (privacy section).

/// Validation, normalization and masking of Swedish personnummer and
/// samordningsnummer (coordination numbers, day + 60).
///
/// Pure Foundation — runs identically on Linux (unit tests) and iOS.
public enum Personnummer {

    /// A validated, normalized identity number.
    public struct Normalized: Hashable, Sendable {
        /// 12 digits: YYYYMMDDXXXX (samordningsnummer keeps day+60).
        public let digits12: String
        /// True when the number is a coordination number (samordningsnummer).
        public let isCoordinationNumber: Bool

        /// "19850312-****" — birth date visible, serial masked.
        public var masked: String {
            let idx = digits12.index(digits12.startIndex, offsetBy: 8)
            return digits12[..<idx] + "-" + String(repeating: "*", count: 4)
        }

        /// "19850312-3210" — full form. Show only when the user reveals it.
        public var full: String {
            let idx = digits12.index(digits12.startIndex, offsetBy: 8)
            return "\(digits12[..<idx])-\(digits12[idx...])"
        }
    }

    // MARK: Validation

    /// Validates structure, real calendar date and the Luhn checksum.
    /// Accepts 10- and 12-digit forms, with or without "-" / "+" separator.
    /// Returns nil for anything invalid — digits are never "fixed" silently.
    public static func validate(_ raw: String) -> Normalized? {
        normalize(raw)
    }

    /// Convenience predicate.
    public static func isValid(_ raw: String) -> Bool {
        normalize(raw) != nil
    }

    /// Normalizes to the 12-digit canonical form, validating on the way.
    public static func normalize(_ raw: String) -> Normalized? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        s = s.replacingOccurrences(of: " ", with: "")

        // Separator handling: plus means the person turned/turns 100.
        var plus = false
        if s.contains("+") {
            plus = true
            s = s.replacingOccurrences(of: "+", with: "")
        } else {
            s = s.replacingOccurrences(of: "-", with: "")
        }

        // Reject anything that isn't purely digits after cleanup.
        guard s.allSatisfy({ $0.isNumber && $0.isASCII }) else { return nil }

        let (year, rest): (Int, String)
        switch s.count {
        case 10:
            let yy = Int(s.prefix(2))!
            let century = centuryFor(twoDigitYear: yy, plus: plus)
            year = century + yy
            rest = String(s.suffix(8))
        case 12:
            year = Int(s.prefix(4))!
            guard (1900...2100).contains(year) else { return nil }
            rest = String(s.suffix(8))
        default:
            return nil
        }

        guard rest.count == 8,
              let month = Int(rest.prefix(2)),
              let dayRaw = Int(rest.dropFirst(2).prefix(2)),
              let serial = Int(rest.suffix(4).dropLast()),
              let check = Int(rest.suffix(1))
        else { return nil }

        // Coordination numbers: day 61–91 → real day is day − 60.
        var day = dayRaw
        var isCoordination = false
        if day > 60 {
            isCoordination = true
            day -= 60
        }

        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Stockholm") ?? .current
        // Round-trip check: some Foundation implementations roll impossible
        // dates over (Feb 30 → Mar 2) instead of failing — compare back to
        // catch invalid dates on every platform.
        guard month >= 1, month <= 12, day >= 1, day <= 31,
              let parsed = cal.date(from: comps) else {
            return nil
        }
        let back = cal.dateComponents([.year, .month, .day], from: parsed)
        guard back.year == year, back.month == month, back.day == day else {
            return nil
        }

        // Luhn checksum over YY MM DD SSS + check digit (10 digits, the
        // coordination day stays as-is in the number itself).
        let yy2 = String(year).suffix(2)
        let tenDigits = "\(yy2)\(rest)"   // YY MMDD SSSC = 10 chars
        guard tenDigits.count == 10,
              tenDigits.allSatisfy({ $0.isNumber })
        else { return nil }
        var digits = tenDigits.compactMap { $0.wholeNumberValue }
        _ = serial // parsed for clarity above; checksum uses raw digits
        _ = check
        // Double every second digit starting from the first (index 0).
        for i in stride(from: 0, to: 9, by: 2) {
            digits[i] *= 2
            if digits[i] > 9 { digits[i] -= 9 }
        }
        let sum = digits.reduce(0, +)
        guard sum % 10 == 0 else { return nil }

        let digits12 = "\(year)\(rest)"
        return Normalized(digits12: digits12, isCoordinationNumber: isCoordination)
    }

    /// Century inference for 10-digit input. "+" → previous century.
    private static func centuryFor(twoDigitYear yy: Int, plus: Bool) -> Int {
        if plus { return 1900 } // "+" historically means born in the 1900s and ≥100 years old
        let currentYear = Calendar(identifier: .gregorian)
            .component(.year, from: Date())
        let currentCentury = (currentYear / 100) * 100
        let candidate = currentCentury + yy
        // A 10-digit year without "+" refers to a year in the last 100 years.
        return candidate <= currentYear ? currentCentury : currentCentury - 100
    }

    // MARK: Duplicate detection

    /// Same identity number (canonical) — used to warn about possible
    /// duplicates WITHOUT exposing or comparing anything else.
    public static func isSamePerson(_ a: String, _ b: String) -> Bool {
        guard let n1 = normalize(a), let n2 = normalize(b) else { return false }
        return n1.digits12 == n2.digits12
    }

    // MARK: Display helpers (from a stored, normalized 12-digit value)

    /// "19850312-****" for a stored normalized number; birth date visible,
    /// serial masked. Falls back to a fully masked string on bad input.
    public static func maskedString(_ digits12: String) -> String {
        guard digits12.count == 12, digits12.allSatisfy({ $0.isNumber }) else { return "••••••••" }
        let idx = digits12.index(digits12.startIndex, offsetBy: 8)
        return digits12[..<idx] + "-" + String(repeating: "*", count: 4)
    }

    /// "19850312-3210" — full form. Reveal only on explicit user action.
    public static func fullString(_ digits12: String) -> String {
        guard digits12.count == 12, digits12.allSatisfy({ $0.isNumber }) else { return digits12 }
        let idx = digits12.index(digits12.startIndex, offsetBy: 8)
        return "\(digits12[..<idx])-\(digits12[idx...])"
    }
}
