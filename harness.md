# Mingo's AI harness

Written for a non-technical reader. "The harness" means everything we built around
the AI models: what we ask them, what they're allowed to hear, how we check their
answers, and what happens when they get it wrong.

**Short version:** Mingo does not use ChatGPT or any cloud AI. It uses two small AI
models that Apple builds into every iPhone, one that turns speech into text and one
that reads words aloud. Both run on the phone, offline, for free. Everything that
decides whether you *said the word right* is our own code.

Mingo is a **workflow, not an agent**: it follows the same fixed steps every time.
No AI decides what to do next.

---

## 1. Every place the code calls an AI model

| # | Model (Apple, on the phone) | Where in the code | What it's for |
|---|---|---|---|
| 1 | **SpeechAnalyzer + SpeechTranscriber** (iOS 26 speech recognition), Mandarin `zh-CN` | `ios/SpeakToWake/SpeakToWake/LiveTranscriber.swift` | Listens to the microphone and turns what you say into Chinese characters, live. Used by the wake-up speaking challenge (`SpeechPromptView.swift`) and the Speech check test screen (`SpeechCheckView.swift`). |
| 2 | **SpeechTranscriber model download** | `SpeechModelManager.swift` | Checks that the Mandarin speech model is on the phone and downloads it if not. No speech is processed here. |
| 3 | **AVSpeechSynthesizer** (text-to-speech), Mandarin voice | `Speaker.swift` | Reads words and example sentences aloud on flashcards and in "hear and tap" quizzes. Normal speed × 0.85, or × 0.6 for "slow". |

Nothing else calls an AI. The tap quizzes (meaning, picture match, match pairs,
true/false, fill-the-blank), the wrong answers they offer, the spaced-repetition
schedule and the word lists are all ordinary code and data written by us.

## 2. The instructions (prompts) each call sends

These models don't take written prompts like a chatbot. The closest thing is the
**settings** we give them:

- **Speech recognizer** (`LiveTranscriber.swift`, lines 43–53):
  - Language: Mandarin, `zh-CN`.
  - Show partial results while you're still talking (`volatileResults`), so the
    screen updates live.
  - **Hints** ("contextual strings"): a short list of words the recognizer should
    expect. In the wake-up challenge (`SpeechPromptView.swift`, line 201) the hints
    are the target word plus any accepted alternates, for example `["你好", "您好"]`.
    On the Speech check screen, the hints are the target plus words that differ only
    by tone, for example `["水", "睡", "谁"]`, and can be switched off to compare.
- **Text-to-speech** (`Speaker.swift`): the Mandarin voice, the speed, and the text
  to read.

## 3. What each model is given, and what it is not

| Model | Given | NOT given |
|---|---|---|
| Speech recognizer | Live microphone audio while the mic button is on; the language; the hint words above | The answer's meaning or pinyin; your history; anything about you. The audio never leaves the phone and is never saved. |
| Text-to-speech | The characters to read | Anything else |

What we **do** save (on the phone, and in your account if you sign in): the text the
recognizer heard, our match score, pass or fail, and which word it was (`Attempt` in
`Models.swift`, uploaded by `SyncService.swift`). Never the recording.

## 4. How we check the answers, and what happens when something fails

The recognizer only produces text. **Deciding whether you said the word right is our
own matcher**, `ios/Core/Sources/PinyinMatcher/Matcher.swift`:

1. Turn both the target word and what the recognizer heard into **pinyin** (sounds
   plus tones), so a different character with the same sound still counts
   (homophones pass).
2. Compare syllable by syllable and score from 0 to 1:
   - a wrong tone costs 0.35, so a tone slip **fails** a one-syllable word;
   - a commonly confused sound pair (like zh/z) costs 0.5;
   - up to 2 extra syllables around the word are free (people say "嗯…水");
     more cost 0.1 each.
3. **Pass** at 0.85 or above. Only a pass counts. "Near" (0.70–0.85) and fail are
   both wrong.

What happens on a wrong answer, or when the AI can't help:

