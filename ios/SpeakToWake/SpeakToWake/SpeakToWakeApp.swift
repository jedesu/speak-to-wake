import SwiftData
import SwiftUI

@main
struct SpeakToWakeApp: App {
    @State private var alarms = AlarmController.shared

    var body: some Scene {
        WindowGroup {
            TabView {
                Tab("Learn", systemImage: "book") {
                    LearnView()
                }
                Tab("Alarm", systemImage: "alarm") {
                    NavigationStack {
                        AlarmTestView()
                            .settingsButton()
                    }
                }
                Tab("Progress", systemImage: "chart.bar") {
                    ProgressTabView()
                }
            }
            .fullScreenCover(isPresented: $alarms.showChallenge) {
                ChallengeView()
            }
            .task { alarms.startObserving() }
        }
        .modelContainer(for: [PackProgress.self, ReviewState.self, Attempt.self])
    }
}
