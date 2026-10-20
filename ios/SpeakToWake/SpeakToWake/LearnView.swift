import SwiftData
import SwiftUI
import WakeCore

/// Learn tab: overall progress, Review, and the sections, browsed either by
/// HSK level or by topic (Food & drink, Places & travel...).
struct LearnView: View {
    private enum Mode: String, CaseIterable {
        case levels = "HSK levels"
        case topics = "Topics"
    }

    private let library = AppContent.library
    @Query private var progress: [PackProgress]
    @Query private var reviews: [ReviewState]
    @State private var reviewing = false
    @AppStorage(AppSettings.Key.learnMode) private var mode = Mode.levels
    @AppStorage(AppSettings.Key.proUnlocked) private var proUnlocked = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header
                    if !reviews.isEmpty { reviewCard }
                    Picker("Browse", selection: $mode) {
                        ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .padding(.vertical, 4)

                    switch mode {
                    case .levels:
                        ForEach(library.hskLevels, id: \.level) { group in
                            groupHeader("HSK \(group.level)", packs: group.packs, isPro: group.level > 1)
                            sectionCards(group.packs, showLevel: false)
                        }
                    case .topics:
                        ForEach(library.topics) { topic in
                            let packs = library.packs(in: topic)
                            groupHeader(topic.title, packs: packs, isPro: false)
                            sectionCards(packs, showLevel: true)
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 24)
            }
            .background(Theme.ground)
            .navigationDestination(for: Pack.self) { pack in
                PackDetailView(pack: pack)
            }
            .settingsButton()
            .fullScreenCover(isPresented: $reviewing) {
                ReviewSessionView()
            }
        }
    }

    private var header: some View {
        let learned = library.packs.filter(isLearned).count
        return VStack(alignment: .leading, spacing: 10) {
            Text("Mandarin · HSK 1–\(library.hskLevels.last?.level ?? 1)")
                .font(.subheadline.bold())
                .foregroundStyle(Theme.muted)
            Text("Learn")
                .font(.largeTitle.weight(.heavy))
            ProgressView(value: Double(learned), total: Double(max(library.packs.count, 1)))
                .tint(Theme.accent)
            Text("\(learned) of \(library.packs.count) sections · \(library.words.count) words")
                .font(.subheadline.bold())
                .foregroundStyle(Theme.muted)
        }
        .padding(.horizontal, 4)
    }

    private func groupHeader(_ title: String, packs: [Pack], isPro: Bool) -> some View {
        let words = packs.reduce(0) { $0 + library.words(in: $1).count }
        let learned = packs.filter(isLearned).count
        return HStack(alignment: .firstTextBaseline) {
            Text(title).font(.title2.weight(.heavy))
            if isPro {
                Text("PRO")
                    .font(.caption2.weight(.heavy))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Theme.accent, in: .capsule)
            }
            Spacer()
            Text("\(learned)/\(packs.count) · \(words) words")
                .font(.subheadline.bold())
                .foregroundStyle(Theme.muted)
        }
        .padding(.horizontal, 4)
        .padding(.top, 10)
    }

    private func sectionCards(_ packs: [Pack], showLevel: Bool) -> some View {
        ForEach(packs) { pack in
            NavigationLink(value: pack) {
                SectionCard(pack: pack, learned: isLearned(pack), locked: !AppSettings.canOpen(pack) && !proUnlocked,
                            showLevel: showLevel)
            }
            .buttonStyle(.plain)
        }
    }

    private var reviewCard: some View {
        let due = Learning.dueCount(reviews)
        return Button {
            reviewing = true
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.title2.bold())
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(Theme.accent, in: .rect(cornerRadius: 16))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Review").font(.headline)
                    Text(due == 0 ? "Nothing due today. You can review early."
                                  : "\(due) \(due == 1 ? "word" : "words") due today")
                        .font(.subheadline.bold())
                        .foregroundStyle(due > Learning.overdueLimit ? Theme.accent : Theme.muted)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(Theme.muted)
            }
            .padding(16)
            .background(Theme.tip, in: .rect(cornerRadius: 24))
        }
        .buttonStyle(.plain)
    }

    private func isLearned(_ pack: Pack) -> Bool {
        progress.contains { $0.packID == pack.id && $0.language == library.language && $0.learnedAt != nil }
    }
}

/// One section: picture tile, number and title, first few words, status.
private struct SectionCard: View {
    let pack: Pack
    let learned: Bool
    let locked: Bool
    /// In the Topics view, say which level the section is from.
    var showLevel = false

    private var words: [Word] { AppContent.library.words(in: pack) }

