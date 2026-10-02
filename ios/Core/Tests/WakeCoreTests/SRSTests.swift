import Foundation
import Testing
@testable import WakeCore

// Same cases as prototype/test_srs.py.

private let d0 = Day(year: 2026, month: 10, day: 1)
private func day(_ n: Int) -> Day { d0 + n }

@Test func newWordStartsInBox1DueTomorrow() {
    let c = SRS.learn("apple", today: d0)
    #expect(c.box == 1 && c.due == day(1))
    #expect(!SRS.isDue(c, today: d0) && SRS.isDue(c, today: day(1)))
}

@Test func correctAnswersClimbBoxesWithGrowingGaps() {
    var c = SRS.learn("apple", today: d0)
    var gaps: [Int] = []
    for _ in 0..<7 {
        let today = c.due
        c = SRS.review(c, .correct, today: today)
        gaps.append(c.due - today)
    }
    #expect(gaps == [2, 4, 8, 16, 32, 32, 32])
    #expect(c.box == SRS.maxBox && SRS.maxBox == 6)
}

@Test func missDropsOneBoxAndReturnsNextDay() {
    let c = SRS.review(Card(itemID: "x", box: 4, due: d0), .missed, today: d0)
    #expect(c.box == 3 && c.due == day(1) && c.timesMissed == 1)
}

@Test func missInBox1StaysInBox1() {
    let c = SRS.review(SRS.learn("x", today: d0), .missed, today: day(1))
    #expect(c.box == 1 && c.due == day(2))
}

@Test func retryKeepsBox() {
    let c = SRS.review(Card(itemID: "x", box: 3, due: d0), .correctAfterRetry, today: d0)
    #expect(c.box == 3 && c.due == d0 + SRS.intervalDays[3]!)
}

@Test func earlyCorrectReviewDoesNotPromoteOrReschedule() {
    let c = SRS.review(Card(itemID: "x", box: 2, due: day(5)), .correct, today: day(2))
    #expect(c.box == 2 && c.due == day(5) && c.timesCorrect == 1)
}

@Test func earlyMissStillDrops() {
    let c = SRS.review(Card(itemID: "x", box: 3, due: day(5)), .missed, today: day(2))
    #expect(c.box == 2 && c.due == day(3))
}

@Test func lateReviewCountsFromTheReviewDay() {
    let c = SRS.review(Card(itemID: "x", box: 1, due: d0), .correct, today: day(3))
    #expect(c.due == day(3) + 2)
}

@Test func eveningLearningIsDueAtNextMorningAlarm() {
    // Date-based: the time of day never matters.
    let calendar = Calendar.current
    let evening = calendar.date(from: DateComponents(year: 2026, month: 10, day: 1, hour: 20))!
    let morning = calendar.date(from: DateComponents(year: 2026, month: 10, day: 2, hour: 7))!
    #expect(SRS.isDue(SRS.learn("x", today: Day(evening)), today: Day(morning)))
}

private func cardsExample() -> [Card] {
    [
        Card(itemID: "a", box: 1, due: day(0)),   // due, struggling
        Card(itemID: "b", box: 5, due: day(0)),   // due, well known
        Card(itemID: "c", box: 3, due: day(-2)),  // due, most overdue
        Card(itemID: "d", box: 2, due: day(3)),   // upcoming (soonest)
        Card(itemID: "e", box: 4, due: day(9)),   // upcoming (later)
    ]
}

@Test func alarmNormalPrefersMostOverdueThenWeakest() {
    #expect(SRS.pickForAlarm(cardsExample(), today: d0, n: 3) == ["c", "a", "b"])
}

@Test func alarmEasyPrefersWellKnownWords() {
    #expect(SRS.pickForAlarm(cardsExample(), today: d0, n: 3, difficulty: .easy) == ["b", "c", "a"])
}

@Test func alarmFillsWithUpcomingWordsWhenFewAreDue() {
    #expect(SRS.pickForAlarm(cardsExample(), today: d0, n: 5) == ["c", "a", "b", "d", "e"])
}

@Test func alarmNeverRepeatsAndHandlesEmptyOrSmallPools() {
    #expect(SRS.pickForAlarm([], today: d0, n: 3) == [])
    #expect(SRS.pickForAlarm(Array(cardsExample().prefix(2)), today: d0, n: 3) == ["a", "b"])
    let picked = SRS.pickForAlarm(cardsExample(), today: d0, n: 4)
    #expect(picked.count == 4 && Set(picked).count == 4)
}

@Test func missedWordIsBackAtTomorrowsAlarm() {
    let c = SRS.review(Card(itemID: "x", box: 5, due: d0), .missed, today: d0)
    #expect(SRS.pickForAlarm([c, Card(itemID: "y", box: 1, due: day(30))], today: day(1), n: 1) == ["x"])
}

@Test func dueCards() {
    #expect(Set(SRS.dueCards(cardsExample(), today: d0).map(\.itemID)) == ["a", "b", "c"])
}

@Test func masteryHelpers() {
    let cards = ["a": Card(itemID: "a", box: 5, due: d0),
                 "b": Card(itemID: "b", box: 4, due: d0),
                 "c": Card(itemID: "c", box: 2, due: d0)]
    #expect(SRS.isMastered(cards["a"]!) && !SRS.isMastered(cards["b"]!))
    #expect(SRS.packMastered(cards, packItemIDs: ["a", "b"]))
    #expect(!SRS.packMastered(cards, packItemIDs: ["a", "b", "c"]))
    #expect(!SRS.packMastered(cards, packItemIDs: ["a", "missing"]))
    #expect(!SRS.packMastered(cards, packItemIDs: []))
    #expect(SRS.wordsLearned(Array(cards.values)) == 3)
}

@Test func dayRoundTripsThroughDates() {
    let d = Day(year: 2026, month: 3, day: 8)  // US daylight saving starts
    #expect(Day(d.startDate()) == d)
    #expect(Day(year: 2026, month: 3, day: 9) - d == 1)
    #expect(d.description == "2026-03-08")
}
