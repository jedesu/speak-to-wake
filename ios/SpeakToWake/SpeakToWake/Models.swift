import Foundation
import SwiftData
import WakeCore

// The user's own data, saved on the phone with SwiftData. Word packs themselves
// are read-only content (see AppContent); these records point at them by id.

/// Set when the user finishes studying a pack. Only learned packs feed the alarm.
@Model
final class PackProgress {
    #Unique<PackProgress>([\.packID, \.language])

    var packID: String
    var language: String
    var learnedAt: Date?

    init(packID: String, language: String, learnedAt: Date? = nil) {
        self.packID = packID
        self.language = language
        self.learnedAt = learnedAt
    }
}

/// Spaced-repetition state for one word (Leitner box, see prototype/srs.py).
@Model
final class ReviewState {
    @Attribute(.unique) var wordID: String
    var box: Int
    /// A calendar day, stored as the start of that day: "due tomorrow", not "due at 8:14 pm".
    var due: Date
    var timesCorrect: Int
    var timesMissed: Int
    var lastReviewed: Date?

    init(wordID: String, box: Int, due: Date, timesCorrect: Int = 0, timesMissed: Int = 0, lastReviewed: Date? = nil) {
        self.wordID = wordID
        self.box = box
        self.due = due
        self.timesCorrect = timesCorrect
        self.timesMissed = timesMissed
        self.lastReviewed = lastReviewed
    }
}

/// One answer to one challenge. Exported as CSV for the Phase 5 test report.
@Model
final class Attempt {
    var date: Date
    var wordID: String
    var challengeType: String
    /// "wake" (from the alarm) or "practice" (Learn tab, midday tests).
    var context: String
    var passed: Bool
    var retryNumber: Int
    /// Speech challenges only.
    var transcript: String?
    var matchScore: Double?
    /// Tap challenges only.
    var chosenOption: String?
    /// The user's own verdict ("I said it right"), for measuring false rejects.
    var userSaidCorrect: Bool?

    init(date: Date = .now, wordID: String, challengeType: String, context: String, passed: Bool,
         retryNumber: Int = 0, transcript: String? = nil, matchScore: Double? = nil, chosenOption: String? = nil) {
        self.date = date
        self.wordID = wordID
        self.challengeType = challengeType
        self.context = context
        self.passed = passed
        self.retryNumber = retryNumber
        self.transcript = transcript
        self.matchScore = matchScore
        self.chosenOption = chosenOption
    }
}

/// The word packs bundled with the app (copied in from the repo's data/ folder).
enum AppContent {
    static let library: ContentLibrary = {
        do {
            return try ContentLibrary.load(language: "zh-CN")
        } catch {
            fatalError("Word data missing from the app bundle: \(error)")
        }
    }()
}
