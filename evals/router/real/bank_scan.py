"""Long digit runs near banking words, and which derived files hold them. Prints counts only, never the numbers.
python3 real/bank_scan.py FILE [FILE...]"""
import pathlib
import re
import sys

HERE = pathlib.Path(__file__).parent
DIGITS = re.compile(r"\d[\d ]{8,}\d")
BANK = re.compile(r"(?i)\b(iban|rib|bic|swift|compte|account|bank|banque|routing|sort code|virement|facture|invoice)\b")


def bank_numbers(text):
    out = set()
    for m in DIGITS.finditer(text):
        digits = m.group(0).replace(" ", "")
        if len(digits) < 9:
            continue
        window = text[max(0, m.start() - 120): m.end() + 40]
        if BANK.search(window):
            out.add(digits)
    return out


def main():
    raw = bank_numbers((HERE / "data" / "corpus.jsonl").read_text(errors="replace"))
    print("digit runs near banking words in the raw corpus:", len(raw))
    for name in sys.argv[1:]:
        p = pathlib.Path(name)
        if not p.exists():
            print(name, "missing")
            continue
        flat = p.read_text(errors="replace").replace(" ", "")
        print(f"{name}: holds {sum(1 for n in raw if n in flat)} of them")


if __name__ == "__main__":
    main()
