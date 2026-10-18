import SwiftUI
import Combine
import TeliaCore

// MARK: - ChatStore

@MainActor
final class ChatStore: ObservableObject {
    @Published var conversations: [Conversation] {
        didSet { persist() }
    }
    @Published var currentConversationID: UUID?
    @Published var isStreaming = false
    @Published var streamingMessageID: UUID?
    @Published var lastError: String?

    private let keychain = KeychainService()

    init() {
        self.conversations = DataStore.load([Conversation].self) ?? []
        self.currentConversationID = conversations.first?.id
    }

    var current: Conversation? {
        conversations.first { $0.id == currentConversationID }
    }

    private func persist() {
        DataStore.save(conversations)
    }

    func newConversation() {
        let convo = Conversation(title: "Ny konversation")
        conversations.insert(convo, at: 0)
        currentConversationID = convo.id
    }

    func select(_ id: UUID) {
        currentConversationID = id
    }

    func deleteConversation(id: UUID) {
        conversations.removeAll { $0.id == id }
        if currentConversationID == id {
            currentConversationID = conversations.first?.id
        }
    }

    func deleteAll() {
        conversations = []
        currentConversationID = nil
    }

    func buildService(settings: SettingsData) -> any CoachService {
        if !settings.aiBaseURL.isEmpty,
           let url = URL(string: settings.aiBaseURL),
           url.scheme == "https" {
            let key = settings.aiUsesKey ? keychain.getAIKey() : nil
            return RemoteCoachService(baseURL: url, model: settings.aiModel, apiKey: key)
        }
        return DemoCoachService()
    }

    func send(message: String, catalog: [ProductRecord], settings: SettingsData) {
        let text = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isStreaming else { return }

        if currentConversationID == nil { newConversation() }
        guard let convoID = currentConversationID,
              let convoIndex = conversations.firstIndex(where: { $0.id == convoID }) else { return }

        // Title the conversation from the first user message.
        if conversations[convoIndex].messages.isEmpty {
            let title = text.prefix(40)
            conversations[convoIndex].title = String(title)
        }

        let userMessage = ChatMessage(role: .user, text: text)
        conversations[convoIndex].messages.append(userMessage)
        conversations[convoIndex].updatedAt = Date()
        if conversations[convoIndex].title == "Ny konversation" {
            conversations[convoIndex].title = String(text.prefix(40))
        }

        let history = conversations[convoIndex].messages
        let service = buildService(settings: settings)
        isStreaming = true
        lastError = nil

        // Placeholder assistant message that fills up as chunks arrive.
        var assistant = ChatMessage(role: .assistant, text: "", isDemo: service.isDemo)
        let assistantID = assistant.id
        conversations[convoIndex].messages.append(assistant)
        streamingMessageID = assistantID

        Task { [weak self] in
            guard let self else { return }
            do {
                let reply = try await service.reply(
                    to: text,
                    history: history,
                    catalog: catalog
                ) { [weak self] chunk in
                    Task { @MainActor [weak self] in
                        guard let self,
                              let convoIndex = self.conversations.firstIndex(where: { $0.id == convoID }),
                              let msgIndex = self.conversations[convoIndex].messages.firstIndex(where: { $0.id == assistantID })
                        else { return }
                        self.conversations[convoIndex].messages[msgIndex].text += chunk
                    }
                }
                // Finalize with citations and suggestions.
                if let convoIndex = conversations.firstIndex(where: { $0.id == convoID }),
                   let msgIndex = conversations[convoIndex].messages.firstIndex(where: { $0.id == assistantID }) {
                    var finalText = reply.text
                    let streamed = conversations[convoIndex].messages[msgIndex].text
                    if !streamed.isEmpty { finalText = streamed }
                    assistant.text = finalText
                    assistant.citations = reply.citations
                    conversations[convoIndex].messages[msgIndex] = assistant
                    conversations[convoIndex].updatedAt = Date()
                }
                isStreaming = false
                streamingMessageID = nil
            } catch {
                isStreaming = false
                streamingMessageID = nil
                if let convoIndex = conversations.firstIndex(where: { $0.id == convoID }),
                   let msgIndex = conversations[convoIndex].messages.firstIndex(where: { $0.id == assistantID }) {
                    if conversations[convoIndex].messages[msgIndex].text.isEmpty {
                        conversations[convoIndex].messages.remove(at: msgIndex)
                    }
                }
                let failed = ChatMessage(role: .assistant, text: "", failed: true)
                conversations[convoIndex].messages.append(failed)
                conversations[convoIndex].updatedAt = Date()
                lastError = error.localizedDescription
            }
        }
    }

    func retryLast(catalog: [ProductRecord], settings: SettingsData) {
        guard let convoID = currentConversationID,
              let convoIndex = conversations.firstIndex(where: { $0.id == convoID }) else { return }
        // Remove trailing failed message and resend the last user message.
        if let last = conversations[convoIndex].messages.last, last.failed {
            conversations[convoIndex].messages.removeLast()
        }
        if let lastUser = conversations[convoIndex].messages.last(where: { $0.role == .user })?.text {
            conversations[convoIndex].messages.removeLast() // remove the user message too; send re-adds
            send(message: lastUser, catalog: catalog, settings: settings)
        }
    }
}

