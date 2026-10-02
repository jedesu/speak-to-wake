import SwiftUI

@main
struct SpeakToWakeApp: App {
    @State private var alarms = AlarmController.shared

    var body: some Scene {
        WindowGroup {
            TabView {
                Tab("Alarm", systemImage: "alarm") {
                    AlarmTestView()
                }
                Tab("Speech", systemImage: "waveform") {
                    SpeechCheckView()
                }
            }
            .fullScreenCover(isPresented: $alarms.showChallenge) {
                ChallengeView()
            }
            .task { alarms.startObserving() }
        }
    }
}
