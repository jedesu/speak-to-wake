"""Japanese helpers (prototype, to be ported to Swift like matcher.py).

The recognizer writes Japanese with kanji (橋), hiragana (はし) or katakana (ハシ),
and the same sound can be written many ways. So, like the Mandarin matcher, we
compare *sounds*: both the target and the transcript become hiragana, split
into morae (beats: か, きゃ, っ, ん, ー each count as one).

Costs (per mora):
* voiced vs unvoiced (か/が, は/ば/ぱ): 0.5, a common slip
* extra or missing small っ (gemination) or long vowel: 0.8. These change the
  word (おばさん aunt, おばあさん grandma), so like Mandarin tones they count
  as wrong in everyday words and are forgiven only in long phrases (7+ beats)
* extra or missing ん: 0.5
* anything else: 1
Pitch accent is not graded, like tones were at first in Mandarin.

In the prototype, readings of kanji come from pykakasi. On iOS, use
CFStringTokenizer with a Japanese locale and its Latin transcription, then
convert to hiragana (see PORTING-ko-ja.md).
"""
import re
import unicodedata
from dataclasses import dataclass, field

import pykakasi

_kakasi = pykakasi.kakasi()

# --- kana basics ---------------------------------------------------------------
SMALL = set("ゃゅょぁぃぅぇぉゎ")
VOICING = str.maketrans("がぎぐげござじずぜぞだぢづでどばびぶべぼぱぴぷぺぽゔ",
                        "かきくけこさしすせそたちつてとはひふへほはひふへほう")
VOWEL_OF = {}
for vowel, row in (("a", "あかさたなはまやらわがざだばぱぁゃゎ"), ("i", "いきしちにひみりぎじぢびぴぃ"),
                   ("u", "うくすつぬふむゆるぐずづぶぷぅゅゔ"), ("e", "えけせてねへめれげぜでべぺぇ"),
                   ("o", "おこそとのほもよろをごぞどぼぽぉょ")):
    for ch in row:
        VOWEL_OF[ch] = vowel


def to_hiragana(text: str) -> str:
    """Katakana -> hiragana (ー stays: it means 'make the vowel long')."""
    text = unicodedata.normalize("NFKC", text)
    return "".join(chr(ord(c) - 0x60) if "ァ" <= c <= "ヶ" else c for c in text)


KANJI_DIGITS = "〇一二三四五六七八九"


def kanji_number(n: int) -> str:
    """12 -> 十二, 300 -> 三百 (how recognizers' digits are read)."""
    if n == 0:
        return "ゼロ"
    out = ""
    for value, name in ((1000, "千"), (100, "百"), (10, "十")):
        d, n = divmod(n, value)
        if d:
            out += ("" if d == 1 else KANJI_DIGITS[d]) + name
    return out + (KANJI_DIGITS[n] if n else "")


def reading(text: str) -> str:
    """Hiragana reading of any Japanese text (kanji, kana, digits)."""
    text = unicodedata.normalize("NFKC", text)
    text = re.sub(r"\d+", lambda m: kanji_number(int(m.group(0))) if len(m.group(0)) < 5 else "", text)
    hira = "".join(item["hira"] for item in _kakasi.convert(text))
    return "".join(c for c in to_hiragana(hira) if "ぁ" <= c <= "ゖ" or c == "ー")


def morae(kana: str) -> list:
    """'きょうっと' -> ['きょ', 'う', 'っ', 'と']."""
    out = []
    for ch in kana:
        if ch in SMALL and out:
            out[-1] += ch
        else:
            out.append(ch)
    return out


def vowel(mora: str) -> str:
    return VOWEL_OF.get(mora[-1], "")


# --- romaji (for the flashcards' pronunciation line) ----------------------------
PARTICLES = {"は": "wa", "へ": "e", "を": "o"}


def romaji(text: str, capitalize: bool = False) -> str:
    """Hepburn-style romaji, word by word. Particles are spelled as said (は -> wa)."""
    words = []
    for item in _kakasi.convert(text):
        orig, roma = item["orig"], item["hepburn"]
        if orig in PARTICLES:
            roma = PARTICLES[orig]
        elif orig.endswith(tuple(PARTICLES)) and len(orig) > 1 and item["hira"] == orig:
            # pykakasi sometimes glues a particle onto kana: 'これは' -> 'kore wa'
            roma = romaji_of_kana(orig[:-1]) + " " + PARTICLES[orig[-1]]
        if re.fullmatch(r"[。、！？!?.,]+", orig):
            if words:
                words[-1] += orig.replace("。", ".").replace("、", ",").replace("！", "!").replace("？", "?")
            continue
        if roma.strip():
            words.append(roma.strip())
    out = " ".join(words)
    return out[:1].upper() + out[1:] if capitalize else out


