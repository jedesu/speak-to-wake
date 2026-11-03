import Foundation
import SwiftData
import WakeCore

/// "Set up demo" (Settings > Developer): realistic progress for a live demo, so
/// the app never starts empty on stage. Demo mode also counts as signed in, so
/// the demo doesn't depend on the network.
enum DemoData {
    /// "Start over": wipes progress, answers, alarms and settings, signs out, and
    /// shows the welcome screens again, like a fresh install.
    @MainActor
    static func startOver(_ context: ModelContext) {
        let alarms = (try? context.fetch(FetchDescriptor<AlarmConfig>())) ?? []
        for alarm in alarms { AlarmController.shared.unschedule(alarm) }
        try? context.delete(model: AlarmConfig.self)
        try? context.delete(model: PackProgress.self)
        try? context.delete(model: ReviewState.self)
        try? context.delete(model: Attempt.self)
        try? context.save()
        AuthService.shared.signOut()
        if let bundleID = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bundleID)
        }
        AppSettings.register()
        UserDefaults.standard.set(false, forKey: AppSettings.Key.hasOnboarded)
    }

    static func load(into context: ModelContext) async {
        let library = AppContent.library
        let today = Day.today
        let hsk1 = library.hskLevels.first?.packs ?? []

        // Start clean: remove old progress and answers.
        try? context.delete(model: PackProgress.self)
        try? context.delete(model: ReviewState.self)
        try? context.delete(model: Attempt.self)

        // HSK 1 sections 1-3 learned over the last few days.
        for (offset, pack) in hsk1.prefix(3).enumerated() {
            let learnedDay = today - (6 - offset * 2)
            context.insert(PackProgress(packID: pack.id, language: library.language,
                                        learnedAt: learnedDay.startDate().addingTimeInterval(19 * 3600)))
            for (i, word) in library.words(in: pack).enumerated() {
                var card = SRS.learn(word.id, today: learnedDay)
                // Section 1: about six words due today (Review and the alarm have work);
                // the rest have been reviewed and come back later.
                if offset == 0 && i < 6 {
                    card = Card(itemID: word.id, box: 2, due: today, timesCorrect: 1, timesMissed: i == 2 ? 1 : 0,
                                lastReviewed: today - 2)
                } else {
                    card = Card(itemID: word.id, box: 2 + (i % 2), due: today + 1 + (i % 4), timesCorrect: 2,
                                timesMissed: i % 5 == 0 ? 1 : 0, lastReviewed: today - 1)
                }
                context.insert(ReviewState(card))
            }
        }

        // A few days of answers, about 80% right, for the Progress tab.
        let learned = hsk1.prefix(3).flatMap { library.words(in: $0) }
        let types = ["say_it", "meaning_to_english", "hear_and_tap", "picture_match", "true_false"]
        for n in 0..<36 {
            let word = learned[n % learned.count]
            let day = today - (n % 5)
            context.insert(Attempt(date: day.startDate().addingTimeInterval(7 * 3600 + Double(n) * 60),
                                   wordID: word.id, challengeType: types[n % types.count],
                                   context: n % 3 == 0 ? "wake" : "review", passed: n % 5 != 3))
        }
        try? context.save()

        // A real-looking weekday alarm.
        let alarms = (try? context.fetch(FetchDescriptor<AlarmConfig>())) ?? []
        if !alarms.contains(where: { $0.label == "Wake up early" }) {
            let alarm = AlarmConfig(hour: 7, minute: 0, weekdays: [2, 3, 4, 5, 6], label: "Wake up early")
            context.insert(alarm)
            try? context.save()
            await AlarmController.shared.schedule(alarm)
        }

        // Tap questions only on stage: speech recognition can stumble with room noise.
        UserDefaults.standard.set(false, forKey: AppSettings.Key.speakingOn)
        UserDefaults.standard.set(true, forKey: AppSettings.Key.proUnlocked)
        UserDefaults.standard.set(true, forKey: AppSettings.Key.demoMode)
        UserDefaults.standard.set(true, forKey: AppSettings.Key.hasOnboarded)
    }
}
