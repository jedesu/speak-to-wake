import SwiftData
import SwiftUI
import WakeCore

/// Progress tab: simple counts as tiles. Streak and detailed stats come later.
struct ProgressTabView: View {
    @Query private var allPacks: [PackProgress]
    @Query private var allReviews: [ReviewState]
    @Query private var allAttempts: [Attempt]
    /// Progress is shown for the current language only.
    @AppStorage(AppSettings.Key.language) private var languageCode = "zh-CN"
    private var language: LanguageOption { LanguageOption.option(for: languageCode) }
    private var library: ContentLibrary { AppContent.library(for: languageCode) }
    private var packs: [PackProgress] { allPacks.forLanguage(language.id) }
    private var reviews: [ReviewState] { allReviews.forLanguage(language.id) }
    private var attempts: [Attempt] { allAttempts.forLanguage(language.id) }

    private var learnedSections: Int {
        packs.filter { p in p.learnedAt != nil && library.packs.contains { $0.id == p.packID } }.count
    }
    private var totalSections: Int { library.packs.count }
    private var accuracy: String {
        guard !attempts.isEmpty else { return "–" }
        return "\(Int((Double(attempts.count { $0.passed }) / Double(attempts.count) * 100).rounded()))%"
    }
    private var wakeUps: Int { attempts.filter { $0.context == "wake" && $0.passed }.count }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(language.flag) \(language.name) · \(language.levelRange(upTo: library.hskLevels.last?.level ?? 1))")
                            .font(.subheadline.bold())
                            .foregroundStyle(Theme.muted)
                        Text("Progress").font(.largeTitle.weight(.heavy))
                    }
                    .padding(.horizontal, 4)

                    VStack(alignment: .leading, spacing: 10) {
                        Text("\(learnedSections) of \(totalSections) sections learned").font(.headline)
                        ProgressView(value: Double(learnedSections), total: Double(max(totalSections, 1)))
                            .tint(Theme.accent)
                        Text("\(SRS.wordsLearned(reviews.map(\.card))) words you know well enough to keep")
                            .font(.subheadline)
                            .foregroundStyle(Theme.muted)
                    }
                    .card(padding: 20)

                    NavigationLink {
                        YourWordsView()
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: "character.book.closed.fill")
                                .font(.title2)
                                .foregroundStyle(.white)
                                .frame(width: 52, height: 52)
                                .background(Theme.accent, in: .rect(cornerRadius: 16))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Your words").font(.headline)
                                Text("\(reviews.count) words unlocked").font(.subheadline.bold()).foregroundStyle(Theme.muted)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(Theme.muted)
                        }
                        .padding(16)
                        .background(Theme.tip, in: .rect(cornerRadius: 24))
                    }
                    .buttonStyle(.plain)

                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible())], spacing: 14) {
                        tile("\(reviews.count)", "words in review", "rectangle.stack.fill")
                        tile("\(Learning.dueCount(reviews))", "due today", "calendar")
                        tile(accuracy, "answers right", "checkmark.circle.fill")
                        tile("\(wakeUps)", "correct wake-up answers", "sun.max.fill")
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 24)
            }
            .background(Theme.ground)
            .settingsButton()
        }
    }

    private func tile(_ value: String, _ label: String, _ icon: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon)
                .foregroundStyle(Theme.link)
                .frame(width: 40, height: 40)
                .background(Theme.chip, in: .rect(cornerRadius: 12))
            Text(value).font(.system(size: 34, weight: .heavy)).monospacedDigit()
            Text(label).font(.subheadline.bold()).foregroundStyle(Theme.muted)
        }
        .card(padding: 16)
    }
}
