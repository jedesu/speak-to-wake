import Foundation

/// The Free vs Pro rules (PLAN.md, "Free vs Premium tiers").
///
/// * Free: level 1 sections, one language at a time, and the alarm and Review
///   pick learned words at random.
/// * Pro: every section, and spaced repetition (the words you're about to forget).
/// * Free users earn a **section token** for every 7 wake-ups in a row. A token
///   unlocks one Pro section for good, in every language.
public enum FreePlan {
    /// Wake-ups in a row needed to earn one token.
    public static let streakForToken = 7

    /// Whether a section can be studied.
    public static func canOpen(_ pack: Pack, isPro: Bool, unlockedPackIDs: Set<String>) -> Bool {
        pack.tier == .free || isPro || unlockedPackIDs.contains(pack.id)
    }

    /// Tokens earned so far: each run of consecutive wake-up days earns one per
    /// full 7 days (a 15-day run earns 2). Missing a day starts a new run.
    public static func tokensEarned(wakeDays: Set<Day>) -> Int {
        runs(wakeDays).reduce(0) { $0 + $1 / streakForToken }
    }

    /// Tokens not spent yet.
    public static func tokensLeft(wakeDays: Set<Day>, unlockedPackIDs: Set<String>) -> Int {
        max(0, tokensEarned(wakeDays: wakeDays) - unlockedPackIDs.count)
    }

    /// Wake-ups in a row up to today. Today not done yet doesn't break the streak
    /// (the alarm may not have rung yet), so it counts back from yesterday.
    public static func currentStreak(wakeDays: Set<Day>, today: Day) -> Int {
        var day = wakeDays.contains(today) ? today : today - 1
        var count = 0
        while wakeDays.contains(day) {
            count += 1
            day = day - 1
        }
        return count
    }

    /// Wake-ups still needed for the next token (1 to 7).
    public static func daysToNextToken(wakeDays: Set<Day>, today: Day) -> Int {
        streakForToken - currentStreak(wakeDays: wakeDays, today: today) % streakForToken
    }

    /// Free users' alarm and Review: `n` learned words at random, no schedule.
    public static func pickRandom<R: RandomNumberGenerator>(_ cards: [Card], n: Int, using rng: inout R) -> [String] {
        Array(cards.map(\.itemID).shuffled(using: &rng).prefix(n))
    }

    /// Lengths of the runs of consecutive days.
    static func runs(_ days: Set<Day>) -> [Int] {
        var result: [Int] = []
        var previous: Day?
        for day in days.sorted() {
            if let previous, day - previous == 1 {
                result[result.count - 1] += 1
            } else {
                result.append(1)
            }
            previous = day
        }
        return result
    }
}
