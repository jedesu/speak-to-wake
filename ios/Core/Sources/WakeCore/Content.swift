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
    /// HSK level (1 for the HSK 1 sections), if the pack is part of the HSK list.
    public let hsk: Int?
    /// Position within its HSK level: section 1, 2, 3...
    public let order: Int?
}

/// A friendly group of sections for the Learn tab's Topics view ("Food & drink"),
/// covering one or more section themes across every HSK level.
public struct Topic: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let themes: [String]
}

public struct Concept: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let packId: String
    public let english: String
    public let emoji: String?
    /// Only these languages have the concept (Korean/Japanese particles). Nil means every language.
    public let languages: [String]?
}

public struct ExampleSentence: Codable, Hashable, Sendable {
    public let text: String
    /// Japanese only: the sentence in hiragana.
    public let reading: String?
    /// Pronunciation in Latin letters: pinyin, Korean romanization or romaji.
    public let pinyin: String
    public let english: String
}

public struct Word: Codable, Hashable, Identifiable, Sendable {
    public let conceptId: String
    public let text: String
    /// Japanese only: the word in hiragana (ねこ for 猫).
    public let reading: String?
    /// Pronunciation in Latin letters: pinyin, Korean romanization or romaji.
    public let pinyin: String
    /// This language's own English, when the shared one doesn't fit ("won (Korean money)").
    public let meaning: String?
    /// A short usage tip ("Written は but said わ").
    public let note: String?
    public let example: ExampleSentence?
    /// Other ways of saying it that also count as correct (您好 for 你好).
    public let alternates: [String]?

    /// Filled in after decoding, since the file stores it once at the top.
    public internal(set) var language: String = ""

    /// Stable across app updates, so saved progress keeps pointing at the right word.
    public var id: String { "\(language):\(conceptId)" }

    enum CodingKeys: String, CodingKey {
        case conceptId, text, reading, pinyin, meaning, note, example, alternates
    }

    /// Japanese words show their kana when the text has kanji (猫 → ねこ).
    public var kanaHint: String? {
        guard let reading, reading != text else { return nil }
        return reading
    }
}

/// Everything the app can teach, held in memory. Read-only: the user's progress
/// is stored separately and refers to packs and words by id.
public struct ContentLibrary: Sendable {
    public let packs: [Pack]
    public let concepts: [String: Concept]
    public let language: String
    public let words: [Word]
    public let topics: [Topic]

    private let wordsByPack: [String: [Word]]
    private let wordsByID: [String: Word]

    public init(packsJSON: Data, wordsJSON: Data, topicsJSON: Data? = nil) throws {
        struct PacksFile: Decodable {
            let packs: [Pack]
            let concepts: [Concept]
        }
        struct WordsFile: Decodable {
            let language: String
            let words: [Word]
        }
        struct TopicsFile: Decodable {
            let topics: [Topic]
        }
        topics = try topicsJSON.map { try JSONDecoder().decode(TopicsFile.self, from: $0).topics } ?? []
        let packsFile = try JSONDecoder().decode(PacksFile.self, from: packsJSON)
        let wordsFile = try JSONDecoder().decode(WordsFile.self, from: wordsJSON)

        concepts = Dictionary(uniqueKeysWithValues: packsFile.concepts.map { ($0.id, $0) })
        language = wordsFile.language
        words = wordsFile.words.map { word in
            var word = word
            word.language = wordsFile.language
            return word
        }
        let concepts = self.concepts
        let wordsByPack = Dictionary(grouping: words) { concepts[$0.conceptId]?.packId ?? "" }
        self.wordsByPack = wordsByPack
        wordsByID = Dictionary(uniqueKeysWithValues: words.map { ($0.id, $0) })
        // Korean and Japanese only have level 1 so far: hide sections with no words.
        packs = packsFile.packs.filter { !(wordsByPack[$0.id] ?? []).isEmpty }
    }

    /// What the word means in English: its own meaning if it has one, else the shared concept's.
    public func english(_ word: Word) -> String {
        word.meaning ?? concepts[word.conceptId]?.english ?? ""
    }

    /// Looks up a word by its saved id, like "zh-CN:apple".
    public func word(id: String) -> Word? {
        wordsByID[id]
    }

    /// Loads `packs.json` and `words.<language>.json` from a bundle (the app's, by default).
    public static func load(language: String = "zh-CN", from bundle: Bundle = .main) throws -> ContentLibrary {
        guard let packsURL = bundle.url(forResource: "packs", withExtension: "json"),
              let wordsURL = bundle.url(forResource: "words.\(language)", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        let topicsData = try bundle.url(forResource: "topics", withExtension: "json").map { try Data(contentsOf: $0) }
        return try ContentLibrary(packsJSON: Data(contentsOf: packsURL), wordsJSON: Data(contentsOf: wordsURL),
                                  topicsJSON: topicsData)
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

    /// A topic's sections, easiest level first.
    public func packs(in topic: Topic) -> [Pack] {
        packs.filter { topic.themes.contains($0.theme) }
            .sorted { ($0.hsk ?? 99, $0.order ?? 0) < ($1.hsk ?? 99, $1.order ?? 0) }
    }

    /// HSK levels, each with its sections in order. Packs outside HSK are left out.
    public var hskLevels: [(level: Int, packs: [Pack])] {
        let levels = Set(packs.compactMap(\.hsk)).sorted()
        return levels.map { level in
            (level, packs.filter { $0.hsk == level }.sorted { ($0.order ?? 0) < ($1.order ?? 0) })
        }
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
