import SwiftData
import SwiftUI
import WakeCore

/// Learn tab: every pack, grouped by theme.
struct LearnView: View {
    private let library = AppContent.library
    @Query private var progress: [PackProgress]

    var body: some View {
        NavigationStack {
            List {
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

/// The words in one pack. Studying them comes in the Learn step (piece 3).
struct PackDetailView: View {
    let pack: Pack
    private let library = AppContent.library

    var body: some View {
        List {
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
