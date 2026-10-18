import Foundation

// MARK: - Content models

public struct LessonContent: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let track: LearningTrack
    public let title: String
    public let summary: String
    /// Markdown-ish plain text pages; the UI renders them as styled paragraphs.
    public let pages: [String]
    public let quiz: [QuizQuestion]
    public let flashcards: [Flashcard]
    public let minutes: Int
    /// Optional day number in the 30-day onboarding program (1...30).
    public let programDay: Int?

    public init(id: String, track: LearningTrack, title: String, summary: String,
                pages: [String], quiz: [QuizQuestion], flashcards: [Flashcard],
                minutes: Int, programDay: Int? = nil) {
        self.id = id
        self.track = track
        self.title = title
        self.summary = summary
        self.pages = pages
        self.quiz = quiz
        self.flashcards = flashcards
        self.minutes = minutes
        self.programDay = programDay
    }
}

public enum LearningTrack: String, Codable, CaseIterable, Sendable {
    case productKnowledge = "product-knowledge"
    case discovery = "discovery"
    case objections = "objection-handling"
    case selling = "needs-based-selling"
    case compliance = "cost-transparency"

    public var displayName: String {
        switch self {
        case .productKnowledge: return "Produktkunskap"
        case .discovery: return "Kartläggning"
        case .objections: return "Invändningar"
        case .selling: return "Behovsbaserat sälj"
        case .compliance: return "Pris & villkor"
        }
    }

    public var symbolName: String {
        switch self {
        case .productKnowledge: return "books.vertical.fill"
        case .discovery: return "questionmark.bubble.fill"
        case .objections: return "shield.lefthalf.filled"
        case .selling: return "target"
        case .compliance: return "checklist"
        }
    }
}

public struct QuizQuestion: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let topic: String
    public let prompt: String
    public let options: [String]
    public let correctIndex: Int
    public let explanation: String

    public init(id: String, topic: String, prompt: String, options: [String],
                correctIndex: Int, explanation: String) {
        self.id = id
        self.topic = topic
        self.prompt = prompt
        self.options = options
        self.correctIndex = correctIndex
        self.explanation = explanation
    }
}

public struct Flashcard: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let topic: String
    public let front: String
    public let back: String

    public init(id: String, topic: String, front: String, back: String) {
        self.id = id
        self.topic = topic
        self.front = front
        self.back = back
    }
}

public struct LearningContent: Codable, Sendable {
    public let lessons: [LessonContent]
    public let glossary: [GlossaryTerm]
    public let tips: [SalesTip]

    public init(lessons: [LessonContent], glossary: [GlossaryTerm], tips: [SalesTip]) {
        self.lessons = lessons
        self.glossary = glossary
        self.tips = tips
    }
}

public struct GlossaryTerm: Codable, Hashable, Identifiable, Sendable {
    public var id: String { term }
    public let term: String
    public let definition: String

    public init(term: String, definition: String) {
        self.term = term
        self.definition = definition
    }
}

public struct SalesTip: Codable, Hashable, Identifiable, Sendable {
    public var id: String { text }
    public let text: String
    public let category: String

    public init(text: String, category: String) {
        self.text = text
        self.category = category
    }
}

// MARK: - Learner state

public struct QuizAnswerRecord: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public let questionId: String
    public let topic: String
    public let correct: Bool
    public let date: Date

    public init(questionId: String, topic: String, correct: Bool, date: Date = Date()) {
        self.id = UUID()
        self.questionId = questionId
        self.topic = topic
        self.correct = correct
        self.date = date
    }
}

public struct LessonProgress: Codable, Hashable, Identifiable, Sendable {
    public let lessonId: String
    public let completedAt: Date
    public let score: Int
    public let total: Int

    public var id: String { lessonId }
    public init(lessonId: String, completedAt: Date = Date(), score: Int, total: Int) {
        self.lessonId = lessonId
        self.completedAt = completedAt
        self.score = score
        self.total = total
    }
}

public struct TopicMastery: Codable, Hashable, Identifiable, Sendable {
    public var id: String { topic }
    public let topic: String
    public let answered: Int
    public let correct: Int

    public var accuracy: Double { answered > 0 ? Double(correct) / Double(answered) : 0 }

    public init(topic: String, answered: Int, correct: Int) {
        self.topic = topic
        self.answered = answered
        self.correct = correct
    }
}

// MARK: - SRS (SM-2)

public struct SrsCardState: Codable, Hashable, Identifiable, Sendable {
    public let cardId: String
    public let easeFactor: Double
    public let intervalDays: Double
    public let due: Date
    public let lapses: Int

    public var id: String { cardId }
    public init(cardId: String, easeFactor: Double = 2.5, intervalDays: Double = 0,
                due: Date = Date(), lapses: Int = 0) {
        self.cardId = cardId
        self.easeFactor = easeFactor
        self.intervalDays = intervalDays
        self.due = due
        self.lapses = lapses
    }
}

