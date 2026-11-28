import Foundation
import Testing
@testable import WakeCore

private let today = Day(year: 2026, month: 12, day: 1)

private func days(_ offsets: ClosedRange<Int>) -> Set<Day> {
    Set(offsets.map { today - $0 })
}

@Test func levelOneIsFreeAndHigherLevelsNeedProOrAToken() {
    let free = library.hskLevels[0].packs[0]
    let pro = library.hskLevels[1].packs[0]
    #expect(FreePlan.canOpen(free, isPro: false, unlockedPackIDs: []))
    #expect(!FreePlan.canOpen(pro, isPro: false, unlockedPackIDs: []))
    #expect(FreePlan.canOpen(pro, isPro: true, unlockedPackIDs: []))
    #expect(FreePlan.canOpen(pro, isPro: false, unlockedPackIDs: [pro.id]))
}

@Test func sevenWakeUpsInARowEarnOneToken() {
    #expect(FreePlan.tokensEarned(wakeDays: days(0...5)) == 0)
    #expect(FreePlan.tokensEarned(wakeDays: days(0...6)) == 1)
    #expect(FreePlan.tokensEarned(wakeDays: days(0...14)) == 2)
}

@Test func aMissedDayStartsOver() {
    // 4 days, a gap, then 4 more: no token yet.
    var wake = days(0...3)
    wake.formUnion(days(5...8))
    #expect(FreePlan.tokensEarned(wakeDays: wake) == 0)
    #expect(FreePlan.currentStreak(wakeDays: wake, today: today) == 4)
}

@Test func spentTokensAreSubtracted() {
    #expect(FreePlan.tokensLeft(wakeDays: days(0...13), unlockedPackIDs: ["a"]) == 1)
    #expect(FreePlan.tokensLeft(wakeDays: days(0...6), unlockedPackIDs: ["a", "b"]) == 0)
}

@Test func streakCountsFromYesterdayUntilTodaysAlarmIsDone() {
    #expect(FreePlan.currentStreak(wakeDays: days(1...3), today: today) == 3)
    #expect(FreePlan.currentStreak(wakeDays: days(0...3), today: today) == 4)
    #expect(FreePlan.currentStreak(wakeDays: days(2...3), today: today) == 0)
    #expect(FreePlan.daysToNextToken(wakeDays: days(1...3), today: today) == 4)
    #expect(FreePlan.daysToNextToken(wakeDays: days(0...6), today: today) == 7)
}

@Test func randomPickHasNoRepeatsAndOnlyLearnedWords() {
    let cards = library.words.prefix(10).map { SRS.learn($0.id, today: today) }
    var rng = SeededRandom(seed: 1)
    let picked = FreePlan.pickRandom(cards, n: 3, using: &rng)
    #expect(picked.count == 3 && Set(picked).count == 3)
    #expect(Set(picked).isSubset(of: Set(cards.map(\.itemID))))
    #expect(FreePlan.pickRandom(cards, n: 50, using: &rng).count == 10)
}
