"""Korean helpers (prototype, to be ported to Swift like matcher.py).

1. romanize(): Revised Romanization, the official system used on Korean
   road signs, with the sound changes it writes down (감사합니다 is
   'gamsahamnida', not 'gamsahapnida'; 같이 is 'gachi').
2. check(): forgiving speech matcher. Hangul is phonetic, so we compare what
   the recognizer heard letter by letter (consonant, vowel, final consonant)
   instead of character by character. Sounds most speakers merge (ㅐ/ㅔ) are
   nearly free; sounds learners commonly mix up (ㄱ/ㅋ/ㄲ) cost half.

Every Hangul syllable block is three parts: initial consonant + vowel +
optional final consonant (받침). 한 = ㅎ + ㅏ + ㄴ.
"""
import re
import unicodedata
from dataclasses import dataclass, field

# --- Hangul blocks -----------------------------------------------------------
INITIALS = "ㄱㄲㄴㄷㄸㄹㅁㅂㅃㅅㅆㅇㅈㅉㅊㅋㅌㅍㅎ"
VOWELS = "ㅏㅐㅑㅒㅓㅔㅕㅖㅗㅘㅙㅚㅛㅜㅝㅞㅟㅠㅡㅢㅣ"
FINALS = ["", "ㄱ", "ㄲ", "ㄳ", "ㄴ", "ㄵ", "ㄶ", "ㄷ", "ㄹ", "ㄺ", "ㄻ", "ㄼ", "ㄽ", "ㄾ",
          "ㄿ", "ㅀ", "ㅁ", "ㅂ", "ㅄ", "ㅅ", "ㅆ", "ㅇ", "ㅈ", "ㅊ", "ㅋ", "ㅌ", "ㅍ", "ㅎ"]


def is_hangul(ch: str) -> bool:
    return "가" <= ch <= "힣"


