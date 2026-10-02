import Foundation

/// Forgiving Mandarin speech matcher, ported from prototype/matcher.py.
///
/// Idea: compare what the recognizer heard against the target by *pronunciation*
/// (pinyin syllables), not by characters. Homophones then match, a wrong tone
/// costs a little, and sounds that learners and recognizers often mix up
/// (z/zh, in/ing, ...) cost half as much as a completely different syllable.
///
/// Pinyin comes from Apple's built-in Mandarin-to-Latin transform. Unlike the
/// Python prototype's pypinyin, it reads each character on its own (银行 becomes
/// yín xíng) and never gives a neutral tone. Both sides of a comparison go
/// through the same transform, so these mostly cancel out; pass `targetPinyin`
/// when a word's reading matters.
public enum Matcher {
    // MARK: Tunable settings
    public static let toneCost = 0.35          // same sounds, different tone (a 1-syllable tone slip fails)
    public static let confusableCost = 0.5     // initial or final is a commonly confused pair
    public static let passScore = 0.85         // at or above: pass
    public static let nearScore = 0.70         // at or above (but below pass): "near", app decides
    public static let freeExtraSyllables = 2   // extra spoken syllables around the target are free
    public static let extraPenalty = 0.10      // per extra syllable beyond the free ones

    static let initials = ["b", "p", "m", "f", "d", "t", "n", "l", "g", "k", "h", "j", "q", "x",
                           "zh", "ch", "sh", "r", "z", "c", "s", "y", "w"]
        .sorted { $0.count > $1.count }
    static let confusableInitials: [Set<String>] = [["z", "zh"], ["c", "ch"], ["s", "sh"], ["n", "l"], ["l", "r"]]
    static let confusableFinals: [Set<String>] = [["in", "ing"], ["en", "eng"], ["an", "ang"]]

    static let digits: [Character: Character] = [
        "0": "零", "1": "一", "2": "二", "3": "三", "4": "四",
        "5": "五", "6": "六", "7": "七", "8": "八", "9": "九",
    ]
    static let toneMarks: [Unicode.Scalar: Int] = ["\u{304}": 1, "\u{301}": 2, "\u{30C}": 3, "\u{300}": 4]

    // MARK: Converting text to syllables

    /// Keep only Chinese characters; turn digits into hanzi (recognizers often write "3" for 三).
    public static func normalize(_ text: String) -> String {
        let mapped = String(text.precomposedStringWithCompatibilityMapping.map { digits[$0] ?? $0 })
        let kept = mapped.unicodeScalars.filter { (0x4E00...0x9FFF).contains($0.value) }
        return String(String.UnicodeScalarView(kept))
    }

    public static func hanziToSyllables(_ text: String) -> [Syllable] {
        let hanzi = normalize(text)
        guard !hanzi.isEmpty, let latin = hanzi.applyingTransform(.mandarinToLatin, reverse: false) else {
            return []
        }
        return pinyinToSyllables(latin)
    }

    /// Parse space-separated pinyin like "píng guǒ" or "ping2 guo3".
    public static func pinyinToSyllables(_ text: String) -> [Syllable] {
        text.split(whereSeparator: \.isWhitespace).compactMap { token in
            var tone = 5
            var letters = ""
            for scalar in token.lowercased().decomposedStringWithCanonicalMapping.unicodeScalars {
                if let mark = toneMarks[scalar] {
                    tone = mark
                } else if scalar == "\u{308}" {
                    // ü decomposes to u + diaeresis; write it as v, like pypinyin does
                    if letters.last == "u" { letters.removeLast() }
                    letters.append("v")
                } else if let digit = Int(String(scalar)), (1...5).contains(digit) {
                    tone = digit
                } else if scalar.properties.isAlphabetic {
                    letters.unicodeScalars.append(scalar)
                }
            }
            return letters.isEmpty ? nil : split(letters, tone: tone)
        }
    }

