import Foundation

/// One tap quiz about one target word, ported from prototype/quizzes.py.
///
/// Wrong answers ("distractors") come from the same theme when `sameTheme` is
/// true (harder, more plausible) or from other themes (easier; better when groggy).
/// Options are words, so the screen decides how to label them.
public enum Quiz: Hashable, Sendable {
    /// See 苹果 píngguǒ, tap "apple".
    case meaningToEnglish(target: Word, options: [Word])
    /// See "apple", tap 苹果.
    case meaningToChinese(target: Word, options: [Word])
    /// Hear the word (text-to-speech), tap it.
    case hearAndTap(target: Word, options: [Word])
    /// See 🍎, tap 苹果.
    case pictureMatch(target: Word, emoji: String, options: [Word])
    /// "苹果 means banana": true or false?
    case trueFalse(target: Word, shownMeaning: String, isTrue: Bool)
    /// Tap the missing word in the example sentence.
    case fillBlank(target: Word, sentence: String, hint: String, options: [Word])
    /// Pair four words with their meanings. `meanings` is the same words, shuffled.
    case matchPairs(target: Word, words: [Word], meanings: [Word])

    public enum Kind: String, CaseIterable, Codable, Sendable {
        case meaningToEnglish = "meaning_to_english"
        case meaningToChinese = "meaning_to_chinese"
        case hearAndTap = "hear_and_tap"
        case pictureMatch = "picture_match"
        case trueFalse = "true_false"
        case fillBlank = "fill_blank"
        case matchPairs = "match_pairs"
    }

    public static let blank = "＿＿"

    public var kind: Kind {
        switch self {
        case .meaningToEnglish: .meaningToEnglish
        case .meaningToChinese: .meaningToChinese
        case .hearAndTap: .hearAndTap
        case .pictureMatch: .pictureMatch
        case .trueFalse: .trueFalse
        case .fillBlank: .fillBlank
        case .matchPairs: .matchPairs
        }
    }

    public var target: Word {
        switch self {
        case .meaningToEnglish(let t, _), .meaningToChinese(let t, _), .hearAndTap(let t, _),
             .pictureMatch(let t, _, _), .trueFalse(let t, _, _), .fillBlank(let t, _, _, _),
             .matchPairs(let t, _, _):
            t
        }
    }

    /// The four buttons, for the multiple-choice kinds. Empty for true/false and match pairs.
    public var options: [Word] {
        switch self {
        case .meaningToEnglish(_, let o), .meaningToChinese(_, let o), .hearAndTap(_, let o),
             .pictureMatch(_, _, let o), .fillBlank(_, _, _, let o):
            o
        case .trueFalse, .matchPairs:
            []
        }
    }
}

public struct QuizMaker: Sendable {
    public let library: ContentLibrary

    public init(library: ContentLibrary) {
        self.library = library
    }

    public enum QuizError: Error, Equatable {
        case notEnoughWords(needed: Int)
        case notAvailable(Quiz.Kind)
    }

    /// Which quiz kinds make sense for this word.
    public func availableKinds(for word: Word) -> [Quiz.Kind] {
        var kinds: [Quiz.Kind] = [.meaningToEnglish, .meaningToChinese, .hearAndTap, .trueFalse, .matchPairs]
        if emoji(word) != nil { kinds.append(.pictureMatch) }
        // Fill the blank only when the word appears once: 一边…一边… would give it away.
        if let example = word.example, example.text.components(separatedBy: word.text).count == 2 {
            kinds.append(.fillBlank)
        }
        return kinds
    }

    /// Builds one quiz. `pool` is every word that may appear as a wrong answer.
    /// `sameTheme` nil uses each kind's default (see quizzes.py).
    public func make<R: RandomNumberGenerator>(
        _ kind: Quiz.Kind? = nil, for word: Word, pool: [Word], sameTheme: Bool? = nil, using rng: inout R
    ) throws -> Quiz {
        let kind = kind ?? availableKinds(for: word).randomElement(using: &rng)!
        guard availableKinds(for: word).contains(kind) else { throw QuizError.notAvailable(kind) }

        switch kind {
        case .meaningToEnglish:
            return .meaningToEnglish(target: word, options: try choices(word, pool, sameTheme ?? false, &rng))
        case .meaningToChinese:
            return .meaningToChinese(target: word, options: try choices(word, pool, sameTheme ?? false, &rng))
        case .hearAndTap:
            return .hearAndTap(target: word, options: try choices(word, pool, sameTheme ?? false, &rng))
        case .pictureMatch:
            let options = try choices(word, pool.filter { emoji($0) != nil }, sameTheme ?? false, &rng)
            return .pictureMatch(target: word, emoji: emoji(word)!, options: options)
        case .trueFalse:
            if Bool.random(using: &rng) {
                return .trueFalse(target: word, shownMeaning: english(word), isTrue: true)
            }
            let wrong = try distractors(word, pool, 1, sameTheme ?? true, &rng)[0]
            return .trueFalse(target: word, shownMeaning: english(wrong), isTrue: false)
        case .fillBlank:
            // Other-theme wrong answers by default: other fruits could also fit "I like eating ＿＿".
            let example = word.example!
            let sentence = example.text.replacing(word.text, with: Quiz.blank, maxReplacements: 1)
            return .fillBlank(target: word, sentence: sentence, hint: example.english,
                              options: try choices(word, pool, sameTheme ?? false, &rng))
        case .matchPairs:
            let group = [word] + (try distractors(word, pool, 3, sameTheme ?? true, &rng))
            return .matchPairs(target: word, words: group, meanings: group.shuffled(using: &rng))
        }
    }

    public func make(_ kind: Quiz.Kind? = nil, for word: Word, pool: [Word], sameTheme: Bool? = nil) throws -> Quiz {
        var rng = SystemRandomNumberGenerator()
        return try make(kind, for: word, pool: pool, sameTheme: sameTheme, using: &rng)
    }

    // MARK: Helpers

    public func english(_ word: Word) -> String {
        library.concept(for: word)?.english ?? ""
    }

    public func emoji(_ word: Word) -> String? {
        library.concept(for: word)?.emoji.flatMap { $0.isEmpty ? nil : $0 }
    }

    func theme(_ word: Word) -> String? {
        library.pack(for: word)?.theme
    }

    private func choices<R: RandomNumberGenerator>(_ word: Word, _ pool: [Word], _ sameTheme: Bool, _ rng: inout R) throws -> [Word] {
        ([word] + (try distractors(word, pool, 3, sameTheme, &rng))).shuffled(using: &rng)
    }

    private func distractors<R: RandomNumberGenerator>(
        _ word: Word, _ pool: [Word], _ count: Int, _ sameTheme: Bool, _ rng: inout R
    ) throws -> [Word] {
        let others = pool.filter { $0.id != word.id && english($0) != english(word) && $0.text != word.text }
        let preferred = others.filter { (theme($0) == theme(word)) == sameTheme }.shuffled(using: &rng)
        let rest = others.filter { (theme($0) == theme(word)) != sameTheme }.shuffled(using: &rng)
        let chosen = Array((preferred + rest).prefix(count))
        guard chosen.count == count else { throw QuizError.notEnoughWords(needed: count) }
        return chosen
    }
}

/// A small seeded random number generator, so tests (and replays) are repeatable.
public struct SeededRandom: RandomNumberGenerator, Sendable {
    private var state: UInt64

    public init(seed: UInt64) {
        state = seed
    }

    // SplitMix64
    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
