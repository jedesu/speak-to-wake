"""Checks on the Korean and Japanese word lists (data/words.ko-KR.json, words.ja-JP.json).
Rebuild them with build_lang.py after editing data/source/<language>.txt."""
import json
import re
from pathlib import Path

import pytest

import japanese
import korean

DATA = Path(__file__).parent.parent / "data"
LANGS = ["ko-KR", "ja-JP"]
PACKS_FILE = json.loads((DATA / "packs.json").read_text(encoding="utf-8"))
PACKS = {p["id"]: p for p in PACKS_FILE["packs"]}
CONCEPTS = {c["id"]: c for c in PACKS_FILE["concepts"]}
FILES = {lang: json.loads((DATA / f"words.{lang}.json").read_text(encoding="utf-8")) for lang in LANGS}
ALL = [(lang, w) for lang in LANGS for w in FILES[lang]["words"]]
IDS = [f"{lang}-{w['conceptId']}" for lang, w in ALL]

# Words whose dictionary reading differs from how they're said (particles), or
# where pykakasi's guess is wrong. Each one was checked by hand.
JA_READING_OK = {
    "こんにちは": "こんにちわ",  # は said わ
    "は": "わ",
    "時": "じ",               # o'clock; pykakasi gives とき (time)
    "四": "よん",             # pykakasi gives し; both are right, よん is the everyday one
    "七": "なな",             # pykakasi gives しち; both are right
    "人": "ひと",             # pykakasi gives にん (the counter reading)
    "歳": "さい",             # age counter; pykakasi gives とし
    "ご飯": "ごはん",          # pykakasi gives ごめし
    "開ける": "あける",        # pykakasi gives ひらける
    "お金": "おかね",          # pykakasi gives おきん
    "小さい": "ちいさい",      # pykakasi writes ちーさい
}


@pytest.mark.parametrize("lang", LANGS)
def test_level_1_sections_fully_covered(lang):
    """Every shared level-1 concept is translated or skipped with a reason, never forgotten."""
    f = FILES[lang]
    done = {w["conceptId"] for w in f["words"]} | set(f["skipped"])
    level1 = {cid for cid, c in CONCEPTS.items()
              if PACKS[c["packId"]].get("hsk") == 1 and lang in c.get("languages", [lang])}
    assert level1 == done
    assert all(reason.strip() for reason in f["skipped"].values())
    assert not set(f["skipped"]) & {w["conceptId"] for w in f["words"]}


@pytest.mark.parametrize("lang", LANGS)
def test_words_unique_and_concepts_exist(lang):
    words = FILES[lang]["words"]
    assert FILES[lang]["language"] == lang
    assert len({w["text"] for w in words}) == len(words)
    assert len({w["conceptId"] for w in words}) == len(words)
    for w in words:
        c = CONCEPTS[w["conceptId"]]
        assert lang in c.get("languages", [lang]), f"{c['id']} isn't for {lang}"


def test_language_only_concepts_are_tagged_correctly():
    for c in CONCEPTS.values():
        if "languages" in c:
            assert c["languages"] and "zh-CN" not in c["languages"]
            assert c["packId"] in PACKS and c["english"]


@pytest.mark.parametrize("lang,w", ALL, ids=IDS)
def test_word_fields(lang, w):
    assert w["text"] not in w.get("alternates", [])
    ex = w["example"]
    assert ex["text"] and ex["pinyin"] and ex["english"].strip()
    assert "^" not in ex["text"] and "{" not in ex["text"]
    if lang == "ko-KR":
        assert re.fullmatch(r"[가-힣 ]+", w["text"])
        assert w["pinyin"] == korean.romanize(w["text"]), "rebuild with build_lang.py"
    else:
        assert re.fullmatch(r"[ぁ-ゖー]+", w["reading"])
        assert re.fullmatch(r"[ぁ-ゖー、。！？「」]+", ex["reading"]), ex["reading"]
        assert w["pinyin"].isascii() and ex["pinyin"].isascii()


@pytest.mark.parametrize("w", FILES["ja-JP"]["words"], ids=[w["text"] for w in FILES["ja-JP"]["words"]])
def test_japanese_reading_matches_independent_source(w):
    expected = JA_READING_OK.get(w["text"]) or japanese.reading(w["text"])
    assert w["reading"] == expected, f"{w['text']}: data says {w['reading']}, pykakasi says {expected}"


def test_reading_exceptions_are_still_needed():
    """Keeps the exception list honest: drop an entry once pykakasi agrees."""
    words = {w["text"] for w in FILES["ja-JP"]["words"]}
    for text, said in JA_READING_OK.items():
        assert text in words, f"{text} is no longer a word"
        assert japanese.reading(text) != said, f"{text}: pykakasi now agrees, remove it"
