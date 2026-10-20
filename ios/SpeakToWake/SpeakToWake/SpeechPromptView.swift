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
    let onFinish: (_ passed: Bool, _ transcript: String, _ score: Double, _ usedHint: Bool) -> Void
    let onSwitchToTap: () -> Void
    var onListeningChange: (Bool) -> Void = { _ in }

    /// Stop listening after this long with nothing heard (the alarm comes back).
    static let silenceTimeout: Duration = .seconds(10)

    @State private var listener = LiveTranscriber()
    @State private var finished = false
    @State private var showText = false
    @State private var usedHint = false
    @State private var idleTask: Task<Void, Never>?
    @State private var timedOut = false

    private let locale = Locale(identifier: "zh-CN")

    /// What has to be said.
    private var target: String {
        challenge == .readAloud ? word.example?.text ?? word.text : word.text
    }

    private var alternates: [String] {
        challenge == .readAloud ? [] : word.alternates ?? []
    }

    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 12) {
                Text(instruction)
                    .font(.caption.weight(.heavy))
                    .textCase(.uppercase)
                    .kerning(1)
                    .foregroundStyle(Theme.muted)
                prompt
                hint
            }
            .frame(maxWidth: .infinity, minHeight: 300)
            .card(padding: 24)

            listeningCard

            if let error = listener.errorMessage {
                Text(error).foregroundStyle(.red)
            }

            Button("Can't talk right now? Answer by tapping") {
                Task {
                    finished = true
                    await listener.stop()
                    onSwitchToTap()
                }
            }
            .font(.subheadline.bold())
            .foregroundStyle(Theme.link)
            .frame(minHeight: 44)
        }
        .padding(.horizontal, 18)
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

    /// "Listening…" with what it heard so far, and the round mic button.
    private var listeningCard: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                if listener.isListening {
                    Text(listener.transcript.isEmpty ? "Listening…" : listener.transcript)
                        .font(.headline)
                    Text("It passes as soon as it hears you")
                        .font(.subheadline)
                        .foregroundStyle(Theme.muted)
                } else if timedOut {
                    Text("Didn't hear anything").font(.headline)
                    Text("Tap the mic and try again")
                        .font(.subheadline)
                        .foregroundStyle(Theme.muted)
                } else {
                    Text("Tap the mic to talk").font(.headline)
                }
            }
            Spacer()
            Button {
                Task {
                    if listener.isListening {
                        await judge()
                    } else {
                        await startListening()
                    }
                }
            } label: {
                Image(systemName: listener.isListening ? "stop.fill" : "mic.fill")
                    .font(.title)
                    .foregroundStyle(.white)
                    .frame(width: 64, height: 64)
                    .background(Theme.accent, in: .circle)
            }
            .accessibilityLabel(listener.isListening ? "Done talking" : "Start talking")
        }
        .card(padding: 16)
    }

    private var instruction: String {
        switch challenge {
        case .hearAndRepeat: "Listen, then say it back"
        case .readAloud: "Read this sentence out loud"
        default: "Say it out loud"
        }
    }

    /// Characters only: no pinyin or English, which would give the answer away.
    @ViewBuilder
    private var prompt: some View {
        switch challenge {
        case .hearAndRepeat:
            VStack(spacing: 12) {
                Button {
                    Speaker.shared.say(word.text)
                } label: {
                    Image(systemName: "speaker.wave.3.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(Theme.accent)
                        .frame(width: 104, height: 104)
                        .background(Theme.chip, in: .circle)
                }
                .accessibilityLabel("Play the word again")
                if showText {
                    Text(word.text).font(.system(size: 56, weight: .medium))
                } else {
                    Button("Show the word") {
                        showText = true
                        usedHint = true
                    }
                    .buttonStyle(ChipButtonStyle())
                }
            }
        case .readAloud:
            Text(word.example?.text ?? word.text)
                .font(.system(size: 34, weight: .medium))
                .multilineTextAlignment(.center)
        default:
            Text(word.text).font(.system(size: 96, weight: .medium))
        }
    }

    /// Show hint reveals the word's picture.
    @ViewBuilder
    private var hint: some View {
        if challenge != .hearAndRepeat, WordPicture.exists(for: word) {
            if usedHint {
                WordPictureBubble(word: word)
            } else {
                Button {
                    usedHint = true
                } label: {
                    Label("Show hint", systemImage: "lightbulb")
                }
                .buttonStyle(ChipButtonStyle())
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
        onFinish(result.verdict == .pass, listener.transcript, result.score, usedHint)
    }
}
