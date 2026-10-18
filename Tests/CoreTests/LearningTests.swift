import XCTest
@testable import TeliaCore

final class LearningTests: XCTestCase {

    let cal = Calendar.current

    // MARK: - SM-2

    func testSrsFirstReviewIntervals() {
        let card = SrsCardState(cardId: "f1")
        let again = SrsEngine.review(card, quality: 1)
        XCTAssertEqual(again.intervalDays, 0)
        XCTAssertEqual(again.lapses, 1)

        let good = SrsEngine.review(card, quality: 4)
        XCTAssertEqual(good.intervalDays, 1)

        let good2 = SrsEngine.review(good, quality: 4)
        XCTAssertEqual(good2.intervalDays, 3)

        let good3 = SrsEngine.review(good2, quality: 4)
        // 3 * ease (2.5) = 7.5
        XCTAssertEqual(good3.intervalDays, 7.5, accuracy: 0.01)
    }

    func testSrsEaseFloor() {
        var card = SrsCardState(cardId: "f1")
        for _ in 0..<20 { card = SrsEngine.review(card, quality: 0) }
        XCTAssertGreaterThanOrEqual(card.easeFactor, 1.3)
        XCTAssertLessThanOrEqual(card.intervalDays, 180)
    }

    func testSrsDueCards() {
        let old = SrsCardState(cardId: "old", due: cal.date(byAdding: .day, value: -3, to: Date())!)
        let future = SrsCardState(cardId: "future", due: cal.date(byAdding: .day, value: 3, to: Date())!)
        let due = SrsEngine.dueCards([old, future])
        XCTAssertEqual(due.map(\.cardId), ["old"])
    }

    // MARK: - Streak

    func testStreakCountsConsecutiveDays() {
        let today = Date()
        let days = (0..<4).compactMap { cal.date(byAdding: .day, value: -$0, to: today) }
        XCTAssertEqual(StreakEngine.currentStreak(activityDays: days), 4)
    }

    func testStreakSurvivesWithoutToday() {
        let today = Date()
        let days = (1..<3).compactMap { cal.date(byAdding: .day, value: -$0, to: today) }
        XCTAssertEqual(StreakEngine.currentStreak(activityDays: days), 2)
    }

    func testStreakBreaksAfterGap() {
        let today = Date()
        let days = [
            cal.date(byAdding: .day, value: -1, to: today)!,
            cal.date(byAdding: .day, value: -2, to: today)!,
            cal.date(byAdding: .day, value: -5, to: today)!,
        ]
        XCTAssertEqual(StreakEngine.currentStreak(activityDays: days), 2)
    }

    func testStreakZeroWhenNothing() {
        XCTAssertEqual(StreakEngine.currentStreak(activityDays: []), 0)
    }

    // MARK: - Mastery & plans

    func testMasteryAndWeakTopics() {
        var answers: [QuizAnswerRecord] = []
        for _ in 0..<5 { answers.append(QuizAnswerRecord(questionId: "q", topic: "Priser", correct: true)) }
        for _ in 0..<4 { answers.append(QuizAnswerRecord(questionId: "q", topic: "Priser", correct: false)) }
        for _ in 0..<4 { answers.append(QuizAnswerRecord(questionId: "q", topic: "Kartläggning", correct: true)) }
        let mastery = LearningEngine.mastery(from: answers)
        XCTAssertEqual(mastery.count, 2)
        let prices = mastery.first { $0.topic == "Priser" }!
        XCTAssertEqual(prices.answered, 9)
        XCTAssertEqual(prices.correct, 5)
        let weak = LearningEngine.weakTopics(from: answers)
        XCTAssertEqual(weak.map(\.topic), ["Priser"])
    }

    func testWeeklyPlanPrioritizesWeakAndProgramOrder() {
        let lessonA = LessonContent(id: "la", track: .productKnowledge, title: "A", summary: "",
                                    pages: ["p"], quiz: [QuizQuestion(id: "q", topic: "Priser", prompt: "", options: ["a"], correctIndex: 0, explanation: "")],
                                    flashcards: [], minutes: 5, programDay: 4)
        let lessonB = LessonContent(id: "lb", track: .discovery, title: "B", summary: "",
                                    pages: ["p"], quiz: [QuizQuestion(id: "q", topic: "Kartläggning", prompt: "", options: ["a"], correctIndex: 0, explanation: "")],
                                    flashcards: [], minutes: 5, programDay: 1)
        let plan = LearningEngine.weeklyPlan(
            lessons: [lessonA, lessonB], completedLessonIDs: [],
            weakTopics: [TopicMastery(topic: "Priser", answered: 5, correct: 1)],
            weekStart: cal.startOfDay(for: Date()), calendar: cal, perDay: 1
        )
        // Weak-topic lesson (A) should come first despite programDay ordering.
        XCTAssertEqual(plan.first?.lessons.first?.id, "la")
        XCTAssertEqual(plan.count, 2)
    }

    func testOnboardingProgramSortedByDay() {
        let l2 = LessonContent(id: "l2", track: .discovery, title: "Dag 2", summary: "", pages: [], quiz: [], flashcards: [], minutes: 3, programDay: 2)
        let l1 = LessonContent(id: "l1", track: .productKnowledge, title: "Dag 1", summary: "", pages: [], quiz: [], flashcards: [], minutes: 3, programDay: 1)
        let lNone = LessonContent(id: "lx", track: .objections, title: "Extra", summary: "", pages: [], quiz: [], flashcards: [], minutes: 3)
        let program = LearningEngine.onboardingProgram([l2, lNone, l1])
        XCTAssertEqual(program.map(\.id), ["l1", "l2"])
    }
}
