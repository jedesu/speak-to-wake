# Mingo: Project Plan

An alarm that won't stop until you say a target word or phrase out loud in the language you're learning.

## Your answers
- Platform: Mac + iPhone on iOS 26, so we go native (Swift + SwiftUI).
- Languages: Chinese, Japanese, Korean. **Decided: Mandarin Chinese first.**
- Time: 5-10 hours/week for about 12 weeks (60-120 hours total).
- Experience: new to native iOS. Goal: a working phone demo.

## Language: Mandarin first (decided)
One language in v1, as your brief says. The data model has a `language` field from day one, so Japanese and Korean become a data-and-matcher addition later, not a rewrite.

Mandarin makes speech-matching harder than Spanish, because the recognizer returns characters (hanzi), not the pinyin you may be learning from:
- **Homophones:** many different characters sound identical. If the target is 他 (tā) and the recognizer writes 她 (also tā), a character comparison would wrongly fail you. Comparing by pinyin passes it.
- **Tones:** the recognizer picks the most likely words, so it may "correct" a wrong tone into a real word. That means the matcher can't reliably judge tones. v1 will check that you said the right *word* and won't grade tone precision. That's an honest limit we'll state in the write-up.
- **No spaces between words:** the transcript is one string of characters, so we compare whole strings.
- **Simplified characters, zh-CN locale:** I'll assume this. Say so if you want Traditional.

**Matcher approach (Phase 1):** convert both the target and the transcript to pinyin and compare. Pass if it's an exact match. Otherwise score close matches: same syllables with different tones count as a near-pass (configurable), and a single-syllable slip counts as a partial. Pinyin conversion is available on iOS through Apple's built-in text transform, and I'll verify that in Phase 1.

**Unverified:** I still need to confirm that SpeechAnalyzer supports `zh-CN` on your iPhone. That's the first check in Phase 0/1.

## Tech stack
| Need | Choice | Why |
|---|---|---|
| App | Swift 6 + SwiftUI, Xcode 26, iOS 26 minimum | Required for the new APIs |
| Alarm | AlarmKit | Rings through Silent/Focus |
| Speech-to-text | SpeechAnalyzer / SpeechTranscriber | Free, on-device |
| Storage | SwiftData | Simple local database, no accounts |
| Matching | Own `Matcher` module, pure Swift, unit-tested | Testable without a phone |
| Logging | Attempts saved in SwiftData, exported as CSV | Needed for Phase 5 |

No backend, no accounts, no network needed.

## Challenge types (multiple formats, not just speaking)
Every wake-up is a short sequence of prompts, and each prompt is one of these types:

| Type | What you do | Needs |
|---|---|---|
| **Say it** | See the word, say it out loud | SpeechAnalyzer |
| **Hear and repeat** | Hear the word, say it back | Text-to-speech + SpeechAnalyzer |
| **Read aloud** | See a short phrase, read it | SpeechAnalyzer |
| **Hear and tap** | Hear a word, tap the right one of 4 options | Text-to-speech |
| **Meaning quiz** | See a word, tap the right meaning (or the reverse) | Nothing extra |
| **Picture match** | See a picture, tap the matching word | Emoji / SF Symbols for v1 (no image licensing) |
| **Match pairs** | Tap to pair 4 words with their meanings | Nothing extra |
| **True or false** | See "苹果 means banana": tap True or False | Nothing extra |
| **Fill the blank** | Complete an example sentence by tapping the missing word | Example sentences in the word data |

The tap-quiz generator is already prototyped in `prototype/quizzes.py`, with tests. Wrong answers come from the same theme (harder) or from other themes (easier, good when groggy). Fill-the-blank uses other-theme wrong answers on purpose, since same-theme words (other fruits) can also fit the blank and make it unfair. The trade-off is that it's easy; a per-word list of safe wrong answers could improve it later.

- **Text-to-speech** uses Apple's built-in voices, which are free and on-device.
- **Mixing the types:** speech prompts are the core of the app. Tap quizzes are the easier variety and also the fallback after failed speech attempts. You choose which types are on in Settings.
- **One rule I'd suggest:** each wake-up has at least one speech prompt, so the app stays different from tap-only language alarms. Do you agree?
- **Quality of the tap options:** wrong answers are drawn from similar words in your list, so they're plausible but not trick questions.

## Learn first, then get quizzed (core loop)
You can't be quizzed on words you've never seen. The app works like this:
1. **Learn tab:** you pick a themed pack (e.g. "Fruit 1"). The app teaches the words with flashcards (script, romanization, meaning, audio, emoji) and a short practice round.
2. **Marking as learned:** a pack's words enter your alarm pool only after you've finished that learning session. Words you haven't studied never appear in the alarm.
3. **Alarm tab:** the alarm only draws from learned words. Missed words come back sooner (spaced repetition).

