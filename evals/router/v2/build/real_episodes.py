"""Real-moment episodes (Router benchmark v2, stage B1): your real messages on their real boards, singly and as short
real timelines, in the v2 episode schema (BENCHMARK.md §Schema), source "real-moment".

    python3 v2/build/real_episodes.py [--seed 7] [--multi 230] [--single 270]  →  v2/data/episodes/raw/real.jsonl

- single: one real moment; state = its trimmed board; gold intended = where it went.
- multi: 2–4 consecutive real messages of the global timeline (any session), each within 30 min of the previous and
  40 min overall; `state` = the first moment's board; between submits a `board` event carries what changed by the next
  moment (cards+ / cards- / cards~ created_min_ago, sessions+ / sessions~, now). Sessions you started inside the episode
  get the runner's id `started-<event id>` and are left to the runner (no sessions~ for them; their cards still arrive).
  Sessions you sent to earlier in the episode get their full row in sessions~ (the runner changed them on delivery).
- flows: chain (one session), switch-back (A→B→A), new-then-follow, backlog (switches to sessions already waiting at the
  start), card-arrives-midway (a switch to a session whose card arrived during the episode).
- gold: intended = went_to, acceptable = [intended], clarify = [], ask/consequential = null (for the labellers).
- group = the first moment's session-day; provenance.groups lists every session-day the episode touches.
- states trimmed (episode_common.trim_state): every session and card kept; turns to the last 4, you ≤ 300, said ≤ 600.
Stratified to research/behavior.md: singles by transition (same 51 / switch 40 / new 9), multis by episode type
(back-and-forth 35, backlog 20, card mid-chain 15, switch-back 12, new 10, normalised); every source group covered."""
import argparse
import collections
import copy
import json
import random

import episode_common as C

OUT = C.DATA / "episodes" / "raw" / "real.jsonl"
GAP_MIN = 30
SPAN_MIN = 40
FLOW_SHARE = {"chain": .35, "backlog": .20, "card-arrives-midway": .15, "switch-back": .12, "new-then-follow": .10}
LEN_WEIGHTS = {2: .45, 3: .33, 4: .22}
SINGLE_SHARE = {"same": .51, "switch": .40, "new": .09}
CONTEXT = {"replyTo": None, "pinned": None, "pills": [], "notTo": None, "shown": None, "router_aside": False}


def created_sid(m):
    return m["group"].split(":")[0]


def raw_target(m):
    return m["went_to"]


MAX_MESSAGE = 20000  # one 1.1 MB paste is left out


def on_board(m):
    """Playable: the target is on the board, or a new session in a project Lookout knows (scratch chats and a
    project's very first session can't be started from the Router)."""
    if len(m["message"] or "") > MAX_MESSAGE:
        return False
    if m["went_to"].startswith("new:"):
        return m["went_to"][4:] in m["state"]["projects"]
    return m["went_to"].startswith("new:") or any(s["id"] == m["went_to"] for s in m["state"]["sessions"])


def classify(ms):
    """Flow of a candidate window, or None when it isn't one we build."""
    started = {}
    seq = []
    for m in ms:
        t = m["went_to"]
        if t.startswith("new:"):
            started[created_sid(m)] = True
            seq.append(("new", created_sid(m)))
        else:
            seq.append(("old", t))
    sids = [s for _, s in seq]
    if any(kind == "new" for kind, _ in seq):
        first_new = next(i for i, (k, _) in enumerate(seq) if k == "new")
        if any(sids[j] == sids[first_new] and seq[j][0] == "old" for j in range(first_new + 1, len(seq))):
            return "new-then-follow"
        return None
    if len(set(sids)) == 1:
        return "chain"
    for i in range(len(sids)):
        for k in range(i + 2, len(sids)):
            if sids[i] == sids[k] and any(sids[j] != sids[i] for j in range(i + 1, k)):
                return "switch-back"
    start_cards = {c["session"] for c in ms[0]["state"]["cards"]}
    start_ids = {c["id"] for c in ms[0]["state"]["cards"]}
    switches = [(j, sids[j]) for j in range(1, len(sids)) if sids[j] != sids[j - 1]]
    arrived = False
    for j, sid in switches:
        cards_now = [c for c in ms[j]["state"]["cards"] if c["session"] == sid]
        if cards_now and not any(c["id"] in start_ids for c in cards_now):
            arrived = True
    if arrived:
        return "card-arrives-midway"
    if all(sid in start_cards for _, sid in switches) or (sids[0] in start_cards and len(set(sids)) >= 2):
        return "backlog"
    return None