def romaji_of_kana(kana: str) -> str:
    return "".join(item["hepburn"] for item in _kakasi.convert(kana))


# --- matcher -------------------------------------------------------------------
PASS_SCORE = 0.85
NEAR_SCORE = 0.70
FREE_EXTRA_MORAE = 3  # Japanese words are longer in beats than Chinese in syllables
EXTRA_PENALTY = 0.10
VOICING_COST = 0.5
LENGTH_COST = 0.8  # small っ or long vowel added/missing: it changes the word (切手 きって stamp, きて come)
N_COST = 0.5


def sub_cost(t: str, s: str) -> float:
    if t == s:
        return 0.0
    if t.translate(VOICING) == s.translate(VOICING):
        return VOICING_COST
    if {t, s} <= {"じ", "ぢ"} or {t, s} <= {"ず", "づ"} or {t, s} <= {"お", "を"}:
        return 0.0
    return 1.0


def indel_cost(mora: str, prev: str | None) -> float:
    """Cost of a mora being extra or missing, given the mora before it."""
    if mora in ("っ", "ー"):
        return LENGTH_COST
    if mora == "ん":
        return N_COST
    if prev and mora in "あいうえお":
        v = vowel(prev)
        if mora == {"a": "あ", "i": "い", "u": "う", "e": "え", "o": "お"}.get(v) or \
                (v == "o" and mora == "う") or (v == "e" and mora == "い"):
            return LENGTH_COST  # long vowel: おお/おう, ええ/えい
    return 1.0


def _edit_distance(t: list, s: list) -> float:
    n, m = len(t), len(s)
    d = [[0.0] * (m + 1) for _ in range(n + 1)]
    for i in range(1, n + 1):
        d[i][0] = d[i - 1][0] + indel_cost(t[i - 1], t[i - 2] if i > 1 else None)
    for j in range(1, m + 1):
        d[0][j] = d[0][j - 1] + indel_cost(s[j - 1], s[j - 2] if j > 1 else None)
    for i in range(1, n + 1):
        for j in range(1, m + 1):
            d[i][j] = min(d[i - 1][j] + indel_cost(t[i - 1], t[i - 2] if i > 1 else None),
                          d[i][j - 1] + indel_cost(s[j - 1], s[j - 2] if j > 1 else None),
                          d[i - 1][j - 1] + sub_cost(t[i - 1], s[j - 1]))
    return d[n][m]


def _score(t: list, s: list) -> float:
    n, m = len(t), len(s)
    if n == 0 or m == 0:
        return 0.0
    best = 0.0
    for size in range(max(1, n - 1), n + 2):
        for start in range(0, max(1, m - size + 1)):
            window = s[start:start + size]
            penalty = EXTRA_PENALTY * max(0, m - len(window) - FREE_EXTRA_MORAE)
            best = max(best, 1.0 - _edit_distance(t, window) / n - penalty)
    return max(0.0, best)


@dataclass
class MatchResult:
    verdict: str
    score: float
    best_target: str = ""
    heard: str = field(default="")


def check(target: str, transcript: str, target_reading: str = "",
          alternates: tuple = ()) -> MatchResult:
    """target: the word as written (猫); target_reading: its kana (ねこ), from the
    word data, which beats any automatic reading."""
    heard_text = unicodedata.normalize("NFKC", transcript)
    heard = reading(transcript)
    best = MatchResult("fail", 0.0, heard=heard)
    candidates = [(target, to_hiragana(target_reading) if target_reading else reading(target))]
    candidates += [(a, reading(a)) for a in alternates]
    for written, kana in candidates:
        if written and unicodedata.normalize("NFKC", written) in heard_text:
            return MatchResult("pass", 1.0, written, heard)
        if kana and kana in heard:
            return MatchResult("pass", 1.0, written, heard)
        score = _score(morae(kana), morae(heard))
        if score > best.score:
            best.score, best.best_target = score, written
    best.verdict = ("pass" if best.score >= PASS_SCORE
                    else "near" if best.score >= NEAR_SCORE else "fail")
    return best


if __name__ == "__main__":
    import sys
    if len(sys.argv) >= 3:
        r = check(sys.argv[1], sys.argv[2], sys.argv[3] if len(sys.argv) > 3 else "")
        print(f"{r.verdict.upper()}  score={r.score:.2f}  heard={r.heard}")
    else:
        print("usage: python japanese.py <target> <what was heard> [target reading]")