| Situation | What Mingo does | Where |
|---|---|---|
| Wrong or "near" answer | Swaps in a **different word** that you must get right | `WakeSession.swift` |
| Two missed speaking prompts in a row | Switches to a **tap quiz**, so a bad mic or recognizer can't trap you | `Challenge.swift`, `replacement(…)` |
| Silence | Alarm sound comes back after 10 seconds of quiet | `SpeechPromptView.swift` |
| Mic permission off, or Mandarin model missing | Shows an error with how to fix it; the 2-miss rule still moves you to tap quizzes | `LiveTranscriber.swift`, `SpeechModelManager.swift` |
| Stuck for a long time | A press-and-hold **emergency exit** appears after 1, 3 or 5 minutes (setting) | `ChallengeView.swift` |
| Speaking prompts turned off (shared room, sore throat) | Tap quizzes only | Settings → Speaking prompts |

There are no cloud servers in this loop, so there is no "API is down" case: it works
in airplane mode.

**Tests on the checks:** the matcher has a shared list of test cases,
`prototype/cases.json`, run against both the Python prototype (`prototype/matcher.py`,
1,219 passing tests with the word-data checks) and the Swift app version
(`cd ios/Core && swift test`). These test the *matcher*, not the *recognizer*: see 6.

## 5. We built this / We rent this

| We built this | We rent this |
|---|---|
| The **pinyin matcher**: tone-aware scoring, homophones pass, confusable sounds, pass/near/fail thresholds | **Apple's speech recognizer** (SpeechAnalyzer / SpeechTranscriber) |
| The **hint lists** we feed the recognizer (target + alternates; tone neighbors on the test screen) | **Apple's Mandarin pinyin transform** (characters → pinyin), used inside the matcher |
| The **challenge rules**: swap in a new word on a miss, tap-quiz fallback after 2 speaking misses, silence timer, emergency exit | **Apple's text-to-speech** voice |
| **Tap quiz generators** and their wrong-answer picks (same HSK level or easier) | **AlarmKit**: the system alarm that rings through Silent and Focus |
| **Spaced repetition** (Leitner boxes) that chooses which words the alarm asks | **Supabase** (accounts and sync) and **Google** sign-in |
| The **word data**: 596 HSK 1–3 words in 61 sections and 14 topics, dictionary-style pinyin, example sentences, built and checked by `build_hsk.py` | **Microsoft Fluent Emoji** pictures (MIT license) and the HSK word lists (drkameleon, MIT) |
| The **test cases** (`cases.json`) and data checks | |
| The **ringing design**: Mingo's own alarm sound that plays until you pass | |

## 6. Fragile, duplicated or missing (listed, not fixed)

1. **One-syllable words are unreliable.** On a real iPhone, saying shuì (水) was
   heard as duì (对). The matcher was right; the recognizer's text was wrong.
   Single characters give it too little sound to go on.
2. **No test set for the recognizer.** All our tests feed the matcher typed text. We
   have no recorded audio clips, so we can't put a number on how often the
   recognizer hears a correct answer correctly.
3. **The hints contain the answer.** In the wake-up challenge we tell the recognizer
   to expect the target word. That probably helps correct speakers, but it might also
   nudge a wrong attempt toward the right word. Untested either way.
4. **The thresholds are hand-picked.** 0.85 pass, 0.70 near, 0.35 tone cost, 2 free
   extra syllables: chosen from test cases, not tuned on real wake-up attempts.
5. **Two copies of the matcher.** A Python version (`prototype/matcher.py`) and a
   Swift version. They share `cases.json`, but a rule changed in one can drift from
   the other.
6. **Apple's pinyin quirks.** Apple's transform reads characters one at a time
   (银行 → yín xíng) and never gives neutral tones. Both sides of a comparison go
   through it, so this mostly cancels out, but some words need a manual reading.
7. **Mandarin only.** The matcher is built on pinyin, so Japanese or Korean would need
   a new matcher, not just new word lists.
8. **The attempt log has no export yet.** Transcripts and scores are saved, but the
   planned CSV export for measuring accuracy isn't built.
9. **Can't run in a browser or simulator.** Speech needs a real iPhone microphone, so
   the browser demo is tap-only.
