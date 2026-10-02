import Foundation
import Testing
@testable import WakeCore

// Same checks as prototype/test_quizzes.py, run against the real word data.

private let maker = QuizMaker(library: library)
private let words = library.words

struct QuizCase: CustomTestStringConvertible, Sendable {
    let word: Word
    let kind: Quiz.Kind
    var testDescription: String { "\(word.conceptId)-\(kind.rawValue)" }

    static let all = words.flatMap { w in maker.availableKinds(for: w).map { QuizCase(word: w, kind: $0) } }
}

@Test(arguments: QuizCase.all, [true, false])
func quizIsWellFormed(_ c: QuizCase, sameTheme: Bool) throws {
    var rng = SeededRandom(seed: 7)
    let quiz = try maker.make(c.kind, for: c.word, pool: words, sameTheme: sameTheme, using: &rng)
    #expect(quiz.kind == c.kind && quiz.target == c.word)

    switch quiz {
    case .meaningToEnglish(_, let options), .meaningToChinese(_, let options),
         .hearAndTap(_, let options), .pictureMatch(_, _, let options), .fillBlank(_, _, _, let options):
        #expect(options.count == 4 && Set(options.map(\.id)).count == 4)
        #expect(options.contains(c.word))
        #expect(Set(options.map { maker.english($0) }).count == 4, "two options mean the same thing")
    case .trueFalse:
        break
    case .matchPairs(_, let left, let right):
        #expect(left.contains(c.word))
        #expect(left.count == 4 && Set(right.map(\.id)) == Set(left.map(\.id)))
    }
}

@Test func trueFalseHasBothOutcomes() throws {
    var answers = Set<Bool>()
    for seed in 0..<20 {
        var rng = SeededRandom(seed: UInt64(seed))
        if case .trueFalse(_, _, let isTrue) = try maker.make(.trueFalse, for: words[0], pool: words, using: &rng) {
            answers.insert(isTrue)
        }
    }
    #expect(answers == [true, false])
}

@Test func trueFalseFalseStatementIsReallyWrong() throws {
    for word in words {
        for seed in 0..<10 {
            var rng = SeededRandom(seed: UInt64(seed))
            if case .trueFalse(_, let shown, false) = try maker.make(.trueFalse, for: word, pool: words, using: &rng) {
                #expect(shown != maker.english(word))
            }
        }
    }
}

@Test func pictureMatchNeedsEmojiAndOnlyUsesEmojiWords() throws {
    if let noEmoji = words.first(where: { maker.emoji($0) == nil }) {
        #expect(!maker.availableKinds(for: noEmoji).contains(.pictureMatch))
        #expect(throws: QuizMaker.QuizError.notAvailable(.pictureMatch)) {
            try maker.make(.pictureMatch, for: noEmoji, pool: words)
        }
    }
    let word = words.first { maker.emoji($0) != nil }!
    var rng = SeededRandom(seed: 3)
    let quiz = try maker.make(.pictureMatch, for: word, pool: words, using: &rng)
    #expect(quiz.options.allSatisfy { maker.emoji($0) != nil })
}

@Test func fillBlankHidesTheAnswerAndAvoidsSameThemeWords() throws {
    for word in words where maker.availableKinds(for: word).contains(.fillBlank) {
        var rng = SeededRandom(seed: 5)
        guard case .fillBlank(_, let sentence, _, let options) = try maker.make(.fillBlank, for: word, pool: words, using: &rng) else {
            Issue.record("wrong kind")
            continue
        }
        #expect(!sentence.contains(word.text) && sentence.contains(Quiz.blank))
        for option in options where option != word {
            #expect(maker.theme(option) != maker.theme(word), "\(option.text) could also fit the blank")
        }
    }
}

@Test func sameSeedGivesSameQuiz() throws {
    var a = SeededRandom(seed: 42)
    var b = SeededRandom(seed: 42)
    #expect(try maker.make(for: words[10], pool: words, using: &a) == maker.make(for: words[10], pool: words, using: &b))
}

@Test func tooSmallPoolThrowsClearError() {
    #expect(throws: QuizMaker.QuizError.notEnoughWords(needed: 3)) {
        try maker.make(.meaningToEnglish, for: words[0], pool: Array(words.prefix(2)))
    }
}
