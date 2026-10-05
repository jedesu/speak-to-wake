import Foundation
import Testing
@testable import WakeCore

private let planner = ChallengePlanner(maker: QuizMaker(library: library))
private let oneCharWord = library.words.first { $0.text.count == 1 }!
private let twoCharWord = library.words.first { $0.text.count >= 2 }!

@Test func singleCharacterWordsAreNeverSaidOnTheirOwn() {
    let speech = planner.speechChallenges(for: oneCharWord)
    #expect(!speech.contains(.sayIt) && !speech.contains(.hearAndRepeat))
    #expect(planner.speechChallenges(for: twoCharWord).contains(.sayIt))
}

@Test func tapChallengesNeverIncludeMatchPairs() {
    for word in library.words {
        #expect(!planner.tapChallenges(for: word).contains(.tap(.matchPairs)))
        #expect(!planner.tapChallenges(for: word).isEmpty)
    }
}

@Test func everyWakeUpHasASpeechPrompt() {
    for seed in 0..<200 {
        var rng = SeededRandom(seed: UInt64(seed))
        let words = Array(library.words.shuffled(using: &rng).prefix(3))
        let plan = planner.plan(words, using: &rng)
        #expect(plan.count == 3)
        let anySpeakable = words.contains { !planner.speechChallenges(for: $0).isEmpty }
        if anySpeakable {
            #expect(plan.contains { $0.isSpeech }, "seed \(seed)")
        }
    }
}

@Test func plannedChallengesFitTheirWords() {
    var rng = SeededRandom(seed: 1)
    let words = Array(library.words.prefix(20))
    for (word, challenge) in zip(words, planner.plan(words, using: &rng)) {
        let allowed = planner.speechChallenges(for: word) + planner.tapChallenges(for: word)
        #expect(allowed.contains(challenge), "\(word.text) got \(challenge)")
    }
}

@Test func speechFallsBackToTapAfterTwoMisses() {
    var rng = SeededRandom(seed: 2)
    let afterOne = planner.replacement(after: .sayIt, for: twoCharWord, speechMissesInARow: 1, using: &rng)
    #expect(afterOne.isSpeech)
    let afterTwo = planner.replacement(after: .sayIt, for: twoCharWord, speechMissesInARow: 2, using: &rng)
    #expect(!afterTwo.isSpeech)
    let afterTap = planner.replacement(after: .tap(.trueFalse), for: twoCharWord, speechMissesInARow: 0, using: &rng)
    #expect(!afterTap.isSpeech)
}