    var body: some View {
        HStack(spacing: 14) {
            Group {
                if let pictured = words.first(where: WordPicture.exists) {
                    WordPicture(word: pictured, size: 38)
                } else {
                    Image(systemName: "character.book.closed.fill").font(.title2).foregroundStyle(Theme.accent)
                }
            }
            .frame(width: 58, height: 58)
            .background(Theme.chip, in: .rect(cornerRadius: 18))
            .opacity(locked ? 0.5 : 1)

            VStack(alignment: .leading, spacing: 3) {
                if showLevel {
                    Text("HSK \(pack.hsk ?? 1)")
                        .font(.caption.weight(.heavy))
                        .foregroundStyle(Theme.link)
                }
                Text(showLevel ? pack.title : pack.order.map { "\($0). \(pack.title)" } ?? pack.title)
                    .font(.headline)
                Text("\(words.count) words · \(words.prefix(3).map(\.text).joined(separator: " "))")
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if learned {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(Theme.accent)
                    .accessibilityLabel("Learned")
            } else if locked {
                Image(systemName: "lock.fill").foregroundStyle(Theme.muted).accessibilityLabel("Pro")
            } else {
                Image(systemName: "chevron.right").foregroundStyle(Theme.muted)
            }
        }
        .card(padding: 14)
    }
}

/// The words in one section, and the buttons to study them.
struct PackDetailView: View {
    let pack: Pack
    private let library = AppContent.library

    @Query private var progress: [PackProgress]
    @Query private var reviews: [ReviewState]
    @State private var studying = false
    @State private var quizzing = false
    @State private var signingIn = false
    private var auth = AuthService.shared

    private var needsSignIn: Bool {
        _ = auth.isSignedIn  // re-check when sign-in changes
        let learnedIDs = Set(progress.filter { $0.learnedAt != nil }.map(\.packID))
        return Learning.needsSignIn(toStudy: pack, learnedPackIDs: learnedIDs)
    }

    private var learned: Bool {
        progress.contains { $0.packID == pack.id && $0.language == library.language && $0.learnedAt != nil }
    }

    @AppStorage(AppSettings.Key.proUnlocked) private var proUnlocked = false

    /// Why studying is blocked, if it is.
    private var blockedReason: String? {
        if !AppSettings.canOpen(pack) && !proUnlocked {
            return "HSK \(pack.hsk ?? 2) is part of Mingo Pro, which isn't available yet."
        }
        let due = Learning.dueCount(reviews)
        if !learned && due > Learning.overdueLimit {
            return "You have \(due) words due. Do a Review first, so old words don't pile up."
        }
        return nil
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                actions
                ForEach(library.words(in: pack)) { word in
                    WordCard(word: word)
                }
                Text("A syllable with no tone mark is a neutral tone: say it short and light, like the second ma in māma.")
                    .font(.footnote)
                    .foregroundStyle(Theme.muted)
                    .padding(.horizontal, 6)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 24)
        }
        .background(Theme.ground)
        .navigationTitle(pack.order.map { "\($0). \(pack.title)" } ?? pack.title)
        .fullScreenCover(isPresented: $studying) {
            StudySessionView(pack: pack, flipMode: learned)
        }
        .fullScreenCover(isPresented: $quizzing) {
            StudySessionView(pack: pack, startWithQuiz: true)
        }
        .sheet(isPresented: $signingIn) {
            SignInView()
        }
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("HSK \(pack.hsk ?? 1) · \(library.words(in: pack).count) words")
                        .font(.subheadline.bold())
                        .foregroundStyle(Theme.muted)
                    Text(learned ? "Learned" : "Not learned yet")
                        .font(.title3.weight(.heavy))
                }
                Spacer()
                if learned {
                    Image(systemName: "checkmark.seal.fill").font(.largeTitle).foregroundStyle(Theme.accent)
                }
            }
            if learned {
                // Already learned: quiz straight away, no need to click through the cards.
                Button { quizzing = true } label: { Label("Quiz me", systemImage: "checklist") }
                    .buttonStyle(PrimaryButtonStyle())
                Button { studying = true } label: { Label("Flashcards", systemImage: "rectangle.on.rectangle") }
                    .buttonStyle(ChipButtonStyle())
                    .frame(maxWidth: .infinity)
            } else if needsSignIn && blockedReason == nil {
                Button { signingIn = true } label: { Label("Sign in to keep learning", systemImage: "person.crop.circle") }
                    .buttonStyle(PrimaryButtonStyle())
                Text("Your first section was free. Sign in to save your progress and learn more.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)
            } else {
                Button { studying = true } label: { Label("Start learning", systemImage: "play.fill") }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(blockedReason != nil)
                    .opacity(blockedReason == nil ? 1 : 0.4)
            }
            if let blockedReason {
                Label(blockedReason, systemImage: "lock.fill")
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)
            }
        }
        .card(padding: 20)
    }
}

/// One word in the section list: picture, characters, pinyin, meaning, example.
private struct WordCard: View {
    let word: Word

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Group {
                if WordPicture.exists(for: word) {
                    WordPicture(word: word, size: 36)
                } else {
                    Text(word.text.prefix(1)).font(.title2.weight(.medium)).foregroundStyle(Theme.accent)
                }
            }
            .frame(width: 54, height: 54)
            .background(Theme.chip, in: .rect(cornerRadius: 16))

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(word.text).font(.title2.weight(.semibold))
                    Text(word.pinyin).foregroundStyle(Theme.muted)
                }
                Text(AppContent.library.concept(for: word)?.english ?? "")
                    .font(.subheadline.bold())
                if let example = word.example {
                    Text("\(example.text)  \(example.english)")
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                }
            }
            Spacer(minLength: 0)
            Button {
                Speaker.shared.say(word.text)
            } label: {
                Image(systemName: "speaker.wave.2.fill")
                    .foregroundStyle(Theme.link)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Play \(word.text)")
        }
        .card(padding: 14)
    }
}
