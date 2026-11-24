"""Matcher and romanization tests for Korean and Japanese."""
import json
from pathlib import Path

import pytest

import japanese
import korean

HERE = Path(__file__).parent
KO_CASES = json.loads((HERE / "cases.ko-KR.json").read_text(encoding="utf-8"))
JA_CASES = json.loads((HERE / "cases.ja-JP.json").read_text(encoding="utf-8"))


@pytest.mark.parametrize("case", KO_CASES, ids=[c["note"] for c in KO_CASES])
def test_korean_matcher(case):
    r = korean.check(case["target"], case["heard"], tuple(case.get("alternates", [])))
    assert r.verdict == case["expect"], f"score={r.score:.2f} heard={r.heard}"


@pytest.mark.parametrize("case", JA_CASES, ids=[c["note"] for c in JA_CASES])
def test_japanese_matcher(case):
    r = japanese.check(case["target"], case["heard"], case.get("reading", ""),
                       tuple(case.get("alternates", [])))
    assert r.verdict == case["expect"], f"score={r.score:.2f} heard={r.heard}"


# Official Revised Romanization examples, covering each sound change we apply.
RR = {
    "감사합니다": "gamsahamnida",   # nasalization ㅂ+ㄴ
    "국물": "gungmul",              # nasalization ㄱ+ㅁ
    "백마": "baengma",
    "신라": "silla",                # ㄴ+ㄹ -> ll
    "설날": "seollal",              # ㄹ+ㄴ -> ll
    "종로": "jongno",               # ㅇ+ㄹ -> n
    "국립": "gungnip",
    "같이": "gachi",                # palatalization
    "굳이": "guji",
    "좋다": "jota",                 # aspiration
    "많다": "manta",
    "좋아요": "joayo",              # silent ㅎ before a vowel
    "괜찮아요": "gwaenchanayo",
    "없어요": "eopseoyo",           # double final: second part links
    "읽어요": "ilgeoyo",
    "읽다": "ikda",                 # double final before a consonant
    "값": "gap",
    "여덟": "yeodeol",
    "물이": "muri",                 # ㄹ links as r
    "텔레비전": "tellebijeon",      # ㄹㄹ -> ll
    "선생님": "seonsaengnim",
    "안녕하세요": "annyeonghaseyo",
}


@pytest.mark.parametrize("hangul,expected", RR.items())
def test_revised_romanization(hangul, expected):
    assert korean.romanize(hangul) == expected


def test_romanize_keeps_spaces_punctuation_and_names():
    assert korean.romanize("저는 ^민수예요.", capitalize=True) == "Jeoneun Minsuyeyo."


def test_korean_hangul_split():
    assert korean.split("한") == ("ㅎ", "ㅏ", "ㄴ")
    assert korean.split("가") == ("ㄱ", "ㅏ", "")


def test_sino_numbers():
    assert [korean.sino_number(n) for n in (0, 3, 10, 12, 20, 300, 3000)] == \
        ["영", "삼", "십", "십이", "이십", "삼백", "삼천"]


def test_kana_helpers():
    assert japanese.to_hiragana("タクシー") == "たくしー"
    assert japanese.morae("きょうっとー") == ["きょ", "う", "っ", "と", "ー"]
    assert [japanese.kanji_number(n) for n in (3, 10, 12, 300)] == ["三", "十", "十二", "三百"]
