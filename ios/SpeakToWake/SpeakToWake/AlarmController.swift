import AlarmKit
import SwiftUI

/// Extra data attached to each alarm. Empty for now.
nonisolated struct WakeMetadata: AlarmMetadata {}

/// Schedules alarms and runs the "re-ring until solved" loop from PHASE0.md:
/// Stop silences one ring but schedules another, until the challenge is passed
/// or the re-ring limit is reached.
@Observable
final class AlarmController {
    static let shared = AlarmController()

    static let maxReRings = 5
    // Short delays for testing. Use about 60 s for real alarms.
    static let reRingDelay: TimeInterval = 15
    static let speakBackupDelay: TimeInterval = 60

    private(set) var authorization = AlarmManager.shared.authorizationState
    private(set) var alarms: [Alarm] = []
    private(set) var log: [String] = UserDefaults.standard.stringArray(forKey: "alarmLog") ?? []
    var showChallenge = false

    /// Stored in UserDefaults so the count survives the app being closed between rings.
    private(set) var reRingCount: Int {
        get { access(keyPath: \.reRingCount); return UserDefaults.standard.integer(forKey: "reRingCount") }
        set { withMutation(keyPath: \.reRingCount) { UserDefaults.standard.set(newValue, forKey: "reRingCount") } }
    }
    private(set) var solved: Bool {
        get { access(keyPath: \.solved); return UserDefaults.standard.bool(forKey: "solved") }
        set { withMutation(keyPath: \.solved) { UserDefaults.standard.set(newValue, forKey: "solved") } }
    }

    private var updatesTask: Task<Void, Never>?

    func startObserving() {
        authorization = AlarmManager.shared.authorizationState
        guard updatesTask == nil else { return }
        updatesTask = Task {
            for await alarms in AlarmManager.shared.alarmUpdates {
                self.alarms = alarms
                // Ringing while the app is open: show our ringing screen, like Alarmy.
                if alarms.contains(where: { $0.state == .alerting }) && !showChallenge {
                    record("Alarm ringing with the app open: showing the ringing screen")
                    showChallenge = true
                    await ensureBackupRing()
                }
            }
        }
    }

    func requestAuthorization() async {
        do {
            authorization = try await AlarmManager.shared.requestAuthorization()
        } catch {
            record("Permission error: \(error.localizedDescription)")
        }
    }

    func scheduleTestAlarm(in seconds: TimeInterval = 5) async {
        cancelAll()  // one test at a time, so extra taps don't stack up alarms
        reRingCount = 0
        solved = false
        await schedule(at: .now + seconds, label: "Test alarm")
    }

    // MARK: Called from the alarm buttons (see AlarmIntents.swift)

    func handleStop() async {
        record("Stop tapped")
        // With the challenge already open, a backup ring is set and the app's own
        // sound is playing, so Stop only silences the system alarm.
        guard !showChallenge else { return }
        await reRingIfUnsolved(after: Self.reRingDelay)
    }

    func handleSpeak() async {
        record("Speak tapped: opening challenge")
        showChallenge = true
        await ensureBackupRing()
    }

    /// Stops a system alarm that is still ringing, once the challenge takes over
    /// (the app's own sound keeps going).
    func silenceSystemAlarm() {
        for alarm in alarms where alarm.state == .alerting {
            try? AlarmManager.shared.stop(id: alarm.id)
        }
    }

    /// Makes sure a system alarm will ring again if the app is closed before the
    /// challenge is passed.
    private func ensureBackupRing() async {
        guard !alarms.contains(where: { $0.state == .scheduled }) else { return }
        await reRingIfUnsolved(after: Self.speakBackupDelay)
    }

    func challengePassed() {
        AlarmSound.shared.stop()
        solved = true
        showChallenge = false
        cancelAll()
        record("Challenge passed: pending re-rings cancelled")
    }

    /// The "press and hold" way out. Stops re-rings, but the log shows it wasn't solved.
    func emergencyDismiss() {
        AlarmSound.shared.stop()
        solved = true
        showChallenge = false
        cancelAll()
        record("Emergency exit used: alarm off without passing")
    }

    func cancelAll() {
        for alarm in alarms {
            try? AlarmManager.shared.cancel(id: alarm.id)
        }
    }

    func clearLog() {
        log = []
        UserDefaults.standard.removeObject(forKey: "alarmLog")
    }

    // MARK: Private

    private func reRingIfUnsolved(after delay: TimeInterval) async {
        guard !solved else { return }
        guard reRingCount < Self.maxReRings else {
            record("Re-ring limit (\(Self.maxReRings)) reached: no more rings")
            return
        }
        reRingCount += 1
        await schedule(at: .now + delay, label: "Re-ring \(reRingCount) of \(Self.maxReRings)")
    }

    private func schedule(at date: Date, label: String) async {
        if authorization == .notDetermined {
            await requestAuthorization()
        }
        guard authorization == .authorized else {
            record("Not scheduled: alarm permission is off")
            return
        }

        let id = UUID()
        let alert = AlarmPresentation.Alert(
            title: "Wake up! Say your word",
            stopButton: AlarmButton(text: "Stop", textColor: .white, systemImageName: "stop.fill"),
            secondaryButton: AlarmButton(text: "Speak", textColor: .white, systemImageName: "mic.fill"),
            secondaryButtonBehavior: .custom
        )
        let attributes = AlarmAttributes(
            presentation: AlarmPresentation(alert: alert),
            metadata: WakeMetadata(),
            tintColor: .orange
        )
        let configuration = AlarmManager.AlarmConfiguration.alarm(
            schedule: .fixed(date),
            attributes: attributes,
            stopIntent: StopAlarmIntent(alarmID: id.uuidString),
            secondaryIntent: OpenChallengeIntent(alarmID: id.uuidString)
        )
        do {
            _ = try await AlarmManager.shared.schedule(id: id, configuration: configuration)
            record("\(label) set for \(date.formatted(date: .omitted, time: .standard))")
        } catch {
            record("Scheduling failed: \(error.localizedDescription)")
        }
    }

    private func record(_ message: String) {
        log.insert("\(Date.now.formatted(date: .omitted, time: .standard))  \(message)", at: 0)
        UserDefaults.standard.set(log, forKey: "alarmLog")
    }
}
