"""Two request variants of the shipped `combo-o` (A9 and A12 in v2/DIRECTIONS.md). Both build the shipped request first
(`formats.build("combo-o", case)`: same redaction, same option names, same order) and only remove or repeat parts of
it, so nothing new reaches Jev. `-fill` sends the same request as the plain shortlist.

- `combo-o-short<K>[-mix]` (A9): the route question offers only a shortlist of K sessions chosen by a prior (see
  `shortlist`), plus every new session and intent; cards' answer checks, the gates and the next-message checks are
  unchanged. Kept options stay in Lookout's order. The fusion then reranks among what was offered.
- `combo-o-2w` (A12): the route question asked a second time (`route2`) with differently worded instructions, the
  same options in the same order; `install_reading` averages the two answers' log-probabilities before the fusion."""
import math

import formats as F

# ---------------------------------------------------------------- A9: the shortlist prior


def _lists(case, bm=True):
    """Candidate session ids in priority lists, each best first (all from the visible board, no Jev)."""
    from explore import lexical as L
    board = case["board"]
    offered = [s["id"] for s in F.sessions_ordered(board)]            # what combo-o offers at all
    ok = set(offered)
    by_idle = sorted(board["sessions"], key=lambda s: (s.get("idle_min", 0), s["id"]))
    running = [s["id"] for s in by_idle if s.get("running") and s["id"] in ok]
    finished = [s["id"] for s in by_idle if not s.get("running") and s["id"] in ok]
    told = []
    for h in reversed(board.get("history", [])):                      # history is oldest first (adapter.to_case)
        if h["to"] in ok and h["to"] not in told:
            told.append(h["to"])
    waits = [c["session"] for c in reversed(F.waiting_cards(board)) if c["session"] in ok]
    lex = []
    if bm:
        sc = L.lex(case, L.STATE.get("cfg", L.LEX))
        lex = [d for d, x in sorted(sc.items(), key=lambda kv: (-kv[1], kv[0])) if x > 0 and d in ok]
    return {"offered": offered, "running": running, "fin": finished, "told": told, "waits": waits, "bm": lex}


# Slot rule: take from each list in turn (round robin by the weights below), dedupe, until K; when every list is spent,
# Lookout's own order fills. On dev recall (explore/v2_short/recall.py) no mix beat Lookout's order alone (working, then
# the latest finished): last-told, BM25, waiting cards add nothing a recency prefix doesn't hold. So the default rule
# is the empty one (a prefix of Lookout's order); MIX keeps one told and one BM25 slot per three by order, as a hedge.
ROUNDS = ()
MIX = (("offered", 3), ("told", 1), ("bm", 1))


def shortlist(case, k, bm=True, rounds=ROUNDS):
    ls = _lists(case, bm)
    out, idx = [], {name: 0 for name, _ in rounds}
    if len(ls["offered"]) <= k:
        return list(ls["offered"])
    while len(out) < k:
        moved = False
        for name, n in rounds:
            for _ in range(n):
                lst = ls[name]
                while idx[name] < len(lst) and lst[idx[name]] in out:
                    idx[name] += 1
                if idx[name] < len(lst) and len(out) < k:
                    out.append(lst[idx[name]])
                    idx[name] += 1
                    moved = True
        if not moved:                                                  # every prior list spent: Lookout's order fills
            for d in ls["offered"]:
                if d not in out and len(out) < k:
                    out.append(d)
            break
    return out


def short(k, bm=True, rounds=ROUNDS, fill=False):
    """fill: the sessions left out stay in the keymap (under `_off:` keys, never sent), and the reading gives them
    Jev's floor probability, so the fusion still ranks the whole board by recency, BM25 and the checks."""
    def build(case, rng=None):
        state, q, keymap = F.build("combo-o", case)
        keep = set(shortlist(case, k, bm, rounds))
        sessions = {s["id"] for s in case["board"]["sessions"]}
        removed = {n for n in q["route"]["criteria"] if keymap.get(n) in sessions and keymap[n] not in keep}
        crit = {n: c for n, c in q["route"]["criteria"].items() if n not in removed}
        q = {**q, "route": {**q["route"], "criteria": crit}}
        out = {n: d for n, d in keymap.items() if n not in removed}
        if fill:
            out.update({"_off:" + n: keymap[n] for n in removed})
        return state, q, out
    return build


# ---------------------------------------------------------------- A12: the route question in a second wording

# The shipped wording (RouterRoute.routeQuestion) says the same four things; this one says them in other words and
# another order, with no fact or rule added.
ROUTE2 = {
    "question": "Which of these destinations is the user's `message` meant for?",
    "focus": ("Judge `message` by itself: `earlier messages` only show what it points back to. When `message` asks "
              "about a session or about the current state (\"is the CI one done?\"), the destination is `question`, "
              "not that session. When it speaks to a session by name or nickname (\"tell the CI one to…\", "
              "\"lcu: …\"), it belongs to that existing session. Choose a new session only if the message asks for one, "
              "or if none of the existing sessions does that work."),
}


def two_wordings(case, rng=None):
    state, q, keymap = F.build("combo-o", case)
    q = {**q, "route2": {**q["route"], "instructions": ROUTE2}}
    return state, q, keymap


FLOOR = 1e-4


def average_route(answers):
    """route's probabilities replaced by the renormalised geometric mean of route's and route2's."""
    p1 = answers["route"].get("probabilities", {})
    p2 = answers["route2"].get("probabilities", {})
    keys = list(dict.fromkeys(list(p1) + list(p2)))
    g = {k: math.exp(0.5 * (math.log(max(p1.get(k, 0), FLOOR)) + math.log(max(p2.get(k, 0), FLOOR)))) for k in keys}
    z = sum(g.values()) or 1
    return {**answers, "route": {**answers["route"], "probabilities": {k: v / z for k, v in g.items()}}}


MODE = {"route": "avg"}            # avg | first | second: which route answer the reading uses (for offline checks)


def install_reading(run):
    """Wrap run.reading once: a row whose answers hold route2 is read through average_route (or one wording alone)."""
    if getattr(run.reading, "_two", False):
        return
    orig = run.reading

    def reading(row):
        a = row["answers"]
        if "route2" in a:
            if MODE["route"] == "avg":
                a2 = average_route(a)
            elif MODE["route"] == "second":
                a2 = {**a, "route": a["route2"]}
            else:
                a2 = a
            r = dict(orig({**row, "answers": a2}))
            r["_route1"] = dict(a["route"].get("probabilities", {}))
            r["_route2"] = dict(a["route2"].get("probabilities", {}))
            return r
        r = orig(row)
        off = [d for n, d in row["keymap"].items() if n.startswith("_off:")]
        if off:
            r = dict(r)
            r["dests"] = {**r["dests"], **{d: 0.0 for d in off if d not in r["dests"]}}
            r["_off"] = off
        return r
    reading._two = True
    run.reading = reading


FORMATS = {"combo-o-2w": two_wordings}
for _k in range(4, 13):
    FORMATS[f"combo-o-short{_k}"] = short(_k)
    FORMATS[f"combo-o-short{_k}-mix"] = short(_k, rounds=MIX)
    FORMATS[f"combo-o-short{_k}-fill"] = short(_k, fill=True)


def format_name(variant):
    if variant == "twoword":
        return "combo-o-2w"
    if variant.startswith("short"):
        return "combo-o-" + variant
    raise ValueError(variant)
