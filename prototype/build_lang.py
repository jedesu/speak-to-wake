"""Builds data/words.<language>.json for Korean or Japanese from a hand-written
source file, reusing the shared sections in data/packs.json.

Usage:  python build_lang.py ko-KR      (reads data/source/ko-KR.txt)
        python build_lang.py ja-JP      (reads data/source/ja-JP.txt)

See the header of each source file for the line format. Checks:
- every concept of each section in the file is translated or skipped (with a reason)
- words are unique, readings are kana (Japanese) / text is Hangul (Korean)
- concepts only some languages have ("+id") are added to packs.json, tagged
  with "languages", so Mandarin isn't expected to have them.
Romanization (Korean) and romaji + example readings (Japanese) are generated.
Running it again rebuilds the file, so edits are safe.
"""
import json
import re
import sys
from pathlib import Path

import japanese
import korean

ROOT = Path(__file__).parent.parent
DATA = ROOT / "data"
PUNCT_JA = set("、。！？「」")


def parse(path: Path, lang: str):
    """-> list of (pack_id, kind, fields) with kind in 'word', 'new', 'skip'."""
    rows, pack = [], None
    width = 8 if lang == "ja-JP" else 7
    for n, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        line = raw.strip()
        if not line or line.startswith("#!"):
            continue
        if line.startswith("## "):
            pack = line[3:].strip()
            continue
        if pack is None:
            raise SystemExit(f"{path.name}:{n}: line before the first '## section'")
        if line.startswith("- "):
            cid, _, reason = line[2:].partition("|")
            rows.append((pack, "skip", [cid.strip(), reason.strip()], n))
            continue
        fields = [f.strip() for f in line.split("|")]
        if len(fields) != width:
            raise SystemExit(f"{path.name}:{n}: expected {width} columns, got {len(fields)}")
        kind = "new" if fields[0].startswith("+") else "word"
        fields[0] = fields[0].lstrip("+")
        rows.append((pack, kind, fields, n))
    return rows


def split_alternates(cell: str) -> list:
    return [a.strip() for a in cell.split(",") if a.strip()]


def japanese_example(sentence: str):
    """'今日{きょう} は 月曜日 です 。' -> (text, reading, romaji)."""
    text, kana, roma = [], [], []
    for token in sentence.split():
        name = token.startswith("^")  # a name: capitalize its romaji
        token = token.lstrip("^")
        m = re.fullmatch(r"(.+?)\{(.+)\}", token)
        written, forced = (m.group(1), m.group(2)) if m else (token, "")
        text.append(written)
        if all(c in PUNCT_JA for c in written):
            kana.append(written)
            mark = {"、": ",", "。": ".", "！": "!", "？": "?"}.get(written, "")
            if roma:
                roma[-1] += mark
            continue
        reading = forced or japanese.reading(written)
        kana.append(reading)
        r = japanese.PARTICLES.get(written) or japanese.romaji_of_kana(reading)
        roma.append(r[:1].upper() + r[1:] if name else r)
    sentence_romaji = " ".join(roma)
    return "".join(text), "".join(kana), sentence_romaji[:1].upper() + sentence_romaji[1:]


def word_romaji(text: str, reading: str) -> str:
    """Particles are spelled as said: を -> o (its reading を would give 'wo')."""
    return japanese.PARTICLES.get(text) or japanese.romaji_of_kana(reading)


