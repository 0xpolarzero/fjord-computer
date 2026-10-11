"""Where in moments.jsonl the bank-context numbers sit (field paths only), and whether triage sent that text to Jev.
python3 real/bank_where.py"""
import json
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).parent))
from bank_scan import bank_numbers  # noqa: E402

HERE = pathlib.Path(__file__).parent


def walk(x, path, hits, nums):
    if isinstance(x, str):
        flat = x.replace(" ", "")
        if any(n in flat for n in nums):
            hits.add(path)
    elif isinstance(x, dict):
        for k, v in x.items():
            walk(v, f"{path}.{k}", hits, nums)
    elif isinstance(x, list):
        for v in x:
            walk(v, f"{path}[]", hits, nums)


def main():
    nums = bank_numbers((HERE / "data" / "corpus.jsonl").read_text(errors="replace"))
    hits, moments = set(), 0
    for line in open(HERE.parent / "v2" / "data" / "states" / "moments.jsonl"):
        before = len(hits)
        walk(json.loads(line), "", hits, nums)
        moments += len(hits) > before
    print("fields:", sorted(hits))
    triage = HERE.parent / "v2" / "build" / "triage.py"
    print("triage.py redacts digits:", "NUMBERS" in triage.read_text() or "\\d{9" in triage.read_text())


if __name__ == "__main__":
    main()
