"""Curate the written episodes (stage B2) into one file the labeller and runner read.

    python3 v2/build/curate_written.py      reads v2/data/episodes/raw/written_{claude,gpt,gemini}.jsonl,
                                            writes v2/data/episodes/raw/written.jsonl and prints what it did

- A rewrite whose packet asked for French but whose real message was English is dropped: the writer translated a real
  message, so the episode no longer stands for anything you typed.
- A rewrite whose first submit is the real message word for word is kept (its follow-ups are new), but that submit is
  marked `duplicate_of_real`: the real episode already scores it, and counting it twice would weight it double.
- `off-spec` episodes (the writer couldn't fit the packet's flow to the board) are kept as realistic episodes, but
  their packet family isn't counted as covered.
"""
import collections
import json
import pathlib
import re
import sys

V2 = pathlib.Path(__file__).resolve().parents[1]
RAW = V2 / "data/episodes/raw"
FAMILIES = ("claude", "gpt", "gemini")
FRENCH = re.compile(r"\b(je|tu|le|la|les|des|est|pas|merci|ça|c'est|oui|non|avec|pour|fais|vas|peux|stp|svp)\b", re.I)


def words(text):
    return re.sub(r"[^\w\s]", " ", (text or "").lower()).split()


def is_french(text):
    return len(FRENCH.findall(text or "")) >= max(1, len(words(text)) // 6)


def task_of(episode):
    task = episode["provenance"].get("task") or {}
    return task if isinstance(task, dict) else {}


def curate(episode, counts):
    provenance, tags = episode["provenance"], episode.get("tags") or {}
    real = task_of(episode).get("real_message")
    submits = [e for e in episode["events"] if e.get("kind") == "submit"]
    if provenance.get("mode") == "rewrite" and real:
        if not is_french(real) and submits and is_french(submits[0].get("message")):
            counts["dropped: translated an English real message into French"] += 1
            return None
        if submits and words(submits[0].get("message")) == words(real):
            submits[0]["duplicate_of_real"] = True
            counts["kept: first submit marked duplicate_of_real"] += 1
    if any(str(s).startswith("off-spec") for s in tags.get("slices") or []):
        tags["covers_packet_family"] = False
        counts["kept: off-spec, family not counted as covered"] += 1
    counts["kept"] += 1
    return episode


def main():
    counts, out = collections.Counter(), []
    for family in FAMILIES:
        path = RAW / f"written_{family}.jsonl"
        if not path.exists():
            continue
        seen = set()
        for line in path.open():
            if not line.strip():
                continue
            episode = json.loads(line)
            if episode["id"] in seen:
                counts["dropped: duplicate id"] += 1
                continue
            seen.add(episode["id"])
            counts[f"read {family}"] += 1
            if (kept := curate(episode, counts)) is not None:
                out.append(kept)
    with (RAW / "written.jsonl").open("w") as f:
        f.writelines(json.dumps(e, ensure_ascii=False) + "\n" for e in out)
    json.dump(dict(sorted(counts.items())), sys.stdout, indent=1)
    print()


if __name__ == "__main__":
    main()