def build(lang: str):
    src = DATA / "source" / f"{lang}.txt"
    packs_path = DATA / "packs.json"
    packs_file = json.loads(packs_path.read_text(encoding="utf-8"))
    packs = {p["id"]: p for p in packs_file["packs"]}
    concepts = packs_file["concepts"]
    by_id = {c["id"]: c for c in concepts}

    rows = parse(src, lang)
    errors, words, skipped, seen_text = [], [], {}, {}

    # Every concept of every section in the file must be covered exactly once.
    sections = sorted({pack for pack, *_ in rows}, key=lambda p: list(packs).index(p) if p in packs else 999)
    for pack in sections:
        if pack not in packs:
            errors.append(f"unknown section {pack}")
            continue
        listed = [f[0] for p, kind, f, _ in rows if p == pack and kind != "new"]
        shared = [c["id"] for c in concepts if c["packId"] == pack and "languages" not in c]
        missing = [c for c in shared if c not in listed]
        extra = [c for c in listed if c not in shared]
        dupes = {c for c in listed if listed.count(c) > 1}
        for label, items in (("missing", missing), ("not in this section", extra), ("listed twice", dupes)):
            if items:
                errors.append(f"{pack}: {label}: {', '.join(sorted(items))}")

    # Concepts only some languages have: add or tag them in packs.json.
    for pack, kind, f, n in rows:
        if kind != "new":
            continue
        cid, meaning = f[0], (f[3] if lang == "ja-JP" else f[2])
        if not meaning:
            errors.append(f"line {n}: new concept {cid} needs a meaning")
            continue
        c = by_id.get(cid)
        if c is None:
            c = {"id": cid, "packId": pack, "english": meaning, "emoji": None, "languages": [lang]}
            last = max(i for i, x in enumerate(concepts) if x["packId"] == pack)
            concepts.insert(last + 1, c)
            by_id[cid] = c
        elif "languages" not in c:
            errors.append(f"line {n}: {cid} is a shared concept; drop the '+'")
        elif c["packId"] != pack:
            errors.append(f"line {n}: {cid} belongs to {c['packId']}")
        elif lang not in c["languages"]:
            c["languages"].append(lang)

    for pack, kind, f, n in rows:
        if kind == "skip":
            if not f[1]:
                errors.append(f"line {n}: skipping {f[0]} needs a reason")
            skipped[f[0]] = f[1]
            continue
        if lang == "ja-JP":
            cid, text, reading, meaning, example, ex_en, alts, note = f
            if not re.fullmatch(r"[ぁ-ゖー]+", reading or ""):
                errors.append(f"line {n}: reading of {text} must be hiragana: {reading!r}")
            ex_text, ex_reading, ex_romaji = japanese_example(example)
            word = {"conceptId": cid, "text": text, "reading": reading,
                    "pinyin": word_romaji(text, reading)}
            ex = {"text": ex_text, "reading": ex_reading, "pinyin": ex_romaji, "english": ex_en}
        else:
            cid, text, meaning, example, ex_en, alts, note = f
            if not re.fullmatch(r"[가-힣 ]+", text):
                errors.append(f"line {n}: {text!r} should be Hangul only")
            word = {"conceptId": cid, "text": text, "pinyin": korean.romanize(text)}
            ex = {"text": example.replace("^", ""), "pinyin": korean.romanize(example, capitalize=True),
                  "english": ex_en}
        if not example or not ex_en:
            errors.append(f"line {n}: {text} needs an example and its English")
        if text in seen_text:
            errors.append(f"line {n}: {text} is already used for {seen_text[text]}")
        seen_text[text] = cid
        alternates = split_alternates(alts)
        if text in alternates:
            errors.append(f"line {n}: {text} lists itself as an alternate")
        if meaning:
            word["meaning"] = meaning
        if alternates:
            word["alternates"] = alternates
        if note:
            word["note"] = note
        word["example"] = ex
        words.append(word)

    if errors:
        raise SystemExit("\n".join(["Not built:"] + errors))

    out = {"language": lang, "words": words, "skipped": skipped}
    (DATA / f"words.{lang}.json").write_text(json.dumps(out, ensure_ascii=False, indent=1) + "\n",
                                            encoding="utf-8")
    packs_path.write_text(json.dumps(packs_file, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    print(f"{lang}: {len(words)} words in {len(sections)} sections, {len(skipped)} skipped")


if __name__ == "__main__":
    if len(sys.argv) != 2 or sys.argv[1] not in ("ko-KR", "ja-JP"):
        raise SystemExit("usage: python build_lang.py ko-KR|ja-JP")
    build(sys.argv[1])
