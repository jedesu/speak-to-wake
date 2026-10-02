import SwiftUI
import WakeCore

/// Shows any tap quiz and reports the answer. Used by Learn practice, Review and
/// (later) the alarm challenge. Give each quiz its own `.id` so state resets.
struct QuizCard: View {
    let quiz: Quiz
    /// Called when the user taps Continue. `chosen` is what they picked, for the log.
    let onFinish: (_ correct: Bool, _ chosen: String) -> Void

    private let maker = QuizMaker(library: AppContent.library)

    @State private var picked: Word?
    @State private var pickedBool: Bool?
    // Match pairs
    @State private var selectedLeft: Word?
    @State private var matched: Set<String> = []
    @State private var mistakes = 0
    @State private var flashWrong: String?

    private var answered: Bool {
        switch quiz {
        case .trueFalse: pickedBool != nil
        // `matched` holds both sides of each pair (word id and "meaning:" id).
        case .matchPairs(_, let words, _): matched.count == words.count * 2
        default: picked != nil
        }
    }

    private var correct: Bool {
        switch quiz {
        case .trueFalse(_, _, let isTrue): pickedBool == isTrue
        case .matchPairs: mistakes == 0
        default: picked == quiz.target
        }
    }

    var body: some View {
        VStack(spacing: 20) {
            Text(instruction)
                .font(.headline)
                .foregroundStyle(.secondary)
            prompt
                .frame(maxWidth: .infinity, minHeight: 140)
            answers
            if answered {
                feedback
                Button {
                    onFinish(correct, chosenText)
                } label: {
                    Text("Continue").font(.title3.bold()).frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(correct ? .green : .orange)
            }
        }
        .padding()
        .onAppear {
            if case .hearAndTap(let target, _) = quiz {
                Speaker.shared.say(target.text)
            }
        }
    }

    // MARK: Prompt

    private var instruction: String {
        switch quiz.kind {
        case .meaningToEnglish: "What does this mean?"
        case .meaningToChinese: "Which word means this?"
        case .hearAndTap: "Tap the word you hear"
        case .pictureMatch: "Which word is this?"
        case .trueFalse: "True or false?"
        case .fillBlank: "Fill in the blank"
        case .matchPairs: "Match each word to its meaning"
        }
    }

    @ViewBuilder
    private var prompt: some View {
        switch quiz {
        case .meaningToEnglish(let target, _):
            VStack(spacing: 6) {
                Text(target.text).font(.system(size: 64))
                HStack {
                    Text(target.pinyin).font(.title3).foregroundStyle(.secondary)
                    speakButton(target.text)
                }
            }
        case .meaningToChinese(let target, _):
            Text(maker.english(target)).font(.largeTitle.bold()).multilineTextAlignment(.center)
        case .hearAndTap(let target, _):
            Button {
                Speaker.shared.say(target.text)
            } label: {
                Image(systemName: "speaker.wave.3.fill").font(.system(size: 64))
            }
            .accessibilityLabel("Play the word again")
        case .pictureMatch(_, let emoji, _):
            Text(emoji).font(.system(size: 110))
        case .trueFalse(let target, let shown, _):
            VStack(spacing: 8) {
                Text(target.text).font(.system(size: 56))
                Text(target.pinyin).foregroundStyle(.secondary)
                Text("means “\(shown)”").font(.title2)
            }
        case .fillBlank(_, let sentence, let hint, _):
            VStack(spacing: 8) {
                Text(sentence).font(.largeTitle).multilineTextAlignment(.center)
                Text(hint).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
        case .matchPairs:
            EmptyView()
        }
    }

    private func speakButton(_ text: String) -> some View {
        Button {
            Speaker.shared.say(text)
        } label: {
            Image(systemName: "speaker.wave.2.fill")
        }
        .accessibilityLabel("Play pronunciation")
    }

    // MARK: Answers

    @ViewBuilder
    private var answers: some View {
        switch quiz {
        case .trueFalse(_, _, let isTrue):
            HStack(spacing: 12) {
                trueFalseButton(true, isTrue: isTrue)
                trueFalseButton(false, isTrue: isTrue)
            }
        case .matchPairs(_, let words, let meanings):
            matchPairsGrid(words: words, meanings: meanings)
        default:
            VStack(spacing: 10) {
                ForEach(quiz.options) { option in
                    optionButton(option)
                }
            }
        }
    }

    private func optionButton(_ option: Word) -> some View {
        Button {
            guard picked == nil else { return }
            picked = option
            if quiz.kind != .meaningToEnglish { Speaker.shared.say(option.text) }
        } label: {
            optionLabel(option)
                .frame(maxWidth: .infinity, minHeight: 56)
        }
        .buttonStyle(.bordered)
        .tint(tint(for: option))
        .allowsHitTesting(picked == nil)
    }

    @ViewBuilder
    private func optionLabel(_ option: Word) -> some View {
        if quiz.kind == .meaningToEnglish {
            Text(maker.english(option)).font(.title3)
        } else {
            VStack(spacing: 2) {
                Text(option.text).font(.title2)
                Text(option.pinyin).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func tint(for option: Word) -> Color {
        guard let picked else { return .primary }
        if option == quiz.target { return .green }
        if option == picked { return .red }
        return .secondary
    }

    private func trueFalseButton(_ value: Bool, isTrue: Bool) -> some View {
        Button {
            guard pickedBool == nil else { return }
            pickedBool = value
        } label: {
            Text(value ? "True" : "False").font(.title2.bold()).frame(maxWidth: .infinity, minHeight: 64)
        }
        .buttonStyle(.bordered)
        .tint(pickedBool == nil ? .primary : value == isTrue ? .green : value == pickedBool ? .red : .secondary)
        .allowsHitTesting(pickedBool == nil)
    }

    private func matchPairsGrid(words: [Word], meanings: [Word]) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 10) {
                ForEach(words) { word in
                    pairButton(id: word.id, selected: selectedLeft == word) {
                        VStack(spacing: 2) {
                            Text(word.text).font(.title2)
                            Text(word.pinyin).font(.caption).foregroundStyle(.secondary)
                        }
                    } action: {
                        selectedLeft = word
                        Speaker.shared.say(word.text)
                    }
                }
            }
            VStack(spacing: 10) {
                ForEach(meanings) { meaning in
                    pairButton(id: "meaning:" + meaning.id, selected: false) {
                        Text(maker.english(meaning)).font(.body)
                    } action: {
                        guard let left = selectedLeft else { return }
                        if left == meaning {
                            matched.formUnion([left.id, "meaning:" + meaning.id])
                        } else {
                            mistakes += 1
                            flashWrong = "meaning:" + meaning.id
                        }
                        selectedLeft = nil
                    }
                }
            }
        }
    }

    private func pairButton<Label: View>(id: String, selected: Bool, @ViewBuilder label: () -> Label,
                                         action: @escaping () -> Void) -> some View {
        let isMatched = matched.contains(id)
        return Button(action: action) {
            label().frame(maxWidth: .infinity, minHeight: 60)
        }
        .buttonStyle(.bordered)
        .tint(isMatched ? .green : selected ? .accentColor : flashWrong == id ? .red : .primary)
        // Not .disabled: that turns the button grey and hides the green.
        .allowsHitTesting(!isMatched)
    }

    // MARK: Feedback

    @ViewBuilder
    private var feedback: some View {
        if correct {
            Label("Correct!", systemImage: "checkmark.circle.fill")
                .font(.title3.bold())
                .foregroundStyle(.green)
        } else if case .matchPairs = quiz {
            Label("\(mistakes) wrong \(mistakes == 1 ? "match" : "matches")", systemImage: "xmark.circle.fill")
                .font(.title3.bold())
                .foregroundStyle(.orange)
        } else {
            VStack(spacing: 4) {
                Label("Not quite", systemImage: "xmark.circle.fill")
                    .font(.title3.bold())
                    .foregroundStyle(.red)
                Text("\(quiz.target.text) (\(quiz.target.pinyin)) means “\(maker.english(quiz.target))”")
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var chosenText: String {
        switch quiz {
        case .trueFalse: pickedBool.map { $0 ? "true" : "false" } ?? ""
        case .matchPairs: "\(mistakes) mistakes"
        default: picked?.text ?? ""
        }
    }
}
