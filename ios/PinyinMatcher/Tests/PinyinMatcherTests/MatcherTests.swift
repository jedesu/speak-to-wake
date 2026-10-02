import Foundation
import Testing
@testable import PinyinMatcher

/// Runs the same cases as prototype/test_matcher.py against the Swift port.
struct Case: Decodable, CustomTestStringConvertible, Sendable {
    let note: String
    let target: String
    let heard: String
    let expect: String
    var target_pinyin: String?
    var alternates: [String]?

    var testDescription: String { note }

    static let all: [Case] = {
        let url = URL(filePath: #filePath)
            .deletingLastPathComponent()
            .appending(path: "../../../../prototype/cases.json")
            .standardized
        let data = try! Data(contentsOf: url)
        return try! JSONDecoder().decode([Case].self, from: data)
    }()
}

@Test(arguments: Case.all)
func sharedCase(_ c: Case) {
    let result = Matcher.check(target: c.target, transcript: c.heard,
                               targetPinyin: c.target_pinyin ?? "", alternates: c.alternates ?? [])
    #expect(result.verdict.rawValue == c.expect,
            "score=\(String(format: "%.2f", result.score)) heard=\(result.heardPinyin)")
}

@Test func parsesToneMarksAndNumbers() {
    #expect(Matcher.pinyinToSyllables("píng guǒ") == Matcher.pinyinToSyllables("ping2 guo3"))
    #expect(Matcher.pinyinToSyllables("lǜ").first == Syllable(initial: "l", final: "v", tone: 4))
    #expect(Matcher.pinyinToSyllables("ma").first?.tone == 5)
}

@Test func normalizeKeepsOnlyHanzi() {
    #expect(Matcher.normalize("苹果。") == "苹果")
    #expect(Matcher.normalize("我有3个") == "我有三个")
    #expect(Matcher.normalize("hello") == "")
}
