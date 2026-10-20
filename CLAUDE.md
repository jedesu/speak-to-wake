# Mingo (repo: speak-to-wake): handoff for Claude sessions

Read PLAN.md (design), PHASE0.md (AlarmKit findings) and this file first.

## What this is
A class project (individual entrepreneurship class, ~3 months from late Sept 2026). An iOS alarm that won't stay off until the user passes a Mandarin challenge: speaking a word out loud, or tap quizzes (meaning, hear-and-tap, picture match, true/false, fill-the-blank, match pairs). The user is a student, new to native iOS, comfortable with code. Explain things in plain language.

## How to work with the user
- Build in small steps. After each step, say how to run and test it, then stop and wait.
- If the platform can't do something, say so plainly and suggest the closest thing that works.
- Keep v1 out of scope: accounts/login, real payments, social features, AI-generated lessons, multiple languages at once.

## Decisions made
- Platform: native iOS 26 (built with Xcode 27), Swift + SwiftUI, AlarmKit, SpeechAnalyzer, SwiftData. Mac + iPhone.
- Language: Mandarin (zh-CN, simplified) only for the MVP. Data model supports more languages later. Japanese and Korean come later.
- AlarmKit cannot remove the Stop button. Design: a second "Speak" button opens the challenge, and Stop schedules a bounded series of re-rings until the challenge is passed. See PHASE0.md.
- Matching is by pinyin, not characters. Homophones pass.
- Pinyin style in the word data follows the standard dictionary (现代汉语词典), like Pleco, HelloChinese and the HSK lists: neutral tones are unmarked (葡萄 pútao, 谢谢 xièxie, 朋友 péngyou). An unmarked syllable means neutral tone, not a missing mark. Show a short note about this in the Learn tab.
- Tones count (user decision, Oct 2026): tone cost is 0.35, so a wrong tone on a 1-syllable word fails and on a 2-syllable word is "near". Only a pass counts as correct; near and fail are both wrong, and a wrong answer swaps in a different word the user must get right. Long phrases (4+ syllables) still forgive one tone slip.
- Tabs: Learn, Alarm, Progress. Settings behind a gear icon.
- Learn first: the alarm only draws from words the user has studied. The alarm is for retrieval, not teaching new words.
- **What each mode shows** (user decision, Oct 2026): Learn-tab flashcards show everything (characters, pinyin, meaning, picture, audio). Quizzes, Review and the wake-up challenge show the **characters only**, with no pinyin, English or audio, because pinyin gives the answer away. A **Show hint** button reveals a flat 2D picture of the word. Plan: use Microsoft Fluent Emoji (Flat, MIT license) for the pictures, mapped from each concept's emoji; grammar words like 的/了/吗 have no picture, so no hint button. Using a hint should count as 'correct after retry' in spaced repetition (the word stays in its box).
- **Visual design**: direction B 'Soft Dawn' chosen from the design canvas (warm off-white background, rounded white cards, Nunito font, one accent color). Palette still to pick: Coral, Matcha, Lantern, Ocean or Plum. Canvas: https://claude.ai/artifact/Kqq3LkZm96Y4wFye193jTR
- **Goal: publish on the App Store** (user decision, Oct 2026). Avoid things App Review may reject.
- **Ringing works like Alarmy** (user decision): AlarmKit gives the first ring, even if the app was force-quit. Speak opens the challenge, where the app's own alarm sound (`AlarmSound.swift`) plays until the challenge is passed. The sound pauses while the mic listens or a word is read aloud, and comes back after 10 s of silence. `UIBackgroundModes: audio` keeps it going when the phone is locked or the user leaves the app. Only use background audio for sound the user actually hears: never silent audio overnight to keep the app alive, which is the App Review risk. The AlarmKit backup re-ring is the safety net.
- **No login for the MVP** (user decision, Oct 2026): progress is saved on the iPhone only. Later options: iCloud sync via SwiftData + CloudKit (no login screen) or Sign in with Apple; both need the paid developer account. Email login would need a server, a privacy policy and in-app account deletion.
- The iOS Simulator (`iPhone 18 Pro`) works for checking screens; alarms, mic and speech need the real iPhone. The free developer account's trust expires about every 7 days: re-trust under Settings → General → VPN & Device Management.
- App name is **Mingo** (user decision, Oct 2026). Code, folders and bundle ID keep the old `SpeakToWake` name, because changing the bundle ID would make a new app and lose on-phone data.
- Monetization (designed, not built; matches the user's discovery report): **Free** = speaking alarm, all challenge types, one language, starter packs (level 1 of each theme), wake-up streak, and an earnable pack token. The free alarm and quizzes pick learned words at random. **Pro** ($4.99/mo or $49.99/yr; tier `premium` in the data files) = **spaced repetition** (user decision: the alarm and Review pick the words you're about to forget), every pack, more languages, custom word lists, and detailed progress stats. Keep saving `ReviewState` for free users too, so upgrading to Pro starts with real history. Packs are shared across languages through language-independent concepts. No surprise charges: remind before a trial ends, offer one-tap cancel, and show no ads on the alarm.

