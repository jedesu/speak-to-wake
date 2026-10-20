import Foundation

/// The user's settings, stored in UserDefaults. Views use the same keys with
/// @AppStorage; the alarm and challenge code reads them through these properties.
enum AppSettings {
    enum Key {
        static let hasOnboarded = "hasOnboarded"
        static let promptsPerWake = "promptsPerWake"
        static let speakingOn = "speakingOn"
        static let gentleWakeUp = "gentleWakeUp"
        static let emergencyMinutes = "emergencyMinutes"
    }

    static func register() {
        UserDefaults.standard.register(defaults: [
            Key.promptsPerWake: 3,
            Key.speakingOn: true,
            Key.gentleWakeUp: false,
            Key.emergencyMinutes: 3,
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
}
