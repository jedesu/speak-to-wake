import SwiftData
import SwiftUI
import WakeCore

/// Every word you've unlocked, by section: picture, characters, pinyin, meaning,
/// and how well you know it (its review level).
struct YourWordsView: View {
    @Query private var progress: [PackProgress]
    @Query private var reviews: [ReviewState]
    private let library = AppContent.library

    private var learnedPacks: [Pack] {
        let ids = Set(progress.filter { $0.learnedAt != nil }.map(\.packID))
        return library.packs.filter { ids.contains($0.id) }
            .sorted { ($0.hsk ?? 0, $0.order ?? 0) < ($1.hsk ?? 0, $1.order ?? 0) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if learnedPacks.isEmpty {
                    Text("Learn a section in the Learn tab and its words show up here.")
                        .foregroundStyle(Theme.muted)
                        .card(padding: 20)
                }
                ForEach(learnedPacks) { pack in
                    Text("HSK \(pack.hsk ?? 1) · \(pack.title)")
                        .font(.headline)
                        .foregroundStyle(Theme.muted)
                        .padding(.horizontal, 6)
                        .padding(.top, 6)
                    VStack(spacing: 0) {
                        ForEach(library.words(in: pack)) { word in
                            row(word)
                            if word != library.words(in: pack).last {
                                Rectangle().fill(Theme.toggleOff).frame(height: 1)
                            }
                        }
                    }
                    .card(padding: 14)
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 24)
        }
        .background(Theme.ground)
        .navigationTitle("Your words")
    }

    private func row(_ word: Word) -> some View {
        let box = reviews.first { $0.wordID == word.id }?.box ?? 0
        return HStack(spacing: 12) {
            Group {
                if WordPicture.exists(for: word) {
                    WordPicture(word: word, size: 28)
                } else {
                    Text(word.text.prefix(1)).font(.title3.weight(.medium)).foregroundStyle(Theme.accent)
                }
            }
            .frame(width: 44, height: 44)
            .background(Theme.chip, in: .rect(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(word.text).font(.title3.weight(.semibold))
                    Text(word.pinyin).font(.subheadline).foregroundStyle(Theme.link)
                }
                Text(library.concept(for: word)?.english ?? "").font(.subheadline).foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 0)
            // Review level as dots: more dots, better known.
            HStack(spacing: 3) {
                ForEach(1...5, id: \.self) { i in
                    Circle().fill(i <= box ? Theme.accent : Theme.toggleOff).frame(width: 6, height: 6)
                }
            }
            .accessibilityLabel("Level \(box) of 5")
        }
        .padding(.vertical, 8)
    }
}