def candidates(moments):
    out = []
    n = len(moments)
    for i in range(n):
        for L in (2, 3, 4):
            if i + L > n:
                break
            ms = moments[i:i + L]
            if any(C.ts(b["at"]) - C.ts(a["at"]) > GAP_MIN * 60 for a, b in zip(ms, ms[1:])):
                break
            if C.ts(ms[-1]["at"]) - C.ts(ms[0]["at"]) > SPAN_MIN * 60:
                break
            ok = True
            started = set()
            for m in ms:
                if len(m["message"] or "") > MAX_MESSAGE:
                    ok = False
                elif m["went_to"].startswith("new:"):
                    if not on_board(m):
                        ok = False
                    started.add(created_sid(m))
                elif not (on_board(m) or m["went_to"] in started):
                    ok = False
            if not ok:
                continue
            flow = classify(ms)
            if flow:
                out.append({"start": i, "len": L, "flow": flow, "group": ms[0]["group"]})
    return out


# ------------------------------------------------------------------------------------------------- building

def diff(tracked, nxt, started_ids, force):
    delta = {"now": nxt["now"]}
    cur_cards = {c["id"]: c for c in tracked["cards"]}
    nxt_cards = {c["id"]: c for c in nxt["cards"]}
    plus = [c for cid, c in nxt_cards.items() if cid not in cur_cards]
    minus = [cid for cid in cur_cards if cid not in nxt_cards]
    tilde = []
    for cid, c in nxt_cards.items():
        if cid in cur_cards:
            ch = {k: v for k, v in c.items() if cur_cards[cid].get(k) != v}
            if ch:
                tilde.append({"id": cid, **ch})
    cur_s = {s["id"]: s for s in tracked["sessions"]}
    s_plus, s_tilde = [], []
    for s in nxt["sessions"]:
        if s["id"] in started_ids:
            continue
        if s["id"] not in cur_s:
            s_plus.append(s)
        elif s["id"] in force:
            s_tilde.append(copy.deepcopy(s))
        else:
            ch = {k: v for k, v in s.items() if cur_s[s["id"]].get(k) != v}
            if ch:
                s_tilde.append({"id": s["id"], **ch})
    for key, val in (("cards+", plus), ("cards-", minus), ("cards~", tilde), ("sessions+", s_plus),
                     ("sessions~", s_tilde)):
        if val:
            delta[key] = val
    return delta


def apply(tracked, delta):
    tracked["now"] = delta["now"]
    for col in ("cards", "sessions"):
        rows = tracked[col]
        gone = set(delta.get(col + "-", []))
        rows[:] = [r for r in rows if r["id"] not in gone]
        rows.extend(copy.deepcopy(delta.get(col + "+", [])))
        by = {r["id"]: r for r in rows}
        for ch in delta.get(col + "~", []):
            by[ch["id"]].update(copy.deepcopy(ch))