def split(ch: str) -> tuple:
    """'한' -> ('ㅎ', 'ㅏ', 'ㄴ')."""
    code = ord(ch) - 0xAC00
    return INITIALS[code // 588], VOWELS[(code % 588) // 28], FINALS[code % 28]


# --- Revised Romanization ----------------------------------------------------
R_INITIAL = dict(zip(INITIALS, ["g", "kk", "n", "d", "tt", "r", "m", "b", "pp", "s", "ss", "",
                                "j", "jj", "ch", "k", "t", "p", "h"]))
R_VOWEL = dict(zip(VOWELS, ["a", "ae", "ya", "yae", "eo", "e", "yeo", "ye", "o", "wa", "wae",
                            "oe", "yo", "u", "wo", "we", "wi", "yu", "eu", "ui", "i"]))
# How each final sounds at the end of a syllable (before a consonant).
FINAL_SOUND = {"": "", "ㄱ": "k", "ㄲ": "k", "ㄳ": "k", "ㄴ": "n", "ㄵ": "n", "ㄶ": "n",
               "ㄷ": "t", "ㄹ": "l", "ㄺ": "k", "ㄻ": "m", "ㄼ": "l", "ㄽ": "l", "ㄾ": "l",
               "ㄿ": "p", "ㅀ": "l", "ㅁ": "m", "ㅂ": "p", "ㅄ": "p", "ㅅ": "t", "ㅆ": "t",
               "ㅇ": "ng", "ㅈ": "t", "ㅊ": "t", "ㅋ": "k", "ㅌ": "t", "ㅍ": "p", "ㅎ": "t"}
# Double finals: the first part stays, the second moves to a following vowel.
DOUBLE_FINAL = {"ㄳ": ("ㄱ", "ㅅ"), "ㄵ": ("ㄴ", "ㅈ"), "ㄶ": ("ㄴ", "ㅎ"), "ㄺ": ("ㄹ", "ㄱ"),
                "ㄻ": ("ㄹ", "ㅁ"), "ㄼ": ("ㄹ", "ㅂ"), "ㄽ": ("ㄹ", "ㅅ"), "ㄾ": ("ㄹ", "ㅌ"),
                "ㄿ": ("ㄹ", "ㅍ"), "ㅀ": ("ㄹ", "ㅎ"), "ㅄ": ("ㅂ", "ㅅ")}
ASPIRATED = {"ㄱ": "k", "ㄷ": "t", "ㅈ": "ch"}


def _romanize_word(word: str) -> str:
    """Romanize a run of Hangul syllables, applying sound changes across them."""
    parts = [split(ch) for ch in word]
    # Romanized initials; a syllable can rewrite the next one's (linking, sound changes).
    initial = [R_INITIAL[p[0]] for p in parts]
    out = []
    for i, (ini, vow, fin) in enumerate(parts):
        nxt = parts[i + 1] if i + 1 < len(parts) else None
        out.append(initial[i])
        out.append(R_VOWEL[vow])
        if not fin:
            continue
        if nxt is None:
            out.append(FINAL_SOUND[fin])
            continue
        n_ini = nxt[0]
        if n_ini == "ㅇ" and fin != "ㅇ":
            # Linking: the final moves onto the next syllable's vowel.
            stay, move = DOUBLE_FINAL.get(fin, ("", fin))
            if move == "ㅎ":
                move = ""  # 좋아 joa, 많아 mana: ㅎ goes silent before a vowel
            if stay:
                out.append(FINAL_SOUND[stay])
            if move in ("ㄷ", "ㅌ") and nxt[1] == "ㅣ":
                initial[i + 1] = "j" if move == "ㄷ" else "ch"  # palatalization: 같이 gachi
            else:
                initial[i + 1] = "r" if move == "ㄹ" else R_INITIAL.get(move, "")
            continue
        sound = FINAL_SOUND[fin]
        if fin in ("ㅎ", "ㄶ", "ㅀ") and n_ini in ASPIRATED:
            # Aspiration: 좋다 jota, 많다 manta.
            out.append({"ㅎ": "", "ㄶ": "n", "ㅀ": "l"}[fin])
            initial[i + 1] = ASPIRATED[n_ini]
            continue
        if n_ini in ("ㄴ", "ㅁ") and sound in ("k", "t", "p"):
            sound = {"k": "ng", "t": "n", "p": "m"}[sound]  # nasalization: 합니다 hamnida
        elif n_ini == "ㄹ":
            if sound in ("n", "l"):
                sound, initial[i + 1] = "l", "l"  # 신라 silla, 설령 seollyeong
            elif sound in ("m", "ng"):
                initial[i + 1] = "n"  # 종로 jongno
            elif sound in ("k", "t", "p"):
                sound = {"k": "ng", "t": "n", "p": "m"}[sound]
                initial[i + 1] = "n"  # 국립 gungnip
        elif n_ini == "ㄴ" and sound == "l":
            initial[i + 1] = "l"  # 설날 seollal
        out.append(sound)
    return "".join(out)


def romanize(text: str, capitalize: bool = False) -> str:
    """Romanize text; non-Hangul characters (spaces, punctuation) pass through.
    A ^ before a word marks a name: ^서울에 -> Seoure."""
    def word(m):
        r = _romanize_word(m.group(2))
        return r[:1].upper() + r[1:] if m.group(1) else r
    out = re.sub(r"(\^?)([가-힣]+)", word, text)
    return out[:1].upper() + out[1:] if capitalize else out


# --- Numbers -------------------------------------------------------------------
SINO = ["영", "일", "이", "삼", "사", "오", "육", "칠", "팔", "구"]


def sino_number(n: int) -> str:
    """12 -> 십이, 300 -> 삼백 (Sino-Korean, how recognizers' digits are read)."""
    if n == 0:
        return "영"
    out = ""
    for value, name in ((1000, "천"), (100, "백"), (10, "십")):
        d, n = divmod(n, value)
        if d:
            out += ("" if d == 1 else SINO[d]) + name
    return out + (SINO[n] if n else "")


def normalize(text: str) -> str:
    """Hangul only; digits become Sino-Korean words (recognizers write '3' for 삼)."""
    text = unicodedata.normalize("NFC", unicodedata.normalize("NFKC", text))
    text = re.sub(r"\d+", lambda m: sino_number(int(m.group(0))) if len(m.group(0)) < 5 else "", text)
    return "".join(ch for ch in text if is_hangul(ch))


# --- Matcher -------------------------------------------------------------------
PASS_SCORE = 0.85
NEAR_SCORE = 0.70
FREE_EXTRA_SYLLABLES = 2
EXTRA_PENALTY = 0.10

MERGED_VOWELS = [{"ㅐ", "ㅔ"}, {"ㅙ", "ㅚ", "ㅞ"}, {"ㅒ", "ㅖ"}]   # most speakers say these the same
CONFUSABLE_VOWELS = [{"ㅓ", "ㅗ"}, {"ㅡ", "ㅜ"}, {"ㅕ", "ㅛ"}, {"ㅢ", "ㅣ"}]
CONFUSABLE_INITIALS = [{"ㄱ", "ㅋ", "ㄲ"}, {"ㄷ", "ㅌ", "ㄸ"}, {"ㅂ", "ㅍ", "ㅃ"},
                       {"ㅈ", "ㅊ", "ㅉ"}, {"ㅅ", "ㅆ"}, {"ㄹ", "ㄴ"}]
MERGED_COST = 0.1
CONFUSABLE_COST = 0.5


def _in_pair(a, b, groups) -> bool:
    return any(a in g and b in g for g in groups)


def syllable_cost(t: str, s: str) -> float:
    (ti, tv, tf), (si, sv, sf) = split(t), split(s)
    cost = 0.0
    if ti != si:
        cost += CONFUSABLE_COST if _in_pair(ti, si, CONFUSABLE_INITIALS) else 1.0
    if tv != sv:
        cost += (MERGED_COST if _in_pair(tv, sv, MERGED_VOWELS)
                 else CONFUSABLE_COST if _in_pair(tv, sv, CONFUSABLE_VOWELS) else 1.0)
    if tf != sf:
        # Finals that end in the same sound (ㅅ/ㄷ/ㅈ all end in 't') are spelling, not speech.
        same_sound = FINAL_SOUND[tf] == FINAL_SOUND[sf]
        nasal = {FINAL_SOUND[tf], FINAL_SOUND[sf]} <= {"n", "ng", "m"}
        cost += 0.1 if same_sound else CONFUSABLE_COST if nasal else 1.0
    return min(1.0, cost)


def _edit_distance(target: str, heard: str) -> float:
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


def _score(target: str, heard: str) -> float:
    n, m = len(target), len(heard)
    if n == 0 or m == 0:
        return 0.0
    best = 0.0
    for size in range(max(1, n - 1), n + 2):
        for start in range(0, max(1, m - size + 1)):
            window = heard[start:start + size]
            penalty = EXTRA_PENALTY * max(0, m - len(window) - FREE_EXTRA_SYLLABLES)
            best = max(best, 1.0 - _edit_distance(target, window) / n - penalty)
    return max(0.0, best)


@dataclass
class MatchResult:
    verdict: str
    score: float
    best_target: str = ""
    heard: str = field(default="")


def check(target: str, transcript: str, alternates: tuple = ()) -> MatchResult:
    heard = normalize(transcript)
    best = MatchResult("fail", 0.0, heard=heard)
    for candidate in (target, *alternates):
        t = normalize(candidate)
        if t and t in heard:
            return MatchResult("pass", 1.0, candidate, heard)
        score = _score(t, heard)
        if score > best.score:
            best.score, best.best_target = score, candidate
    best.verdict = ("pass" if best.score >= PASS_SCORE
                    else "near" if best.score >= NEAR_SCORE else "fail")
    return best


if __name__ == "__main__":
    import sys
    if len(sys.argv) >= 3:
        r = check(sys.argv[1], sys.argv[2])
        print(f"{r.verdict.upper()}  score={r.score:.2f}  heard={r.heard}")
    else:
        print("usage: python korean.py <target> <what was heard>")
