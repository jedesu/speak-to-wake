import SwiftData
import SwiftUI

/// Progress tab. Streak and accuracy come in piece 6; for now, simple counts.
struct ProgressTabView: View {
    @Query private var packs: [PackProgress]
    @Query private var reviews: [ReviewState]
    @Query private var attempts: [Attempt]

    var body: some View {
        NavigationStack {
            List {
                LabeledContent("Packs learned", value: "\(packs.filter { $0.learnedAt != nil }.count)")
                LabeledContent("Words in review", value: "\(reviews.count)")
                LabeledContent("Answers so far", value: "\(attempts.count)")
            }
            .navigationTitle("Progress")
            .settingsButton()
        }
    }
}
