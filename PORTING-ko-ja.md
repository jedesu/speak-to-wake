# Korean and Japanese: porting checklist for the Mac

Done on Windows (Nov 2026): the word lists and the logic, in Python, with tests.
This file lists what the iOS app needs, in small steps. Build and run after each
step, as usual. Nothing here has been compiled yet.

## What exists now

| | Mandarin | Korean | Japanese |
|---|---|---|---|
| Word list | `data/words.zh-CN.json` (HSK 1-3, 596 words) | `data/words.ko-KR.json` (level 1, 146 words) | `data/words.ja-JP.json` (level 1, 146 words) |
| Hand-written source | `data/source/hsk*.txt` | `data/source/ko-KR.txt` | `data/source/ja-JP.txt` |
| Builder | `prototype/build_hsk.py` | `prototype/build_lang.py ko-KR` | `prototype/build_lang.py ja-JP` |
| Matcher (Python) | `prototype/matcher.py` | `prototype/korean.py` | `prototype/japanese.py` |
| Matcher cases | `prototype/cases.json` | `prototype/cases.ko-KR.json` | `prototype/cases.ja-JP.json` |
| Swift matcher | `ios/Core/Sources/PinyinMatcher` | **to port** | **to port** |

How the shared sections work:
- Korean and Japanese reuse the same 16 level-1 sections as Mandarin (Greetings,
  People, Numbers...). Each source file translates every concept of a section or
  skips it with a reason. For example, Korean and Japanese have no word for 了,
  so `le` is skipped. Skipped concepts are listed in the file's `"skipped"` key.
- Four new concepts only Korean and Japanese have: the particles `topic-marker`,
  `subject-marker`, `object-marker` and `place-of-action`. In `packs.json` they
  carry `"languages": ["ko-KR", "ja-JP"]`. Mandarin must ignore them.
- Sections 2-3 (the HSK 2-3 packs) have no Korean or Japanese words yet, so
  those languages must hide sections that have no words.

New optional fields in the word files (Swift's decoder ignores unknown keys, so
the current app still runs):
- `meaning`: replaces the shared English when it doesn't fit. For example,
  `yuan` is "won (Korean money)" in Korean and "yen (Japanese money)" in Japanese.
- `reading`: Japanese only. The hiragana for the word and for each example. Show
  it above or next to kanji on flashcards.
- `note`: a short usage tip, e.g. "Written は but said わ". Show it on flashcards.
- `pinyin` now means "pronunciation in Latin letters" for every language:
  pinyin, Revised Romanization (Korean) or romaji (Japanese). The key name stays,
  so nothing breaks.

## Step 0: Mandarin bug fix (do this first, it's live today)

Wrong answers can sound exactly like the right one. "Hear and tap" may play *tā*
and offer both 他 and 她, so the user is marked wrong for a correct answer.
Mandarin has 21 such groups at HSK 1-3 (他/她/它, 在/再, 坐/做...).

In `ios/Core/Sources/WakeCore/Quiz.swift`, `distractors(...)`, also drop words
that sound the same:

```swift
let others = pool.filter {
    $0.id != word.id && english($0) != english(word) && $0.text != word.text
        && sound($0) != sound(word)
}

/// How a word is said, without spaces or punctuation: Japanese kana if present,
/// otherwise the romanization (pinyin keeps its tone marks).
func sound(_ word: Word) -> String {
    (word.reading ?? word.pinyin).lowercased()
        .filter { !" '’.,!?-".contains($0) }
}
```
(`word.reading` exists after step 1. Until then, use `word.pinyin`.) Add a test
like `prototype/test_quizzes.py`'s same-sound check.

## Step 1: content model (`WakeCore/Content.swift`)

1. `Word`: add `reading: String?`, `meaning: String?`, `note: String?` (plus the
   CodingKeys).
2. `Concept`: add `languages: [String]?`.
3. `ContentLibrary`: keep only packs that have at least one word in this language
   (`packs`, `hskLevels`, `themes`, `packs(in:)`). This makes Korean and Japanese
   show only level 1.
4. `QuizMaker.english(_:)` (in `Quiz.swift`): `word.meaning ?? concept.english`.
   Search the app for other uses of `concept(for:)?.english` and route them
   through the same helper.
5. `ContentTests`: load `words.ko-KR.json` and `words.ja-JP.json` too. Check that
   every word has a concept, every visible pack has words, and ids start with the
   language (`ko-KR:hello`).

## Step 2: pick the language everywhere

1. `AppContent.library` (`Models.swift`, around line 103) is a `static let` that
   loads `"zh-CN"` once. Replace it with a small per-language cache, e.g.
   `AppContent.library(for: LanguageOption.current.id)` backed by a dictionary.
   Views then read the library for the current language, and update when the
   `@AppStorage` language setting changes. Progress is already separate per
   language: word ids are `ko-KR:apple`, and `PackProgress` has a `language`
   column.
2. `Languages.swift`: add Korean (`ko-KR`, 한국어, 🇰🇷) and Japanese (`ja-JP`,
   日本語, 🇯🇵) with `available: true` and `levels: "Level"`. Update the "Mandarin
   is ready now" text.
