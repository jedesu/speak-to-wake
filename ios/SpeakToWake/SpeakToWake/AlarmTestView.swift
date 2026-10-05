import AlarmKit
import SwiftUI

/// Phase 2 test screen: set an alarm, watch what happens when it rings.
struct AlarmTestView: View {
    private var controller = AlarmController.shared

    var body: some View {
        Group {
            List {
                Section("Volume") {
                    VolumeCheckView()
                }
                Section {
                    LabeledContent("Permission", value: permissionText)
                    if controller.authorization == .notDetermined {
                        Button("Allow alarms") {
                            Task { await controller.requestAuthorization() }
                        }
                    }
                    if controller.authorization == .denied {
                        Text("Turn alarms on in Settings → Apps → Mingo.")
                            .foregroundStyle(.red)
                    }
                    Button {
                        Task { await controller.scheduleTestAlarm() }
                    } label: {
                        Label("Ring in 5 seconds", systemImage: "alarm.fill")
                            .font(.title3)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(controller.authorization == .denied)
                    Button("Try the wake-up challenge now") {
                        controller.showChallenge = true
                    }
                }

                Section("Pending alarms (\(controller.alarms.count))") {
                    if controller.alarms.isEmpty {
                        Text("None").foregroundStyle(.secondary)
                    }
                    ForEach(controller.alarms, id: \.id) { alarm in
                        LabeledContent(scheduleText(alarm), value: stateText(alarm.state))
                    }
                    if !controller.alarms.isEmpty {
                        Button("Cancel all", role: .destructive) { controller.cancelAll() }
                    }
                }

                Section {
                    LabeledContent("Re-rings used", value: "\(controller.reRingCount) of \(AlarmController.maxReRings)")
                    LabeledContent("Challenge passed", value: controller.solved ? "Yes" : "No")
                }

                Section("What happened") {
                    if controller.log.isEmpty {
                        Text("Nothing yet").foregroundStyle(.secondary)
                    }
                    ForEach(Array(controller.log.enumerated()), id: \.offset) { _, line in
                        Text(line).font(.caption.monospaced())
                    }
                    if !controller.log.isEmpty {
                        Button("Clear log") { controller.clearLog() }
                    }
                }
            }
            .navigationTitle("Alarm test")
        }
    }

    private var permissionText: String {
        switch controller.authorization {
        case .authorized: "Allowed"
        case .denied: "Denied"
        case .notDetermined: "Not asked yet"
        @unknown default: "Unknown"
        }
    }

    private func scheduleText(_ alarm: Alarm) -> String {
        if case .fixed(let date) = alarm.schedule {
            return date.formatted(date: .omitted, time: .standard)
        }
        return "Alarm"
    }

    private func stateText(_ state: Alarm.State) -> String {
        switch state {
        case .scheduled: "Scheduled"
        case .countdown: "Counting down"
        case .paused: "Paused"
        case .alerting: "Ringing"
        @unknown default: "Unknown"
        }
    }
}
