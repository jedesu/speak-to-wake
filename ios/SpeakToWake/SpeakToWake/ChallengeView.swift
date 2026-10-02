import PinyinMatcher
import SwiftUI

/// Full-screen challenge opened by the alarm's Speak button. Only a pass gets
/// you out; a miss swaps in a different word.
struct ChallengeView: View {
    @State private var listener = LiveTranscriber()
    @State private var word = PracticeWord.forAlarm.randomElement()!
    @State private var message: String?

    private let locale = Locale(identifier: "zh-CN")

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Text("Say this to turn off the alarm")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text(word.hanzi).font(.system(size: 80))
            Text("\(word.pinyin) · \(word.english)")
                .font(.title3)
                .foregroundStyle(.secondary)

            if listener.isListening {
                Text(listener.transcript.isEmpty ? "Listening…" : listener.transcript)
                    .font(.title)
            } else if let message {
                Text(message)
                    .font(.headline)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
            if let error = listener.errorMessage {
                Text(error).foregroundStyle(.red)
            }

            Spacer()
            Button {
                Task {
                    if listener.isListening {
                        await judge()
                    } else {
                        message = nil
                        await listener.start(locale: locale, hints: word.hints)
                    }
                }
            } label: {
                Label(listener.isListening ? "Done" : "Start talking",
                      systemImage: listener.isListening ? "stop.circle.fill" : "mic.circle.fill")
                    .font(.title2)
                    .frame(maxWidth: .infinity, minHeight: 56)
            }
            .buttonStyle(.borderedProminent)
            .tint(listener.isListening ? .red : .orange)
        }
        .padding()
    }

    private func judge() async {
        await listener.stop()
        let heard = listener.transcript
        let result = Matcher.check(target: word.hanzi, transcript: heard)
        if result.verdict == .pass {
            AlarmController.shared.challengePassed()
        } else {
            message = "Not quite: it heard \(heard.isEmpty ? "nothing" : heard). Try this word instead."
            word = PracticeWord.forAlarm.filter { $0 != word }.randomElement() ?? word
        }
    }
}
