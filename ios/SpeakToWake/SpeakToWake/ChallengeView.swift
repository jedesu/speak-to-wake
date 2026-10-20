import SwiftData
import SwiftUI
import WakeCore

/// Full-screen wake-up challenge, opened by the alarm's Speak button.
/// A few correct answers turn the alarm off; a wrong answer swaps in another word.
struct ChallengeView: View {

    @Environment(\.modelContext) private var modelContext
    @Query private var reviews: [ReviewState]
    @State private var session: WakeSession?
    @State private var started = false

    var body: some View {
        if started {
            challenge
        } else {
            RingingView(label: AlarmController.shared.ringingLabel) {
                AlarmController.shared.silenceSystemAlarm()
                started = true
            }
                .onAppear { AlarmSound.shared.start() }
        }
    }

    private var challenge: some View {
        VStack(spacing: 0) {
            if let session {
                header(session)
                if session.finished {
                    goodMorning
                } else if !session.hasWords {
                    noWords
                } else if let prompt = session.prompt {
                    ScrollView {
                        if let message = session.message {
                            Label(message, systemImage: "arrow.triangle.2.circlepath")
                                .font(.headline)
                                .foregroundStyle(Theme.accent)
                                .padding(.bottom, 4)
                        }
                        promptView(prompt, session: session)
                            .id(prompt.id)
                    }
                }
                Spacer(minLength: 0)
                emergencyExit(session)
            }
        }
        .background(Theme.ground)
        .onAppear {
            if session == nil { session = WakeSession(reviews: reviews) }
            AlarmSound.shared.start()
        }
        .onDisappear {
            AlarmSound.shared.stop()
        }
    }

    private func header(_ session: WakeSession) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Good morning")
                    .font(.subheadline.bold())
                    .foregroundStyle(Theme.muted)
                Text("Say \(session.required) \(session.required == 1 ? "word" : "words") to wake up")
                    .font(.title3.weight(.heavy))
            }
            Spacer()
            HStack(spacing: 6) {
                ForEach(0..<session.required, id: \.self) { i in
                    Circle()
                        .fill(i < session.passed ? Theme.accent : Theme.toggleOff)
                        .frame(width: 12, height: 12)
                }
            }
            .accessibilityElement()
            .accessibilityLabel("\(session.passed) of \(session.required) done")
        }
        .padding(.horizontal, 22)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    @ViewBuilder
    private func promptView(_ prompt: WakeSession.Prompt, session: WakeSession) -> some View {
        if prompt.challenge.isSpeech {
            SpeechPromptView(word: prompt.word, challenge: prompt.challenge) { passed, transcript, score, usedHint in
                session.answer(correct: passed, transcript: transcript, score: score, usedHint: usedHint,
                               reviews: reviews, context: modelContext)
            } onSwitchToTap: {
                session.switchToTap()
            } onListeningChange: { listening in
                AlarmSound.shared.setPaused(listening, reason: "listening")
            }
        } else if let quiz = prompt.quiz {
            QuizCard(quiz: quiz) { correct, chosen, usedHint in
                session.answer(correct: correct, chosen: chosen, usedHint: usedHint, reviews: reviews, context: modelContext)
            }
        }
    }

    private var goodMorning: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "sun.max.fill")
                .font(.system(size: 90))
                .foregroundStyle(Theme.accent)
            Text("You're up!").font(.largeTitle.bold())
            Text("Alarm off. Have a good day.").foregroundStyle(.secondary)
            Spacer()
        }
        .task {
            try? await Task.sleep(for: .seconds(1.5))
            AlarmController.shared.challengePassed()
        }
    }

    private var noWords: some View {
        VStack(spacing: 16) {
            Spacer()
            Text("No words to ask yet").font(.title.bold())
            Text("Your alarm only asks words you've learned. Learn a pack in the Learn tab so tomorrow's alarm has words.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Turn off alarm") {
                AlarmController.shared.challengePassed()
            }
            .buttonStyle(PrimaryButtonStyle())
            Spacer()
        }
        .padding()
    }

    /// Appears after a few minutes. Holding (not tapping) keeps it from being an easy way out.
    private func emergencyExit(_ session: WakeSession) -> some View {
        TimelineView(.periodic(from: .now, by: 5)) { context in
            if context.date.timeIntervalSince(session.startedAt) >= AppSettings.emergencyAfter && !session.finished {
                Text("Stuck? Press and hold here for 3 seconds to turn the alarm off.")
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(Theme.tip, in: .rect(cornerRadius: 16))
                    .padding()
                    .onLongPressGesture(minimumDuration: 3) {
                        AlarmController.shared.emergencyDismiss()
                    }
            }
        }
    }
}
