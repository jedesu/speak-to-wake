# Phase 0: Feasibility Findings

Sources are Apple's WWDC25 session, WWDC notes, an Apple developer forum thread, and community projects. I could not run any of this on a device. Items marked **TEST** need checking on your iPhone in Phase 2.

## 1. Can the app control how the alarm is dismissed?
**No, not fully.** Apple's alert is a system screen: title, app name, a **mandatory Stop button**, and an optional second button. The app can change the Stop button's text, color and icon. It cannot remove it or block it.

The second button can run a custom action (an App Intent), such as opening your app. That is where our speaking challenge goes.

Another app that does math-to-dismiss on AlarmKit states in its README that it is not an unbreakable gate: Stop works, so the app re-rings the alarm a limited number of times while the challenge is unsolved.

## 2. Does it ring if the app is closed?
**Yes.** Alarms stay active when the app isn't running. They break through **Silent mode and Focus**, which is what your research said. The user must grant permission once (an `NSAlarmKitUsageDescription` text in Info.plist, then an authorization prompt). Permission can be withdrawn silently later, so the app should re-check it.

Caveat from Apple's session: Live Activity UI may not be available until the phone is unlocked after a restart.

## 3. Known risks
- **Stop-intent bug:** a forum thread reports that on iOS 26.2.1 the Stop button's custom action did not run when the alarm was dismissed by swiping or while the phone was unlocked. Apple's engineer could not reproduce it and the thread was unresolved. **TEST** on your phone.
- **No control over the sound pattern:** AlarmKit rings at the system alarm volume. No ramping, no custom vibration.
- **Not for critical alerts:** Apple says AlarmKit isn't a replacement for critical or time-sensitive notifications.

## 4. The closest thing that works: "re-ring until solved"
1. The alarm rings. The alert has **Stop** and a second button, **Speak**.
2. **Speak** opens the app straight into the challenge.
3. If the user taps **Stop** (or dismisses without solving), our stop action schedules another alarm a short time later (for example 1-2 minutes).
4. When the challenge is passed, the app cancels all pending re-rings.
5. After a bounded number of re-rings (for example 5), or a time limit, the app stops re-ringing. **This doubles as our built-in "never stuck" safety.**

Result: the user can silence one ring but not escape for good without doing the challenge. That's the same trade-off Alarmy faces, and it fits your fallback rules.

## 5. Speech check (SpeechAnalyzer)
- Reported to cover 22 languages (42 locales), including Mandarin `zh-CN`. This comes from a third-party summary, so **TEST** it with `SpeechTranscriber.supportedLocales` on your device.
- The model downloads once through `AssetInventory`. We should download it during setup, not at 6 a.m.
- Third-party reviews flag live-microphone wiring as tricky, so Phase 1 is a good place to learn that.

## 6. Android comparison
| | iOS (AlarmKit) | Android |
|---|---|---|
| Rings when app is closed / Silent | Yes, system-guaranteed | Yes, with exact-alarm permission |
| Who draws the ringing screen | Apple (mandatory Stop button) | **Your app** (full-screen activity) |
| Can the app force a challenge before silence? | No, only re-ring | **Yes**, the app controls the sound and screen |
| Permissions | One authorization | Exact-alarm permission (alarm apps can declare `USE_EXACT_ALARM`) and full-screen intent permission (Android 14+ limits it to alarm and calling apps) |
| Free on-device Mandarin speech | SpeechAnalyzer | Possible, but varies by device/vendor |

Android gives much more control over dismissal. The catch is more fiddly setup and device differences. I haven't verified Android details beyond the exact-alarm and full-screen-intent rules above.

## Recommendation
**Stay on iOS with AlarmKit and the re-ring design.** You have the Mac and iPhone, SpeechAnalyzer is the best free on-device option, and AlarmKit gives the reliability that matters most (rings through Silent and Focus). We trade away a hard block on Stop, but the re-ring loop plus a bounded limit gives the same penalty with a built-in safety. Android remains a "later" option if hard blocking turns out to be essential.

## Things to TEST on the device
1. Alarm rings with the app closed, phone on Silent, and Focus on. **Not yet tested systematically.**
2. The second button opens the app into the challenge. **PASSED (Oct 2, 2026):** Speak opens the full-screen challenge; passing it cancels pending re-rings.
3. Stop's custom action runs reliably (the forum bug). **PASSED so far:** Stop ran its intent every time in testing (phone unlocked, alarm shown as a banner). Keep checking with the phone locked.
4. Re-ring scheduling works from the Stop action. **PASSED:** each Stop scheduled the next re-ring, counted up to the limit.

Also confirmed: **AlarmKit works with a free Apple ID** (Personal Team), no paid developer account needed.
5. `zh-CN` appears in `SpeechTranscriber.supportedLocales` and downloads. **PASSED (Oct 2, 2026, iPhone 17 Pro, iOS 26.6):** zh-CN supported and model already installed.
