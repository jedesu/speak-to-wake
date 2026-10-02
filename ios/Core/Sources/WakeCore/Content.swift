import Foundation

// The starter word packs, decoded from data/packs.json and data/words.<language>.json.
//
// Packs and concepts are shared by every language ("Fruit 1" = apple, banana, ...).
// Each language file supplies its own word for each concept.

public struct Pack: Codable, Hashable, Identifiable, Sendable {
    public enum Tier: String, Codable, Sendable {
        case free, premium
    }

    public let id: String
    public let theme: String
    public let level: Int
    public let title: String
    public let tier: Tier
}

public struct Concept: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let packId: String
    public let english: String
    public let emoji: String?
}

public struct ExampleSentence: Codable, Hashable, Sendable {
    public let text: String
    public let pinyin: String
    public let english: String
}

public struct Word: Codable, Hashable, Identifiable, Sendable {
    public let conceptId: String
    public let text: String
    public let pinyin: String
    public let example: ExampleSentence?
    /// Other ways of saying it that also count as correct (您好 for 你好).
    public let alternates: [String]?

    /// Filled in after decoding, since the file stores it once at the top.
    public internal(set) var language: String = ""

    /// Stable across app updates, so saved progress keeps pointing at the right word.
    public var id: String { "\(language):\(conceptId)" }

    enum CodingKeys: String, CodingKey {
        case conceptId, text, pinyin, example, alternates
    }
}

/// Everything the app can teach, held in memory. Read-only: the user's progress
/// is stored separately and refers to packs and words by id.
public struct ContentLibrary: Sendable {
    public let packs: [Pack]
    public let concepts: [String: Concept]
    public let language: String
    public let words: [Word]

    private let wordsByPack: [String: [Word]]

    public init(packsJSON: Data, wordsJSON: Data) throws {
        struct PacksFile: Decodable {
            let packs: [Pack]
            let concepts: [Concept]
        }
        struct WordsFile: Decodable {
            let language: String
            let words: [Word]
        }
        let packsFile = try JSONDecoder().decode(PacksFile.self, from: packsJSON)
        let wordsFile = try JSONDecoder().decode(WordsFile.self, from: wordsJSON)

        packs = packsFile.packs
        concepts = Dictionary(uniqueKeysWithValues: packsFile.concepts.map { ($0.id, $0) })
        language = wordsFile.language
        words = wordsFile.words.map { word in
            var word = word
            word.language = wordsFile.language
            return word
        }
        let concepts = self.concepts
        wordsByPack = Dictionary(grouping: words) { concepts[$0.conceptId]?.packId ?? "" }
    }

    /// Loads `packs.json` and `words.<language>.json` from a bundle (the app's, by default).
    public static func load(language: String = "zh-CN", from bundle: Bundle = .main) throws -> ContentLibrary {
        guard let packsURL = bundle.url(forResource: "packs", withExtension: "json"),
              let wordsURL = bundle.url(forResource: "words.\(language)", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try ContentLibrary(packsJSON: Data(contentsOf: packsURL), wordsJSON: Data(contentsOf: wordsURL))
    }

    public func words(in pack: Pack) -> [Word] {
        wordsByPack[pack.id] ?? []
    }

    public func concept(for word: Word) -> Concept? {
        concepts[word.conceptId]
    }

    public func pack(for word: Word) -> Pack? {
        guard let packId = concepts[word.conceptId]?.packId else { return nil }
        return packs.first { $0.id == packId }
    }

    /// Themes in the order they first appear in packs.json, each with its packs by level.
    public var themes: [(theme: String, packs: [Pack])] {
        var order: [String] = []
        for pack in packs where !order.contains(pack.theme) {
            order.append(pack.theme)
        }
        return order.map { theme in
            (theme, packs.filter { $0.theme == theme }.sorted { $0.level < $1.level })
        }
    }
}