    static func split(_ base: String, tone: Int) -> Syllable {
        for initial in initials where base.hasPrefix(initial) && base.count > initial.count {
            return Syllable(initial: initial, final: String(base.dropFirst(initial.count)), tone: tone)
        }
        return Syllable(initial: "", final: base, tone: tone)
    }

    // MARK: Scoring

    static func confusable(_ a: String, _ b: String, _ pairs: [Set<String>]) -> Bool {
        pairs.contains { $0.contains(a) && $0.contains(b) }
    }

    static func syllableCost(_ t: Syllable, _ s: Syllable) -> Double {
        let tone = t.tone != s.tone ? toneCost : 0
        if t.base == s.base { return tone }
        if t.final == s.final && confusable(t.initial, s.initial, confusableInitials) {
            return confusableCost + tone
        }
        if t.initial == s.initial && confusable(t.final, s.final, confusableFinals) {
            return confusableCost + tone
        }
        return 1
    }

    static func editDistance(_ target: [Syllable], _ heard: ArraySlice<Syllable>) -> Double {
        let heard = Array(heard)
        let n = target.count, m = heard.count
        var d = Array(repeating: Array(repeating: 0.0, count: m + 1), count: n + 1)
        for i in 0...n { d[i][0] = Double(i) }
        for j in 0...m { d[0][j] = Double(j) }
        if n > 0 && m > 0 {
            for i in 1...n {
                for j in 1...m {
                    d[i][j] = min(d[i - 1][j] + 1, d[i][j - 1] + 1,
                                  d[i - 1][j - 1] + syllableCost(target[i - 1], heard[j - 1]))
                }
            }
        }
        return d[n][m]
    }

    /// Best score over windows of what was heard, so extra words around the
    /// target ("um, 苹果") are mostly forgiven.
    static func score(_ target: [Syllable], _ heard: [Syllable]) -> Double {
        let n = target.count, m = heard.count
        guard n > 0, m > 0 else { return 0 }
        var best = 0.0
        for size in max(1, n - 1)...(n + 1) {
            for start in 0..<max(1, m - size + 1) {
                let window = heard[start..<min(m, start + size)]
                let outside = m - window.count
                let penalty = extraPenalty * Double(max(0, outside - freeExtraSyllables))
                best = max(best, 1 - editDistance(target, window) / Double(n) - penalty)
            }
        }
        return max(0, best)
    }

    // MARK: Public entry point

    /// Compare what was heard to the target (and any accepted alternates).
    public static func check(target: String, transcript: String, targetPinyin: String = "",
                             alternates: [String] = []) -> MatchResult {
        let heard = hanziToSyllables(transcript)
        let heardPinyin = heard.map { $0.base + String($0.tone) }
        var best = MatchResult(verdict: .fail, score: 0, bestTarget: "", heardPinyin: heardPinyin)
        let candidates = [(target, targetPinyin)] + alternates.map { ($0, "") }
        for (text, pinyin) in candidates {
            let normalized = normalize(text)
            if !normalized.isEmpty && normalize(transcript).contains(normalized) {
                return MatchResult(verdict: .pass, score: 1, bestTarget: text, heardPinyin: heardPinyin)
            }
            let syllables = pinyin.isEmpty ? hanziToSyllables(text) : pinyinToSyllables(pinyin)
            let s = score(syllables, heard)
            if s > best.score {
                best.score = s
                best.bestTarget = text
            }
        }
        best.verdict = best.score >= passScore ? .pass : best.score >= nearScore ? .near : .fail
        return best
    }
}

public struct Syllable: Equatable, Sendable {
    public let initial: String
    public let final: String
    public let tone: Int  // 1-4, 5 = neutral

    public var base: String { initial + final }
}

public enum Verdict: String, Sendable {
    case pass, near, fail
}

public struct MatchResult: Equatable, Sendable {
    public var verdict: Verdict
    public var score: Double
    public var bestTarget: String
    public var heardPinyin: [String]
}
