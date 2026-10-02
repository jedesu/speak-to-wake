import SwiftData
import SwiftUI
import WakeCore

/// Learn tab: every pack, grouped by theme.
struct LearnView: View {
    private let library = AppContent.library
    @Query private var progress: [PackProgress]
    @Query private var reviews: [ReviewState]
    @State private var reviewing = false

    var body: some View {
        NavigationStack {
            List {
                if !reviews.isEmpty {
                    Section {
                        let due = Learning.dueCount(reviews)
                        Button {
                            reviewing = true
                        } label: {
                            HStack {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .font(.title2)
                                VStack(alignment: .leading) {
                                    Text("Review").font(.headline)
                                    Text(due == 0 ? "Nothing due today. You can review early."
                                                  : "\(due) \(due == 1 ? "word" : "words") due today")
                                        .font(.subheadline)
                                        .foregroundStyle(due > Learning.overdueLimit ? .red : .secondary)
                                }
                            }
                        }
                    }
                }
                ForEach(library.themes, id: \.theme) { group in
                    Section(group.theme.capitalized) {
                        ForEach(group.packs) { pack in
                            NavigationLink(value: pack) {
                                PackRow(pack: pack, learned: isLearned(pack))
                            }
                        }
                    }
                }
            }
            .navigationTitle("Learn")
            .navigationDestination(for: Pack.self) { pack in
                PackDetailView(pack: pack)
            }
            .settingsButton()
            .fullScreenCover(isPresented: $reviewing) {
                ReviewSessionView()
            }
        }
    }

    private func isLearned(_ pack: Pack) -> Bool {
        progress.contains { $0.packID == pack.id && $0.language == library.language && $0.learnedAt != nil }
    }
}

private struct PackRow: View {
    let pack: Pack
    let learned: Bool

    private var words: [Word] { AppContent.library.words(in: pack) }

    var body: some View {
        HStack(spacing: 12) {
            Text(words.first.flatMap { AppContent.library.concept(for: $0)?.emoji } ?? "📦")
                .font(.largeTitle)
            VStack(alignment: .leading, spacing: 2) {
                Text(pack.title).font(.headline)
                Text("\(words.count) words · \(words.prefix(3).map(\.text).joined(separator: " "))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if learned {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            } else if pack.tier == .premium {
                Image(systemName: "lock.fill").foregroundStyle(.secondary)
            }
        }
    }
}

/// The words in one pack, and the button to study them.
struct PackDetailView: View {
    let pack: Pack
    private let library = AppContent.library

    @Query private var progress: [PackProgress]
    @Query private var reviews: [ReviewState]
    @State private var studying = false
    @State private var quizzing = false

    private var learned: Bool {
        progress.contains { $0.packID == pack.id && $0.language == library.language && $0.learnedAt != nil }
    }

    /// Why studying is blocked, if it is.
    private var blockedReason: String? {
        if pack.tier == .premium {
            return "This is a Premium pack. Unlocking packs comes later."
        }
        let due = Learning.dueCount(reviews)
        if !learned && due > Learning.overdueLimit {
            return "You have \(due) words due. Do a Review first, so old words don't pile up."
        }
        return nil
    }

    var body: some View {
        List {
            Section {
                if learned {
                    // Already learned: quiz straight away, no need to click through the cards.
                    Button {
                        quizzing = true
                    } label: {
                        Label("Quiz me", systemImage: "checklist")
                            .font(.title3.bold())
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
                Button {
                    studying = true
                } label: {
                    Label(learned ? "Flashcards" : "Start learning", systemImage: learned ? "rectangle.on.rectangle" : "play.fill")
                        .font(.title3.bold())
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(learned ? AnyPrimitiveButtonStyle(.bordered) : AnyPrimitiveButtonStyle(.borderedProminent))
                .disabled(blockedReason != nil)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
                if let blockedReason {
                    Label(blockedReason, systemImage: "lock.fill")
                        .foregroundStyle(.secondary)
                }
                if learned {
                    Label("Learned. These words are in your reviews and alarm.", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }
            Section {
                ForEach(library.words(in: pack)) { word in
                    WordRow(word: word)
                }
            } footer: {
                VStack(alignment: .leading, spacing: 8) {
                    Text("A syllable with no tone mark is a neutral tone: say it short and light, like the second ma in māma.")
                    if pack.tier == .premium {
                        Label("Premium pack", systemImage: "lock.fill")
                    }
                }
            }
        }
        .navigationTitle(pack.title)
        .fullScreenCover(isPresented: $studying) {
            StudySessionView(pack: pack, flipMode: learned)
        }
        .fullScreenCover(isPresented: $quizzing) {
            StudySessionView(pack: pack, startWithQuiz: true)
        }
    }
}

private struct WordRow: View {
    let word: Word

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(AppContent.library.concept(for: word)?.emoji ?? "")
                .font(.title)
                .frame(width: 40)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(word.text).font(.title2)
                    Text(word.pinyin).foregroundStyle(.secondary)
                }
                Text(AppContent.library.concept(for: word)?.english ?? "")
                if let example = word.example {
                    Text("\(example.text)  \(example.english)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

/// Lets one button switch between bordered and prominent styles.
struct AnyPrimitiveButtonStyle: PrimitiveButtonStyle {
    private let make: (Configuration) -> AnyView

    init<S: PrimitiveButtonStyle>(_ style: S) {
        make = { AnyView(style.makeBody(configuration: $0)) }
    }

    func makeBody(configuration: Configuration) -> some View {
        make(configuration)
    }
}
