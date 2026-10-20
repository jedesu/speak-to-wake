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

extension ReviewState {
    /// The saved record as a card the SRS rules can work with.
    var card: Card {
        Card(itemID: wordID, box: box, due: Day(due), timesCorrect: timesCorrect,
             timesMissed: timesMissed, lastReviewed: lastReviewed.map { Day($0) })
    }

    convenience init(_ card: Card) {
        self.init(wordID: card.itemID, box: card.box, due: card.due.startDate())
        update(from: card)
    }

    /// Saves the result of `SRS.learn` or `SRS.review` back into this record.
    func update(from card: Card) {
        box = card.box
        due = card.due.startDate()
        timesCorrect = card.timesCorrect
        timesMissed = card.timesMissed
        lastReviewed = card.lastReviewed?.startDate()
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

/// One of the user's alarms. Its id is also the system (AlarmKit) alarm's id.
@Model
final class AlarmConfig {
    @Attribute(.unique) var id: UUID
    var hour: Int
    var minute: Int
    /// Calendar weekdays, 1 = Sunday ... 7 = Saturday. Empty means ring once.
    var weekdays: [Int]
    var label: String
    var enabled: Bool
    /// When it's next due to ring; used to switch off one-time alarms after they ring.
    var nextRing: Date?
    var createdAt: Date

    init(hour: Int = 7, minute: Int = 0, weekdays: [Int] = [], label: String = "", enabled: Bool = true) {
        id = UUID()
        self.hour = hour
        self.minute = minute
        self.weekdays = weekdays
        self.label = label
        self.enabled = enabled
        createdAt = .now
    }

    var timeText: String {
        let date = Calendar.current.date(from: DateComponents(hour: hour, minute: minute)) ?? .now
        return date.formatted(date: .omitted, time: .shortened)
    }

    var daysText: String {
        let days = Set(weekdays)
        switch days {
        case []: return "Once"
        case Set(1...7): return "Every day"
        case [2, 3, 4, 5, 6]: return "Weekdays"
        case [1, 7]: return "Weekends"
        default:
            let symbols = Calendar.current.shortWeekdaySymbols
            return (1...7).filter(days.contains).map { symbols[$0 - 1] }.joined(separator: " ")
        }
    }

    /// The next time this alarm will ring, from `now`.
    func nextRingDate(after now: Date = .now, calendar: Calendar = .current) -> Date? {
        if weekdays.isEmpty {
            return calendar.nextDate(after: now, matching: DateComponents(hour: hour, minute: minute, second: 0),
                                     matchingPolicy: .nextTime)
        }
        return weekdays.compactMap { day in
            calendar.nextDate(after: now, matching: DateComponents(hour: hour, minute: minute, second: 0, weekday: day),
                              matchingPolicy: .nextTime)
        }.min()
    }
}