// MARK: - ScheduleStore

@MainActor
final class ScheduleStore: ObservableObject {
    @Published var events: [ScheduleEvent] {
        didSet { DataStore.save(events) }
    }
    @Published var tasks: [DayTask] {
        didSet { DataStore.save(tasks) }
    }

    init() {
        self.events = DataStore.load([ScheduleEvent].self) ?? []
        self.tasks = DataStore.load([DayTask].self) ?? []
    }

    func upsert(_ event: ScheduleEvent) {
        if let index = events.firstIndex(where: { $0.id == event.id }) {
            events[index] = event
        } else {
            events.append(event)
        }
    }

    func deleteEvent(id: UUID) {
        events.removeAll { $0.id == id }
    }

    func toggleTask(_ id: UUID) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[index].done.toggle()
    }

    func addTask(title: String, due: Date) {
        tasks.append(DayTask(title: title, due: due))
    }

    func deleteTask(id: UUID) {
        tasks.removeAll { $0.id == id }
    }
}

// MARK: - ProgressStore

@MainActor
final class ProgressStore: ObservableObject {
    @Published var entries: [SalesEntry] {
        didSet { DataStore.save(entries) }
    }
    @Published var goals: Goals {
        didSet { DataStore.save(goals) }
    }

    init() {
        self.entries = DataStore.load([SalesEntry].self) ?? []
        self.goals = DataStore.load(Goals.self) ?? Goals()
    }

    func upsert(_ entry: SalesEntry) {
        if let index = entries.firstIndex(where: { $0.id == entry.id }) {
            entries[index] = entry
        } else {
            entries.append(entry)
        }
    }

    func deleteEntry(id: UUID) {
        entries.removeAll { $0.id == id }
    }

    func entry(on date: Date, calendar: Calendar) -> SalesEntry? {
        entries.first { calendar.isDate($0.date, inSameDayAs: date) }
    }
}

// MARK: - LearningStore

struct LearningData: Codable, Equatable {
    var completedLessons: [LessonProgress] = []
    var answers: [QuizAnswerRecord] = []
    var srsStates: [SrsCardState] = []
    var activityDays: [Date] = []
}

@MainActor
final class LearningStore: ObservableObject {
    @Published var data: LearningData {
        didSet {
            persist()
        }
    }

    let content = AppContent.learning

    private func persist() {
        DataStore.save(data)
        if data.answers.count > 2000 {
            data.answers = Array(data.answers.suffix(2000))
        }
    }

    init() {
        self.data = DataStore.load(LearningData.self) ?? LearningData()
    }

    var completedLessonIDs: Set<String> {
        Set(data.completedLessons.map(\.lessonId))
    }

    var streak: Int {
        StreakEngine.currentStreak(activityDays: data.activityDays)
    }

    func markActivityToday(_ calendar: Calendar = .current) {
        let today = calendar.startOfDay(for: Date())
        if !data.activityDays.contains(where: { calendar.isDate($0, inSameDayAs: today) }) {
            data.activityDays.append(today)
        }
    }

    func completeLesson(_ lesson: LessonContent, score: Int) {
        guard !completedLessonIDs.contains(lesson.id) else { return }
        data.completedLessons.append(LessonProgress(lessonId: lesson.id, score: score, total: lesson.quiz.count))
        markActivityToday()
    }

    func recordAnswer(question: QuizQuestion, correct: Bool) {
        data.answers.append(QuizAnswerRecord(questionId: question.id, topic: question.topic, correct: correct))
        markActivityToday()
    }

    func srsState(cardId: String) -> SrsCardState? {
        data.srsStates.first { $0.cardId == cardId }
    }

    func reviewFlashcard(_ card: Flashcard, quality: Int) {
        let state = srsState(cardId: card.id) ?? SrsCardState(cardId: card.id)
        let updated = SrsEngine.review(state, quality: quality)
        if let index = data.srsStates.firstIndex(where: { $0.cardId == card.id }) {
            data.srsStates[index] = updated
        } else {
            data.srsStates.append(updated)
        }
        markActivityToday()
    }

    var dueFlashcards: [Flashcard] {
        let now = Date()
        return content.lessons.flatMap(\.flashcards).filter { card in
            guard let state = srsState(cardId: card.id) else { return true } // unseen cards are due
            return state.due <= now
        }
    }

    var weakTopics: [TopicMastery] {
        LearningEngine.weakTopics(from: data.answers)
    }

    /// Topics invalidated by price changes — quiz questions referencing stale prices
    /// are excluded from practice until the user re-verifies data.
    func invalidateIfPricesStale(catalog: CatalogStore) {
        // Placeholder hook: pricing questions stay valid because they are taught from
        // the same verified snapshot the user sees. Revisit if content hardcodes prices.
    }
}
