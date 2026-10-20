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
            .modifier(SyncOnOpen())
            .fullScreenCover(isPresented: $alarms.showChallenge) {
                ChallengeView()
                    .fontDesign(.rounded)
                    .tint(Theme.accent)
            }
            .fontDesign(.rounded)
            .tint(Theme.accent)
            .foregroundStyle(Theme.text)
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

/// Syncs the account copy when the app opens or comes back to the front.
private struct SyncOnOpen: ViewModifier {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            .task { await SyncService.shared.sync(modelContext) }
            .onChange(of: scenePhase) {
                if scenePhase == .active {
                    Task { await SyncService.shared.sync(modelContext) }
                }
            }
    }
}
