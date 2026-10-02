from datetime import date, timedelta

import pytest

from srs import (CORRECT, INTERVAL_DAYS, MAX_BOX, MISSED, RETRY, Card, due_cards,
                 is_due, is_mastered, learn, pack_mastered, pick_for_alarm, review,
                 words_learned)

D0 = date(2026, 10, 1)


def day(n):
    return D0 + timedelta(days=n)


def test_new_word_starts_in_box_1_due_tomorrow():
    c = learn("apple", D0)
    assert (c.box, c.due) == (1, day(1))
    assert not is_due(c, D0) and is_due(c, day(1))


def test_correct_answers_climb_boxes_with_growing_gaps():
    c, today, gaps = learn("apple", D0), D0, []
    for _ in range(7):
        today = c.due
        c = review(c, CORRECT, today)
        gaps.append((c.due - today).days)
    assert gaps == [2, 4, 8, 16, 32, 32, 32]
    assert c.box == MAX_BOX == 6


def test_miss_drops_one_box_and_returns_next_day():
    c = Card("x", box=4, due=D0)
    c2 = review(c, MISSED, D0)
    assert (c2.box, c2.due, c2.times_missed) == (3, day(1), 1)


def test_miss_in_box_1_stays_in_box_1():
    c = review(learn("x", D0), MISSED, day(1))
    assert (c.box, c.due) == (1, day(2))


def test_retry_keeps_box():
    c = Card("x", box=3, due=D0)
    c2 = review(c, RETRY, D0)
    assert (c2.box, c2.due) == (3, D0 + timedelta(days=INTERVAL_DAYS[3]))


def test_early_correct_review_does_not_promote_or_reschedule():
    c = Card("x", box=2, due=day(5))
    c2 = review(c, CORRECT, day(2))
    assert (c2.box, c2.due) == (2, day(5)) and c2.times_correct == 1


def test_early_miss_still_drops():
    c = Card("x", box=3, due=day(5))
    c2 = review(c, MISSED, day(2))
    assert (c2.box, c2.due) == (2, day(3))


def test_late_review_counts_from_the_review_day():
    c = Card("x", box=1, due=D0)
    c2 = review(c, CORRECT, day(3))  # three days overdue
    assert c2.due == day(3) + timedelta(days=2)


def test_unknown_outcome_rejected():
    with pytest.raises(ValueError):
        review(learn("x", D0), "maybe", day(1))


def test_evening_learning_is_due_at_next_morning_alarm():
    # Date-based: the time of day never matters.
    assert is_due(learn("x", date(2026, 10, 1)), date(2026, 10, 2))


def cards_example():
    return [
        Card("a", box=1, due=day(0)),   # due, struggling
        Card("b", box=5, due=day(0)),   # due, well known
        Card("c", box=3, due=day(-2)),  # due, most overdue
        Card("d", box=2, due=day(3)),   # upcoming (soonest)
        Card("e", box=4, due=day(9)),   # upcoming (later)
    ]


def test_alarm_normal_prefers_most_overdue_then_weakest():
    assert pick_for_alarm(cards_example(), D0, 3) == ["c", "a", "b"]


def test_alarm_easy_prefers_well_known_words():
    assert pick_for_alarm(cards_example(), D0, 3, "easy") == ["b", "c", "a"]


def test_alarm_fills_with_upcoming_words_when_few_are_due():
    assert pick_for_alarm(cards_example(), D0, 5) == ["c", "a", "b", "d", "e"]


def test_alarm_never_repeats_and_handles_empty_or_small_pools():
    assert pick_for_alarm([], D0, 3) == []
    assert pick_for_alarm(cards_example()[:2], D0, 3) == ["a", "b"]
    picked = pick_for_alarm(cards_example(), D0, 4)
    assert len(picked) == len(set(picked)) == 4


def test_missed_word_is_back_at_tomorrows_alarm():
    c = review(Card("x", box=5, due=D0), MISSED, D0)
    assert pick_for_alarm([c, Card("y", box=1, due=day(30))], day(1), 1) == ["x"]


def test_due_cards():
    assert {c.item_id for c in due_cards(cards_example(), D0)} == {"a", "b", "c"}


def test_mastery_helpers():
    cards = {"a": Card("a", 5, D0), "b": Card("b", 4, D0), "c": Card("c", 2, D0)}
    assert is_mastered(cards["a"]) and not is_mastered(cards["b"])
    assert pack_mastered(cards, ["a", "b"]) is True
    assert pack_mastered(cards, ["a", "b", "c"]) is False
    assert pack_mastered(cards, ["a", "missing"]) is False
    assert pack_mastered(cards, []) is False
    assert words_learned(cards.values()) == 3
