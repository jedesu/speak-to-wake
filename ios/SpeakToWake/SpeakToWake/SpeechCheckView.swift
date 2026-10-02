import PinyinMatcher
import SwiftUI

/// Phase 1 debug screen: is Mandarin speech recognition available on this phone?
struct SpeechCheckView: View {
    @State private var model = SpeechModelManager()
    @State private var listener = LiveTranscriber()
    @State private var target = targets[0]

    @State private var useHints = true

    struct Target: Hashable {
        let hanzi: String
        let pinyin: String
        let english: String
        /// Same sounds with other tones, so the recognizer hears the right syllable
        /// but still has to pick by tone.
        var toneNeighbors: [String] = []

        var hints: [String] { [hanzi] + toneNeighbors }
    }

    static let targets = [
        Target(hanzi: "苹果", pinyin: "píngguǒ", english: "apple"),
        Target(hanzi: "你好", pinyin: "nǐ hǎo", english: "hello"),
        Target(hanzi: "谢谢", pinyin: "xièxie", english: "thank you", toneNeighbors: ["写写"]),
        Target(hanzi: "老师", pinyin: "lǎoshī", english: "teacher", toneNeighbors: ["老是", "老实"]),
        Target(hanzi: "水", pinyin: "shuǐ", english: "water", toneNeighbors: ["睡", "谁"]),
        Target(hanzi: "买", pinyin: "mǎi", english: "buy", toneNeighbors: ["卖", "埋"]),
        Target(hanzi: "我是学生", pinyin: "wǒ shì xuéshēng", english: "I am a student"),
    ]

    /// What happened on the last attempt, shown after you tap Stop.
    enum Outcome {
        case correct(word: String, result: MatchResult)
        case wrong(word: String, heard: String, result: MatchResult)
    }
    @State private var outcome: Outcome?

    /// Re-checked every time the transcript changes, so the verdict updates as you talk.
    private var liveResult: MatchResult? {
        guard listener.isListening, !listener.transcript.isEmpty else { return nil }
        return Matcher.check(target: target.hanzi, transcript: listener.transcript)
    }

    /// Only a Pass counts. Near and Fail are both wrong, and you get a different word to say.
    private func stopAndJudge() async {
        await listener.stop()
        let heard = listener.transcript
        let result = Matcher.check(target: target.hanzi, transcript: heard)
        if result.verdict == .pass {
            outcome = .correct(word: target.hanzi, result: result)
        } else {
            outcome = .wrong(word: target.hanzi, heard: heard, result: result)
            target = Self.targets.filter { $0 != target }.randomElement() ?? target
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if model.state == .installed, let locale = model.matchedLocale {
                    Section {
                        Picker("Say this", selection: $target) {
                            ForEach(Self.targets, id: \.hanzi) { t in
                                Text("\(t.hanzi)  \(t.pinyin)").tag(t)
                            }
                        }
                        VStack(spacing: 4) {
                            Text(target.hanzi).font(.system(size: 56))
                            Text("\(target.pinyin) · \(target.english)").foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        if listener.isListening {
                            LabeledContent("Heard", value: listener.transcript.isEmpty ? "—" : listener.transcript)
                            if let liveResult {
                                resultRow(liveResult)
                            }
                        } else if let outcome {
                            outcomeRow(outcome)
                        }
                        if !listener.volatileText.isEmpty {
                            Text("Still guessing: \(listener.volatileText)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Button {
                            Task {
                                if listener.isListening {
                                    await stopAndJudge()
                                } else {
                                    outcome = nil
                                    await listener.start(locale: locale, hints: useHints ? target.hints : [])
                                }
                            }
                        } label: {
                            Label(listener.isListening ? "Stop" : "Start talking",
                                  systemImage: listener.isListening ? "stop.circle.fill" : "mic.circle.fill")
                                .font(.title2)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(listener.isListening ? .red : .accentColor)
                        if let error = listener.errorMessage {
                            Text(error).foregroundStyle(.red)
                        }
                        Toggle("Give the recognizer hints", isOn: $useHints)
                            .disabled(listener.isListening)
                        if useHints {
                            Text("Expecting: \(target.hints.joined(separator: " · "))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } header: {
                        Text("Try it")
                    }
                }

                Section("Mandarin (zh-CN)") {
                    statusRow
                    if let locale = model.matchedLocale {
                        LabeledContent("Matched locale", value: locale.identifier(.bcp47))
                    }
                    if model.state == .notInstalled {
                        Button("Download Mandarin model") {
                            Task { await model.download() }
                        }
                    }
                    if model.state == .downloading {
                        ProgressView(value: model.progress)
                    }
                }

                Section("Chinese locales on this phone") {
                    if model.chineseLocales.isEmpty {
                        Text("None found").foregroundStyle(.secondary)
                    }
                    ForEach(model.chineseLocales, id: \.self) { Text($0) }
                }

                Section {
                    LabeledContent("Languages supported", value: "\(model.supportedCount)")
                    Button("Check again") {
                        Task { await model.check() }
                    }
                }
            }
            .navigationTitle("Speech check")
            .task { await model.check() }
        }
    }

    @ViewBuilder
    private func outcomeRow(_ outcome: Outcome) -> some View {
        switch outcome {
        case .correct(let word, let result):
            VStack(alignment: .leading, spacing: 4) {
                Label("Correct! \(word)", systemImage: "checkmark.circle.fill")
                    .font(.title3.bold())
                    .foregroundStyle(.green)
                scoreLine(result)
            }
        case .wrong(let word, let heard, let result):
            VStack(alignment: .leading, spacing: 4) {
                Label("Wrong. Try this word instead.", systemImage: "xmark.circle.fill")
                    .font(.title3.bold())
                    .foregroundStyle(.red)
                Text("You were asked for \(word) and it heard \(heard.isEmpty ? "nothing" : heard).")
                scoreLine(result)
            }
        }
    }

    private func scoreLine(_ result: MatchResult) -> some View {
        Text("\(result.verdict.rawValue) · score \(result.score, format: .number.precision(.fractionLength(2))) · heard as \(result.heardPinyin.joined(separator: " "))")
            .font(.caption.monospaced())
            .foregroundStyle(.secondary)
    }

    private func resultRow(_ result: MatchResult) -> some View {
        let (label, icon, color): (String, String, Color) = switch result.verdict {
        case .pass: ("Pass", "checkmark.circle.fill", .green)
        case .near: ("Near", "circle.lefthalf.filled", .orange)
        case .fail: ("Fail", "xmark.circle.fill", .red)
        }
        return VStack(alignment: .leading, spacing: 4) {
            Label("\(label)  ·  score \(result.score, format: .number.precision(.fractionLength(2)))",
                  systemImage: icon)
                .font(.title3.bold())
                .foregroundStyle(color)
            Text("Heard as: \(result.heardPinyin.joined(separator: " "))")
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var statusRow: some View {
        switch model.state {
        case .checking:
            Label("Checking…", systemImage: "hourglass")
        case .unsupported:
            Label("Not supported on this phone", systemImage: "xmark.circle.fill")
                .foregroundStyle(.red)
        case .notInstalled:
            Label("Supported, model not downloaded", systemImage: "arrow.down.circle")
                .foregroundStyle(.orange)
        case .downloading:
            Label("Downloading…", systemImage: "arrow.down.circle")
        case .installed:
            Label("Ready", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
        }
    }
}

#Preview {
    SpeechCheckView()
}
