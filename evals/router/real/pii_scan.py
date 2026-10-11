"""Which files hold account numbers (IBAN-like) found in the raw corpus. Prints counts only, never the numbers.
python3 real/pii_scan.py FILE [FILE...]"""
import pathlib
import re
import sys

HERE = pathlib.Path(__file__).parent
IBAN = re.compile(r"\b[A-Z]{2}\d{2}(?:\s?[A-Z0-9]{4}){3,7}\s?[A-Z0-9]{1,4}\b")


def numbers(text):
    return {m.group(0).replace(" ", "") for m in IBAN.finditer(text) if sum(c.isdigit() for c in m.group(0)) >= 12}


def main():
    raw = numbers((HERE / "data" / "corpus.jsonl").read_text(errors="replace"))
    print("IBAN-like numbers in the raw corpus:", len(raw))
    for name in sys.argv[1:]:
        p = pathlib.Path(name)
        if not p.exists():
            print(name, "missing")
            continue
        flat = p.read_text(errors="replace").replace(" ", "")
        print(f"{name}: holds {sum(1 for n in raw if n in flat)} of them")


if __name__ == "__main__":
    main()
