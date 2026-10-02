/// A handful of test words until the real word packs are ported (Phase 3).
struct PracticeWord: Hashable {
    let hanzi: String
    let pinyin: String
    let english: String
    /// Same sounds with other tones, so the recognizer hears the right syllable
    /// but still has to pick by tone.
    var toneNeighbors: [String] = []

    var hints: [String] { [hanzi] + toneNeighbors }

    static let all = [
        PracticeWord(hanzi: "苹果", pinyin: "píngguǒ", english: "apple"),
        PracticeWord(hanzi: "你好", pinyin: "nǐ hǎo", english: "hello"),
        PracticeWord(hanzi: "谢谢", pinyin: "xièxie", english: "thank you", toneNeighbors: ["写写"]),
        PracticeWord(hanzi: "老师", pinyin: "lǎoshī", english: "teacher", toneNeighbors: ["老是", "老实"]),
        PracticeWord(hanzi: "水", pinyin: "shuǐ", english: "water", toneNeighbors: ["睡", "谁"]),
        PracticeWord(hanzi: "买", pinyin: "mǎi", english: "buy", toneNeighbors: ["卖", "埋"]),
        PracticeWord(hanzi: "我是学生", pinyin: "wǒ shì xuéshēng", english: "I am a student"),
    ]

    /// Single syllables are often misheard (see CLAUDE.md), so the alarm only asks for longer words.
    static let forAlarm = all.filter { $0.hanzi.count >= 2 }
}
