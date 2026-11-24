import Foundation
import Testing
@testable import WakeCore

/// Loads the real files in data/, so these tests also catch mistakes in the word lists.
func loadLibrary(_ language: String) -> ContentLibrary {
    let data = URL(filePath: #filePath)
        .deletingLastPathComponent()
        .appending(path: "../../../../data")
        .standardized
    return try! ContentLibrary(
        packsJSON: Data(contentsOf: data.appending(path: "packs.json")),
        wordsJSON: Data(contentsOf: data.appending(path: "words.\(language).json")),
        topicsJSON: Data(contentsOf: data.appending(path: "topics.json"))
    )
}

let library = loadLibrary("zh-CN")
let korean = loadLibrary("ko-KR")
let japanese = loadLibrary("ja-JP")

@Test(arguments: ["ko-KR", "ja-JP"])
func koreanAndJapaneseLoadLevelOneOnly(language: String) {
    let lib = loadLibrary(language)
    #expect(lib.language == language)
    #expect(lib.words.count == 146)
    #expect(lib.hskLevels.map(\.level) == [1])
    #expect(lib.words.allSatisfy { $0.id.hasPrefix(language + ":") })
    for word in lib.words {
        #expect(lib.concept(for: word) != nil && lib.pack(for: word) != nil, "\(word.text)")
    }
    for pack in lib.packs {
        #expect(!lib.words(in: pack).isEmpty, "\(pack.id) has no words")
    }
}

@Test func languageOnlyConceptsStayOutOfMandarin() {
    #expect(!library.words.contains { $0.conceptId == "topic-marker" })
    #expect(korean.words.contains { $0.conceptId == "topic-marker" })
}

@Test func wordsUseTheirOwnMeaning() {
    #expect(korean.english(korean.word(id: "ko-KR:yuan")!) == "won (Korean money)")
    #expect(japanese.english(japanese.word(id: "ja-JP:yuan")!) == "yen (Japanese money)")
    #expect(library.english(library.word(id: "zh-CN:yuan")!) == "yuan (money)")
}

@Test func japaneseHasReadings() {
    let cat = japanese.words.first { $0.text == "猫" }
    #expect(cat?.reading == "ねこ" && cat?.kanaHint == "ねこ")
    #expect(japanese.words.first { $0.text == "ありがとう" }?.kanaHint == nil)
    #expect(japanese.words.allSatisfy { $0.reading != nil })
}

@Test func loadsStarterContent() {
    #expect(library.language == "zh-CN")
    // HSK 1-3 so far (HSK 2.0 lists): 151 + 147 + 298 words.
    #expect(library.hskLevels.map(\.level) == [1, 2, 3])
    #expect(library.words.count == 596)
}

@Test func everyWordHasAConceptAndPack() {
    for word in library.words {
        #expect(library.concept(for: word) != nil, "no concept for \(word.text)")
        #expect(library.pack(for: word) != nil, "no pack for \(word.text)")
    }
}

@Test func everyPackHasWords() {
    for pack in library.packs {
        #expect(!library.words(in: pack).isEmpty, "\(pack.id) has no words")
    }
}

@Test func wordIDsAreUnique() {
    #expect(Set(library.words.map(\.id)).count == library.words.count)
    #expect(library.words.first?.id == "zh-CN:hello")
}

@Test func hskSectionsAreInOrderAndFree() {
    for (level, packs) in library.hskLevels {
        #expect(packs.map { $0.order ?? 0 } == Array(1...packs.count), "HSK \(level) order")
        #expect(packs.allSatisfy { $0.tier == (level == 1 ? .free : .premium) }, "HSK \(level) tier")
    }
    #expect(library.hskLevels.first?.packs.first?.title == "Greetings")
}

@Test func everySectionIsInExactlyOneTopic() {
    #expect(library.topics.count == 14)
    for pack in library.packs {
        #expect(library.topics.count { $0.themes.contains(pack.theme) } == 1, "\(pack.id)")
    }
    let food = library.topics.first { $0.id == "food" }!
    #expect(library.packs(in: food).map { $0.hsk ?? 0 } == library.packs(in: food).map { $0.hsk ?? 0 }.sorted())
}
