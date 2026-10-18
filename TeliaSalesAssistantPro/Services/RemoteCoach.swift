import Foundation
import SwiftUI
import TeliaCore

// MARK: - Keychain

final class KeychainService {
    private let service = "se.sthlm.teliacoachpro.ai"
    private let account = "api-key"

    func saveAIKey(_ key: String) {
        let data = Data(key.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        guard !key.isEmpty else { return }
        var attributes = query
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(attributes as CFDictionary, nil)
    }

    func getAIKey() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func deleteAIKey() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - RemoteCoachService (OpenAI-compatible, SSE streaming)

/// Talks to any OpenAI-compatible `/v1/chat/completions` endpoint with `stream: true`.
/// The API key is expected to live on the user's own server (see backend/openai-proxy) —
/// never hardcodes secrets into the app.
struct RemoteCoachService: CoachService {
    let name = "AI Coach (server)"
    let isDemo = false

    let baseURL: URL
    let model: String
    let apiKey: String?

    init(baseURL: URL, model: String, apiKey: String?) {
        self.baseURL = baseURL
        self.model = model.isEmpty ? "gpt-4o-mini" : model
        self.apiKey = apiKey
    }

    // MARK: Prompt construction

    /// Grounded system prompt: the model may only quote prices from the retrieved context.
    func systemPrompt(catalog: [ProductRecord], retrieved: [ProductRecord], campaigns: [CampaignRecord]) -> String {
        var lines: [String] = []
        lines.append("""
        Du är en erfaren svensk butikssäljcoach för Telia i Sverige. Du hjälper en säljare i butik att bli bättre: ge konkreta råd, exempelfraser och Rollspel. Alltid ärligt: press, överdrifter eller dolda avgifter är aldrig okej.

        VIKTIGA REGLER:
        - Citera bara priser som finns i PRODUKTDATA eller KAMPANJDATA nedan. Osäker? Säg att säljaren ska kontrollera telia.se.
        - Skilj tydligt på verifierade produktfakta och allmänt råd.
        - Redovisa alltid kampanjperiod, ordinarie pris och bindningstid när du nämner priser.
        - Nämner du en kampanj: redogör för dess slutdatum om det finns i KAMPANJDATA, och påminn om att kampanjer kan ha utgått sedan verifieringen. Hittar du kampanjen inte i KAMPANJDATA — säg det istället för att hitta på priser, datum eller villkor.
        - Svara på samma språk som frågan (svenska eller engelska).
        """)
        if !retrieved.isEmpty {
            lines.append("PRODUKTDATA (hämtade ur säljarens verifierade katalog):")
            for p in retrieved {
                var line = "- \(p.name) (\(p.kind.displayName))"
                if let m = CostCalculator.currentMonthly(p) {
                    line += ": \(Int(m)) kr/mån"
                    if let o = p.ordinaryMonthlyPriceSEK, o > m { line += " (ord. \(Int(o)))" }
                    if let months = p.campaignMonths { line += ", kampanj \(months) mån" }
                    if let b = p.bindingMonths, b > 0 { line += ", \(b) mån bindning" } else { line += ", obundet" }
                } else {
                    line += ": pris ej verifierat – be säljaren kolla telia.se"
                }
                if !p.includedServices.isEmpty { line += ". Ingår: \(p.includedServices.joined(separator: ", "))" }
                if let url = p.sourceURL { line += ". Källa: \(url)" }
                lines.append(line)
            }
        }
        let activeCampaigns = CampaignEngine.activeCampaigns(campaigns)
        if !activeCampaigns.isEmpty {
            lines.append("KAMPANJDATA (aktiva poster ur säljarens Kampanj Center, verifierade mot telia.se):")
            for c in activeCampaigns {
                var line = "- \(c.title) [\(c.id)]"
                line += c.priceKind == .monthly
                    ? ": \(Int(c.campaignPriceSEK)) kr/mån"
                    : ": \(Int(c.campaignPriceSEK)) kr engångspris"
                if let o = c.ordinaryPriceSEK { line += " (ord. \(Int(o)))" }
                if let promo = c.promoMonths { line += ", kampanjpris \(promo) mån" }
                if let after = c.priceAfterCampaignSEK { line += ", därefter \(Int(after)) kr/mån" }
                if let b = c.bindingMonths, b > 0 { line += ", \(b) mån bindning" }
                if let end = c.endDate { line += ", t.o.m. \(Format.dayMonth.string(from: end))" } else { line += ", slutdatum ej verifierat" }
                if let elig = c.eligibility { line += ". Villkor: \(elig)" }
                line += ". Källa: \(c.sourceURL)"
                lines.append(line)
            }
        } else {
            lines.append("KAMPANJDATA: inga aktiva kampanjer cachade. Säg det ärligt om säljaren frågar om kampanjer.")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: SSE

    struct SSELine {
        let data: String
    }

    func reply(
        to message: String,
        history: [ChatMessage],
        catalog: [ProductRecord],
        campaigns: [CampaignRecord],
        streamChunk: @escaping (String) -> Void
    ) async throws -> CoachReply {
        let retrieved = CatalogQuery.retrieve(message: message, in: catalog, topK: 5)

        var messages: [[String: String]] = [["role": "system", "content": systemPrompt(catalog: catalog, retrieved: retrieved, campaigns: campaigns)]]
        for m in history.suffix(10) where m.role != .system && !m.failed {
            messages.append(["role": m.role == .user ? "user" : "assistant", "content": m.text])
        }
        messages.append(["role": "user", "content": message])

        let endpoint = baseURL.appendingPathComponent("v1/chat/completions")
        var request = URLRequest(url: endpoint, timeoutInterval: 60)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let apiKey, !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": model,
            "messages": messages,
            "stream": true,
            "temperature": 0.4,
        ])

        let (bytes, response): (URLSession.AsyncBytes, URLResponse)
        do {
            (bytes, response) = try await URLSession.shared.bytes(for: request)
        } catch let urlError as URLError {
            throw CoachError.network(urlError.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw CoachError.network("Oväntat svar från servern.")
        }
        switch httpResponse.statusCode {
        case 200..<300: break
        case 429: throw CoachError.rateLimited
        default: throw CoachError.server(httpResponse.statusCode)
        }

        var fullText = ""
        for try await line in bytes.lines {
            guard line.hasPrefix("data:") else { continue }
            let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            if payload == "[DONE]" { break }
            guard let data = payload.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let delta = choices.first?["delta"] as? [String: Any],
                  let content = delta["content"] as? String
            else { continue }
            if !content.isEmpty {
                fullText += content
                streamChunk(content)
            }
        }

        guard !fullText.isEmpty else { throw CoachError.emptyResponse }

        let citations = retrieved.map { p in
            ChatCitation(
                productId: p.id,
                productName: p.name,
                sourceURL: p.sourceURL,
                priceSEK: CostCalculator.currentMonthly(p),
                verifiedAt: p.verifiedAt
            )
        }
        return CoachReply(text: fullText, citations: citations)
    }
}
