import Foundation
import WakeCore

/// The user's settings, stored in UserDefaults. Views use the same keys with
/// @AppStorage; the alarm and challenge code reads them through these properties.
enum AppSettings {
    enum Key {
        static let hasOnboarded = "hasOnboarded"
        static let promptsPerWake = "promptsPerWake"
        static let speakingOn = "speakingOn"
        static let gentleWakeUp = "gentleWakeUp"
        static let emergencyMinutes = "emergencyMinutes"
        static let proUnlocked = "proUnlocked"
        static let learnMode = "learnMode"
        static let demoMode = "demoMode"
        static let language = "language"
        /// Days a wake-up challenge was passed, as `Day.ordinal`s (for streaks and tokens).
        static let wakeDays = "wakeDays"
        /// Pro sections unlocked with an earned token, comma-separated pack ids
        /// (a string, so views can watch it with @AppStorage).
        static let unlockedPacks = "unlockedPacks"
    }

    static func register() {
        #if targetEnvironment(simulator)
        // The browser demo (Appetize) runs the simulator build: count it as signed in, tap questions only.
        let demoByDefault = true
        #else
        let demoByDefault = false
        #endif
        UserDefaults.standard.register(defaults: [
            Key.demoMode: demoByDefault,
            Key.promptsPerWake: 3,
            Key.speakingOn: !demoByDefault,  // no mic in the browser demo
            Key.gentleWakeUp: false,
            Key.emergencyMinutes: 3,
            Key.language: "zh-CN",
        ])
    }

    /// Correct answers needed to turn the alarm off.
    static var promptsPerWake: Int { UserDefaults.standard.integer(forKey: Key.promptsPerWake) }
    /// Off: tap quizzes only (for shared rooms, or a sore throat).
    static var speakingOn: Bool { UserDefaults.standard.bool(forKey: Key.speakingOn) }
    /// The in-app alarm sound starts quiet and gets louder over 30 seconds.
    static var gentleWakeUp: Bool { UserDefaults.standard.bool(forKey: Key.gentleWakeUp) }
    /// How long before the emergency "press and hold" exit appears.
    static var emergencyAfter: TimeInterval { TimeInterval(UserDefaults.standard.integer(forKey: Key.emergencyMinutes) * 60) }
    /// Pro isn't for sale yet; Settings > Developer can unlock it for testing.
    static var proUnlocked: Bool { UserDefaults.standard.bool(forKey: Key.proUnlocked) }
    /// Set by "Set up demo": counts as signed in, so a live demo never depends on the network.
    static var demoMode: Bool { UserDefaults.standard.bool(forKey: Key.demoMode) }
    /// Signed in, or in demo mode: unlocks sections past the trial and the alarm's words.
    static var hasAccountAccess: Bool { AuthService.shared.isSignedIn || demoMode }

    /// Pro: every section and spaced repetition. On with an active App Store
    /// subscription (`Store`), or the Settings > Developer switch for testing.
    static var isPro: Bool { proUnlocked || UserDefaults.standard.bool(forKey: Store.proKey) }

    /// Whether a section can be studied: level 1 is free, higher levels need Pro or a token.
    static func canOpen(_ pack: Pack) -> Bool {
        FreePlan.canOpen(pack, isPro: isPro, unlockedPackIDs: unlockedPackIDs)
    }

    // MARK: Wake-up streak and section tokens (free plan)

    static var wakeDays: Set<Day> {
        Set((UserDefaults.standard.array(forKey: Key.wakeDays) as? [Int] ?? []).map(Day.init(ordinal:)))
    }

    static var unlockedPackIDs: Set<String> {
        Set((UserDefaults.standard.string(forKey: Key.unlockedPacks) ?? "").split(separator: ",").map(String.init))
    }

    static var tokensLeft: Int {
        FreePlan.tokensLeft(wakeDays: wakeDays, unlockedPackIDs: unlockedPackIDs)
    }

    /// Call when a wake-up challenge is passed (not the emergency exit).
    static func recordWakeUp(on day: Day = .today) {
        let days = wakeDays.union([day]).map(\.ordinal).sorted()
        UserDefaults.standard.set(days, forKey: Key.wakeDays)
    }

    /// Spends a token on a Pro section. Returns false if there's no token left.
    @discardableResult
    static func unlockWithToken(_ pack: Pack) -> Bool {
        guard tokensLeft > 0, !canOpen(pack) else { return false }
        UserDefaults.standard.set(unlockedPackIDs.union([pack.id]).sorted().joined(separator: ","), forKey: Key.unlockedPacks)
        return true
    }
}
