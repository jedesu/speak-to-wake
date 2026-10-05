import Foundation
import SwiftData
import WakeCore

/// One wake-up: `required` correct answers turn the alarm off.
///
/// Words come from the review schedule (learned words only, most overdue first).
/// A wrong answer swaps in a different word that must be answered instead.
@Observable
final class WakeSession {
    struct Prompt: Identifiable {
        let id = UUID()
        let word: Word
        let challenge: Challenge
        /// Built ahead of time for tap challenges, so it doesn't change on redraw.
        let quiz: Quiz?
    }

    static let defaultRequired = 3

    let required: Int
    let startedAt = Date.now
    private(set) var prompt: Prompt?
    private(set) var passed = 0
    private(set) var message: String?
    private(set) var finished = false

    var hasWords: Bool { !pool.isEmpty }

    private let library = AppContent.library
    private let planner = ChallengePlanner(maker: Learning.maker)
    private var pool: [Word] = []
    private var planned: [(word: Word, challenge: Challenge)] = []
    private var nextIndex = 0
    private var answeredOnce: Set<String> = []
    private var speechMissesInARow = 0
    private var misses = 0
    private var rng = SystemRandomNumberGenerator()

    init(reviews: [ReviewState], required: Int = defaultRequired, difficulty: SRS.Difficulty = .normal) {
        let library = AppContent.library
        let pool = reviews.compactMap { library.word(id: $0.wordID) }
        self.required = min(required, max(pool.count, 1))
        self.pool = pool
        let ids = SRS.pickForAlarm(reviews.map(\.card), today: .today, n: self.required, difficulty: difficulty)
        let words = ids.compactMap { library.word(id: $0) }
        planned = Array(zip(words, planner.plan(words, using: &rng)))
        advance()
    }

    /// Call when a prompt is answered. Updates the review schedule and the log.
    func answer(correct: Bool, transcript: String? = nil, score: Double? = nil, chosen: String? = nil,
                reviews: [ReviewState], context: ModelContext) {
        guard let prompt else { return }
        context.insert(Attempt(wordID: prompt.word.id, challengeType: prompt.challenge.logName, context: "wake",
                               passed: correct, retryNumber: misses, transcript: transcript, matchScore: score,
                               chosenOption: chosen))
        // Only the first answer for a word moves it in the review schedule.
        if answeredOnce.insert(prompt.word.id).inserted,
           let state = reviews.first(where: { $0.wordID == prompt.word.id }) {
            state.update(from: SRS.review(state.card, correct ? .correct : .missed, today: .today))
        }
        try? context.save()

        if correct {
            passed += 1
            speechMissesInARow = 0
            message = nil
            if passed >= required {
                finished = true
                self.prompt = nil
            } else {
                advance()
            }
        } else {
            misses += 1
            if prompt.challenge.isSpeech { speechMissesInARow += 1 }
            replace(after: prompt)
            message = "Not quite. Try this one instead."
        }
    }

    /// "Can't speak right now": same word, as a tap question. Not counted as a miss.
    func switchToTap() {
        guard let prompt, let challenge = planner.tapChallenges(for: prompt.word).randomElement(using: &rng) else { return }
        self.prompt = make(prompt.word, challenge)
        message = nil
    }

    // MARK: Private

    private func advance() {
        if nextIndex < planned.count {
            let (word, challenge) = planned[nextIndex]
            nextIndex += 1
            prompt = make(word, challenge)
        } else if let word = pool.randomElement(using: &rng) {
            // Fewer planned words than required (a small pool): ask any learned word.
            prompt = make(word, planner.plan([word], using: &rng)[0])
        }
    }

    private func replace(after missed: Prompt) {
        let others = pool.filter { $0 != missed.word }
        let word = others.randomElement(using: &rng) ?? missed.word
        let challenge = planner.replacement(after: missed.challenge, for: word,
                                            speechMissesInARow: speechMissesInARow, using: &rng)
        prompt = make(word, challenge)
    }

    private func make(_ word: Word, _ challenge: Challenge) -> Prompt {
        var quiz: Quiz?
        if case .tap(let kind) = challenge {
            quiz = try? Learning.maker.make(kind, for: word, pool: library.words)
        }
        return Prompt(word: word, challenge: challenge, quiz: quiz)
    }
}
