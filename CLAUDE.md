# Speak-to-Wake: handoff for Claude sessions

Read PLAN.md (design), PHASE0.md (AlarmKit findings) and this file first.

## What this is
A class project (individual entrepreneurship class, ~3 months from late Sept 2026). An iOS alarm that won't stay off until the user passes a Mandarin challenge: speaking a word out loud, or tap quizzes (meaning, hear-and-tap, picture match, true/false, fill-the-blank, match pairs). The user is a student, new to native iOS, comfortable with code. Explain things in plain language.

## How to work with the user
- Build in small steps. After each step, say how to run and test it, then stop and wait.
- If the platform can't do something, say so plainly and suggest the closest thing that works.
- Keep v1 out of scope: accounts/login, real payments, social features, AI-generated lessons, multiple languages at once.

## Decisions made
- Platform: native iOS 26 (built with Xcode 27), Swift + SwiftUI, AlarmKit, SpeechAnalyzer, SwiftData. Mac + iPhone.
- Language: Mandarin (zh-CN, simplified) first. Data model supports more languages later. Japanese and Korean come later.
- AlarmKit cannot remove the Stop button. Design: a second "Speak" button opens the challenge, and Stop schedules a bounded series of re-rings until the challenge is passed. See PHASE0.md.
- Matching is by pinyin, not characters. Homophones pass.
- Tones count (user decision, Oct 2026): tone cost is 0.35, so a wrong tone on a 1-syllable word fails and on a 2-syllable word is "near". Only a pass counts as correct; near and fail are both wrong, and a wrong answer swaps in a different word the user must get right. Long phrases (4+ syllables) still forgive one tone slip.
- Tabs: Learn, Alarm, Progress. Settings behind a gear icon.
- Learn first: the alarm only draws from words the user has studied. The alarm is for retrieval, not teaching new words.
- Monetization (designed, not built): Free = one language, level-1 packs, earnable pack tokens. Premium = all languages and packs. Packs are shared across languages through language-independent concepts.

## Status
Done (Python prototypes in prototype/, run on Windows, 1,200+ tests):
- matcher.py + cases.json: forgiving pinyin matcher (Phase 1a)
- data/packs.json + data/words.zh-CN.json: 14 packs, 74 words (Phase 3a)
- quizzes.py: tap-quiz generators
- srs.py: Leitner spaced repetition, plus simulate_srs.py

Run the Python tests: `cd prototype && python -m pytest -q` (needs `pip install pypinyin pytest`; a venv at .venv is gitignored).

Done on the Mac (Oct 2026):
- Setup: macOS 27, **Xcode 27** (iOS 27 SDK), iPhone 17 Pro on **iOS 26.6**, Developer Mode on, free Apple ID (Personal Team `522FQ565F9`). Deployment target is iOS 26.0.
- iOS app in `ios/SpeakToWake/` (hand-written project file using a synchronized folder: new .swift files in `ios/SpeakToWake/SpeakToWake/` are picked up automatically). Bundle ID `com.jedesu.SpeakToWake`.
- Speech check screen: **zh-CN is supported on the phone and its model is installed** (also yue-CN, zh-HK, zh-TW; 30 locales total).

Build, install and launch on the phone from the command line (phone plugged in):
```
cd ios/SpeakToWake
xcodebuild -project SpeakToWake.xcodeproj -scheme SpeakToWake -destination 'id=00008150-001A0C3C3A02401C' -derivedDataPath build -allowProvisioningUpdates build
xcrun devicectl device install app --device 00008150-001A0C3C3A02401C build/Build/Products/Debug-iphoneos/SpeakToWake.app
xcrun devicectl device process launch --device 00008150-001A0C3C3A02401C com.jedesu.SpeakToWake
```
Screenshots: `xcrun devicectl device capture screenshot --device <id> --destination shot.png`. Launch the app first, and ask before taking one, since it captures whatever is on screen.

## Next steps (on the Mac)
1. ~~Confirm setup.~~ Done.
2. Phase 1: ~~zh-CN check~~, ~~live mic transcription~~, ~~matcher ported to Swift~~ (`ios/PinyinMatcher`, a local Swift package used by the app; run its tests with `cd ios/PinyinMatcher && swift test`, which reads prototype/cases.json). Speech check screen judges on Stop and swaps in a new word on a miss. Not done: log every attempt (CSV export). Note: the Mac's Python is 3.9, which only runs test_matcher.py; the other Python tests need 3.10+.
3. Phase 2: AlarmKit alarm with Speak button and re-ring loop. Run the device tests listed in PHASE0.md. Open question: does AlarmKit work with a free Apple ID?
4. Port srs.py, quizzes.py and the data files, then build the Learn and Alarm tabs.

**Open issue: recognizer accuracy on single syllables (come back to this).** On the phone, saying shuì (target 水) was transcribed as 对 duì: with one short syllable the recognizer guesses a common word. The matcher is fine; the input is wrong. Tried: `AnalysisContext.contextualStrings` hints with the target plus tone neighbors (水 · 睡 · 谁), toggle on the speech check screen. User's first impression: it still didn't hear it correctly; not tested systematically yet. Ideas to try: test with/without hints and log results, alternatives (`transcriptionWithAlternatives`) checked against the target, prefer 2+ syllable words or short phrases for speech prompts (e.g. 喝水 instead of 水), and use tap quizzes for single-character words.

Open items: Windows-side options not yet built are the free-tier/pack-token logic and the Phase 5 analysis script. Have a Mandarin reader skim the starter packs.
