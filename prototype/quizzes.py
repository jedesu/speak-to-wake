"""Tap-quiz generators (Phase 3 prototype). Pure logic, no UI.

Every generator takes one target `Item` and the pool of all unlocked items,
and returns a plain dict the UI can render. Wrong answers ("distractors")
come from the same theme when `same_theme=True` (harder, more plausible) or
from other themes (easier; better when groggy).

Types: meaning (word -> English, or reverse), hear_and_tap, picture_match,
true_false, fill_blank, match_pairs.
"""
import json
import random
from dataclasses import dataclass
from pathlib import Path

DATA = Path(__file__).parent.parent / "data"
BLANK = "＿＿"


@dataclass(frozen=True)
class Item:
    id: str
    theme: str
    level: int
    english: str
    emoji: str | None
    text: str
    pinyin: str
    example_text: str
    example_pinyin: str
    example_english: str


def load_items(data_dir: Path = DATA, language: str = "zh-CN") -> list:
    packs = json.loads((data_dir / "packs.json").read_text(encoding="utf-8"))
    words = json.loads((data_dir / f"words.{language}.json").read_text(encoding="utf-8"))
    pack_by_id = {p["id"]: p for p in packs["packs"]}
    word_by_concept = {w["conceptId"]: w for w in words["words"]}
    items = []
    for c in packs["concepts"]:
        w, p = word_by_concept[c["id"]], pack_by_id[c["packId"]]
        ex = w["example"]
        items.append(Item(c["id"], p["theme"], p["level"], c["english"], c["emoji"],
                          w["text"], w["pinyin"], ex["text"], ex["pinyin"], ex["english"]))
    return items


# --- availability -----------------------------------------------------------
def available_types(item: Item) -> list:
    """Which quiz types make sense for this word."""
    types = ["meaning_to_english", "meaning_to_chinese", "hear_and_tap",
             "true_false", "match_pairs"]
    if item.emoji:
        types.append("picture_match")
    if item.example_text.count(item.text) == 1:  # 一边…一边… would give it away
        types.append("fill_blank")
    return types


# --- helpers ----------------------------------------------------------------
def _distractors(item, pool, k, rng, same_theme, need=lambda i: True):
    others = [i for i in pool if i.id != item.id and need(i)
              and i.english != item.english and i.text != item.text]
    preferred = [i for i in others if (i.theme == item.theme) == same_theme]
    rest = [i for i in others if i not in preferred]
    rng.shuffle(preferred)
    rng.shuffle(rest)
    chosen = (preferred + rest)[:k]
    if len(chosen) < k:
        raise ValueError(f"not enough words to build {k} wrong answers")
    return chosen


def _shuffled_options(correct, wrong, rng):
    options = [correct] + list(wrong)
    rng.shuffle(options)
    return options, options.index(correct)


def _word_label(i: Item) -> str:
    return f"{i.text} ({i.pinyin})"


# --- generators -------------------------------------------------------------
def meaning_to_english(item, pool, rng, same_theme=False):
    wrong = _distractors(item, pool, 3, rng, same_theme)
    options, ans = _shuffled_options(item.english, [w.english for w in wrong], rng)
    return {"type": "meaning_to_english", "item": item.id,
            "prompt": _word_label(item), "options": options, "answer": ans}


def meaning_to_chinese(item, pool, rng, same_theme=False):
    wrong = _distractors(item, pool, 3, rng, same_theme)
    options, ans = _shuffled_options(_word_label(item), [_word_label(w) for w in wrong], rng)
    return {"type": "meaning_to_chinese", "item": item.id,
            "prompt": item.english, "options": options, "answer": ans}


def hear_and_tap(item, pool, rng, same_theme=False):
    """The UI speaks `audio` with text-to-speech and hides the prompt text."""
    wrong = _distractors(item, pool, 3, rng, same_theme)
    options, ans = _shuffled_options(_word_label(item), [_word_label(w) for w in wrong], rng)
    return {"type": "hear_and_tap", "item": item.id, "audio": item.text,
            "options": options, "answer": ans}


def picture_match(item, pool, rng, same_theme=False):
    if not item.emoji:
        raise ValueError(f"{item.id} has no emoji")
    wrong = _distractors(item, pool, 3, rng, same_theme, need=lambda i: bool(i.emoji))
    options, ans = _shuffled_options(_word_label(item), [_word_label(w) for w in wrong], rng)
    return {"type": "picture_match", "item": item.id, "prompt": item.emoji,
            "options": options, "answer": ans}


def true_false(item, pool, rng, same_theme=True):
    """'苹果 means apple' (true) or 'means banana' (false)."""
    if rng.random() < 0.5:
        shown, answer = item.english, True
    else:
        shown, answer = _distractors(item, pool, 1, rng, same_theme)[0].english, False
    return {"type": "true_false", "item": item.id,
            "statement": f"{_word_label(item)} means \"{shown}\"", "answer": answer}


def fill_blank(item, pool, rng, same_theme=False):
    """Blank the word out of its example sentence. Distractors default to other
    themes because words from the same theme (e.g. other fruits) can also fit
    the blank and make the question unfair."""
    if item.text not in item.example_text:
        raise ValueError(f"{item.id}: example sentence lacks the word")
    wrong = _distractors(item, pool, 3, rng, same_theme)
    options, ans = _shuffled_options(_word_label(item), [_word_label(w) for w in wrong], rng)
    return {"type": "fill_blank", "item": item.id,
            "prompt": item.example_text.replace(item.text, BLANK, 1),
            "hint": item.example_english, "options": options, "answer": ans}


def match_pairs(item, pool, rng, same_theme=True, size=4):
    """Pair `size` Chinese words with their English meanings; includes `item`."""
    others = _distractors(item, pool, size - 1, rng, same_theme)
    group = [item] + others
    right = [i.english for i in group]
    rng.shuffle(right)
    left = [i.text for i in group]
    return {"type": "match_pairs", "item": item.id, "left": left, "right": right,
            "answer": {i.text: i.english for i in group}}


GENERATORS = {
    "meaning_to_english": meaning_to_english,
    "meaning_to_chinese": meaning_to_chinese,
    "hear_and_tap": hear_and_tap,
    "picture_match": picture_match,
    "true_false": true_false,
    "fill_blank": fill_blank,
    "match_pairs": match_pairs,
}


def make_quiz(item, pool, quiz_type=None, seed=None, **kwargs):
    rng = random.Random(seed)
    quiz_type = quiz_type or rng.choice(available_types(item))
    return GENERATORS[quiz_type](item, pool, rng, **kwargs)


if __name__ == "__main__":
    items = load_items()
    rng = random.Random(1)
    for item in rng.sample(items, 5):
        print(json.dumps(make_quiz(item, items, seed=rng.random()), ensure_ascii=False))
