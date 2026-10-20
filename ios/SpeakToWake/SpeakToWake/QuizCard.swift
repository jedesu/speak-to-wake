import SwiftUI
import WakeCore

/// Shows any tap quiz and reports the answer. Used by Learn practice, Review and
/// the wake-up challenge. Give each quiz its own `.id` so state resets.
///
/// Quizzes show characters only, never pinyin: pinyin would give the answer away.
/// Where it helps, a Show hint button reveals the word's picture.
struct QuizCard: View {
    let quiz: Quiz
    /// Called when the user taps Continue. `chosen` is what they picked, for the log.
    let onFinish: (_ correct: Bool, _ chosen: String, _ usedHint: Bool) -> Void

    private let maker = QuizMaker(library: AppContent.library)

    @State private var picked: Word?
    @State private var pickedBool: Bool?
    @State private var usedHint = false
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

    /// The picture hint, for quizzes that show the word and ask what it means.
    private var hintPicture: String? {
        switch quiz.kind {
        case .meaningToEnglish, .trueFalse: maker.emoji(quiz.target)
        default: nil
        }
    }

    var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 12) {
                Text(instruction)
                    .font(.caption.weight(.heavy))
                    .textCase(.uppercase)
                    .kerning(1)
                    .foregroundStyle(Theme.muted)
                prompt
                hint
            }
            .frame(maxWidth: .infinity, minHeight: 220)
            .card(padding: 24)

            answers

            if answered {
                feedback
                Button("Continue") {
                    onFinish(correct, chosenText, usedHint)
                }
                .buttonStyle(PrimaryButtonStyle())
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
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
            Text(target.text).font(.system(size: 72, weight: .medium))
        case .meaningToChinese(let target, _):
            Text(maker.english(target)).font(.largeTitle.bold()).multilineTextAlignment(.center)
        case .hearAndTap(let target, _):
            Button {
                Speaker.shared.say(target.text)
            } label: {
                Image(systemName: "speaker.wave.3.fill").font(.system(size: 56))
            }
            .accessibilityLabel("Play the word again")
        case .pictureMatch(_, let emoji, _):
            Text(emoji).font(.system(size: 100))
        case .trueFalse(let target, let shown, _):
            VStack(spacing: 6) {
                Text(target.text).font(.system(size: 64, weight: .medium))
                Text("means “\(shown)”").font(.title2.bold())
            }
        case .fillBlank(_, let sentence, let hint, _):
            VStack(spacing: 8) {
                Text(sentence).font(.largeTitle).multilineTextAlignment(.center)
                Text(hint).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
            }
        case .matchPairs:
            EmptyView()
        }
    }

    @ViewBuilder
    private var hint: some View {
        if let picture = hintPicture {
            if usedHint || answered {
                Text(picture)
                    .font(.system(size: 64))
                    .frame(width: 112, height: 112)
                    .background(Theme.chip, in: .circle)
                    .accessibilityLabel("Hint picture")
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
            Group {
                if quiz.kind == .meaningToEnglish {
                    Text(maker.english(option)).font(.title3.bold())
                } else {
                    Text(option.text).font(.title.weight(.medium))
                }
            }
            .frame(maxWidth: .infinity, minHeight: 60)
            .foregroundStyle(Theme.text)
            .background(fill(for: option), in: .rect(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(border(for: option), lineWidth: 2))
        }
        .buttonStyle(.plain)
        .allowsHitTesting(picked == nil)
    }

    private func fill(for option: Word) -> Color {
        guard let picked else { return Theme.card }
        if option == quiz.target { return Color.green.opacity(0.15) }
        if option == picked { return Color.red.opacity(0.12) }
        return Theme.card.opacity(0.6)
    }

    private func border(for option: Word) -> Color {
        guard let picked else { return Theme.toggleOff }
        if option == quiz.target { return .green }
        if option == picked { return .red }
        return .clear
    }

    private func trueFalseButton(_ value: Bool, isTrue: Bool) -> some View {
        let state: Color? = pickedBool == nil ? nil : value == isTrue ? .green : value == pickedBool ? .red : nil
        return Button {
            guard pickedBool == nil else { return }
            pickedBool = value
        } label: {
            Text(value ? "True" : "False")
                .font(.title2.bold())
                .frame(maxWidth: .infinity, minHeight: 64)
                .foregroundStyle(Theme.text)
                .background((state ?? Theme.card).opacity(state == nil ? 1 : 0.15), in: .rect(cornerRadius: 20))
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(state ?? Theme.toggleOff, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .allowsHitTesting(pickedBool == nil)
    }

    private func matchPairsGrid(words: [Word], meanings: [Word]) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 10) {
                ForEach(words) { word in
                    pairButton(id: word.id, selected: selectedLeft == word) {
                        Text(word.text).font(.title2.weight(.medium))
                    } action: {
                        selectedLeft = word
                        Speaker.shared.say(word.text)
                    }
                }
            }
            VStack(spacing: 10) {
                ForEach(meanings) { meaning in
                    pairButton(id: "meaning:" + meaning.id, selected: false) {
                        Text(maker.english(meaning)).font(.body.bold()).multilineTextAlignment(.center)
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
        let edge: Color = isMatched ? .green : selected ? Theme.accent : flashWrong == id ? .red : Theme.toggleOff
        return Button(action: action) {
            label()
                .padding(.horizontal, 6)
                .frame(maxWidth: .infinity, minHeight: 64)
                .foregroundStyle(Theme.text)
                .background(isMatched ? Color.green.opacity(0.15) : Theme.card, in: .rect(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(edge, lineWidth: 2))
        }
        .buttonStyle(.plain)
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
                .foregroundStyle(Theme.accent)
        } else {
            VStack(spacing: 4) {
                Label("Not quite", systemImage: "xmark.circle.fill")
                    .font(.title3.bold())
                    .foregroundStyle(.red)
                // After answering, show the pinyin too: now it teaches instead of giving it away.
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
