import SwiftUI
import TeliaCore

// MARK: - Academy home

struct AcademyView: View {
    @EnvironmentObject private var learning: LearningStore
    @EnvironmentObject private var progress: ProgressStore
    @EnvironmentObject private var catalog: CatalogStore

    var body: some View {
        List {
            statsSection
            weakSection
            programSection
            trackSection
        }
        .scrollContentBackground(.hidden)
        .navigationTitle("Akademin")
    }

    private var statsSection: some View {
        Section {
            HStack(spacing: DS.Space.m) {
                StatTile(value: "\(learning.streak)", label: "dagars streak", symbol: "flame.fill")
                StatTile(value: "\(learning.completedLessonIDs.count)", label: "klarade lektioner", symbol: "checkmark.seal.fill")
                StatTile(value: "\(learning.dueFlashcards.count)", label: "flashcards nu", symbol: "rectangle.stack.fill")
            }
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 4, leading: DS.Space.m, bottom: 4, trailing: DS.Space.m))
            NavigationLink {
                FlashcardsView()
            } label: {
                Label("Repetition – flashcards", systemImage: "rectangle.stack.fill")
            }
        } header: {
            Text("Din träning")
        }
    }

    private var weakSection: some View {
        let weak = learning.weakTopics
        return Group {
            if !weak.isEmpty {
                Section("Förbättringsområden") {
                    ForEach(weak) { topic in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(topic.topic)
                                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            ProgressBar(progress: topic.accuracy, color: .orange, height: 6)
                            Text("\(Int(topic.accuracy * 100))% rätt av \(topic.answered) svar")
                                .font(.system(.caption, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private var programSection: some View {
        let program = LearningEngine.onboardingProgram(learning.content.lessons)
        return Section("30-dagarsprogrammet") {
            if program.isEmpty {
                Text("Inget program inlagt.")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(program) { lesson in
                    NavigationLink {
                        LessonView(lesson: lesson)
                    } label: {
                        HStack {
                            Image(systemName: learning.completedLessonIDs.contains(lesson.id)
                                  ? "checkmark.circle.fill" : "circle.dashed")
                                .foregroundStyle(learning.completedLessonIDs.contains(lesson.id) ? .green : Color.secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Dag \(lesson.programDay ?? 0): \(lesson.title)")
                                    .font(.system(.subheadline, design: .rounded).weight(.medium))
                                Text(lesson.summary)
                                    .font(.system(.caption, design: .rounded))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
            }
        }
    }

    private var trackSection: some View {
        Section("Alla spår") {
            ForEach(LearningTrack.allCases, id: \.self) { track in
                let lessons = learning.content.lessons.filter { $0.track == track }
                let done = lessons.filter { learning.completedLessonIDs.contains($0.id) }.count
                NavigationLink {
                    TrackDetailView(track: track)
                } label: {
                    HStack {
                        Label(track.displayName, systemImage: track.symbolName)
                        Spacer()
                        Text("\(done)/\(lessons.count)")
                            .font(.system(.caption, design: .rounded).weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

// MARK: - Track detail

struct TrackDetailView: View {
    let track: LearningTrack
    @EnvironmentObject private var learning: LearningStore

    var body: some View {
        List {
            ForEach(learning.content.lessons.filter { $0.track == track }) { lesson in
                NavigationLink {
                    LessonView(lesson: lesson)
                } label: {
                    HStack {
                        Image(systemName: learning.completedLessonIDs.contains(lesson.id)
                              ? "checkmark.circle.fill" : "circle.dashed")
                            .foregroundStyle(learning.completedLessonIDs.contains(lesson.id) ? .green : Color.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(lesson.title)
                                .font(.system(.subheadline, design: .rounded).weight(.medium))
                            Text("\(lesson.minutes) min · \(lesson.quiz.count) quizfrågor")
                                .font(.system(.caption, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle(track.displayName)
    }
}

// MARK: - Lesson

struct LessonView: View {
    let lesson: LessonContent

    @EnvironmentObject private var learning: LearningStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var page = 0
    @State private var quizIndex = 0
    @State private var selected: Int? = nil
    @State private var correctCount = 0
    @State private var finished = false

    var body: some View {
        ScrollView {
            VStack(spacing: DS.Space.m) {
                if page < lesson.pages.count {
                    readerView
                } else if quizIndex < lesson.quiz.count {
                    quizView
                } else {
                    completionView
                }
            }
            .padding(DS.Space.m)
        }
        // Transparent so the app-wide premium canvas shows through.
        .navigationTitle(lesson.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var readerView: some View {
        VStack(spacing: DS.Space.m) {
            SectionCard(title: "Del \(page + 1) av \(lesson.pages.count)", symbol: "book.fill") {
                Text(lesson.pages[page])
                    .font(.system(.subheadline, design: .rounded))
                    .lineSpacing(4)
            }
            PrimaryButton(title: page == lesson.pages.count - 1
                          ? (lesson.quiz.isEmpty ? "Klar" : "Till quizet")
                          : "Nästa del",
                          symbol: "arrow.right") {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: DS.Motion.content)) {
                    if page < lesson.pages.count - 1 { page += 1 } else if !lesson.quiz.isEmpty { page += 1 } else { finished = true }
                }
            }
        }
    }

    private var quizView: some View {
        let question = lesson.quiz[quizIndex]
        return SectionCard(title: "Quiz \(quizIndex + 1)/\(lesson.quiz.count)", symbol: "questionmark.bubble.fill") {
            VStack(alignment: .leading, spacing: DS.Space.m) {
                Text(question.prompt)
                    .font(.system(.body, design: .rounded).weight(.medium))
                VStack(spacing: DS.Space.s) {
                    ForEach(Array(question.options.enumerated()), id: \.offset) { index, option in
                        let isCorrect = index == question.correctIndex
                        let isSelected = selected == index
                        Button {
                            guard selected == nil else { return }
                            withAnimation(.easeInOut(duration: DS.Motion.reveal)) { selected = index }
                            if isCorrect { correctCount += 1; Haptics.success() }
                            learning.recordAnswer(question: question, correct: isCorrect)
                        } label: {
                            HStack {
                                Text(option)
                                    .font(.system(.subheadline, design: .rounded))
                                    .multilineTextAlignment(.leading)
                                Spacer()
                                if selected != nil {
                                    Image(systemName: isCorrect ? "checkmark.circle.fill" : (isSelected ? "xmark.circle.fill" : "circle"))
                                        .foregroundStyle(isCorrect ? .green : (isSelected ? .red : Color.secondary))
                                }
                            }
                            .padding(DS.Space.m)
                            .background(
                                RoundedRectangle(cornerRadius: DS.Radius.tile, style: .continuous)
                                    .fill(optionFill(isCorrect: isCorrect, isSelected: isSelected))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: DS.Radius.tile, style: .continuous)
                                    .strokeBorder(optionBorder(isCorrect: isCorrect, isSelected: isSelected), lineWidth: 1.5)
                            )
                        }
                        .buttonStyle(PressableStyle(scale: 0.98))
                        .foregroundStyle(.primary)
                    }
                }
                if selected != nil {
                    VStack(alignment: .leading, spacing: DS.Space.s) {
                        Text(question.explanation)
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(.secondary)
                        PrimaryButton(title: quizIndex == lesson.quiz.count - 1 ? "Visa resultat" : "Nästa fråga", symbol: "arrow.right") {
                            quizIndex += 1
                            selected = nil
                        }
                    }
                    .transition(.opacity)
                }
            }
        }
    }

    private var completionView: some View {
        SectionCard(title: "Klart!", symbol: "checkmark.seal.fill") {
            VStack(spacing: DS.Space.m) {
                Text("\(correctCount) av \(max(1, lesson.quiz.count)) rätt")
                    .font(.system(.title2, design: .rounded).weight(.bold))
                if lesson.flashcards.isEmpty == false {
                    Text("Flashcards från lektionen läggs in i din repetition.")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                PrimaryButton(title: "Markera lektionen som klar", symbol: "checkmark") {
                    learning.completeLesson(lesson, score: correctCount)
                    finished = true
                    Haptics.success()
                }
            }
        }
    }

    private func optionFill(isCorrect: Bool, isSelected: Bool) -> Color {
        guard selected != nil else { return Color(.tertiarySystemFill) }
        if isCorrect { return DS.Purple.base.opacity(0.14) }
        if isSelected { return Color.red.opacity(0.1) }
        return Color(.tertiarySystemFill)
    }

    private func optionBorder(isCorrect: Bool, isSelected: Bool) -> Color {
        guard selected != nil else { return .clear }
        if isCorrect { return DS.Purple.base }
        if isSelected { return .red.opacity(0.6) }
        return .clear
    }
}

// MARK: - Flashcards (SRS)

struct FlashcardsView: View {
    @EnvironmentObject private var learning: LearningStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var index = 0
    @State private var showingBack = false

    private var cards: [Flashcard] {
        learning.dueFlashcards
    }

    var body: some View {
        ScrollView {
            VStack(spacing: DS.Space.m) {
                if cards.isEmpty {
                    EmptyStateView(
                        symbol: "checkmark.seal",
                        title: "Allt repeterat!",
                        message: "Inga flashcards förfaller just nu. Kom tillbaka imorgon – spaced repetition fungerar bäst lite varje dag."
                    )
                } else if index < cards.count {
                    let card = cards[index]
                    VStack(spacing: DS.Space.m) {
                        Text("Kort \(index + 1) av \(cards.count)")
                            .font(.system(.caption, design: .rounded).weight(.semibold))
                            .foregroundStyle(.secondary)
                        ZStack {
                            frontCard(card)
                                .opacity(showingBack ? 0 : 1)
                                .rotation3DEffect(.degrees(showingBack ? 180 : 0), axis: (x: 0, y: 1, z: 0))
                            backCard(card)
                                .opacity(showingBack ? 1 : 0)
                                .rotation3DEffect(.degrees(showingBack ? 0 : -180), axis: (x: 0, y: 1, z: 0))
                        }
                        .frame(height: 230)
                        .onTapGesture {
                            flip()
                        }
                        .accessibilityLabel(showingBack ? "Baksida" : "Framsida")
                        .accessibilityHint("Dubbeltryck för att vända")

                        if showingBack {
                            VStack(spacing: DS.Space.s) {
                                Text("Hur gick det?")
                                    .font(.system(.caption, design: .rounded).weight(.semibold))
                                    .foregroundStyle(.secondary)
                                HStack(spacing: DS.Space.s) {
                                    gradeButton("Igen", quality: 1, color: .red)
                                    gradeButton("Svårt", quality: 3, color: .orange)
                                    gradeButton("Bra", quality: 4, color: DS.Purple.base)
                                    gradeButton("Lätt", quality: 5, color: .green)
                                }
                            }
                            .transition(.opacity)
                        } else {
                            PrimaryButton(title: "Vänd kortet", symbol: "arrow.triangle.2.circlepath") {
                                flip()
                            }
                        }
                    }
                } else {
                    SectionCard(title: "Passet klart", symbol: "checkmark.seal.fill") {
                        Text("Bra jobbat – repetitionen är sparad och nästa förfallodag är räknad ut.")
                            .font(.system(.subheadline, design: .rounded))
                    }
                }
            }
            .padding(DS.Space.m)
        }
        // Transparent so the app-wide premium canvas shows through.
        .navigationTitle("Repetition")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func flip() {
        if reduceMotion {
            showingBack.toggle()
        } else {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                showingBack.toggle()
            }
        }
    }

    private func frontCard(_ card: Flashcard) -> some View {
        SectionCard(title: card.topic, symbol: "questionmark") {
            Text(card.front)
                .font(.system(.title3, design: .rounded).weight(.semibold))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
        .frame(height: 230)
    }

    private func backCard(_ card: Flashcard) -> some View {
        SectionCard(title: card.topic, symbol: "lightbulb", gradient: true) {
            Text(card.back)
                .font(.system(.subheadline, design: .rounded))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
        .frame(height: 230)
    }

    private func gradeButton(_ title: String, quality: Int, color: Color) -> some View {
        Button {
            guard index < cards.count else { return }
            learning.reviewFlashcard(cards[index], quality: quality)
            withAnimation(reduceMotion ? nil : .easeInOut(duration: DS.Motion.content)) {
                showingBack = false
                index += 1
            }
            Haptics.tap()
        } label: {
            Text(title)
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .padding(.horizontal, DS.Space.m)
                .padding(.vertical, DS.Space.s + 2)
                .background(Capsule().fill(color.opacity(0.15)))
                .foregroundStyle(color)
        }
        .buttonStyle(PressableStyle())
    }
}