def episode(ms, eid, flow):
    started = {}
    state0 = C.trim_state(ms[0]["state"])
    tracked = copy.deepcopy(state0)
    events, families, slices, langs, force = [], [], [], [], set()
    for k, m in enumerate(ms):
        ev = f"e{k + 1}"
        if k:
            nxt = C.trim_state(m["state"], ids=started)
            delta = diff(tracked, nxt, set(started.values()), force)
            apply(tracked, delta)
            events.append({"id": f"b{k}", "kind": "board", "delta": delta})
        if m["went_to"].startswith("new:"):
            intended = m["went_to"]
            started[created_sid(m)] = "started-" + ev
        else:
            sid = started.get(m["went_to"], m["went_to"])
            intended = "session:" + sid
            force.add(sid)
        fam = C.family_of(m)
        sl = C.slices_of(m)
        families.append(fam)
        slices.extend(sl)
        langs.append(C.lang(m["message"]))
        rank = m["flags"].get("recency_rank")
        events.append({
            "id": ev, "kind": "submit", "message": C.redact(m["message"]), "context": dict(CONTEXT),
            "gold": {"intended": intended, "acceptable": [intended], "clarify": [], "ask": None,
                     "consequential": None,
                     "evidence": f"real moment {m['id']}: you sent it to {intended} "
                                 f"({m['flags'].get('transition')}{', recency rank %s' % rank if rank else ''})"},
            "tags": {"family": fam, "slices": sl, "moment": m["id"]}})
    lang = "fr" if all(x == "fr" for x in langs) else "mix" if any(x != "en" for x in langs) else "en"
    eps = {"schema": 2, "id": eid, "family": families[0], "group": ms[0]["group"],
           "provenance": {"source": "real-moment", "anchors": [m["id"] for m in ms], "writer": "human",
                          "writer_model": "real transcript", "state_fidelity": "transcript", "synthetic": [],
                          "groups": sorted({m["group"] for m in ms})},
           "tags": {"primary": families[0], "flow": flow,
                    "slices": sorted(set(slices) | ({"multi-submit", f"submits-{len(ms)}"} if len(ms) > 1 else set())),
                    "lang": lang, "families": families},
           "state": state0, "events": events}
    return eps


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--seed", type=int, default=7)
    ap.add_argument("--multi", type=int, default=230)
    ap.add_argument("--single", type=int, default=270)
    ap.add_argument("--out", default=str(OUT))
    args = ap.parse_args()
    rng = random.Random(args.seed)
    moments = sorted(C.load_moments(), key=lambda m: m["at"])
    cands = candidates(moments)
    rng.shuffle(cands)
    used = set()
    covered = collections.Counter()
    chosen = []
    total = sum(FLOW_SHARE.values())
    quotas = {f: round(args.multi * s / total) for f, s in FLOW_SHARE.items()}
    by_flow = collections.defaultdict(list)
    for c in cands:
        by_flow[c["flow"]].append(c)
    avail = {f: len(v) for f, v in by_flow.items()}
    # rarest flows first so common ones can't eat their moments
    for flow in sorted(quotas, key=lambda f: avail.get(f, 0)):
        for _ in range(quotas[flow]):
            want = rng.choices(list(LEN_WEIGHTS), weights=list(LEN_WEIGHTS.values()))[0]
            if flow == "backlog":
                want = max(want, 3)
            pool = [c for c in by_flow[flow] if not any(i in used for i in range(c["start"], c["start"] + c["len"]))]
            if not pool:
                break
            pool.sort(key=lambda c: (covered[c["group"]], abs(c["len"] - want)))
            c = pool[0]
            used.update(range(c["start"], c["start"] + c["len"]))
            covered[c["group"]] += 1
            chosen.append(c)
    episodes = []
    for c in chosen:
        ms = moments[c["start"]:c["start"] + c["len"]]
        episodes.append(episode(ms, f"ep-real-{ms[0]['id'][3:]}-m{c['len']}", c["flow"]))
    # singles: every uncovered group first, then transition quotas (behavior.md), least-covered groups first
    free = [i for i, m in enumerate(moments) if i not in used and on_board(m)]
    rng.shuffle(free)
    singles = []
    groups = {m["group"] for m in moments}
    tcount = collections.Counter()
    quota = {t: round(args.single * s) for t, s in SINGLE_SHARE.items()}
    for g in sorted(groups):
        if covered[g]:
            continue
        opts = [i for i in free if moments[i]["group"] == g and i not in used]
        if not opts:
            continue
        opts.sort(key=lambda i: tcount[moments[i]["flags"]["transition"]] / max(quota[moments[i]["flags"]["transition"]], 1))
        i = opts[0]
        used.add(i)
        covered[g] += 1
        tcount[moments[i]["flags"]["transition"]] += 1
        singles.append(i)
    for t in ("new", "switch", "same"):
        while tcount[t] < quota[t]:
            opts = [i for i in free if i not in used and moments[i]["flags"]["transition"] == t]
            if not opts:
                break
            fam = collections.Counter(C.family_of(moments[j]) for j in singles)
            opts.sort(key=lambda i: (covered[moments[i]["group"]], fam[C.family_of(moments[i])] > 60))
            i = opts[0]
            used.add(i)
            covered[moments[i]["group"]] += 1
            tcount[t] += 1
            singles.append(i)
    for i in singles:
        episodes.append(episode([moments[i]], f"ep-real-{moments[i]['id'][3:]}-s", "single"))
    episodes.sort(key=lambda e: e["state"]["now"])
    C.pathlib.Path(args.out).parent.mkdir(parents=True, exist_ok=True)
    with open(args.out, "w") as f:
        for e in episodes:
            f.write(json.dumps(e, ensure_ascii=False) + "\n")
    multi = [e for e in episodes if len(e["provenance"]["anchors"]) > 1]
    print(json.dumps({"episodes": len(episodes), "multi": len(multi), "single": len(episodes) - len(multi),
                      "candidates_by_flow": avail, "quotas": quotas,
                      "flows": collections.Counter(e["tags"]["flow"] for e in episodes),
                      "groups_as_episode_group": len({e["group"] for e in episodes}),
                      "groups_touched": len({g for e in episodes for g in e["provenance"]["groups"]}),
                      "groups_total": len(groups), "moments_used": len(used)}, indent=1))


if __name__ == "__main__":
    main()
