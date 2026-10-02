import Foundation
import SwiftData
import WakeCore

/// The rules that connect studying, reviewing and saved progress.
enum Learning {
    /// Words per Review session (from simulate_srs.py: alarm + a 10-word review keeps the backlog small).
    static let reviewSessionSize = 10
    /// New packs are blocked while more words than this are due, so the backlog can't pile up.
    static let overdueLimit = 15

    /// Tap quiz kinds used for one word at a time. Match pairs is added separately.
    static let singleWordKinds: [Quiz.Kind] = [.meaningToEnglish, .meaningToChinese, .hearAndTap,
                                               .pictureMatch, .trueFalse, .fillBlank]

    static let maker = QuizMaker(library: AppContent.library)

    /// A random single-word quiz, preferring a different kind from `avoiding` (for retries).
    static func quiz(for word: Word, avoiding: Quiz.Kind? = nil) -> Quiz {
        let kinds = maker.availableKinds(for: word).filter { singleWordKinds.contains($0) }
        let kind = kinds.filter { $0 != avoiding }.randomElement() ?? kinds.randomElement()!
        // The pool is every word in the app: wrong answers may be words you haven't learned yet.
        return try! maker.make(kind, for: word, pool: AppContent.library.words)
    }

    static func dueCount(_ reviews: [ReviewState], today: Day = .today) -> Int {
        reviews.count { Day($0.due) <= today }
    }

    /// Call when a study session ends. Words already in review keep their progress.
    static func markLearned(_ pack: Pack, in context: ModelContext, today: Day = .today) {
        let library = AppContent.library
        let packID = pack.id
        let language = library.language
        let existing = try? context.fetch(FetchDescriptor<PackProgress>(
            predicate: #Predicate { $0.packID == packID && $0.language == language }))
        if let progress = existing?.first {
            progress.learnedAt = progress.learnedAt ?? .now
        } else {
            context.insert(PackProgress(packID: pack.id, language: language, learnedAt: .now))
        }

        for word in library.words(in: pack) {
            let id = word.id
            let found = try? context.fetch(FetchDescriptor<ReviewState>(predicate: #Predicate { $0.wordID == id }))
            if found?.isEmpty ?? true {
                context.insert(ReviewState(SRS.learn(word.id, today: today)))
            }
        }
        try? context.save()
    }

    /// Saves one answer to the attempt log (exported as CSV later).
    static func record(_ quiz: Quiz, correct: Bool, chosen: String, context: String, retry: Int,
                       in modelContext: ModelContext) {
        modelContext.insert(Attempt(wordID: quiz.target.id, challengeType: quiz.kind.rawValue, context: context,
                                    passed: correct, retryNumber: retry, chosenOption: chosen))
    }
}
