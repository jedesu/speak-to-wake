import random

import pytest

from quizzes import GENERATORS, available_types, load_items, make_quiz

ITEMS = load_items()
CASES = [(i, t) for i in ITEMS for t in available_types(i)]
IDS = [f"{i.id}-{t}" for i, t in CASES]


@pytest.mark.parametrize("item,qtype", CASES, ids=IDS)
@pytest.mark.parametrize("same_theme", [True, False])
def test_quiz_is_well_formed(item, qtype, same_theme):
    quiz = make_quiz(item, ITEMS, qtype, seed=7, same_theme=same_theme)
    assert quiz["type"] == qtype and quiz["item"] == item.id
    if "options" in quiz:
        options = quiz["options"]
        assert len(options) == 4 and len(set(options)) == 4
        assert 0 <= quiz["answer"] < 4
    if qtype in ("meaning_to_english",):
        assert options[quiz["answer"]] == item.english
    if qtype in ("meaning_to_chinese", "hear_and_tap", "picture_match", "fill_blank"):
        assert item.text in options[quiz["answer"]]
    if qtype == "match_pairs":
        assert item.text in quiz["left"]
        assert len(quiz["left"]) == len(set(quiz["right"])) == 4
        assert sorted(quiz["answer"].values()) == sorted(quiz["right"])


def test_true_false_has_both_outcomes():
    item = ITEMS[0]
    answers = {make_quiz(item, ITEMS, "true_false", seed=s)["answer"] for s in range(20)}
    assert answers == {True, False}


def test_true_false_false_statement_is_really_wrong():
    for item in ITEMS:
        for seed in range(10):
            q = make_quiz(item, ITEMS, "true_false", seed=seed)
            if q["answer"] is False:
                assert f'"{item.english}"' not in q["statement"]


def test_picture_match_needs_emoji_and_only_uses_emoji_words():
    no_emoji = next(i for i in ITEMS if not i.emoji)
    assert "picture_match" not in available_types(no_emoji)
    with pytest.raises(ValueError):
        GENERATORS["picture_match"](no_emoji, ITEMS, random.Random(1))
    item = next(i for i in ITEMS if i.emoji)
    q = make_quiz(item, ITEMS, "picture_match", seed=3)
    by_label = {f"{i.text} ({i.pinyin})": i for i in ITEMS}
    assert all(by_label[o].emoji for o in q["options"])


def test_fill_blank_hides_the_answer_and_avoids_same_theme_words():
    for item in ITEMS:
        q = make_quiz(item, ITEMS, "fill_blank", seed=5)
        assert item.text not in q["prompt"] and "＿＿" in q["prompt"]
        themes = {next(i.theme for i in ITEMS if f"{i.text} ({i.pinyin})" == o)
                  for k, o in enumerate(q["options"]) if k != q["answer"]}
        assert item.theme not in themes


def test_same_seed_gives_same_quiz():
    item = ITEMS[10]
    assert make_quiz(item, ITEMS, seed=42) == make_quiz(item, ITEMS, seed=42)


def test_too_small_pool_raises_clear_error():
    with pytest.raises(ValueError):
        make_quiz(ITEMS[0], ITEMS[:2], "meaning_to_english", seed=1)
