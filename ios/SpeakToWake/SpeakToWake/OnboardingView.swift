import AVFoundation
import SwiftData
import SwiftUI

/// First-run setup, in the style of Alarmy's: a few short steps with a progress
/// bar. Welcome, how it works, permissions, first alarm, volume.
struct OnboardingView: View {
    let onFinish: () -> Void

    private enum Step: Int, CaseIterable {
        case welcome, language, howItWorks, permissions, alarm, volume
    }

    @Environment(\.modelContext) private var modelContext
    @AppStorage(AppSettings.Key.gentleWakeUp) private var gentleWakeUp = false

    @State private var step = Step.welcome
    @State private var signingIn = false
    @State private var alarmTime = Calendar.current.date(from: DateComponents(hour: 7, minute: 0)) ?? .now
    @State private var weekdays: Set<Int> = [2, 3, 4, 5, 6]
    @State private var alarmsAllowed = AlarmController.shared.authorization == .authorized
    @State private var micAllowed = AVAudioApplication.shared.recordPermission == .granted

    var body: some View {
        VStack(spacing: 0) {
            if step != .welcome {
                HStack(spacing: 12) {
                    Button {
                        withAnimation { step = Step(rawValue: step.rawValue - 1) ?? .welcome }
                    } label: {
                        Image(systemName: "chevron.left").font(.title3.bold())
                    }
                    .accessibilityLabel("Back")
                    ProgressView(value: Double(step.rawValue), total: Double(Step.allCases.count - 1))
                        .tint(Theme.accent)
                    Text("\(step.rawValue)/\(Step.allCases.count - 1)")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .padding()
            }

            Group {
                switch step {
                case .welcome: welcome
                case .language: languageStep
                case .howItWorks: howItWorks
                case .permissions: permissions
                case .alarm: alarm
                case .volume: volume
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 24)
            .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)).combined(with: .opacity))
            .id(step)

            Button(action: next) {
                Text(buttonTitle)
                    .font(.title3.bold())
                    .frame(maxWidth: .infinity, minHeight: 56)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            .clipShape(.capsule)
            .padding(24)
        }
        .background(Theme.ground)
    }

    private var buttonTitle: String {
        switch step {
        case .welcome: "Get started"
        case .alarm: "Set alarm"
        case .volume: "Learn my first words"
        default: "Next"
        }
    }

    private func next() {
        switch step {
        case .alarm:
            saveAlarm()
        case .volume:
            onFinish()
            return
        default:
            break
        }
        withAnimation { step = Step(rawValue: step.rawValue + 1) ?? .volume }
    }

    // MARK: Steps

    private var welcome: some View {
        VStack(spacing: 20) {
            Spacer()
            Text("🐼").font(.system(size: 120))
            Text("Mingo").font(.system(size: 48, weight: .bold, design: .rounded))
            Text("Wake up speaking a new language.")
                .font(.title2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
            Button("I already have an account") { signingIn = true }
                .font(.headline)
                .foregroundStyle(Theme.link)
                .frame(minHeight: 44)
                .sheet(isPresented: $signingIn) {
                    SignInView(title: "Welcome back", message: "Sign in to bring back your progress.")
                }
        }
    }

    private var languageStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("What are you learning?").font(.largeTitle.bold())
                Text("Your alarm will ask you words in this language.")
                    .foregroundStyle(.secondary)
                LanguageList()
            }
            .padding(.top, 12)
        }
        .scrollIndicators(.hidden)
    }

    private var howItWorks: some View {
        VStack(alignment: .leading, spacing: 28) {
            Text("How it works").font(.largeTitle.bold())
            stepRow("book.fill", .blue, "Learn a few words",
                    "Study short sections of everyday words with flashcards, audio and quick quizzes.")
            stepRow("alarm.fill", Theme.accent, "Your alarm asks them",
                    "In the morning, Mingo quizzes you on words you've learned.")
            stepRow("mic.fill", .green, "Say it to turn it off",
                    "Answer out loud or by tapping. A wrong answer gives you a new word.")
            stepRow("lifepreserver.fill", .purple, "Never stuck",
                    "Easier questions if you struggle, and an emergency exit if you need it.")
            Spacer()
        }
        .padding(.top, 12)
    }

    private func stepRow(_ icon: String, _ color: Color, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(color, in: .rect(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(detail).foregroundStyle(.secondary)
            }
        }
    }

    private var permissions: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Two permissions").font(.largeTitle.bold())
            Text("iOS will ask you about each one.")
                .foregroundStyle(.secondary)
            permissionRow("alarm.fill", "Alarms",
                          "So your alarm rings even when the phone is locked, on Silent, or in Focus.",
                          allowed: alarmsAllowed) {
                await AlarmController.shared.requestAuthorization()
                alarmsAllowed = AlarmController.shared.authorization == .authorized
            }
            permissionRow("mic.fill", "Microphone",
                          "So Mingo can hear you say words. Your voice is checked on your iPhone and never uploaded.",
                          allowed: micAllowed) {
                micAllowed = await AVAudioApplication.requestRecordPermission()
            }
            Spacer()
        }
        .padding(.top, 12)
    }

    private func permissionRow(_ icon: String, _ title: String, _ detail: String, allowed: Bool,
                               request: @escaping () async -> Void) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(Theme.accent)
                .frame(width: 36)
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
                if allowed {
                    Label("Allowed", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.subheadline.bold())
                } else {
                    Button("Allow \(title.lowercased())") { Task { await request() } }
                        .buttonStyle(.bordered)
                }
            }
        }
    }

    private var alarm: some View {
        VStack(spacing: 16) {
            Text("Set your wake-up alarm").font(.largeTitle.bold()).multilineTextAlignment(.center)
            DatePicker("Time", selection: $alarmTime, displayedComponents: .hourAndMinute)
                .datePickerStyle(.wheel)
                .labelsHidden()
            HStack(spacing: 8) {
                ForEach(1...7, id: \.self) { day in
                    let on = weekdays.contains(day)
                    Button {
                        if on { weekdays.remove(day) } else { weekdays.insert(day) }
                    } label: {
                        Text(Calendar.current.veryShortWeekdaySymbols[day - 1])
                            .font(.headline)
                            .frame(width: 40, height: 40)
                            .background(on ? Theme.accent : Color.secondary.opacity(0.15), in: .circle)
                            .foregroundStyle(on ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Calendar.current.weekdaySymbols[day - 1])
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            Text(AlarmConfig.daysText(for: weekdays, never: "Rings once"))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.top, 12)
    }

    private var volume: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Make it loud enough").font(.largeTitle.bold())
            Text("While you do the morning challenge, Mingo plays its own alarm at your phone's volume until you pass.")
                .foregroundStyle(.secondary)
            VolumeCheckView()
            Toggle(isOn: $gentleWakeUp) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Gentle wake-up").font(.headline)
                    Text("Start quiet and get louder over 30 seconds")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .tint(Theme.accent)
            Label("Your progress is saved on this iPhone.", systemImage: "iphone")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.top, 12)
    }

    private func saveAlarm() {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: alarmTime)
        let config = AlarmConfig(hour: parts.hour ?? 7, minute: parts.minute ?? 0, weekdays: weekdays.sorted())
        modelContext.insert(config)
        try? modelContext.save()
        Task { await AlarmController.shared.schedule(config) }
    }
}

#Preview {
    OnboardingView {}
}
