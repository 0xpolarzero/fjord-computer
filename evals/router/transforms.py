"""Case transforms for robustness runs."""
import copy
import random
import re

import run

_POOL = None


def words(text):
    return {w for w in re.findall(r"[a-zà-ÿ0-9]+", text.lower()) if len(w) >= 4}


def pool():
    """Idle sessions from every case, one per title."""
    global _POOL
    if _POOL is None:
        seen, out = set(), []
        for c in run.load_cases():
            for s in c["board"]["sessions"]:
                if s["title"].lower() not in seen:
                    seen.add(s["title"].lower())
                    out.append(s)
        _POOL = out
    return _POOL


def pad(case, size=22, seed=0):
    """The board padded to `size` sessions with idle sessions of other cases that share no word with the message or
    with any session or card already on the board (so they can't be a right answer)."""
    c = copy.deepcopy(case)
    b = c["board"]
    taken = words(c["message"])
    titles = {s["title"].lower() for s in b["sessions"]}
    for s in b["sessions"]:
        taken |= words(s["title"])
    rng = random.Random(f"{case['id']}-{seed}")
    candidates = [s for s in pool() if s["title"].lower() not in titles and not (words(s["title"]) & taken)]
    rng.shuffle(candidates)
    for i, s in enumerate(candidates[:max(0, size - len(b["sessions"]))]):
        f = copy.deepcopy(s)
        f["id"] = f"pad{i}"
        f["running"] = False
        f["activity"] = ""
        f["idle_min"] = max(f.get("idle_min", 0), rng.choice([45, 90, 200, 600, 1500, 3000]))
        b["sessions"].append(f)
        if f["project"] not in b["projects"]:
            b["projects"].append(f["project"])
    return c
