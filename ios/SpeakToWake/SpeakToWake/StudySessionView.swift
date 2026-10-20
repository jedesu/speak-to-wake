import SwiftData
import SwiftUI
import WakeCore

/// Studying one pack: a flashcard for each word, then an optional practice round
/// (until every word has been answered right). Either way the pack is marked learned.
///
/// The first time, cards show everything. In `flipMode` ("Study again") each card
/// hides the meaning until you tap, so you try to recall it first: that's retrieval
/// practice, which beats just looking (see the research notes in PLAN.md).
struct StudySessionView: View {
    let pack: Pack
    var flipMode = false
    /// Skip the cards and go straight to the quiz (for packs already learned).
    var startWithQuiz = false

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    private enum Stage { case cards, choice, practice, done }

    @State private var stage = Stage.cards
    @State private var cardIndex = 0
    @State private var queue: [Quiz] = []
    @State private var position = 0
    @State private var missed: Set<String> = []
    @State private var revealed = false
    @State private var notKnown: Set<String> = []

    private var words: [Word] { AppContent.library.words(in: pack) }

    private var progress: Double {
        switch stage {
        case .cards: Double(cardIndex) / Double(words.count) * 0.5
        case .choice: 0.5
        case .practice: 0.5 + Double(position) / Double(max(queue.count, 1)) * 0.5
        case .done: 1
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ProgressView(value: progress)
                    .padding()
                switch stage {
                case .cards:
                    cards
                case .choice:
                    choice
                case .practice:
                    if position < queue.count {
                        ScrollView {
                            QuizCard(quiz: queue[position]) { correct, chosen, _ in
                                answered(correct: correct, chosen: chosen)
                            }
                            .id(position)
                        }
                    }
                case .done:
                    done
                }
            }
            .background(Theme.ground)
            .navigationTitle(pack.title)
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                if startWithQuiz && stage == .cards { startPractice() }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    // MARK: Flashcards

    private var cards: some View {
        VStack {
            FlashcardView(word: words[cardIndex], revealed: !flipMode || revealed)
                .id(cardIndex)
                .contentShape(.rect)
                .onTapGesture {
                    if flipMode { revealed = true }
                }
            Spacer()
            if flipMode {
                flipButtons
            } else {
                nextButtons
            }
        }
    }

    @ViewBuilder
    private var flipButtons: some View {
        if !revealed {
            Button {
                revealed = true
            } label: {
                Text("Show meaning").font(.title3.bold()).frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .padding()
        } else {
            HStack(spacing: 12) {
                Button {
                    rate(knewIt: false)
                } label: {
                    Text("Not yet").font(.title3.bold()).frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .tint(.orange)
                Button {
                    rate(knewIt: true)
                } label: {
                    Text("I knew it").font(.title3.bold()).frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
            }
            .padding()
        }
    }

    /// Self-rated, so it's logged but doesn't move the word in the review schedule.
    private func rate(knewIt: Bool) {
        let word = words[cardIndex]
        modelContext.insert(Attempt(wordID: word.id, challengeType: "flashcard", context: "learn", passed: knewIt))
        if !knewIt { notKnown.insert(word.id) }
        revealed = false
        if cardIndex + 1 < words.count {
            cardIndex += 1
        } else {
            stage = .choice
        }
    }

    private var nextButtons: some View {
            HStack {
                Button("Back") { cardIndex -= 1 }
                    .disabled(cardIndex == 0)
                Spacer()
                Button {
                    if cardIndex + 1 < words.count {
                        cardIndex += 1
                    } else {
                        stage = .choice
                    }
                } label: {
                    Text(cardIndex + 1 < words.count ? "Next" : "Done")
                        .font(.title3.bold())
                        .frame(minWidth: 160, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
    }

    // MARK: Practice or finish

    private var choice: some View {
        VStack(spacing: 16) {
            Spacer()
            Text(flipMode ? "You knew \(words.count - notKnown.count) of \(words.count)"
                          : "You've seen all \(words.count) words")
                .font(.title.bold())
            HStack(spacing: 8) {
                ForEach(words) { word in
                    Text(word.text).font(.title2)
                }
            }
            Text("A quick quiz now helps them stick. Recalling a word beats reading it again.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                startPractice()
            } label: {
                Text("Practice now").font(.title3.bold()).frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            Button {
                Learning.markLearned(pack, in: modelContext)
                stage = .done
            } label: {
                Text("Finish without practice").frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
            Button("Look at the cards again") {
                cardIndex = 0
                revealed = false
                stage = .cards
            }
            .padding(.top, 4)
        }
        .padding()
    }

    // MARK: Practice

    private func startPractice() {
        queue = words.shuffled().map { Learning.quiz(for: $0) }
        if let first = words.first, let pairs = try? Learning.maker.make(.matchPairs, for: first, pool: AppContent.library.words) {
            queue.append(pairs)
        }
        position = 0
        stage = .practice
    }

    private func answered(correct: Bool, chosen: String) {
        let quiz = queue[position]
        let retry = queue[..<position].count { $0.target == quiz.target }
        Learning.record(quiz, correct: correct, chosen: chosen, context: "learn", retry: retry, in: modelContext)
        if !correct {
            missed.insert(quiz.target.id)
            // Ask about the same word again later, in a different way.
            if quiz.kind != .matchPairs {
                queue.append(Learning.quiz(for: quiz.target, avoiding: quiz.kind))
            }
        }
        position += 1
        if position == queue.count {
            Learning.markLearned(pack, in: modelContext)
            stage = .done
        }
    }

    // MARK: Done

    private var done: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 80))
                .foregroundStyle(.green)
            let again = flipMode || startWithQuiz
            Text(again ? "Nice work!" : "\(pack.title) learned!").font(.largeTitle.bold())
            Text(again ? "These words stay in your review schedule and your alarm."
                       : "These \(words.count) words are now in your review schedule and your alarm. They'll come back tomorrow.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            if !missed.isEmpty {
                Text("You got \(words.count - missed.count) of \(words.count) right the first time.")
            }
            Spacer()
            Button {
                dismiss()
            } label: {
                Text("Done").font(.title3.bold()).frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}

/// One flashcard: picture, word, pinyin, meaning and an example, read aloud.
struct FlashcardView: View {
    let word: Word
    /// False hides the picture, meaning and example, for flip-card recall.
    var revealed = true

    private var concept: Concept? { AppContent.library.concept(for: word) }

    var body: some View {
        VStack(spacing: 12) {
            if !revealed {
                Text("?").font(.system(size: 90, weight: .bold)).foregroundStyle(.tertiary)
            } else if let emoji = concept?.emoji {
                Text(emoji).font(.system(size: 90))
            }
            Text(word.text).font(.system(size: 72))
            HStack {
                Text(word.pinyin).font(.title).foregroundStyle(.secondary)
                Button {
                    Speaker.shared.say(word.text)
                } label: {
                    Image(systemName: "speaker.wave.2.fill").font(.title2)
                }
                .accessibilityLabel("Play pronunciation")
                Button {
                    Speaker.shared.say(word.text, slow: true)
                } label: {
                    Image(systemName: "tortoise.fill").font(.title2)
                }
                .accessibilityLabel("Play slowly")
            }
            Text(revealed ? concept?.english ?? "" : "What does it mean?")
                .font(.title2.bold())
                .foregroundStyle(revealed ? .primary : .secondary)

            if revealed, let example = word.example {
                VStack(spacing: 4) {
                    HStack {
                        Text(example.text).font(.title3)
                        Button {
                            Speaker.shared.say(example.text)
                        } label: {
                            Image(systemName: "speaker.wave.2")
                        }
                        .accessibilityLabel("Play example sentence")
                    }
                    Text(example.pinyin).font(.subheadline).foregroundStyle(.secondary)
                    Text(example.english).font(.subheadline)
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(Theme.chip, in: .rect(cornerRadius: 20))
            }
        }
        .padding()
        .onAppear { Speaker.shared.say(word.text) }
    }
}