/// Classic SM-2 spaced repetition. Quality: 0–5.
/// The UI maps buttons: Igen = 1, Svårt = 3, Bra = 4, Lätt = 5.
public enum SrsEngine {
    public static func review(_ card: SrsCardState, quality: Int, now: Date = Date(), calendar: Calendar = .current) -> SrsCardState {
        let q = max(0, min(5, quality))
        var ease = card.easeFactor
        var interval = card.intervalDays
        var lapses = card.lapses

        if q < 3 {
            interval = 0
            lapses += 1
        } else {
            if interval < 1 { interval = 1 }
            else if interval < 2 { interval = 3 }
            else { interval = interval * ease }
        }
        ease = ease + (0.1 - Double(5 - q) * (0.08 + Double(5 - q) * 0.02))
        ease = max(1.3, ease)
        interval = min(interval, 180)

        let days = Int(interval.rounded(.up))
        let due = calendar.date(byAdding: .day, value: max(days, q < 3 ? 0 : 1), to: now) ?? now
        return SrsCardState(cardId: card.cardId, easeFactor: ease, intervalDays: interval, due: due, lapses: lapses)
    }

    public static func dueCards(_ states: [SrsCardState], before date: Date = Date()) -> [SrsCardState] {
        states.filter { $0.due <= date }.sorted { $0.due < $1.due }
    }
}

// MARK: - Streaks

public enum StreakEngine {
    /// `activityDays` are calendar day-starts the user actually trained.
    public static func currentStreak(activityDays: [Date], now: Date = Date(), calendar: Calendar = .current) -> Int {
        let days = Set(activityDays.map { calendar.startOfDay(for: $0) })
        guard !days.isEmpty else { return 0 }
        var cursor = calendar.startOfDay(for: now)
        // A streak survives if today or yesterday has activity.
        if !days.contains(cursor) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: cursor), days.contains(yesterday) else { return 0 }
            cursor = yesterday
        }
        var streak = 0
        while days.contains(cursor) {
            streak += 1
            cursor = calendar.date(byAdding: .day, value: -1, to: cursor) ?? cursor
        }
        return streak
    }
}

// MARK: - Learning engine (aggregates)

public enum LearningEngine {

    public static func mastery(from answers: [QuizAnswerRecord]) -> [TopicMastery] {
        var grouped: [String: (answered: Int, correct: Int)] = [:]
        for a in answers {
            var g = grouped[a.topic] ?? (0, 0)
            g.answered += 1
            if a.correct { g.correct += 1 }
            grouped[a.topic] = g
        }
        return grouped.map { TopicMastery(topic: $0.key, answered: $0.value.answered, correct: $0.value.correct) }
            .sorted { $0.topic < $1.topic }
    }

    /// Topics with at least 3 answers below 70% accuracy.
    public static func weakTopics(from answers: [QuizAnswerRecord], minimumAnswers: Int = 3) -> [TopicMastery] {
        mastery(from: answers).filter { $0.answered >= minimumAnswers && $0.accuracy < 0.7 }
            .sorted { $0.accuracy < $1.accuracy }
    }

    /// Personalized weekly plan: next uncompleted lessons, prioritizing weak tracks.
    public static func weeklyPlan(
        lessons: [LessonContent],
        completedLessonIDs: Set<String>,
        weakTopics: [TopicMastery],
        weekStart: Date,
        calendar: Calendar = .current,
        perDay: Int = 2
    ) -> [(date: Date, lessons: [LessonContent])] {
        let weakSet = Set(weakTopics.map(\.topic))
        let pending = lessons
            .filter { !completedLessonIDs.contains($0.id) }
            .sorted { a, b in
                let aWeak = a.quiz.contains { weakSet.contains($0.topic) } ? 1 : 0
                let bWeak = b.quiz.contains { weakSet.contains($0.topic) } ? 1 : 0
                if aWeak != bWeak { return aWeak > bWeak }
                return (a.programDay ?? 99) < (b.programDay ?? 99)
            }
        var plan: [(Date, [LessonContent])] = []
        var index = 0
        for dayOffset in 0..<7 {
            guard let date = calendar.date(byAdding: .day, value: dayOffset, to: weekStart) else { continue }
            let chunk = Array(pending[index..<min(index + perDay, pending.count)])
            index += chunk.count
            if !chunk.isEmpty { plan.append((date, chunk)) }
        }
        return plan
    }

    /// The 30-day onboarding program: lessons tagged with programDay, in order.
    public static func onboardingProgram(_ lessons: [LessonContent]) -> [LessonContent] {
        lessons.filter { $0.programDay != nil }.sorted { ($0.programDay ?? 0) < ($1.programDay ?? 0) }
    }
}
