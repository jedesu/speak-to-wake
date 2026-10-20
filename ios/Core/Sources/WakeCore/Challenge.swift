import Foundation

/// One wake-up prompt type: speaking, or one of the tap quizzes.
public enum Challenge: Hashable, Sendable {
    /// See the word, say it.
    case sayIt
    /// Hear the word, say it back.
    case hearAndRepeat
    /// Read the example sentence aloud.
    case readAloud
    /// A tap quiz (never match pairs: it covers four words, not one).
    case tap(Quiz.Kind)

    public var isSpeech: Bool {
        if case .tap = self { false } else { true }
    }

    /// The name saved in the attempt log.
    public var logName: String {
        switch self {
        case .sayIt: "say_it"
        case .hearAndRepeat: "hear_and_repeat"
        case .readAloud: "read_aloud"
        case .tap(let kind): kind.rawValue
        }
    }
}

/// Decides which challenge each wake-up word gets.
///
/// Rules (PLAN.md and CLAUDE.md):
/// * At least one speech prompt per wake-up, when any word allows it.
/// * Speech only for words of 2+ characters: the recognizer often mishears a
///   lone syllable (水 shuì came out as 对 duì). Single-character words can still
///   be read aloud through their example sentence.
/// * After `speechFallbackAfter` failed speech tries in a row, switch to a tap quiz.
public struct ChallengePlanner: Sendable {
    public let maker: QuizMaker
    public static let minSpeechCharacters = 2
    public static let speechFallbackAfter = 2
    /// Chance that a word gets a speech prompt rather than a tap quiz.
    public static let speechShare = 0.5

    public init(maker: QuizMaker) {
        self.maker = maker
    }

    public func speechChallenges(for word: Word) -> [Challenge] {
        var challenges: [Challenge] = []
        if hanziCount(word.text) >= Self.minSpeechCharacters {
            challenges += [.sayIt, .hearAndRepeat]
        }
        if let example = word.example, hanziCount(example.text) >= Self.minSpeechCharacters {
            challenges.append(.readAloud)
        }
        return challenges
    }

    public func tapChallenges(for word: Word) -> [Challenge] {
        maker.availableKinds(for: word).filter { $0 != .matchPairs }.map(Challenge.tap)
    }

    /// One challenge per word, with at least one speech prompt if possible.
    /// `allowSpeech` false (the user turned speaking off) gives tap quizzes only.
    public func plan<R: RandomNumberGenerator>(_ words: [Word], requireSpeech: Bool = true, allowSpeech: Bool = true,
                                               using rng: inout R) -> [Challenge] {
        var plan = words.map { word -> Challenge in
            let speech = allowSpeech ? speechChallenges(for: word) : []
            if !speech.isEmpty && Double.random(in: 0..<1, using: &rng) < Self.speechShare {
                return speech.randomElement(using: &rng)!
            }
            return tapChallenges(for: word).randomElement(using: &rng)!
        }
        if allowSpeech && requireSpeech && !plan.contains(where: \.isSpeech),
           let i = words.firstIndex(where: { !speechChallenges(for: $0).isEmpty }) {
            plan[i] = speechChallenges(for: words[i]).randomElement(using: &rng)!
        }
        return plan
    }

    /// The challenge for a replacement word after a wrong answer. Speech stays
    /// speech (so the wake-up keeps its speaking prompt) until too many misses in a row.
    public func replacement<R: RandomNumberGenerator>(after missed: Challenge, for word: Word,
                                                      speechMissesInARow: Int, allowSpeech: Bool = true,
                                                      using rng: inout R) -> Challenge {
        if allowSpeech && missed.isSpeech && speechMissesInARow < Self.speechFallbackAfter,
           let speech = speechChallenges(for: word).randomElement(using: &rng) {
            return speech
        }
        return tapChallenges(for: word).randomElement(using: &rng)!
    }

    private func hanziCount(_ text: String) -> Int {
        text.unicodeScalars.count { (0x4E00...0x9FFF).contains($0.value) }
    }
}
