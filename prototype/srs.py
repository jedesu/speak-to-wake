"""Spaced repetition (Leitner boxes) for the alarm and the review screens.

Plain-language rules
--------------------
* A word you've studied starts in Box 1 and is due the next calendar day.
* Each box has a gap before the next review: 1, 2, 4, 8, 16, 32 days.
* Right on the first try  -> move up a box (longer gap).
* Right but only after a retry/hint/fallback -> stay in the same box.
* Wrong -> drop one box, and the word comes back the next day.
* Dates, not clock times: learn a word at 8 pm and it is due at tomorrow's
  7 am alarm.
* Reviewing a word *before* it's due (the alarm filling its quota) never moves
  it up, because early reviews don't earn the longer gap. A miss still drops it.
"""
import random
from dataclasses import dataclass, replace
from datetime import date, timedelta

INTERVAL_DAYS = {1: 1, 2: 2, 3: 4, 4: 8, 5: 16, 6: 32}
MAX_BOX = 6
MASTERED_BOX = 5  # a word counts as "learned well" from this box up

CORRECT, RETRY, MISSED = "correct", "correct_after_retry", "missed"


@dataclass(frozen=True)
class Card:
    item_id: str
    box: int
    due: date
    times_correct: int = 0
    times_missed: int = 0
    last_reviewed: date | None = None


def learn(item_id: str, today: date) -> Card:
    """Call when the user finishes studying a word in the Learn tab."""
    return Card(item_id, 1, today + timedelta(days=INTERVAL_DAYS[1]))


def review(card: Card, outcome: str, today: date) -> Card:
    """Return the updated card after one review."""
    if outcome not in (CORRECT, RETRY, MISSED):
        raise ValueError(f"unknown outcome: {outcome}")
    if outcome == MISSED:
        box = max(1, card.box - 1)
        return replace(card, box=box, due=today + timedelta(days=1),
                       times_missed=card.times_missed + 1, last_reviewed=today)
    early = today < card.due
    if early:
        # No spacing benefit from an early review: keep box and due date.
        return replace(card, times_correct=card.times_correct + 1, last_reviewed=today)
    box = min(MAX_BOX, card.box + 1) if outcome == CORRECT else card.box
    return replace(card, box=box, due=today + timedelta(days=INTERVAL_DAYS[box]),
                   times_correct=card.times_correct + 1, last_reviewed=today)


def is_due(card: Card, today: date) -> bool:
    return card.due <= today


def due_cards(cards, today: date) -> list:
    return [c for c in cards if is_due(c, today)]


def pick_for_alarm(cards, today: date, n: int, difficulty: str = "normal") -> list:
    """Choose up to `n` item ids for this morning's alarm (no repeats).

    Due words come first. normal: most overdue first, then lowest box (the
    words you struggle with). easy: highest box first (the words you know best),
    which suits a groggy brain. If fewer than `n` are due, the rest are filled
    with the soonest-upcoming words so the alarm always has something to ask.
    """
    due = due_cards(cards, today)
    if difficulty == "easy":
        due.sort(key=lambda c: (-c.box, c.due, c.item_id))
    else:
        due.sort(key=lambda c: (c.due, c.box, c.item_id))
    chosen = [c.item_id for c in due[:n]]
    if len(chosen) < n:
        upcoming = sorted((c for c in cards if not is_due(c, today)),
                          key=lambda c: (c.due, c.item_id))
        chosen += [c.item_id for c in upcoming[:n - len(chosen)]]
    return chosen


def is_mastered(card: Card) -> bool:
    return card.box >= MASTERED_BOX


def pack_mastered(cards_by_id: dict, pack_item_ids, min_box: int = 4) -> bool:
    """True when every word in the pack is learned and sits at `min_box`+.
    Used for the 'master a pack, earn a pack token' rule."""
    ids = list(pack_item_ids)
    return bool(ids) and all(i in cards_by_id and cards_by_id[i].box >= min_box for i in ids)


def words_learned(cards) -> int:
    """For the Progress screen: words you've studied and are not failing."""
    return sum(1 for c in cards if c.box >= 2)
