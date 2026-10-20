import SwiftData
import SwiftUI
import WakeCore

/// Progress tab: simple counts as tiles. Streak and detailed stats come later.
struct ProgressTabView: View {
    @Query private var packs: [PackProgress]
    @Query private var reviews: [ReviewState]
    @Query private var attempts: [Attempt]

    private var learnedSections: Int { packs.filter { $0.learnedAt != nil }.count }
    private var totalSections: Int { AppContent.library.packs.count }
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
                        Text("HSK 1").font(.subheadline.bold()).foregroundStyle(Theme.muted)
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
