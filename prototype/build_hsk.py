"""Adds one HSK level to data/packs.json and data/words.zh-CN.json.

Usage:  python build_hsk.py 2        (reads data/source/hsk2.txt)

The source file is written by hand, one section at a time:

    ## theme | Section title
    hanzi | pinyin | English | emoji | example, words split by spaces | example in English | id (optional)

- The example's pinyin is generated here (word by word, with the tone changes
  of 一 and 不), so only the words need typing. Force a reading with 还{hái}
  (several characters: 银行{yín háng}); capitalize a name with ^北京.
- Checks: every word of the official list (data/source/hsk2.0/<n>.min.json)
  appears exactly once and nothing else does; ids and emoji stay unique.
- Running it again replaces that level's sections, so edits are safe.
"""
import json
import re
import sys
import unicodedata
from pathlib import Path

from pypinyin import Style, pinyin

ROOT = Path(__file__).parent.parent
DATA = ROOT / "data"
PUNCT = {"，": ",", "。": ".", "？": "?", "！": "!", "、": ",", "：": ":"}
MARKS = {1: "̄", 2: "́", 3: "̌", 4: "̀"}


def render(base: str, tone: int) -> str:
    """'ping' + 2 -> 'píng' (tone mark on a/e, the o of ou, else the last vowel)."""
    base = base.replace("v", "ü")
    if tone not in MARKS:
        return base
    if "a" in base:
        i = base.index("a")
    elif "e" in base:
        i = base.index("e")
    elif "ou" in base:
        i = base.index("o")
    else:
        i = max(base.rfind(v) for v in "aeiouü")
    return unicodedata.normalize("NFC", base[:i + 1] + MARKS[tone] + base[i + 1:])


def syllables(token: str):
    """[(char, base, tone)] for a word, using an explicit {reading} if given."""
    m = re.fullmatch(r"\^?([一-鿿]+)\{(.+)\}", token)
    if m:
        chars, written = m.group(1), m.group(2)
        out = []
        for ch, syl in zip(chars, written.split()):
            nfd = unicodedata.normalize("NFD", syl)
            tone = next((t for t, mk in MARKS.items() if mk in nfd), 5)
            base = "".join(c for c in nfd if c not in MARKS.values()).replace("ü", "v")
            out.append((ch, unicodedata.normalize("NFC", base), tone))
        return out
    chars = token.lstrip("^")
    out = []
    for ch, (item,) in zip(chars, pinyin(chars, style=Style.TONE3, neutral_tone_with_five=True)):
        mm = re.fullmatch(r"([a-zü]+)([1-5])", item.replace("ü", "v"))
        out.append((ch, mm.group(1), int(mm.group(2))) if mm else (ch, item, 5))
    if chars == "个":
        return [("个", "ge", 5)]  # the measure word is said lightly: yí ge
    return use_known_tones(chars, out)


KNOWN = {}  # word -> its dictionary pinyin from the app's data (fills in neutral tones)


def use_known_tones(chars, out):
    """If the word is in the app's data, copy the tones from its pinyin, so
    sentences match the flashcards (衣服 yīfu, not yīfú)."""
    known = KNOWN.get(chars)
    if not known:
        return out
    letters = unicodedata.normalize("NFD", known.lower())
    letters = [c for c in letters if c.isalpha() or c in MARKS.values() or c == "\u0308"]
    fixed, k = [], 0
    for ch, base, _ in out:
        want = base.replace("v", "u\u0308")
        tone, got = 5, ""
        while k < len(letters) and len(got) < len(want):
            c = letters[k]
            if c in MARKS.values():
                tone = next(t for t, mk in MARKS.items() if mk == c)
            else:
                got += c
            k += 1
        while k < len(letters) and letters[k] in MARKS.values():
            tone = next(t for t, mk in MARKS.items() if mk == letters[k])
            k += 1
        if got != want:
            return out  # couldn't line them up: keep the library's reading
        fixed.append((ch, base, tone))
    return fixed if k == len(letters) else out


def sentence_pinyin(tokens: list) -> str:
    """Pinyin for a sentence typed as space-separated words."""
    parts = []  # each: ("word", capitalize?, [syllables]) or ("punct", text)
    for token in tokens:
        for piece in re.split(r"([，。？！、：])", token):
            if not piece:
                continue
            if piece in PUNCT:
                parts.append(("punct", PUNCT[piece]))
            else:
                parts.append(("word", piece.startswith("^"), syllables(piece)))
    flat = [s for p in parts if p[0] == "word" for s in p[2]]
    # Tone changes: 不 before a 4th tone -> bú; 一 before a 4th -> yí, before
    # 1st-3rd -> yì, but 第一/十一 and a final 一 keep yī.
    fixed, k = [], 0
    for i, (ch, base, tone) in enumerate(flat):
        nxt = flat[i + 1][2] if i + 1 < len(flat) else None
        if i + 1 < len(flat) and flat[i + 1][0] == "个":
            nxt = 4  # 个 is a light 4th tone: 一个 yí ge
        prev = flat[i - 1][0] if i > 0 else ""
        if ch == "不" and nxt == 4:
            tone = 2
        if ch == "一" and nxt is not None and prev not in "第十":
            tone = 2 if nxt == 4 else 4 if nxt in (1, 2, 3) else tone
        fixed.append((ch, base, tone))
    out, first = "", True
    for p in parts:
        if p[0] == "punct":
            out = out.rstrip() + p[1] + " "
            continue
        n = len(p[2])
        word = "".join(render(b, t) for _, b, t in fixed[k:k + n])
        k += n
        name = "".join(ch for ch, _, _ in fixed[k - n:k])
        if p[1] or first or KNOWN.get(name, "")[:1].isupper():  # names keep their capital: Hànyǔ
            word = word[:1].upper() + word[1:]
        first = False
        out += word + " "
    return out.strip()