3. Replace hard-coded "HSK" with `LanguageOption.current.levels`. It appears in
   `LearnView.swift` (lines 9, 36, 181, 235, 276), `AlarmTabView.swift` (98, 101),
   `YourWordsView.swift` (27), `SettingsView.swift` (98, 120, 129) and
   `PaywallView.swift` (27).
4. The neutral-tone note in the Learn tab is Mandarin-only.

## Step 3: voice and speech recognition

1. `Speaker.swift:19`: `AVSpeechSynthesisVoice(language: LanguageOption.current.id)`.
   iOS ships Korean and Japanese voices. **TEST** that they're installed on your
   phone.
2. `SpeechModelManager.swift:17` and `SpeechPromptView.swift:26`: use the current
   language's locale. Line 31 filters locales starting with `zh`/`yue`, so
   widen it.
3. **TEST on the phone, first:** do `ko-KR` and `ja-JP` appear in
   `SpeechTranscriber.supportedLocales`, and do their models download? Earlier
   research says SpeechAnalyzer covers about 22 languages, but it was never
   checked for these two. If either is missing, that language can't use
   speaking prompts. It would get tap quizzes only until Apple adds it.
4. Contextual-string hints: pass the target plus `alternates`, same as Mandarin.

## Step 4: port the matchers

Make `PinyinMatcher` one of three matchers. You could rename the package product
to `SpeechMatchers`, or add `KoreanMatcher` and `JapaneseMatcher` targets.

**Korean** (`prototype/korean.py`): pure Swift, no Apple APIs needed. A Hangul
syllable splits into consonant + vowel + final by arithmetic on its Unicode value
(`code - 0xAC00`; 588 and 28 are the sizes). Port `split`, `syllable_cost`,
`_edit_distance`, `_score`, `normalize` (digits become Sino-Korean words) and
`check`. Test with `cases.ko-KR.json`. You don't need the romanizer in the app,
because the romanization is already in the data.

**Japanese** (`prototype/japanese.py`): the only part that needs an Apple API is
turning what was heard (kanji or kana) into hiragana. Python uses pykakasi.
On iOS, use `CFStringTokenizer`:

```swift
import Foundation

/// Hiragana reading of Japanese text (kanji, kana). Untested sketch.
func hiraganaReading(_ text: String) -> String {
    let cf = text as CFString
    let range = CFRange(location: 0, length: CFStringGetLength(cf))
    let tokenizer = CFStringTokenizerCreate(nil, cf, range, kCFStringTokenizerUnitWordBoundary,
                                            Locale(identifier: "ja_JP") as CFLocale)
    var out = ""
    while !CFStringTokenizerAdvanceToNextToken(tokenizer).isEmpty {
        if let latin = CFStringTokenizerCopyCurrentTokenAttribute(
            tokenizer, kCFStringTokenizerAttributeLatinTranscription) as? String {
            out += latin.applyingTransform(.latinToHiragana, reverse: false) ?? ""
        }
    }
    return out
}
```

Check it against the readings in `words.ja-JP.json`, since every word has a
known-good `reading`. Some readings will differ (pykakasi also got about 10 wrong).
That's fine, for two reasons. The matcher compares against the word's own
`reading` from the data. And if the heard text contains the target word or an
alternate as written, it passes before any reading is needed. Port `morae`,
`sub_cost`, `indel_cost`, `_edit_distance`, `_score` and `check`, and test with
`cases.ja-JP.json`.

Then in `SpeechPromptView` (and the speech check screen), choose the matcher by
language and pass the word's `alternates` (and `reading` for Japanese).
Verb words accept their polite form only through `alternates` (먹다 / 먹어요,
食べる / 食べます), so always pass them.

## Step 5: flashcards and quizzes

1. Flashcards show `reading` (Japanese), the `pinyin` line (romanization or
   romaji), `meaning` and `note`.
2. **Decision for the user:** quizzes show "characters only" because pinyin gives
   the answer away. Hangul is phonetic, so Korean is fine as-is. Japanese level-1
   learners usually can't read kanji yet, so 猫 alone may be too hard. Options:
   show kana under kanji in quizzes, or show kana only.
3. Pictures: Korean and Japanese reuse each concept's emoji, so no new assets.
   The particles have no picture, so no hint button.

## Step 6: device tests

1. ko-KR and ja-JP speech models: supported, downloaded (step 3).
2. Korean and Japanese voices read words aloud.
3. Say 10 words in each language. Do the transcripts match the target, and does
   the verdict feel right? Single-syllable words (물, 차, 猫) will likely have the
   same problem as Mandarin 水. Consider tap quizzes for 1-syllable words.
4. Switch languages back and forth: progress for each stays separate, and the
   alarm asks words in the current language.

## Open questions for the user
- Free tier: one language only, as in the plan? The picker currently lets anyone
  switch. Switching could stay free (progress is kept per language) while
  learning two at once is Pro.
- Japanese quizzes: kana under kanji, or kana only (step 5)?
- Levels 2-3 for Korean and Japanese: same process (`build_lang.py` with a
  `## hsk2-..` section per pack). They'd show as "Level 2-3", which doesn't match
  TOPIK or JLPT levels.
- Have a native Korean speaker and a native Japanese speaker review the source
  files before release.