This also fixes the "I never learned this word" problem and gives us something to sell (see Monetization).

## How vocabulary learning works (research-based)
- **Learn when alert, review when groggy.** Sleep inertia (a drop in memory and attention after waking) typically lasts 15-30 minutes. So the alarm is for *retrieving* words you already learned, never for teaching new ones. New words are taught in the Learn tab at a time you choose.
- **Small batches, then immediate recall.** A study session introduces about 5 words, then tests you on them right away. Actively recalling beats rereading.
- **Evidence for quizzing over flashcards alone (the "testing effect"):**
  - Karpicke & Roediger (2008, *Science*), 40 Swahili–English word pairs. After one week, students who kept testing themselves recalled about 80%; students who kept re-studying recalled about a third.
  - Meta-analyses: Rowland (2014), 159 comparisons, g = 0.50. Adesope et al. (2017), 217 studies, g = 0.61. Feedback roughly doubles the benefit (0.73 vs 0.39).
  - Multiple-choice quizzes also work when the wrong options are plausible (Little, Bjork et al. 2012). Effortful recall, such as saying the word aloud, helps more.
  - **In the app:** a first study session shows plain flashcards (you can't recall an unseen word), then offers practice as the recommended next step. "Study again" uses flip cards: you try to recall the meaning before revealing it. Every quiz shows the right answer as feedback.
  - **Caveat:** the studies are mostly college students in labs, and none involve just-woken users. Phase 5 can compare flashcard-only words with practiced words.
- **Spacing.** Words come back at growing gaps: a simple Leitner box system, with Box 1 the next day, Box 2 two days later, Box 3 four days later, roughly doubling. A miss drops the word back a box. A fancier algorithm (SM-2 or FSRS) is a later upgrade.
- **Many exposures, varied ways.** Words usually need 10-30 encounters. The mix of challenge types (say it, hear and tap, picture match, and so on) gives varied exposure.
- **Mandarin specifics:** teach each word with its pinyin and tone from the start, plus audio. Show an example sentence with each word. Order words within a pack by frequency, such as the HSK 1 list (about 150 words).
- **Alarm word choice:** 1-3 prompts, drawn from words that are due. Normal difficulty asks the most overdue and weakest words first. Easy difficulty asks the best-known words first, which suits a groggy brain. If few words are due, it fills with the soonest-upcoming ones.
- **Dates, not clock times:** a word learned at 8 pm is due at tomorrow's 7 am alarm.
- **Early reviews don't promote:** reviewing a word before it's due never moves it up a box. A miss still drops it.
- **Alarm alone can't keep up (simulated, with assumed accuracy rates):** with 35 words learned in the first week and 3 alarm prompts a day, about 30 words stayed overdue for weeks. Adding a 10-word **Review** session in the Learn tab cut it to about 2 within a month. So the Learn tab gets a "Review" button, and new packs are gated when too many words are overdue, so the backlog can't pile up.

## Screens
Bottom tab bar with three tabs. (You suggested two, and Learn and Alarm are the core. I'd add Progress as a third so the streak has a home. Settings sits behind a gear icon.)
1. **Learn tab** – pack list (locked or unlocked), pack detail, flashcard study session, and a "My words" area to add your own.
2. **Alarm tab** – time, repeat days, on/off, and which learned packs the alarm draws from.
3. **Progress tab** – streak, words learned, accuracy.
4. **Challenge** (full-screen when the alarm rings) – shows one prompt at a time. Each type above has its own small view: speech prompts get a mic button, live transcript and pass/fail, and tap prompts get option buttons. Every type has a fallback button.
5. **Settings** – language, difficulty, prompts per wake-up, emergency-dismiss timer.
6. **Prototype/Debug** (Phase 1 only) – speech-check screen with attempt log and CSV export.

## Monetization (design now, charge later)
**Decided (Oct 2026, matches the discovery report):** freemium with one **Pro** subscription at $4.99/month or $49.99/year. Pro is called `premium` in the data files.
- **Free:** the speaking alarm, all challenge types, and the first level of each theme (Fruit 1, Animals 1, and so on) in one language. The alarm picks from words you've learned at random.
- **Pro:** **spaced repetition** (the alarm and Review pick the words you're about to forget), every "level 2+" pack (Fruit 2, ...), more languages, custom word lists and detailed progress stats.
- **Why a subscription over per-pack purchases:** per-pack payments ask for a decision every time and feel nickel-and-dimey. One Premium unlock is simpler and gives recurring revenue. I'd still test per-pack pricing in your survey.
- **Pricing guess:** about $4-6/month or $40-60/year. This sits just under Alarmy Premium ($59.99/year) and Memrise ($61.99/year).
- **Keep the alarm free.** The alarm is the hook, and the content is what you charge for.

### Packs are shared across languages
A pack such as "Fruit 1" is a list of **concepts** (apple, banana, ...). Each language supplies its own words for those same concepts (苹果 / りんご / 사과). So:
- Unlocking "Fruit 2" unlocks it for every language you have access to. Pack access and language access are two separate gates.
- Adding a new language means translating the existing concept lists, not designing new packs. Emoji for picture match are shared as well.
- Translations aren't always one-to-one (measure words, politeness levels), so each language entry can carry its own notes.

### Free vs Premium tiers
| | Free | Premium |
|---|---|---|
| Alarm and all challenge types | Yes | Yes |
| Spaced repetition | No: random learned words | **Yes** |
| Progress | Streak | Streak plus detailed stats |
| Languages | **One** (chosen at setup) | **All** |
| Packs | Starter packs (level 1 of each theme) | **All** packs |
| Earning more | Yes, see below | Not needed |
| Extras (custom-word import, chained challenges) | No | Yes |

**Earning packs on Free:** consistent use unlocks the next pack. For example, a 7-day wake-up streak earns one pack token to spend on any locked pack, in your one language. Earned packs stay unlocked. This rewards the behavior we want (waking up and learning), gives free users a reason to stay, and still leaves Premium as the shortcut to everything.
- **Risk to test:** if earning is too easy, nobody pays. If it's too hard, free users leave. The exact thresholds are a pricing experiment for your class survey.

**For v1:** your brief excludes payments, so we build packs with a `isPremium` flag and show locked-pack screens. We don't wire up real payments (StoreKit) unless there's time. For the class, you can test willingness to pay with a survey or a "fake door" paywall instead.

## Data model (SwiftData)
- `Pack`: id, theme (e.g. fruit), level (1, 2, ...), title, tier (free or premium). Not tied to a language.
- `Concept`: id, packID, englishGloss, emoji. One row per idea, shared by all languages.
- `Word`: id, conceptID (nil for user-added words), language, text, romanization, meaning, notes, source (starter or user), difficulty, learned (true once studied)
- `Entitlement`: isPremium, chosenLanguage (Free tier), unlockedPackIDs, packTokens (earned)
- `PackProgress`: packID, language, learnedAt (nil until you finish studying that pack in that language)
- `ReviewState`: wordID, box (spaced repetition level 0-5), dueDate, timesCorrect, timesMissed
- `Word` also gets optional `emoji` (for picture match) and `exampleSentence` (for read aloud).
- `Attempt`: id, wordID, challengeType, date, transcript (speech types only), chosenOption (tap types only), matchScore, passed, retryNumber, context (wake or midday), userSaidCorrect? (self-labeled for Phase 5)
- `AlarmConfig`: time, days, enabled, promptsRequired
- `Settings`: language, difficulty, enabledChallengeTypes, emergencyDismissSeconds

In code, each challenge type follows one shared `Challenge` interface (a prompt, a way to answer, and a result). New types are then easy to add later.

## Phases and rough timeline
| Phase | Weeks | Output |
|---|---|---|
| 0 Feasibility | 1 | Written findings on AlarmKit limits and Android comparison, plus a recommendation |
| 1 Speech prototype | 2-4 | Single screen with forgiving matcher and attempt log |
| 2 Alarm | 5-7 | Ringing alarm opens the challenge, with fallbacks |
| 3 Vocab + challenge types | 8-10 | Themed packs, Learn tab (flashcards), learned-words-only alarm pool, spaced repetition, add-your-own, and the tap-based and listening challenge types |
| 4 Polish | 11 | Progress, settings, design |
| 5 Testing | 12 | Wake-up and midday test, false-reject/accept report |

## Fallbacks (so you're never stuck)
Repeat-after-me mode, then an easier word after 2 failed tries, then a tap-based quiz instead of speech, then an emergency dismiss after N seconds. Exact behavior depends on what Phase 0 finds about the Stop button.

### Lessons from Alarmy (research)
- Alarmy's emergency escape is a "tap a moving button 100 times" mode. Its help page says it exists only for Photo and QR/Barcode missions, and each use adds 100 taps next time. I found no documented escape for math.
- Users can still bypass a mission by deleting the app, which suggests the system's own controls always win. We'll plan around that, not fight it.
- Our version: the escape should be effortful but possible, and it should be on for every challenge type, including speech.

## Out of scope for v1
Accounts, payments, social features, AI lessons, multiple languages at once.

## Working rules
- Small steps. After each one I'll tell you how to run it and what to check, then wait.
- Plain-language explanations of each piece.
- If the platform can't do something, I'll say so and suggest the closest alternative.

## Next step once approved
Phase 0: research and write up AlarmKit's real limits. No code until we've seen the results.
