import SwiftData
import SwiftUI

@main
struct SpeakToWakeApp: App {
    @State private var alarms = AlarmController.shared
    @AppStorage(AppSettings.Key.hasOnboarded) private var hasOnboarded = false

    init() {
        AppSettings.register()
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if hasOnboarded {
                    tabs
                } else {
                    OnboardingView { hasOnboarded = true }
                }
            }
            .fullScreenCover(isPresented: $alarms.showChallenge) {
                ChallengeView()
            }
            .task { alarms.startObserving() }
        }
        .modelContainer(for: [PackProgress.self, ReviewState.self, Attempt.self, AlarmConfig.self])
    }

    private var tabs: some View {
        TabView {
            Tab("Learn", systemImage: "book") {
                LearnView()
            }
            Tab("Alarm", systemImage: "alarm") {
                AlarmTabView()
            }
            Tab("Progress", systemImage: "chart.bar") {
                ProgressTabView()
            }
        }
    }
}
