"""Checks on the starter content in data/. Run after editing any word list."""
import json
import re
import unicodedata
from pathlib import Path

import pytest
from pypinyin import Style, pinyin

DATA = Path(__file__).parent.parent / "data"
packs_file = json.loads((DATA / "packs.json").read_text(encoding="utf-8"))
words_file = json.loads((DATA / "words.zh-CN.json").read_text(encoding="utf-8"))
PACKS = {p["id"]: p for p in packs_file["packs"]}
CONCEPTS = {c["id"]: c for c in packs_file["concepts"]}
WORDS = words_file["words"]

SANDHI_FREE = {"一": "1245", "不": "245",  # tone changes before other tones
               "只": "13"}  # zhī (measure word); the library often guesses zhǐ
ALT_READINGS = {"谁": ["shei2"]}  # shéi is the everyday reading; the library only gives shuí


def render(base: str, tone: int) -> str:
    """base like 'ping' + tone 2 -> 'píng'."""
    base = base.replace("v", "ü")
    marks = {1: "̄", 2: "́", 3: "̌", 4: "̀"}
    if tone not in marks:
        return base
    if "a" in base:
        i = base.index("a")
    elif "e" in base:
        i = base.index("e")
    elif "ou" in base:
        i = base.index("o")
    else:
        i = max(base.rfind(v) for v in "aeiouü")
    return unicodedata.normalize("NFC", base[:i + 1] + marks[tone] + base[i + 1:])


def flat(s: str) -> str:
    s = unicodedata.normalize("NFC", s.lower())
    return re.sub(r"[\s'’.,!?，。！？、]", "", s)


def pinyin_regex(text: str) -> re.Pattern:
    """Pinyin we expect for `text`. Tone 5 (neutral) may also be written with a
    tone mark, and 一/不 may take their changed tones."""
    parts = []
    syllables = pinyin(re.sub(r"[^一-鿿]", "", text), style=Style.TONE3,
                       neutral_tone_with_five=True)
    chars = re.sub(r"[^一-鿿]", "", text)
    for ch, (item,) in zip(chars, syllables):
        m = re.fullmatch(r"([a-zü]+)([1-5])", item.replace("v", "ü"))
        base, tone = m.group(1), int(m.group(2))
        if ch in SANDHI_FREE:
            tones = {int(t) for t in SANDHI_FREE[ch]} | {tone}
        elif tone == 5:
            tones = {1, 2, 3, 4, 5}
        else:
            tones = {tone, 5}  # many words are normally said with a neutral tone
        options = [flat(render(base, t)) for t in sorted(tones)]
        for alt in ALT_READINGS.get(ch, []):
            options.append(flat(render(alt[:-1], int(alt[-1]))))
        parts.append("(?:" + "|".join(re.escape(o) for o in options) + ")")
    return re.compile("".join(parts))


def test_ids_are_unique():
    assert len(CONCEPTS) == len(packs_file["concepts"])
    assert len({w["conceptId"] for w in WORDS}) == len(WORDS)


def test_every_concept_has_one_word_and_known_pack():
    assert {w["conceptId"] for w in WORDS} == set(CONCEPTS)
    assert all(c["packId"] in PACKS for c in CONCEPTS.values())


def test_level_1_free_and_higher_premium():
    for p in PACKS.values():
        assert p["tier"] == ("free" if p["level"] == 1 else "premium")


def test_emoji_unique_where_present():
    """Two concepts sharing an emoji would make picture match ambiguous."""
    emoji = [c["emoji"] for c in CONCEPTS.values() if c["emoji"]]
    assert len(emoji) == len(set(emoji))


@pytest.mark.parametrize("w", WORDS, ids=[w["text"] for w in WORDS])
def test_word_pinyin_matches_independent_source(w):
    assert pinyin_regex(w["text"]).fullmatch(flat(w["pinyin"])), (
        f"{w['text']}: data says {w['pinyin']}")


@pytest.mark.parametrize("w", WORDS, ids=[w["text"] for w in WORDS])
def test_example_sentence(w):
    ex = w["example"]
    assert w["text"] in ex["text"], "example sentence must contain the word"
    assert pinyin_regex(ex["text"]).fullmatch(flat(ex["pinyin"])), (
        f"{ex['text']}: data says {ex['pinyin']}")
    assert ex["english"].strip()
