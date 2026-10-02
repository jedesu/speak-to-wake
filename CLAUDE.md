# Speak-to-Wake: handoff for Claude sessions

Read PLAN.md (design), PHASE0.md (AlarmKit findings) and this file first.

## What this is
A class project (individual entrepreneurship class, ~3 months from late Sept 2026). An iOS alarm that won't stay off until the user passes a Mandarin challenge: speaking a word out loud, or tap quizzes (meaning, hear-and-tap, picture match, true/false, fill-the-blank, match pairs). The user is a student, new to native iOS, comfortable with code. Explain things in plain language.

## How to work with the user
- Build in small steps. After each step, say how to run and test it, then stop and wait.
- If the platform can't do something, say so plainly and suggest the closest thing that works.
- Keep v1 out of scope: accounts/login, real payments, social features, AI-generated lessons, multiple languages at once.

## Decisions made
- Platform: native iOS 26, Swift + SwiftUI, AlarmKit, SpeechAnalyzer, SwiftData. Mac + iPhone.
- Language: Mandarin (zh-CN, simplified) first. Data model supports more languages later. Japanese and Korean come later.
- AlarmKit cannot remove the Stop button. Design: a second "Speak" button opens the challenge, and Stop schedules a bounded series of re-rings until the challenge is passed. See PHASE0.md.
- Matching is by pinyin, not characters. Tones are not graded precisely.
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

Not done: everything that needs a Mac and iPhone.

## Next steps (on the Mac)
1. Confirm Xcode 26, iOS 26 on the iPhone, Developer Mode on, free Apple ID signed in.
2. Phase 1: minimal SwiftUI app that checks `SpeechTranscriber.supportedLocales` for zh-CN, downloads the model, and runs the speech check screen. Port matcher.py to Swift and run cases.json against it. Log every attempt (CSV export).
3. Phase 2: AlarmKit alarm with Speak button and re-ring loop. Run the device tests listed in PHASE0.md. Open question: does AlarmKit work with a free Apple ID?
4. Port srs.py, quizzes.py and the data files, then build the Learn and Alarm tabs.

Open items: Windows-side options not yet built are the free-tier/pack-token logic and the Phase 5 analysis script. Have a Mandarin reader skim the starter packs.
