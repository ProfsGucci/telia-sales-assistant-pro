import Foundation

// MARK: - Playbook

public struct PlaybookEntry: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let section: PlaybookSection
    public let title: String
    public let summary: String
    /// For objection entries: the structured six-step format.
    public let objection: ObjectionGuide?
    /// General guidance entries: markdown-ish bullet blocks.
    public let guidance: [String]
    /// Product ids from the catalog to show as verified references.
    public let relatedProductIds: [String]

    public init(id: String, section: PlaybookSection, title: String, summary: String,
                objection: ObjectionGuide? = nil, guidance: [String] = [],
                relatedProductIds: [String] = []) {
        self.id = id
        self.section = section
        self.title = title
        self.summary = summary
        self.objection = objection
        self.guidance = guidance
        self.relatedProductIds = relatedProductIds
    }
}

public enum PlaybookSection: String, Codable, CaseIterable, Sendable {
    case discovery, needs, products, objections, competitors, closing, service

    public var displayName: String {
        switch self {
        case .discovery: return "Kartläggning"
        case .needs: return "Behovsanalys"
        case .products: return "Produktförklaringer"
        case .objections: return "Invändningar"
        case .competitors: return "Konkurrenter"
        case .closing: return "Avslut"
        case .service: return "Service & efterarbete"
        }
    }

    public var symbolName: String {
        switch self {
        case .discovery: return "questionmark.circle.fill"
        case .needs: return "scope"
        case .products: return "cube.box.fill"
        case .objections: return "shield.lefthalf.filled"
        case .competitors: return "chart.bar.doc.horizontal"
        case .closing: return "hand.thumbsup.fill"
        case .service: return "person.crop.circle.badge.checkmark"
        }
    }
}

public struct ObjectionGuide: Codable, Hashable, Sendable {
    public let whatTheyMean: String
    public let clarifyingQuestion: String
    public let empatheticResponse: String
    public let nextStep: String
    public let commonMistakes: [String]

    public init(whatTheyMean: String, clarifyingQuestion: String, empatheticResponse: String,
                nextStep: String, commonMistakes: [String]) {
        self.whatTheyMean = whatTheyMean
        self.clarifyingQuestion = clarifyingQuestion
        self.empatheticResponse = empatheticResponse
        self.nextStep = nextStep
        self.commonMistakes = commonMistakes
    }
}

public struct PlaybookContent: Codable, Sendable {
    public let entries: [PlaybookEntry]
    public init(entries: [PlaybookEntry]) { self.entries = entries }
}

// MARK: - Saved scripts (user content)

public struct SavedScript: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var title: String
    public var body: String
    public var updatedAt: Date
    public var linkedProductId: String?

    public init(id: UUID = UUID(), title: String, body: String, updatedAt: Date = Date(), linkedProductId: String? = nil) {
        self.id = id
        self.title = title
        self.body = body
        self.updatedAt = updatedAt
        self.linkedProductId = linkedProductId
    }
}

// MARK: - Notes & saved answers

public struct PersonalNote: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var title: String
    public var body: String
    public var updatedAt: Date

    public init(id: UUID = UUID(), title: String, body: String, updatedAt: Date = Date()) {
        self.id = id
        self.title = title
        self.body = body
        self.updatedAt = updatedAt
    }
}
