"""Downloads the flat Fluent Emoji picture for every word that has an emoji but
no picture yet, into the app's Pictures.xcassets (imageset "pic-<concept id>").

Usage:  python fetch_pictures.py

Pictures: Microsoft Fluent Emoji, MIT license (credited in the app's Settings).
Names are matched through the emoji's Unicode name; ALIASES covers the ones
Microsoft names differently. Words with no match keep showing their emoji.
"""
import json
import unicodedata
import urllib.parse
import urllib.request
from pathlib import Path

ROOT = Path(__file__).parent.parent
ASSETS = ROOT / "ios/SpeakToWake/SpeakToWake/Pictures.xcassets"
REPO = "https://raw.githubusercontent.com/microsoft/fluentui-emoji/main/"
TREE = "https://api.github.com/repos/microsoft/fluentui-emoji/git/trees/main?recursive=1"

# concept id -> Fluent Emoji folder name, where the Unicode name doesn't match.
ALIASES = {
    "hello": "waving hand", "thanks": "folded hands", "not": "prohibited", "i": "person raising hand",
    "you": "index pointing at the viewer", "person": "person standing",
    "one": "keycap 1", "two": "keycap 2", "three": "keycap 3", "four": "keycap 4", "five": "keycap 5",
    "six": "keycap 6", "seven": "keycap 7", "eight": "keycap 8", "nine": "keycap 9", "ten": "keycap 10",
    "zero": "keycap 0", "home": "house", "love": "red heart", "classmate": "student", "teacher": "teacher",
    "student": "backpack", "month": "spiral calendar", "noon": "twelve oclock", "go": "person walking",
    "return": "right arrow curving left", "open": "unlocked", "on": "up arrow", "under": "down arrow",
    "talk": "speaking head", "buy": "shopping cart", "like": "thumbs up", "computer": "laptop",
    "good": "ok hand", "cold": "cold face", "hot": "hot face", "character": "memo",
    # HSK 2-3
    "wife": "person with veil", "everyone": "raising hands", "delicious": "face savoring food",
    "waiter": "cook", "yuan-2": "dollar banknote", "hundred": "hundred points", "kilogram": "balance scale",
    "time": "hourglass done", "hour": "one oclock", "first": "1st place medal", "to-wash": "soap",
    "to-begin": "play button", "to-play-basketball": "basketball", "to-run": "person running",
    "to-swim": "person swimming", "to-dance": "woman dancing", "sport": "person lifting weights",
    "left-side": "left arrow", "right-side": "right arrow", "to-laugh": "grinning face with smiling eyes",
    "sunny": "sun", "white": "white circle", "black": "black circle", "red": "red circle", "tall": "giraffe",
    "new": "new button", "to-understand": "light bulb", "cell-phone": "mobile phone with arrow",
    "happy-2": "partying face", "fast": "high voltage", "to-look-for": "magnifying glass tilted left",
    "again": "repeat button", "grandma": "old woman", "grandpa": "old man", "neighbor": "houses",
    "colleague": "office worker", "hair": "person getting haircut", "sound": "speaker high volume",
    "shoe": "running shoe", "glasses": "glasses", "refrigerator": "ice", "light": "red paper lantern",
    "world": "globe showing europe-africa", "country": "white flag", "environment": "recycling symbol",
    "animal": "lion", "panda": "panda", "moon": "full moon", "to-blow": "wind face",
    "change": "counterclockwise arrows button", "half": "first quarter moon", "math": "input numbers",
    "grade-2": "a button (blood type)", "pencil": "crayon", "to-improve": "chart increasing",
    "to-solve": "puzzle piece", "to-end": "end arrow", "to-draw": "framed picture", "story": "fairy",
    "satisfied": "clapping hands", "to-care-about": "heart hands", "strange": "face with raised eyebrow",
    "cute": "smiling face with hearts", "famous": "star", "quiet": "shushing face",
    "important": "red exclamation mark", "yellow": "yellow circle", "blue": "blue circle",
    "green": "green circle", "to-pay-attention": "warning", "to-be-late": "hourglass not done",
    "gift": "wrapped gift",
}
# Unicode name -> Fluent name, for common differences.
NAME_FIXES = {
    "white heavy check mark": "check mark button", "heavy dollar sign": "dollar banknote",
}


def fluent_name(emoji: str) -> list:
    chars = [ch for ch in emoji if ch not in "️‍" and not (0x1F3FB <= ord(ch) <= 0x1F3FF)]
    names = []
    try:
        names.append(" ".join(unicodedata.name(ch) for ch in chars).lower())
        names.append(unicodedata.name(chars[0]).lower())
    except (ValueError, IndexError):
        pass
    return [NAME_FIXES.get(n, n) for n in names]


def main():
    tree = json.loads(urllib.request.urlopen(TREE, timeout=60).read())["tree"]
    by_folder = {}
    for item in tree:
        path = item["path"]
        if "/Flat/" in path and path.endswith(".svg"):
            by_folder.setdefault(path.split("/")[1].lower().replace("’", ""), []).append(path)

    concepts = json.loads((ROOT / "data/packs.json").read_text(encoding="utf-8"))["concepts"]
    added, missing = 0, []
    for c in concepts:
        if not c.get("emoji") or (ASSETS / f"pic-{c['id']}.imageset").exists():
            continue
        candidates = ([ALIASES[c["id"]]] if c["id"] in ALIASES else []) + fluent_name(c["emoji"])
        files = next((by_folder[n.replace("’", "")] for n in candidates if n.replace("’", "") in by_folder), None)
        if not files:
            missing.append(f"{c['id']} {c['emoji']} ({', '.join(candidates)})")
            continue
        path = next((f for f in files if "/Default/" in f), files[0])
        data = urllib.request.urlopen(REPO + urllib.parse.quote(path), timeout=30).read()
        folder = ASSETS / f"pic-{c['id']}.imageset"
        folder.mkdir(parents=True)
        (folder / f"{c['id']}.svg").write_bytes(data)
        (folder / "Contents.json").write_text(json.dumps({
            "images": [{"filename": f"{c['id']}.svg", "idiom": "universal"}],
            "info": {"author": "xcode", "version": 1},
            "properties": {"preserves-vector-representation": True},
        }, indent=2))
        added += 1
    print(f"{added} pictures added")
    for m in missing:
        print("no picture:", m)


if __name__ == "__main__":
    main()
