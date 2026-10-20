import SwiftUI

/// Settings, opened from the gear icon on every tab. Soft Dawn cards, one per group.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @AppStorage(AppSettings.Key.promptsPerWake) private var promptsPerWake = 3
    @AppStorage(AppSettings.Key.speakingOn) private var speakingOn = true
    @AppStorage(AppSettings.Key.gentleWakeUp) private var gentleWakeUp = false
    @AppStorage(AppSettings.Key.emergencyMinutes) private var emergencyMinutes = 3
    @AppStorage(AppSettings.Key.hasOnboarded) private var hasOnboarded = true
    @AppStorage(AppSettings.Key.proUnlocked) private var proUnlocked = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    group("Account") {
                        AccountCard()
                    }

                    group("Wake-up challenge",
                          footer: "A wrong answer swaps in a different word. After two missed speaking prompts in a row, you get a tap quiz instead.") {
                        HStack {
                            rowText("Answers to turn off", "How many you need to get right")
                            Spacer()
                            CountPicker(value: $promptsPerWake, range: 1...5)
                        }
                        divider
                        Toggle(isOn: $speakingOn) {
                            rowText("Speaking prompts", speakingOn ? "Say words out loud, plus tap quizzes"
                                                                   : "Tap quizzes only, for shared rooms")
                        }
                        .tint(Theme.accent)
                    }

                    group("Sound",
                          footer: "The first ring uses your iPhone's alarm volume. During the challenge, Mingo plays its own sound at your phone's volume until you pass.") {
                        Toggle(isOn: $gentleWakeUp) {
                            rowText("Gentle wake-up", "Starts quiet and gets louder over 30 seconds")
                        }
                        .tint(Theme.accent)
                        divider
                        VStack(alignment: .leading, spacing: 10) {
                            rowText("Emergency exit after", "A press-and-hold exit appears if you're stuck")
                            Picker("Emergency exit after", selection: $emergencyMinutes) {
                                Text("1 min").tag(1)
                                Text("3 min").tag(3)
                                Text("5 min").tag(5)
                            }
                            .pickerStyle(.segmented)
                        }
                        divider
                        VolumeCheckView()
                    }

                    group("Your data") {
                        Button {
                            hasOnboarded = false
                            dismiss()
                        } label: {
                            navRow("Show the welcome screens again", icon: "sparkles")
                        }
                        .buttonStyle(.plain)
                    }

                    group("About") {
                        NavigationLink { LicenseView() } label: { navRow("Picture credits", icon: "photo") }
                            .buttonStyle(.plain)
                    }

                    group("Developer", footer: "Pro isn't for sale yet. This switch opens HSK 2 and up for testing.") {
                        Toggle(isOn: $proUnlocked) {
                            rowText("Pro unlocked (for testing)", "HSK 2–3 sections")
                        }
                        .tint(Theme.accent)
                        divider
                        NavigationLink { SpeechCheckView().softDawnList() } label: { navRow("Speech check", icon: "waveform") }
                            .buttonStyle(.plain)
                        divider
                        NavigationLink { AlarmTestView().softDawnList() } label: { navRow("Alarm test", icon: "alarm") }
                            .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 32)
            }
            .background(Theme.ground)
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: Building blocks

    private func group<Content: View>(_ title: String, footer: String? = nil,
                                      @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.bold())
                .foregroundStyle(Theme.muted)
                .padding(.horizontal, 6)
                .padding(.top, 12)
            VStack(alignment: .leading, spacing: 12) {
                content()
            }
            .card(padding: 18)
            if let footer {
                Text(footer)
                    .font(.footnote)
                    .foregroundStyle(Theme.muted)
                    .padding(.horizontal, 6)
            }
        }
    }

    private func rowText(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.headline)
            Text(detail).font(.subheadline).foregroundStyle(Theme.muted)
        }
    }

    private func navRow(_ title: String, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(Theme.link)
                .frame(width: 32, height: 32)
                .background(Theme.chip, in: .rect(cornerRadius: 10))
            Text(title).font(.headline)
            Spacer()
            Image(systemName: "chevron.right").font(.subheadline.bold()).foregroundStyle(Theme.muted)
        }
        .frame(minHeight: 44)
        .contentShape(.rect)
    }

    private var divider: some View {
        Rectangle().fill(Theme.toggleOff).frame(height: 1)
    }
}

/// "−  3  +" in round chip buttons.
private struct CountPicker: View {
    @Binding var value: Int
    let range: ClosedRange<Int>

    var body: some View {
        HStack(spacing: 10) {
            step("minus", enabled: value > range.lowerBound) { value -= 1 }
                .accessibilityLabel("Fewer")
            Text("\(value)")
                .font(.title2.weight(.heavy))
                .monospacedDigit()
                .frame(minWidth: 24)
            step("plus", enabled: value < range.upperBound) { value += 1 }
                .accessibilityLabel("More")
        }
    }

    private func step(_ icon: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.headline)
                .foregroundStyle(enabled ? Theme.text : Theme.off)
                .frame(width: 44, height: 44)
                .background(Theme.chip, in: .circle)
        }
        .disabled(!enabled)
    }
}

/// Credits for the word pictures (the MIT license asks for its notice to be included).
private struct LicenseView: View {
    private var license: String {
        Bundle.main.url(forResource: "FLUENT-EMOJI-LICENSE", withExtension: "txt")
            .flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? ""
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Word pictures are Microsoft Fluent Emoji (flat style), used under the MIT License.")
                    .font(.headline)
                Text(license)
                    .font(.footnote.monospaced())
                    .foregroundStyle(Theme.muted)
            }
            .card(padding: 20)
            .padding(18)
        }
        .background(Theme.ground)
        .navigationTitle("Picture credits")
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
