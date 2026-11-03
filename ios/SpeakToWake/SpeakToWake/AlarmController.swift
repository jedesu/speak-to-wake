import AlarmKit
import SwiftUI

/// Extra data attached to each alarm. Empty for now.
nonisolated struct WakeMetadata: AlarmMetadata {}

/// Schedules alarms and runs the "re-ring until solved" loop from PHASE0.md:
/// Stop silences one ring but schedules another, until the challenge is passed
/// or the re-ring limit is reached.
///
/// Two kinds of system alarms exist: the user's own alarms (one per AlarmConfig,
/// sharing its id) and short-lived re-rings. Passing a challenge cancels only the
/// re-rings, never the user's alarms.
@Observable
final class AlarmController {
    static let shared = AlarmController()

    static let maxReRings = 5
    static let reRingDelay: TimeInterval = 60
    static let speakBackupDelay: TimeInterval = 90

    private(set) var authorization = AlarmManager.shared.authorizationState
    private(set) var alarms: [Alarm] = []
    private(set) var log: [String] = UserDefaults.standard.stringArray(forKey: "alarmLog") ?? []
    var showChallenge = false
    /// Shown on the ringing screen: the label of the alarm that rang.
    private(set) var ringingLabel: String?

    /// Stored in UserDefaults so the state survives the app being closed between rings.
    private(set) var reRingCount: Int {
        get { access(keyPath: \.reRingCount); return UserDefaults.standard.integer(forKey: "reRingCount") }
        set { withMutation(keyPath: \.reRingCount) { UserDefaults.standard.set(newValue, forKey: "reRingCount") } }
    }
    private(set) var solved: Bool {
        get { access(keyPath: \.solved); return UserDefaults.standard.bool(forKey: "solved") }
        set { withMutation(keyPath: \.solved) { UserDefaults.standard.set(newValue, forKey: "solved") } }
    }
    private var reRingIDs: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: "reRingIDs") ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: "reRingIDs") }
    }
    private var labels: [String: String] {
        get { UserDefaults.standard.dictionary(forKey: "alarmLabels") as? [String: String] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: "alarmLabels") }
    }

    private var updatesTask: Task<Void, Never>?

    func startObserving() {
        authorization = AlarmManager.shared.authorizationState
        alarms = (try? AlarmManager.shared.alarms) ?? []
        guard updatesTask == nil else { return }
        updatesTask = Task {
            for await alarms in AlarmManager.shared.alarmUpdates {
                self.alarms = alarms
                // Ringing while the app is open: show our ringing screen, like Alarmy.
                if let ringing = alarms.first(where: { $0.state == .alerting }), !showChallenge {
                    beginWake(alarmID: ringing.id.uuidString)
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

    // MARK: The user's alarms

    /// Schedules (or reschedules) one of the user's alarms in the system.
    func schedule(_ config: AlarmConfig) async {
        unschedule(config)
        guard config.enabled else { return }
        let timing = Alarm.Schedule.relative(.init(
            time: .init(hour: config.hour, minute: config.minute),
            repeats: config.weekdays.isEmpty ? .never : .weekly(config.weekdays.compactMap(Self.weekday))
        ))
        labels[config.id.uuidString] = config.label
        if await schedule(id: config.id, timing, title: config.label.isEmpty ? "Wake up! Say your word" : config.label) {
            config.nextRing = config.nextRingDate()
            record("Alarm set: \(config.timeText) \(config.daysText)")
        }
    }

    func unschedule(_ config: AlarmConfig) {
        try? AlarmManager.shared.cancel(id: config.id)
    }

    /// Makes the system match the saved alarms (after a reinstall, or if one went missing).
    func sync(_ configs: [AlarmConfig]) async {
        let scheduled = Set(((try? AlarmManager.shared.alarms) ?? []).map(\.id))
        for config in configs where config.enabled {
            // A one-time alarm that already rang turns itself off, like the Clock app.
            if config.weekdays.isEmpty, let next = config.nextRing, next < .now {
                config.enabled = false
                continue
            }
            if !scheduled.contains(config.id) {
                await schedule(config)
            }
        }
    }

    // MARK: Testing (Settings → Developer)

    func scheduleTestAlarm(in seconds: TimeInterval = 5) async {
        cancelReRings()
        let id = UUID()
        labels[id.uuidString] = "Test alarm"
        _ = await schedule(id: id, .fixed(.now + seconds), title: "Test alarm: say your word")
        record("Test alarm set for \((Date.now + seconds).formatted(date: .omitted, time: .standard))")
    }

    // MARK: Called from the alarm buttons (see AlarmIntents.swift)

    func handleStop(alarmID: String) async {
        beginWake(alarmID: alarmID)
        record("Stop tapped")
        // With the challenge already open, a backup ring is set and the app's own
        // sound is playing, so Stop only silences the system alarm.
        guard !showChallenge else { return }
        await reRingIfUnsolved(after: Self.reRingDelay)
    }

    func handleSpeak(alarmID: String) async {
        beginWake(alarmID: alarmID)
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

    func challengePassed() {
        AlarmSound.shared.stop()
        solved = true
        showChallenge = false
        cancelReRings()
        record("Challenge passed: pending re-rings cancelled")
    }

    /// The "press and hold" way out. Stops re-rings, but the log shows it wasn't solved.
    func emergencyDismiss() {
        AlarmSound.shared.stop()
        solved = true
        showChallenge = false
        cancelReRings()
        record("Emergency exit used: alarm off without passing")
    }

    func cancelReRings() {
        for id in reRingIDs {
            if let uuid = UUID(uuidString: id) { try? AlarmManager.shared.cancel(id: uuid) }
        }
        reRingIDs = []
    }

    func clearLog() {
        log = []
        UserDefaults.standard.removeObject(forKey: "alarmLog")
    }

    func isReRing(_ alarm: Alarm) -> Bool {
        reRingIDs.contains(alarm.id.uuidString)
    }

    // MARK: Private

    /// A user's alarm (not a re-ring) starting to ring is a new wake-up: reset the
    /// re-ring count and "solved", or yesterday's pass would skip today's re-rings.
    private func beginWake(alarmID: String) {
        guard !reRingIDs.contains(alarmID) else { return }
        if !showChallenge {
            solved = false
            reRingCount = 0
        }
        ringingLabel = labels[alarmID].flatMap { $0.isEmpty ? nil : $0 }
    }

    /// Makes sure a system alarm will ring again if the app is closed before the
    /// challenge is passed.
    private func ensureBackupRing() async {
        let pending = alarms.contains { reRingIDs.contains($0.id.uuidString) && $0.state == .scheduled }
        guard !pending else { return }
        await reRingIfUnsolved(after: Self.speakBackupDelay)
    }

    private func reRingIfUnsolved(after delay: TimeInterval) async {
        guard !solved else { return }
        guard reRingCount < Self.maxReRings else {
            record("Re-ring limit (\(Self.maxReRings)) reached: no more rings")
            return
        }
        reRingCount += 1
        let id = UUID()
        reRingIDs.insert(id.uuidString)
        let date = Date.now + delay
        if await schedule(id: id, .fixed(date), title: ringingLabel ?? "Still time to wake up! Say your word") {
            record("Re-ring \(reRingCount) of \(Self.maxReRings) set for \(date.formatted(date: .omitted, time: .standard))")
        }
    }

    @discardableResult
    private func schedule(id: UUID, _ schedule: Alarm.Schedule, title: String) async -> Bool {
        if authorization == .notDetermined {
            await requestAuthorization()
        }
        guard authorization == .authorized else {
            record("Not scheduled: alarm permission is off")
            return false
        }
        let alert = AlarmPresentation.Alert(
            title: LocalizedStringResource(stringLiteral: title),
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
            schedule: schedule,
            attributes: attributes,
            stopIntent: StopAlarmIntent(alarmID: id.uuidString),
            secondaryIntent: OpenChallengeIntent(alarmID: id.uuidString),
            // The same beeps the challenge screen plays (AlarmSound), so the ring doesn't change sound.
            sound: .named("MingoAlarm.wav")
        )
        do {
            _ = try await AlarmManager.shared.schedule(id: id, configuration: configuration)
            return true
        } catch {
            record("Scheduling failed: \(error.localizedDescription)")
            return false
        }
    }

    /// Calendar weekday (1 = Sunday ... 7 = Saturday) to AlarmKit's weekday.
    private static func weekday(_ number: Int) -> Locale.Weekday? {
        [1: .sunday, 2: .monday, 3: .tuesday, 4: .wednesday, 5: .thursday, 6: .friday, 7: .saturday][number]
    }

    private func record(_ message: String) {
        log.insert("\(Date.now.formatted(date: .omitted, time: .standard))  \(message)", at: 0)
        log = Array(log.prefix(200))
        UserDefaults.standard.set(log, forKey: "alarmLog")
    }
}