def slug(text: str) -> str:
    text = re.split(r"[,;(]", text)[0]
    return re.sub(r"[^a-z0-9]+", "-", text.lower()).strip("-")


def main(level: int):
    source = (DATA / f"source/hsk{level}.txt").read_text(encoding="utf-8")
    official = [e["s"] for e in json.loads((DATA / f"source/hsk2.0/{level}.min.json").read_text(encoding="utf-8"))]
    packs_file = json.loads((DATA / "packs.json").read_text(encoding="utf-8"))
    words_file = json.loads((DATA / "words.zh-CN.json").read_text(encoding="utf-8"))

    # Replace this level's sections if they're already there.
    old_ids = {p["id"] for p in packs_file["packs"] if p.get("hsk") == level}
    old_concepts = {c["id"] for c in packs_file["concepts"] if c["packId"] in old_ids}
    packs_file["packs"] = [p for p in packs_file["packs"] if p["id"] not in old_ids]
    packs_file["concepts"] = [c for c in packs_file["concepts"] if c["id"] not in old_concepts]
    words_file["words"] = [w for w in words_file["words"] if w["conceptId"] not in old_concepts]
    used_ids = {c["id"] for c in packs_file["concepts"]}
    KNOWN.update({w["text"]: w["pinyin"] for w in words_file["words"]})
    for line in source.splitlines():
        cols = [c.strip() for c in line.split("|")]
        if len(cols) >= 6 and not line.startswith("#"):
            KNOWN[cols[0]] = cols[1]
    used_emoji = {c["emoji"]: c["id"] for c in packs_file["concepts"] if c.get("emoji")}

    packs, concepts, words, seen, problems = [], [], [], [], []
    for line in source.splitlines():
        line = line.strip()
        if not line or line.startswith("#!"):
            continue
        if line.startswith("##"):
            theme, title = [x.strip() for x in line[2:].split("|")]
            packs.append({"id": f"hsk{level}-{len(packs) + 1:02d}", "theme": theme, "level": level,
                          "hsk": level, "order": len(packs) + 1, "title": title,
                          "tier": "free" if level == 1 else "premium"})
            continue
        cols = [c.strip() for c in line.split("|")]
        if len(cols) not in (6, 7):
            problems.append(f"needs 6 or 7 columns: {line}")
            continue
        text, py, english, emoji, example, example_en = cols[:6]
        cid = cols[6] if len(cols) == 7 and cols[6] else slug(english) or slug(py)
        base, n = cid, 2
        while cid in used_ids:
            cid, n = f"{base}-{n}", n + 1
        used_ids.add(cid)
        if emoji:
            if emoji in used_emoji:
                problems.append(f"emoji {emoji} on {text} is already used by {used_emoji[emoji]}")
            used_emoji[emoji] = cid
        tokens = re.findall(r"\S+?\{[^}]*\}\S*|\S+", example)  # keep 银行{yín háng} together
        ex_text = "".join(t.lstrip("^") for t in tokens)
        ex_text = re.sub(r"\{[^}]*\}", "", ex_text)
        seen.append(text)
        concepts.append({"id": cid, "packId": packs[-1]["id"], "english": english, "emoji": emoji or None})
        words.append({"conceptId": cid, "text": text, "pinyin": py,
                      "example": {"text": ex_text, "pinyin": sentence_pinyin(tokens), "english": example_en}})

    missing = [w for w in official if w not in seen]
    extra = [w for w in seen if w not in official]
    twice = sorted({w for w in seen if seen.count(w) > 1})
    if missing: problems.append(f"official words missing: {' '.join(missing)}")
    if extra: problems.append(f"not in the official list: {' '.join(extra)}")
    if twice: problems.append(f"listed twice: {' '.join(twice)}")
    for p in problems:
        print("PROBLEM:", p)
    if problems:
        sys.exit(1)

    packs_file["packs"] += packs
    packs_file["concepts"] += concepts
    words_file["words"] += words
    for name, obj in (("packs.json", packs_file), ("words.zh-CN.json", words_file)):
        (DATA / name).write_text(json.dumps(obj, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    print(f"HSK {level}: {len(packs)} sections, {len(words)} words")


if __name__ == "__main__":
    main(int(sys.argv[1]))
