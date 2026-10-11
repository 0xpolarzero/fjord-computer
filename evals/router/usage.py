"""How many Jev calls the eval caches hold, and their input tokens. python3 usage.py CACHE_DIR [CACHE_DIR...]"""
import json
import pathlib
import sys


def main():
    total_calls = total_tokens = 0
    for d in sys.argv[1:]:
        calls = tokens = 0
        for p in pathlib.Path(d).rglob("*.json"):
            try:
                j = json.loads(p.read_text())
            except (json.JSONDecodeError, OSError):
                continue
            calls += 1
            tokens += (j.get("usage") or {}).get("input_tokens", 0)
        print(f"{d}: {calls} calls, {tokens:,} input tokens")
        total_calls += calls
        total_tokens += tokens
    print(f"total: {total_calls} calls, {total_tokens:,} input tokens, ≈ ${total_tokens * 0.042 / 1e6:.2f} at $0.042/M")


if __name__ == "__main__":
    main()
