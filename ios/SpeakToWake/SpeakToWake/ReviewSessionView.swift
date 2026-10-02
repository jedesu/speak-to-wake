import SwiftData
import SwiftUI
import WakeCore

/// Review: up to 10 of your due words. The first answer for each word moves it
/// in the review schedule; a miss brings the word back once more at the end.
struct ReviewSessionView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var reviews: [ReviewState]

    @State private var queue: [(quiz: Quiz, isRetry: Bool)] = []
    @State private var position = 0
    @State private var rightFirstTime = 0
    @State private var reviewedCount = 0

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ProgressView(value: Double(position), total: Double(max(queue.count, 1)))
                    .padding()
                if queue.isEmpty {
                    ContentUnavailableView("Nothing to review", systemImage: "checkmark.circle",
                                           description: Text("Learn a pack first."))
                } else if position < queue.count {
                    ScrollView {
                        QuizCard(quiz: queue[position].quiz) { correct, chosen in
                            answered(correct: correct, chosen: chosen)
                        }
                        .id(position)
                    }
                } else {
                    summary
                }
            }
            .navigationTitle("Review")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .onAppear(perform: start)
    }

    private func start() {
        guard queue.isEmpty else { return }
        let ids = SRS.pickForAlarm(reviews.map(\.card), today: .today, n: Learning.reviewSessionSize)
        queue = ids.compactMap { AppContent.library.word(id: $0) }.map { (Learning.quiz(for: $0), false) }
    }

    private func answered(correct: Bool, chosen: String) {
        let (quiz, isRetry) = queue[position]
        Learning.record(quiz, correct: correct, chosen: chosen, context: "review", retry: isRetry ? 1 : 0,
                        in: modelContext)
        if !isRetry {
            reviewedCount += 1
            if correct { rightFirstTime += 1 }
            if let state = reviews.first(where: { $0.wordID == quiz.target.id }) {
                state.update(from: SRS.review(state.card, correct ? .correct : .missed, today: .today))
            }
            if !correct {
                queue.append((Learning.quiz(for: quiz.target, avoiding: quiz.kind), true))
            }
        }
        position += 1
        try? modelContext.save()
    }

    private var summary: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "star.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(.yellow)
            Text("Review done").font(.largeTitle.bold())
            Text("\(rightFirstTime) of \(reviewedCount) right the first time.")
                .font(.title3)
            Text("Words you got right come back later. Missed words come back tomorrow.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                dismiss()
            } label: {
                Text("Done").font(.title3.bold()).frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}
