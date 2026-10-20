import Foundation
import Testing
@testable import WakeCore

/// Loads the real files in data/, so these tests also catch mistakes in the word lists.
let library: ContentLibrary = {
    let data = URL(filePath: #filePath)
        .deletingLastPathComponent()
        .appending(path: "../../../../data")
        .standardized
    return try! ContentLibrary(
        packsJSON: Data(contentsOf: data.appending(path: "packs.json")),
        wordsJSON: Data(contentsOf: data.appending(path: "words.zh-CN.json"))
    )
}()

@Test func loadsStarterContent() {
    #expect(library.language == "zh-CN")
    #expect(library.packs.count == 16)
    #expect(library.words.count == 152)
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
    let hsk1 = library.hskLevels.first { $0.level == 1 }
    #expect(hsk1?.packs.count == 16)
    #expect(hsk1?.packs.map { $0.order ?? 0 } == Array(1...16))
    #expect(hsk1?.packs.allSatisfy { $0.tier == .free } == true)
    #expect(hsk1?.packs.first?.title == "Greetings")
}
