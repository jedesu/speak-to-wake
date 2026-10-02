import json
from pathlib import Path

import pytest

from matcher import check

CASES = json.loads((Path(__file__).parent / "cases.json").read_text(encoding="utf-8"))


@pytest.mark.parametrize("case", CASES, ids=[c["note"] for c in CASES])
def test_case(case):
    result = check(case["target"], case["heard"],
                   target_pinyin=case.get("target_pinyin", ""),
                   alternates=tuple(case.get("alternates", [])))
    assert result.verdict == case["expect"], (
        f"score={result.score:.2f} heard={result.heard_pinyin}")
