import SwiftUI

/// Settings, opened from the gear icon on every tab.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @AppStorage(AppSettings.Key.promptsPerWake) private var promptsPerWake = 3
    @AppStorage(AppSettings.Key.speakingOn) private var speakingOn = true
    @AppStorage(AppSettings.Key.gentleWakeUp) private var gentleWakeUp = false
    @AppStorage(AppSettings.Key.emergencyMinutes) private var emergencyMinutes = 3
    @AppStorage(AppSettings.Key.hasOnboarded) private var hasOnboarded = true

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Stepper(value: $promptsPerWake, in: 1...5) {
                        LabeledContent("Answers to turn off", value: "\(promptsPerWake)")
                    }
                    Toggle(isOn: $speakingOn) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Speaking prompts")
                            Text(speakingOn ? "Say words out loud, plus tap quizzes"
                                            : "Tap quizzes only, for shared rooms")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Wake-up challenge")
                } footer: {
                    Text("A wrong answer swaps in a different word. After two missed speaking prompts in a row, you get a tap quiz instead.")
                }

                Section {
                    Toggle(isOn: $gentleWakeUp) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Gentle wake-up")
                            Text("The challenge sound starts quiet and gets louder over 30 seconds")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Picker("Emergency exit after", selection: $emergencyMinutes) {
                        Text("1 minute").tag(1)
                        Text("3 minutes").tag(3)
                        Text("5 minutes").tag(5)
                    }
                    VolumeCheckView()
                } header: {
                    Text("Sound")
                } footer: {
                    Text("The first ring uses your iPhone's alarm volume. During the challenge, Mingo plays its own sound at your phone's volume until you pass. If you're stuck, a press-and-hold exit appears after the time above.")
                }

                Section("Your data") {
                    Label("Your progress is saved on this iPhone.", systemImage: "iphone")
                    Button("Show the welcome screens again") {
                        hasOnboarded = false
                        dismiss()
                    }
                }

                Section("Developer") {
                    NavigationLink("Speech check") { SpeechCheckView() }
                    NavigationLink("Alarm test") { AlarmTestView() }
                }
            }
            .softDawnList()
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct SettingsButton: ViewModifier {
    @State private var showSettings = false

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Settings", systemImage: "gearshape") { showSettings = true }
                }
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
    }
}

extension View {
    /// Adds the gear icon that opens Settings.
    func settingsButton() -> some View {
        modifier(SettingsButton())
    }
}
