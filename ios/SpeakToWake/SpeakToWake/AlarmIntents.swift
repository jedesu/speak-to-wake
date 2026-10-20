import AlarmKit
import AppIntents

/// Runs when the user taps Stop on the ringing alarm. The system wakes the app in
/// the background to run it, which is where the re-ring gets scheduled.
struct StopAlarmIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Stop alarm"
    static let isDiscoverable = false

    @Parameter(title: "Alarm ID")
    var alarmID: String

    init(alarmID: String) {
        self.alarmID = alarmID
    }

    init() {
        alarmID = ""
    }

    func perform() async throws -> some IntentResult {
        await AlarmController.shared.handleStop(alarmID: alarmID)
        return .result()
    }
}

/// Runs when the user taps Speak. Opens the app into the challenge.
struct OpenChallengeIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Open speaking challenge"
    static let isDiscoverable = false
    static let openAppWhenRun = true

    @Parameter(title: "Alarm ID")
    var alarmID: String

    init(alarmID: String) {
        self.alarmID = alarmID
    }

    init() {
        alarmID = ""
    }

    func perform() async throws -> some IntentResult {
        await AlarmController.shared.handleSpeak(alarmID: alarmID)
        return .result()
    }
}