## Status
Done (Python prototypes in prototype/, run on Windows, 1,200+ tests):
- matcher.py + cases.json: forgiving pinyin matcher (Phase 1a)
- data/packs.json + data/words.zh-CN.json: **HSK 1 (HSK 2.0 list), 152 words in 16 topic sections** (user decision for the MVP, Oct 2026: Mandarin only, vocabulary organised by HSK). Each pack has `hsk` and `order`; `theme` is the topic, used to pick fair wrong answers. All HSK 1 sections are free; Pro later adds HSK 2+. Erhua forms (这儿/那儿/哪儿) are left out because the pinyin check can't match them yet; 这/那/哪 are in. 谁 uses the everyday reading shéi (the data check accepts shéi or shuí).
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
3. Phase 2: ~~AlarmKit alarm with Speak button and re-ring loop~~ (test version done: Alarm tab with "Ring in 5 seconds", event log; `AlarmController.swift`, `AlarmIntents.swift`, `ChallengeView.swift`). Works with a free Apple ID; Speak, Stop intent and re-ring all passed on device (see PHASE0.md). **Test delays are short** (re-ring 15 s, test alarm 5 s) in `AlarmController`; set back to about 60 s before real use. The alarm-permission text lives in `ios/SpeakToWake/Info.plist`, because `INFOPLIST_KEY_NSAlarmKitUsageDescription` is not a recognized build setting. Locked phone, Silent, Focus and force-quit also passed. Still to build: real alarm time picker, repeat days, and an emergency exit after the re-ring limit.
4. Full-app build order (user wants the whole v1 app, not a demo): (1) ~~tabs, Settings gear, bundled packs, SwiftData models~~ done; (2) ~~SRS port~~ done (`ios/Core/Sources/WakeCore/SRS.swift`, `Day` type for calendar days; `ReviewState.card` / `update(from:)` bridge to SwiftData); (3) ~~Learn tab~~ done: flashcards with TTS audio (`Speaker.swift`), then a choice of practice or finish (user wanted flashcards first, quiz optional); "Study again" uses flip cards; 10-word Review; new packs blocked when more than 15 words are due (`Learning.overdueLimit`, a guess, not from the simulation). Quiz generator ported early (`WakeCore/Quiz.swift`), and `QuizCard` renders every tap type; (4) all challenge types (port quizzes.py); (5) real alarm: time, repeat days, packs, due-word selection, fallbacks, real re-ring delays; (6) Progress; (7) Settings; (8) attempt log + CSV export; (9) Free/Pro: gate spaced repetition (free picks random learned words), lock level-2+ packs, pack tokens, fake-door paywall; (10) onboarding and polish.

**Open issue: recognizer accuracy on single syllables (come back to this).** On the phone, saying shuì (target 水) was transcribed as 对 duì: with one short syllable the recognizer guesses a common word. The matcher is fine; the input is wrong. Tried: `AnalysisContext.contextualStrings` hints with the target plus tone neighbors (水 · 睡 · 谁), toggle on the speech check screen. User's first impression: it still didn't hear it correctly; not tested systematically yet. Ideas to try: test with/without hints and log results, alternatives (`transcriptionWithAlternatives`) checked against the target, prefer 2+ syllable words or short phrases for speech prompts (e.g. 喝水 instead of 水), and use tap quizzes for single-character words.

**Alarmy reference (user screenshots, Oct 2026), to copy in pieces 5 and 10:**
- Onboarding in 4 steps with a progress bar: set alarm time, permissions, choose a sound (categories: Default, Loud, Classic, Nature, Trending), set the volume.
- Each system prompt gets its own explanation; Alarmy's AlarmKit text is "We need this permission to ring the alarm when the phone is locked." Alarmy also asks for notification permission.
- Volume sheet: an alarm volume slider (90%), a "Gentle wake-up: gradually increase for 30 seconds" toggle, and a Preview button.
- Our limits: apps can't set the system volume. The in-app sound can ramp (crescendo) and be quieter than system volume, never louder; the app asks the user to raise the system volume (`VolumeCheck.swift`). A custom sound file can be used for the AlarmKit ring too (`AlertSound.named`), so a sound choice could cover both rings.

Open items: Windows-side options not yet built are the free-tier/pack-token logic and the Phase 5 analysis script. Have a Mandarin reader skim the starter packs.
