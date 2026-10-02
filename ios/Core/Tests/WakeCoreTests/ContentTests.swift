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
    #expect(library.packs.count == 14)
    #expect(library.words.count == 74)
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
    #expect(library.words.first?.id == "zh-CN:apple")
}

@Test func themesGroupLevelsInOrder() {
    let fruit = library.themes.first { $0.theme == "fruit" }
    #expect(fruit?.packs.map(\.level) == [1, 2])
    #expect(fruit?.packs.first?.tier == .free)
}
