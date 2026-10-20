import Foundation
import SwiftData
import WakeCore

/// Keeps the signed-in user's account copy and the phone's copy in step.
///
/// The phone is always the working copy (the alarm must work offline at 6 a.m.).
/// Sync merges the two: a learned section stays learned, each word keeps whichever
/// copy has been reviewed more, and new answers are uploaded once.
@Observable
final class SyncService {
    static let shared = SyncService()

    private(set) var lastSync: Date?
    private(set) var lastError: String?
    private var running = false

    func sync(_ context: ModelContext) async {
        let auth = AuthService.shared
        guard auth.isSignedIn, let userID = auth.userID, !running else { return }
        running = true
        defer { running = false }
        do {
            try await pull(context)
            try await push(context, userID: userID)
            try? context.save()
            lastSync = .now
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: Download and merge

    private struct RemotePack: Decodable { let pack_id: String; let language: String; let learned_at: String? }
    private struct RemoteReview: Decodable {
        let word_id: String; let box: Int; let due: String
        let times_correct: Int; let times_missed: Int; let last_reviewed: String?
    }

    private func pull(_ context: ModelContext) async throws {
        let auth = AuthService.shared
        let packs = try JSONDecoder().decode([RemotePack].self, from: try await auth.database("pack_progress?select=*"))
        let local = (try? context.fetch(FetchDescriptor<PackProgress>())) ?? []
        for remote in packs where remote.learned_at != nil {
            if !local.contains(where: { $0.packID == remote.pack_id && $0.language == remote.language && $0.learnedAt != nil }) {
                if let row = local.first(where: { $0.packID == remote.pack_id && $0.language == remote.language }) {
                    row.learnedAt = Self.instant(remote.learned_at) ?? .now
                } else {
                    context.insert(PackProgress(packID: remote.pack_id, language: remote.language,
                                                learnedAt: Self.instant(remote.learned_at) ?? .now))
                }
            }
        }

        let reviews = try JSONDecoder().decode([RemoteReview].self, from: try await auth.database("review_states?select=*"))
        let localReviews = (try? context.fetch(FetchDescriptor<ReviewState>())) ?? []
        for remote in reviews {
            guard let due = Self.day(remote.due) else { continue }
            let card = Card(itemID: remote.word_id, box: remote.box, due: due, timesCorrect: remote.times_correct,
                            timesMissed: remote.times_missed, lastReviewed: remote.last_reviewed.flatMap(Self.day))
            if let row = localReviews.first(where: { $0.wordID == remote.word_id }) {
                // Each review adds one to a count, so the copy with more reviews is newer.
                if remote.times_correct + remote.times_missed > row.timesCorrect + row.timesMissed {
                    row.update(from: card)
                }
            } else {
                context.insert(ReviewState(card))
            }
        }
    }

    // MARK: Upload

    private func push(_ context: ModelContext, userID: String) async throws {
        let auth = AuthService.shared
        let upsert = "resolution=merge-duplicates,return=minimal"

        let packs = ((try? context.fetch(FetchDescriptor<PackProgress>())) ?? []).filter { $0.learnedAt != nil }
        if !packs.isEmpty {
            let rows: [[String: Any]] = packs.map {
                ["user_id": userID, "pack_id": $0.packID, "language": $0.language,
                 "learned_at": Self.iso.string(from: $0.learnedAt!), "updated_at": Self.iso.string(from: .now)]
            }
            try await auth.database("pack_progress", method: "POST", body: try Self.json(rows), prefer: upsert)
        }

        let reviews = (try? context.fetch(FetchDescriptor<ReviewState>())) ?? []
        if !reviews.isEmpty {
            let rows: [[String: Any]] = reviews.map { r in
                let card = r.card
                return ["user_id": userID, "word_id": r.wordID, "box": r.box, "due": card.due.description,
                        "times_correct": r.timesCorrect, "times_missed": r.timesMissed,
                        "last_reviewed": card.lastReviewed?.description ?? NSNull(),
                        "updated_at": Self.iso.string(from: .now)]
            }
            try await auth.database("review_states", method: "POST", body: try Self.json(rows), prefer: upsert)
        }

        let attempts = ((try? context.fetch(FetchDescriptor<Attempt>())) ?? []).filter { !$0.uploaded }
        for batch in stride(from: 0, to: attempts.count, by: 200).map({ Array(attempts[$0..<min($0 + 200, attempts.count)]) }) {
            let rows: [[String: Any]] = batch.map { a in
                ["id": a.uuid.uuidString, "user_id": userID, "answered_at": Self.iso.string(from: a.date),
                 "word_id": a.wordID, "challenge_type": a.challengeType, "context": a.context, "passed": a.passed,
                 "retry_number": a.retryNumber, "transcript": a.transcript ?? NSNull(),
                 "match_score": a.matchScore ?? NSNull(), "chosen_option": a.chosenOption ?? NSNull(),
                 "user_said_correct": a.userSaidCorrect ?? NSNull()]
            }
            try await auth.database("attempts", method: "POST", body: try Self.json(rows), prefer: upsert)
            batch.forEach { $0.uploaded = true }
        }
    }

    // MARK: Helpers

    private static let iso = ISO8601DateFormatter()

    private static func json(_ rows: [[String: Any]]) throws -> Data {
        try JSONSerialization.data(withJSONObject: rows)
    }

    private static func instant(_ text: String?) -> Date? {
        guard let text else { return nil }
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return withFraction.date(from: text) ?? iso.date(from: text)
    }

    /// "2026-10-20" -> Day.
    private static func day(_ text: String) -> Day? {
        let parts = text.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return Day(year: parts[0], month: parts[1], day: parts[2])
    }
}
