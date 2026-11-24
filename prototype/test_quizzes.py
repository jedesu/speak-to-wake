import random

import pytest

from quizzes import GENERATORS, available_types, load_items, make_quiz

LANGS = ["zh-CN", "ko-KR", "ja-JP"]
POOLS = {lang: load_items(language=lang) for lang in LANGS}
CASES = [(lang, i, t) for lang in LANGS for i in POOLS[lang] for t in available_types(i)]
IDS = [f"{lang}-{i.id}-{t}" for lang, i, t in CASES]


def label(i):
    return f"{i.text} ({i.pinyin})"


@pytest.mark.parametrize("lang,item,qtype", CASES, ids=IDS)
@pytest.mark.parametrize("same_theme", [True, False])
def test_quiz_is_well_formed(lang, item, qtype, same_theme):
    pool = POOLS[lang]
    quiz = make_quiz(item, pool, qtype, seed=7, same_theme=same_theme)
    assert quiz["type"] == qtype and quiz["item"] == item.id
    if "options" in quiz:
        options = quiz["options"]
        assert len(options) == 4 and len(set(options)) == 4
        assert 0 <= quiz["answer"] < 4
    if qtype in ("meaning_to_english",):
        assert options[quiz["answer"]] == item.english
    if qtype in ("meaning_to_chinese", "hear_and_tap", "picture_match", "fill_blank"):
        assert item.text in options[quiz["answer"]]
        # No wrong answer may sound like the right one (三 and さん are both 'san').
        by_label = {label(i): i for i in pool}
        wrong = [by_label[o] for k, o in enumerate(options) if k != quiz["answer"]]
        assert all(w.sound != item.sound for w in wrong)
    if qtype == "match_pairs":
        assert item.text in quiz["left"]
        assert len(quiz["left"]) == len(set(quiz["right"])) == 4
        assert sorted(quiz["answer"].values()) == sorted(quiz["right"])


@pytest.mark.parametrize("lang", LANGS)
def test_true_false_has_both_outcomes(lang):
    item = POOLS[lang][0]
    answers = {make_quiz(item, POOLS[lang], "true_false", seed=s)["answer"] for s in range(20)}
    assert answers == {True, False}


@pytest.mark.parametrize("lang", LANGS)
def test_true_false_false_statement_is_really_wrong(lang):
    for item in POOLS[lang]:
        for seed in range(10):
            q = make_quiz(item, POOLS[lang], "true_false", seed=seed)
            if q["answer"] is False:
                assert f'"{item.english}"' not in q["statement"]


@pytest.mark.parametrize("lang", LANGS)
def test_picture_match_needs_emoji_and_only_uses_emoji_words(lang):
    pool = POOLS[lang]
    no_emoji = next(i for i in pool if not i.emoji)
    assert "picture_match" not in available_types(no_emoji)
    with pytest.raises(ValueError):
        GENERATORS["picture_match"](no_emoji, pool, random.Random(1))
    item = next(i for i in pool if i.emoji)
    q = make_quiz(item, pool, "picture_match", seed=3)
    by_label = {label(i): i for i in pool}
    assert all(by_label[o].emoji for o in q["options"])


@pytest.mark.parametrize("lang", LANGS)
def test_fill_blank_hides_the_answer_and_avoids_same_theme_words(lang):
    pool = POOLS[lang]
    for item in pool:
        if "fill_blank" not in available_types(item):
            continue  # e.g. 问 in 我可以问你一个问题吗: blanking one 问 would leave the other
        q = make_quiz(item, pool, "fill_blank", seed=5)
        assert item.text not in q["prompt"] and "＿＿" in q["prompt"]
        themes = {next(i.theme for i in pool if label(i) == o)
                  for k, o in enumerate(q["options"]) if k != q["answer"]}
        assert item.theme not in themes


def test_language_specific_meaning_is_used():
    by_id = {i.id: i for i in POOLS["ko-KR"]}
    assert by_id["yuan"].english == "won (Korean money)"
    assert {i.id: i for i in POOLS["zh-CN"]}["yuan"].english == "yuan (money)"


def test_skipped_concepts_are_not_quizzed():
    assert "see" not in {i.id for i in POOLS["ko-KR"]}
    assert "topic-marker" not in {i.id for i in POOLS["zh-CN"]}
    assert "topic-marker" in {i.id for i in POOLS["ja-JP"]}


def test_same_seed_gives_same_quiz():
    item = POOLS["zh-CN"][10]
    assert make_quiz(item, POOLS["zh-CN"], seed=42) == make_quiz(item, POOLS["zh-CN"], seed=42)


def test_too_small_pool_raises_clear_error():
    pool = POOLS["zh-CN"]
    with pytest.raises(ValueError):
        make_quiz(pool[0], pool[:2], "meaning_to_english", seed=1)
