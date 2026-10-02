"""What-if simulation of the review backlog. The accuracy numbers are ASSUMPTIONS,
not measurements: use this to sanity-check the design, not to predict results.

usage: python simulate_srs.py
"""
import random
from datetime import date, timedelta

from srs import CORRECT, MISSED, due_cards, learn, pick_for_alarm, review

START = date(2026, 10, 1)
P_CORRECT_BY_BOX = {1: 0.70, 2: 0.80, 3: 0.85, 4: 0.90, 5: 0.93, 6: 0.95}  # assumed


def simulate(days=60, words=35, new_per_day=5, alarm_prompts=3, extra_reviews=0,
             difficulty="normal", seed=1):
    rng = random.Random(seed)
    cards, next_word, rows = {}, 0, []
    for d in range(days):
        today = START + timedelta(days=d)
        # Learn tab: study a few new words per day until the list is used up.
        for _ in range(new_per_day):
            if next_word < words:
                cards[f"w{next_word}"] = learn(f"w{next_word}", today)
                next_word += 1
        # Morning alarm, then optional extra review in the Learn tab.
        for n in (alarm_prompts, extra_reviews):
            for item_id in pick_for_alarm(list(cards.values()), today, n, difficulty):
                c = cards[item_id]
                ok = rng.random() < P_CORRECT_BY_BOX[c.box]
                cards[item_id] = review(c, CORRECT if ok else MISSED, today)
        due = len(due_cards(cards.values(), today + timedelta(days=1)))
        rows.append((d + 1, due, sum(c.box >= 5 for c in cards.values())))
    return rows


if __name__ == "__main__":
    scenarios = [("alarm only, 3 prompts/day", dict(alarm_prompts=3)),
                 ("alarm 3 + Learn-tab review 10", dict(alarm_prompts=3, extra_reviews=10)),
                 ("alarm 3 + Learn-tab review 20", dict(alarm_prompts=3, extra_reviews=20))]
    for name, kw in scenarios:
        rows = simulate(**kw)
        print(f"\n{name}  (35 words, 5 new/day for the first 7 days)")
        print("  day  words due next morning  words in boxes 5-6")
        for day, due, strong in rows:
            if day in (7, 14, 21, 30, 45, 60):
                print(f"  {day:>3}  {due:>22}  {strong:>18}")
