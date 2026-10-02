import Foundation

/// Spaced repetition (Leitner boxes), ported from prototype/srs.py.
///
/// Plain-language rules:
/// * A word you've studied starts in Box 1 and is due the next calendar day.
/// * Each box has a gap before the next review: 1, 2, 4, 8, 16, 32 days.
/// * Right on the first try -> move up a box (longer gap).
/// * Right but only after a retry/hint/fallback -> stay in the same box.
/// * Wrong -> drop one box, and the word comes back the next day.
/// * Dates, not clock times: learn a word at 8 pm and it is due at tomorrow's 7 am alarm.
/// * Reviewing a word *before* it's due (the alarm filling its quota) never moves
///   it up, because early reviews don't earn the longer gap. A miss still drops it.
public enum SRS {
    public static let intervalDays = [1: 1, 2: 2, 3: 4, 4: 8, 5: 16, 6: 32]
    public static let maxBox = 6
    /// A word counts as "learned well" from this box up.
    public static let masteredBox = 5

    public enum Outcome: String, Codable, Sendable {
        case correct
        case correctAfterRetry = "correct_after_retry"
        case missed
    }

    public enum Difficulty: String, Codable, Sendable, CaseIterable {
        case normal, easy
    }

    /// Call when the user finishes studying a word in the Learn tab.
    public static func learn(_ itemID: String, today: Day) -> Card {
        Card(itemID: itemID, box: 1, due: today + intervalDays[1]!)
    }

    /// Returns the updated card after one review.
    public static func review(_ card: Card, _ outcome: Outcome, today: Day) -> Card {
        var card = card
        card.lastReviewed = today
        if outcome == .missed {
            card.box = max(1, card.box - 1)
            card.due = today + 1
            card.timesMissed += 1
            return card
        }
        card.timesCorrect += 1
        if today < card.due {
            // No spacing benefit from an early review: keep box and due date.
            return card
        }
        if outcome == .correct {
            card.box = min(maxBox, card.box + 1)
        }
        card.due = today + intervalDays[card.box]!
        return card
    }

    public static func isDue(_ card: Card, today: Day) -> Bool {
        card.due <= today
    }

    public static func dueCards(_ cards: [Card], today: Day) -> [Card] {
        cards.filter { isDue($0, today: today) }
    }

    /// Chooses up to `n` item ids for this morning's alarm (no repeats).
    ///
    /// Due words come first. normal: most overdue first, then lowest box (the
    /// words you struggle with). easy: highest box first (the words you know best),
    /// which suits a groggy brain. If fewer than `n` are due, the rest are filled
    /// with the soonest-upcoming words so the alarm always has something to ask.
    public static func pickForAlarm(_ cards: [Card], today: Day, n: Int, difficulty: Difficulty = .normal) -> [String] {
        var due = dueCards(cards, today: today)
        switch difficulty {
        case .easy:
            due.sort { (-$0.box, $0.due, $0.itemID) < (-$1.box, $1.due, $1.itemID) }
        case .normal:
            due.sort { ($0.due, $0.box, $0.itemID) < ($1.due, $1.box, $1.itemID) }
        }
        var chosen = due.prefix(n).map(\.itemID)
        if chosen.count < n {
            let upcoming = cards
                .filter { !isDue($0, today: today) }
                .sorted { ($0.due, $0.itemID) < ($1.due, $1.itemID) }
            chosen += upcoming.prefix(n - chosen.count).map(\.itemID)
        }
        return chosen
    }

    public static func isMastered(_ card: Card) -> Bool {
        card.box >= masteredBox
    }

    /// True when every word in the pack is learned and sits at `minBox`+.
    /// Used for the "master a pack, earn a pack token" rule.
    public static func packMastered(_ cardsByID: [String: Card], packItemIDs: [String], minBox: Int = 4) -> Bool {
        !packItemIDs.isEmpty && packItemIDs.allSatisfy { (cardsByID[$0]?.box ?? 0) >= minBox }
    }

    /// For the Progress screen: words you've studied and are not failing.
    public static func wordsLearned(_ cards: [Card]) -> Int {
        cards.count { $0.box >= 2 }
    }
}

public struct Card: Hashable, Codable, Sendable {
    public let itemID: String
    public var box: Int
    public var due: Day
    public var timesCorrect: Int
    public var timesMissed: Int
    public var lastReviewed: Day?

    public init(itemID: String, box: Int, due: Day, timesCorrect: Int = 0, timesMissed: Int = 0, lastReviewed: Day? = nil) {
        self.itemID = itemID
        self.box = box
        self.due = due
        self.timesCorrect = timesCorrect
        self.timesMissed = timesMissed
        self.lastReviewed = lastReviewed
    }
}

/// A calendar day with no time or time zone, so "due tomorrow" means the same
/// thing at 8 pm and at 7 am, across daylight-saving changes.
public struct Day: Hashable, Comparable, Codable, Sendable, CustomStringConvertible {
    /// Days since 1970-01-01.
    public let ordinal: Int

    private static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    public init(ordinal: Int) {
        self.ordinal = ordinal
    }

    public init(year: Int, month: Int, day: Int) {
        let date = Self.utc.date(from: DateComponents(year: year, month: month, day: day))!
        ordinal = Int((date.timeIntervalSince1970 / 86_400).rounded(.down))
    }

    /// The calendar day `date` falls on, in the user's own calendar and time zone.
    public init(_ date: Date, calendar: Calendar = .current) {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: parts.year!, month: parts.month!, day: parts.day!)
    }

    public static var today: Day { Day(.now) }

    /// Midnight at the start of this day in `calendar`, for storing as a Date.
    public func startDate(calendar: Calendar = .current) -> Date {
        let utcDate = Date(timeIntervalSince1970: Double(ordinal) * 86_400)
        let parts = Self.utc.dateComponents([.year, .month, .day], from: utcDate)
        return calendar.date(from: parts)!
    }

    public static func + (day: Day, days: Int) -> Day { Day(ordinal: day.ordinal + days) }
    public static func - (day: Day, days: Int) -> Day { Day(ordinal: day.ordinal - days) }
    public static func - (a: Day, b: Day) -> Int { a.ordinal - b.ordinal }
    public static func < (a: Day, b: Day) -> Bool { a.ordinal < b.ordinal }

    public var description: String {
        startDate(calendar: Self.utc).formatted(.iso8601.year().month().day())
    }
}
