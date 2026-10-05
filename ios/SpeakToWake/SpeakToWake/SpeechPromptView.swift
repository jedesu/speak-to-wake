import PinyinMatcher
import SwiftUI
import WakeCore

/// A speaking prompt: say the word, repeat what you hear, or read the example aloud.
///
/// The mic starts by itself, and a correct answer passes as soon as it's heard,
/// so a groggy user doesn't have to find a button.
struct SpeechPromptView: View {
    let word: Word
    let challenge: Challenge
    let onFinish: (_ passed: Bool, _ transcript: String, _ score: Double) -> Void
    let onSwitchToTap: () -> Void
    var onListeningChange: (Bool) -> Void = { _ in }

    /// Stop listening after this long with nothing heard (the alarm comes back).
    static let silenceTimeout: Duration = .seconds(10)

    @State private var listener = LiveTranscriber()
    @State private var finished = false
    @State private var showText = false
    @State private var idleTask: Task<Void, Never>?
    @State private var timedOut = false

    private let locale = Locale(identifier: "zh-CN")
    private var english: String { AppContent.library.concept(for: word)?.english ?? "" }

    /// What has to be said.
    private var target: String {
        challenge == .readAloud ? word.example?.text ?? word.text : word.text
    }

    private var alternates: [String] {
        challenge == .readAloud ? [] : word.alternates ?? []
    }

    var body: some View {
        VStack(spacing: 20) {
            Text(instruction)
                .font(.headline)
                .foregroundStyle(.secondary)
            prompt
                .frame(maxWidth: .infinity, minHeight: 160)

            Text(listener.transcript.isEmpty ? (listener.isListening ? "Listening…" : " ") : listener.transcript)
                .font(.title2)
                .foregroundStyle(listener.transcript.isEmpty ? .secondary : .primary)
            if let error = listener.errorMessage {
                Text(error).foregroundStyle(.red)
            }
            if timedOut && !listener.isListening {
                Text("Didn't hear anything. Tap Start talking.")
                    .foregroundStyle(.orange)
            }

            Button {
                Task {
                    if listener.isListening {
                        await judge()
                    } else {
                        await startListening()
                    }
                }
            } label: {
                Label(listener.isListening ? "Done" : "Start talking",
                      systemImage: listener.isListening ? "stop.circle.fill" : "mic.circle.fill")
                    .font(.title2.bold())
                    .frame(maxWidth: .infinity, minHeight: 56)
            }
            .buttonStyle(.borderedProminent)
            .tint(listener.isListening ? .red : .orange)

            Button("Can't talk right now? Answer by tapping") {
                Task {
                    finished = true
                    await listener.stop()
                    onSwitchToTap()
                }
            }
            .font(.footnote)
        }
        .padding()
        .task {
            if challenge == .hearAndRepeat {
                Speaker.shared.say(word.text)
                try? await Task.sleep(for: .seconds(1.5))
            }
            await startListening()
        }
        .onChange(of: listener.transcript) {
            // Pass as soon as the right word is heard.
            guard listener.isListening, !finished else { return }
            if check().verdict == .pass {
                Task { await judge() }
            }
        }
        .onChange(of: listener.isListening) {
            onListeningChange(listener.isListening)
        }
        .onDisappear {
            idleTask?.cancel()
            onListeningChange(false)
            Task { await listener.stop() }
        }
    }

    private var instruction: String {
        switch challenge {
        case .hearAndRepeat: "Listen, then say it back"
        case .readAloud: "Read this sentence out loud"
        default: "Say this word out loud"
        }
    }

    @ViewBuilder
    private var prompt: some View {
        switch challenge {
        case .hearAndRepeat:
            VStack(spacing: 12) {
                Button {
                    Speaker.shared.say(word.text)
                } label: {
                    Image(systemName: "speaker.wave.3.fill").font(.system(size: 64))
                }
                .accessibilityLabel("Play the word again")
                if showText {
                    Text("\(word.text)  \(word.pinyin)").font(.title)
                } else {
                    Button("Show the word") { showText = true }
                        .font(.footnote)
                }
            }
        case .readAloud:
            if let example = word.example {
                VStack(spacing: 8) {
                    Text(example.text).font(.largeTitle).multilineTextAlignment(.center)
                    Text(example.pinyin).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Text(example.english).font(.subheadline).multilineTextAlignment(.center)
                }
            }
        default:
            VStack(spacing: 6) {
                Text(word.text).font(.system(size: 80))
                Text(word.pinyin).font(.title2).foregroundStyle(.secondary)
                Text(english).font(.title3)
            }
        }
    }

    private func check() -> MatchResult {
        Matcher.check(target: target, transcript: listener.transcript, alternates: alternates)
    }

    private func startListening() async {
        guard !finished else { return }
        timedOut = false
        onListeningChange(true)  // quiet the alarm before the mic opens
        await listener.start(locale: locale, hints: [target] + alternates)
        if !listener.isListening {
            onListeningChange(false)  // the mic failed to start
            return
        }
        idleTask?.cancel()
        idleTask = Task {
            try? await Task.sleep(for: Self.silenceTimeout)
            guard !Task.isCancelled, listener.isListening, listener.transcript.isEmpty else { return }
            timedOut = true
            await listener.stop()
        }
    }

    private func judge() async {
        guard !finished else { return }
        finished = true
        idleTask?.cancel()
        await listener.stop()
        let result = check()
        onFinish(result.verdict == .pass, listener.transcript, result.score)
    }
}
