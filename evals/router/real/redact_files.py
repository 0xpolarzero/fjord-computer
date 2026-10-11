"""Redact keys and tokens in case files in place (every string). python3 real/redact_files.py FILE [FILE...]"""
import json
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).parent))
from boards import redact  # noqa: E402


def walk(x):
    if isinstance(x, str):
        return redact(x)
    if isinstance(x, list):
        return [walk(v) for v in x]
    if isinstance(x, dict):
        return {k: walk(v) for k, v in x.items()}
    return x


def main():
    for f in sys.argv[1:]:
        lines = [l for l in open(f) if l.strip()]
        out = [json.dumps(walk(json.loads(l)), ensure_ascii=False) for l in lines]
        changed = sum(a.strip() != b for a, b in zip(lines, out))
        open(f, "w").write("\n".join(out) + "\n")
        print(f, "cases changed:", changed)


if __name__ == "__main__":
    main()
