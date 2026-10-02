"""Forgiving Mandarin speech matcher (Phase 1a prototype).

Idea: compare what the recognizer heard against the target by *pronunciation*
(pinyin syllables), not by characters. Homophones then match, a wrong tone
costs a little, and sounds that learners and recognizers often mix up
(z/zh, in/ing, ...) cost half as much as a completely different syllable.

This is a prototype of the logic that will be ported to Swift in Phase 1.
The same cases in cases.json will check the Swift version.
"""
import re
import unicodedata
from dataclasses import dataclass, field

from pypinyin import Style, pinyin

# --- Tunable settings -------------------------------------------------------
TONE_COST = 0.35         # same sounds, different tone (a 1-syllable tone slip fails)
CONFUSABLE_COST = 0.5    # initial or final is a commonly confused pair
PASS_SCORE = 0.85        # at or above: pass
NEAR_SCORE = 0.70        # at or above (but below pass): "near", app decides
FREE_EXTRA_SYLLABLES = 2  # extra spoken syllables around the target are free
EXTRA_PENALTY = 0.10     # per extra syllable beyond the free ones

INITIALS = sorted(
    ["b", "p", "m", "f", "d", "t", "n", "l", "g", "k", "h", "j", "q", "x",
     "zh", "ch", "sh", "r", "z", "c", "s", "y", "w"],
    key=len, reverse=True)
CONFUSABLE_INITIALS = [{"z", "zh"}, {"c", "ch"}, {"s", "sh"}, {"n", "l"}, {"l", "r"}]
CONFUSABLE_FINALS = [{"in", "ing"}, {"en", "eng"}, {"an", "ang"}]

DIGITS = {"0": "零", "1": "一", "2": "二", "3": "三", "4": "四",
          "5": "五", "6": "六", "7": "七", "8": "八", "9": "九"}
TONE_MARKS = {"̄": "1", "́": "2", "̌": "3", "̀": "4"}


@dataclass(frozen=True)
class Syllable:
    initial: str
    final: str
    tone: int  # 1-4, 5 = neutral

    @property
    def base(self) -> str:
        return self.initial + self.final


@dataclass
class MatchResult:
    verdict: str  # "pass", "near" or "fail"
    score: float
    best_target: str = ""
    heard_pinyin: list = field(default_factory=list)


def _split(base: str, tone: int) -> Syllable:
    for ini in INITIALS:
        if base.startswith(ini) and len(base) > len(ini):
            return Syllable(ini, base[len(ini):], tone)
    return Syllable("", base, tone)


def normalize(text: str) -> str:
    """Keep only Chinese characters; turn digits into hanzi (recognizers often
    write '3' for 三)."""
    text = unicodedata.normalize("NFKC", text)
    text = "".join(DIGITS.get(c, c) for c in text)
    return re.sub(r"[^一-鿿]", "", text)


def hanzi_to_syllables(text: str) -> list:
    out = []
    for item in pinyin(normalize(text), style=Style.TONE3,
                       neutral_tone_with_five=True, errors="ignore"):
        m = re.fullmatch(r"([a-zv]+)([1-5])", item[0].replace("ü", "v"))
        if m:
            out.append(_split(m.group(1), int(m.group(2))))
    return out


def pinyin_to_syllables(text: str) -> list:
    """Parse 'píng guǒ' or 'ping2 guo3' (use when a character is read
    differently than the default, e.g. 行 háng vs xíng)."""
    out = []
    for token in text.split():
        token = unicodedata.normalize("NFD", token.lower().replace("ü", "ü"))
        token = token.replace("ü", "v")
        tone = 5
        for mark, t in TONE_MARKS.items():
            if mark in token:
                tone = int(t)
                token = token.replace(mark, "")
        if token and token[-1] in "12345":
            tone, token = int(token[-1]), token[:-1]
        out.append(_split(token, tone))
    return out


def _confusable(a: str, b: str, pairs: list) -> bool:
    return any(a in p and b in p for p in pairs)


def syllable_cost(t: Syllable, s: Syllable) -> float:
    tone = TONE_COST if t.tone != s.tone else 0.0
    if t.base == s.base:
        return tone
    same_final = t.final == s.final
    same_initial = t.initial == s.initial
    if same_final and _confusable(t.initial, s.initial, CONFUSABLE_INITIALS):
        return CONFUSABLE_COST + tone
    if same_initial and _confusable(t.final, s.final, CONFUSABLE_FINALS):
        return CONFUSABLE_COST + tone
    return 1.0


def _edit_distance(target: list, heard: list) -> float:
    n, m = len(target), len(heard)
    d = [[0.0] * (m + 1) for _ in range(n + 1)]
    for i in range(1, n + 1):
        d[i][0] = float(i)
    for j in range(1, m + 1):
        d[0][j] = float(j)
    for i in range(1, n + 1):
        for j in range(1, m + 1):
            d[i][j] = min(d[i - 1][j] + 1.0, d[i][j - 1] + 1.0,
                          d[i - 1][j - 1] + syllable_cost(target[i - 1], heard[j - 1]))
    return d[n][m]


def _score(target: list, heard: list) -> float:
    """Best score over windows of what was heard, so extra words around the
    target ("um, 苹果") are mostly forgiven."""
    n, m = len(target), len(heard)
    if n == 0 or m == 0:
        return 0.0
    best = 0.0
    for size in range(max(1, n - 1), n + 2):
        for start in range(0, max(1, m - size + 1)):
            window = heard[start:start + size]
            outside = m - len(window)
            penalty = EXTRA_PENALTY * max(0, outside - FREE_EXTRA_SYLLABLES)
            best = max(best, 1.0 - _edit_distance(target, window) / n - penalty)
    return max(0.0, best)


def check(target: str, transcript: str, target_pinyin: str = "",
          alternates: tuple = ()) -> MatchResult:
    """Compare what was heard to the target (and any accepted alternates)."""
    heard = hanzi_to_syllables(transcript)
    best = MatchResult("fail", 0.0, heard_pinyin=[s.base + str(s.tone) for s in heard])
    candidates = [(target, target_pinyin)] + [(a, "") for a in alternates]
    for text, py in candidates:
        if normalize(text) and normalize(text) in normalize(transcript):
            return MatchResult("pass", 1.0, text, best.heard_pinyin)
        syl = pinyin_to_syllables(py) if py else hanzi_to_syllables(text)
        score = _score(syl, heard)
        if score > best.score:
            best.score, best.best_target = score, text
    best.verdict = ("pass" if best.score >= PASS_SCORE
                    else "near" if best.score >= NEAR_SCORE else "fail")
    return best


if __name__ == "__main__":
    import sys
    if len(sys.argv) >= 3:
        r = check(sys.argv[1], sys.argv[2])
        print(f"{r.verdict.upper()}  score={r.score:.2f}  heard={' '.join(r.heard_pinyin)}")
    else:
        print("usage: python matcher.py <target> <what was heard>")
