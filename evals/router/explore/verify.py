"""Explorer `verify`: a second look before sending.

The first call routes as usual; when its top destination would be sent, a verification may veto the send (ask instead).
Policies here see the raw answers of the row being scored (run.reading is wrapped to remember the row; nothing it
returns changes), and, for a second sequential call, the case (looked up by id).
"""
import collections
import json
import random

import jev

# ---------------------------------------------------------------- plumbing: the row behind a reading, the case behind a row
# This module is imported while run.py is still loading (formats.py pulls explorers in), so nothing touches run, bench or
# analyze at import. bench.py looks a policy up by name: a module __getattr__ installs the wrapper first.

_last = {}
_cases = {}
POLICIES = {}


def install():
    import run
    if getattr(run.reading, "_verify", False):
        return
    orig = run.reading

    def reading(row):
        _last["row"] = row
        return orig(row)

    reading._verify = True
    run.reading = reading


def __getattr__(name):
    if name in POLICIES:
        install()
        return POLICIES[name]
    raise AttributeError(name)


def case_of(row_id):
    import bench
    if not _cases:
        for s in ("synth", "heldout", "real", "style"):
            for c in bench.load_set(s):
                _cases[c["id"]] = c
    return _cases[row_id]


def base_policy():
    import analyze
    import bench
    return analyze.policy("gates", **bench.FINAL)


# ---------------------------------------------------------------- diagnosis

def diag(fmt="swift", pol="final", sets="real"):
    import bench, formats, run
    install()
    p = bench.policy(pol) if isinstance(pol, str) else pol
    for s in sets.split(","):
        cases = {c["id"]: c for c in bench.load_set(s)}
        rows = run.load(f"{fmt}@{s}")
        cnt = collections.Counter()
        for row in rows:
            c = cases[row["id"]]
            r = run.reading(row)
            k, w = p(r)
            gold = set(c["gold"]["to"])
            if k == "send":
                kind = w if w in bench.INTENTS else ("new" if w.startswith("new:") else "session")
                cnt[(kind, w in gold)] += 1
        print(s, sorted(cnt.items()))


def show_wrongs(fmt="swift", pol="final", s="real", kinds=("session",), n=40):
    import bench, formats, run
    install()
    p = bench.policy(pol) if isinstance(pol, str) else pol
    cases = {c["id"]: c for c in bench.load_set(s)}
    for row in run.load(f"{fmt}@{s}"):
        c = cases[row["id"]]
        r = run.reading(row)
        k, w = p(r)
        gold = set(c["gold"]["to"])
        if k != "send" or w in gold:
            continue
        kind = w if w in bench.INTENTS else ("new" if w.startswith("new:") else "session")
        if kind not in kinds:
            continue
        by = formats.session_by_id(c["board"])
        t = lambda d: (by[d]["title"][:40] + f" [{by[d].get('idle_min')}m]") if d in by else d
        top = sorted(r["dests"].items(), key=lambda x: -x[1])[:3]
        print(f"- {c['id']} {c['gold'].get('label')} msg={c['message'][:140]!r}\n    sent={t(w)}  gold={[t(g) for g in gold]}"
              f"\n    top={[(t(d), round(q, 2)) for d, q in top]} replies={ {t(d): round(q, 2) for d, q in r.get('replies', {}).items()} }")
        n -= 1
        if not n:
            break


# ---------------------------------------------------------------- checks in the same call (no latency)
# A send to one of Lookout's own intents is checked by a yes/no that does not depend on the first answer, so it rides
# in the same call: is the message spoken to a session ("did you…"), and is it one message for one session?

CHECKS = {
    "gate_addressed": {"type": "noul", "instructions": {
        "question": ("Is `message` spoken to a Claude Code session about its own work or what it said (\"did you…\", "
                     "\"what do you mean\", \"is everything done on your end?\"), rather than a question to the user's "
                     "assistant about their sessions from outside (\"is the CI one done?\", \"what's waiting on me?\")?")}},
    "gate_onesession": {"type": "noul", "instructions": {
        "question": ("Is `message` one message for one Claude Code session, even with several points or steps, rather "
                     "than separate requests meant for different places (a session and Lookout's settings, or two "
                     "different sessions)?")}},
}


def with_checks(fmt, checks=None):
    def build(case, rng=None):
        import formats
        state, q, keymap = formats.FORMATS[fmt](case, rng=rng)
        return state, {**q, **{k: CHECKS[k] for k in (checks or CHECKS)}}, keymap
    return build


FORMATS = {"verify1": with_checks("swift")}


def checked(base=None, addressed=0.5, onesession=0.5):
    """Base policy; a send to `question` is vetoed when the message is spoken to a session, one to `compound` when it is
    one message for one session."""
    def pol(r):
        k, w = (base or base_policy())(r)
        g = r.get("gates") or {}
        if k == "send" and w == "question" and g.get("gate_addressed", 0) >= addressed:
            return ("ask", _top3(r))
        if k == "send" and w == "compound" and g.get("gate_onesession", 0) >= onesession:
            return ("ask", _top3(r))
        return k, w
    return pol


def _top3(r):
    import run
    return run.ranked_targets(r)[:3]


def gate_dump(fmt="verify1", sets="realA,synth,heldout,style", dest="question", gate="gate_addressed"):
    """Each set's sends to `dest` by the base policy: the gate's yes for right ones and wrong ones."""
    import bench
    import run
    install()
    p = base_policy()
    for s in sets.split(","):
        cases = {c["id"]: c for c in bench.load_set(s)}
        ok, bad = [], []
        for row in run.load(f"{fmt}@{s}"):
            r = run.reading(row)
            k, w = p(r)
            if k == "send" and w == dest:
                (ok if w in cases[row["id"]]["gold"]["to"] else bad).append(round(r["gates"].get(gate, 0), 2))
        print(f"{s:8} right {sorted(ok)}\n{'':8} wrong {sorted(bad)}")


# ---------------------------------------------------------------- the second look

LOOKOUT = {"question": "Lookout's assistant answers it: a question about what is going on (sessions, cards, the inbox)",
           "compound": "Lookout's assistant splits it: several different things for different places",
           "change_fjord": "Lookout changes itself: a setting, its notifications, inbox categories or groups"}


def describe(case, dest):
    """The destination as the route question described it (session: title, project, now, what the user last told it)."""
    import formats
    if dest in LOOKOUT:
        return {"kind": "not a session: Lookout itself", "what": LOOKOUT[dest]}
    if dest.startswith("new:"):
        return {"kind": "a new Claude Code session", "project": dest[4:]}
    _, q, km = formats.v2(case, told=True)
    for name, d in km.items():
        if d == dest and name in q["route"]["criteria"]:
            return {"session": name, **q["route"]["criteria"][name]}
    return {"session": dest}


def most_recent(case):
    ss = sorted(case["board"]["sessions"], key=lambda s: s.get("idle_min", 0))
    return ss[0]["id"] if ss else None


def rivals(r, case, dest):
    """Who else it could be for: the route's runner-up target, and the most recently active session."""
    import run
    out = []
    for d in run.ranked_targets(r):
        if d != dest:
            out.append(d)
            break
    m = most_recent(case)
    if m and m != dest and m not in out:
        out.append(m)
    return out


FITS_Q = {"session": "Is `message` meant for `destination`: a reply to what it asks or said, or more work for it to do?",
          "other": "Is `message` meant for `destination`?"}
PAIR_Q = "Is `message` meant for `this` rather than for `other`?"


def verify_call(case, dest, alts):
    state = {"message": case["message"]}
    d = describe(case, dest)
    q = {"fits": {"type": "noul", "instructions": {
        "question": FITS_Q["session" if "session" in d else "other"], "destination": d}}}
    for i, a in enumerate(alts):
        da = describe(case, a)
        q[f"pair{i}"] = {"type": "noul", "instructions": {"question": PAIR_Q, "this": d, "other": da}}
        q[f"rpair{i}"] = {"type": "noul", "instructions": {"question": PAIR_Q, "this": da, "other": d}}
    return state, q


def verdict(case, r, dest):
    """Scores of the second look at sending `message` to dest: fits, and per rival the pairwise preference (both orders)."""
    alts = rivals(r, case, dest)
    a = jev.ask(*verify_call(case, dest, alts))["answers"]
    out = {"fits": a["fits"]["noul"], "pairs": {}}
    for i, alt in enumerate(alts):
        out["pairs"][alt] = (a[f"pair{i}"]["noul"] + 1 - a[f"rpair{i}"]["noul"]) / 2
    return out


def prefetch(fmt="swift", sets="synth,heldout,real,style", pol=None):
    """Ask every second look the base policy would need, in parallel, so scoring later is cached."""
    import bench
    import run
    install()
    p = pol or base_policy()
    calls = []
    for s in sets.split(","):
        rows = run.load(f"{fmt}@{s}")
        for row in rows:
            r = run.reading(row)
            k, w = p(r)
            if k == "send":
                c = case_of(row["id"])
                calls.append(verify_call(c, w, rivals(r, c, w)))
    print(len(calls), "calls")
    jev.ask_many(calls)


def table(fmt="swift", sets="real,synth,heldout,style", pol=None):
    """Every send of the base policy with its second-look scores and whether it was right."""
    import bench
    import run
    install()
    p = pol or base_policy()
    out = {}
    for s in sets.split(","):
        cases = {c["id"]: c for c in bench.load_set(s)}
        rows = []
        for row in run.load(f"{fmt}@{s}"):
            r = run.reading(row)
            k, w = p(r)
            if k != "send":
                continue
            c = cases[row["id"]]
            v = verdict(c, r, w)
            rows.append({"id": c["id"], "dest": w, "right": w in set(c["gold"]["to"]), "v": v, "r": r})
        out[s] = rows
    return out


def dump(fmt="swift", sets="realA,realB,synth,heldout,style", kinds="session", only_wrong=False):
    import formats
    t = table(fmt, sets)
    for s, rows in t.items():
        print("==", s)
        for x in rows:
            if kind_of(x["dest"]) not in kinds.split(",") or (only_wrong and x["right"]):
                continue
            c = case_of(x["id"])
            by = formats.session_by_id(c["board"])
            r = x["r"]
            src = "reply" if r.get("replies", {}).get(x["dest"], 0) >= 0.5 else "route"
            top = sorted(r["dests"].items(), key=lambda y: -y[1])[0]
            idle = by[x["dest"]].get("idle_min") if x["dest"] in by else "-"
            recent = most_recent(c) == x["dest"]
            pairs = {(by[k]["title"][:20] if k in by else k): round(p, 2) for k, p in x["v"]["pairs"].items()}
            if kinds != "session":
                print(f"{'OK ' if x['right'] else 'BAD'} {x['dest'][:8]} fits={x['v']['fits']:.2f} pairs={pairs} "
                      f"gates={ {k[5:]: round(p, 2) for k, p in r.get('gates', {}).items()} } {c['message'][:90]!r}")
                continue
            print(f"{'OK ' if x['right'] else 'BAD'} {src:5} p={r['dests'].get(x['dest'], 0):.2f} top={top[0] if top[0] not in by else 'S'}:{top[1]:.2f} "
                  f"idle={idle} recent={recent} fits={x['v']['fits']:.2f} pairs={pairs} {c['message'][:60]!r}")


def kind_of(d):
    return d if d in LOOKOUT else ("new" if d.startswith("new:") else "session")


RULES = {
    "fits": lambda v: v["fits"],
    "pair0": lambda v: min(list(v["pairs"].values())[:1] or [1]),
    "pairmin": lambda v: min(v["pairs"].values() or [1]),
}


def tradeoff(fmt="swift", sets="realA,realB,synth,heldout,style", rules="fits,pairmin", ths=(0.3, 0.4, 0.5, 0.6),
             kinds="session,new,question,compound,change_fjord", t=None):
    """Wrong sends removed vs right sends lost, per veto rule, threshold and kind of destination."""
    t = t or table(fmt, sets)
    for name in rules.split(","):
        f = RULES[name]
        for th in ths:
            print(f"== {name} < {th}")
            for k in kinds.split(","):
                cells = []
                for s, rows in t.items():
                    rows = [x for x in rows if k == "all" or kind_of(x["dest"]) == k]
                    wr = sum(not x["right"] for x in rows)
                    kw = sum(not x["right"] and f(x["v"]) < th for x in rows)
                    kr = sum(x["right"] and f(x["v"]) < th for x in rows)
                    cells.append(f"{s}: -{kw}/{wr}w -{kr}/{len(rows) - wr}r")
                print(f"  {k:14} " + " | ".join(cells))
    return t


# ---------------------------------------------------------------- policies: the base decision, then the second look

def second_look(session=0.45, new=0.0, intent=None, intent_fits=None, intents=("question", "compound", "change_fjord"),
                reply_route=0.0, reply_pair=0.5, base=None):
    """Send only when the second look agrees: for a session or a new session, every pairwise preference against its
    rivals at least the bar; for Lookout's intents, the same (intent) and/or the fits yes (intent_fits)."""
    cache = {}

    def pol(r):
        if "base" not in cache:
            cache["base"] = base or base_policy()
        k, w = cache["base"](r)
        if k != "send":
            return k, w
        row = _last["row"]
        v = verdict(case_of(row["id"]), r, w)
        pmin = min(v["pairs"].values() or [1])
        kind = kind_of(w)
        if kind == "session" and (pmin < session or (r["dests"].get(w, 0) < reply_route and pmin < reply_pair)):
            return ("ask", _top3(r))
        if kind == "new" and pmin < new:
            return ("ask", _top3(r))
        if kind in intents:
            if intent is not None and pmin < intent:
                return ("ask", _top3(r))
            if intent_fits is not None and v["fits"] < intent_fits:
                return ("ask", _top3(r))
        return k, w
    return pol


def sweep(fmt="swift", tune="realA", test="realB,synth,heldout,style", grid=None):
    """Score second_look settings on the tuning set and the others (saved runs, cached second looks)."""
    import bench
    import run
    install()
    grid = grid or [dict(session=s, intent=i, intent_fits=f) for s in (0, 0.4, 0.45, 0.5)
                    for i in (None, 0.4, 0.45, 0.5) for f in (None, 0.4, 0.5)]
    sets = [tune] + test.split(",")
    data = {s: (bench.load_set(s), run.load(f"{fmt}@{s if not s.startswith('real') else 'real'}")) for s in sets}
    for params in grid:
        cells = []
        for s in sets:
            cases, rows = data[s]
            ids = {c["id"] for c in cases}
            t = bench.score(cases, [x for x in rows if x["id"] in ids], second_look(**params))
            n = t["n"]
            cells.append(f"{s}: {100 * t['right'] / n:4.1f}/{100 * t['wrong'] / n:4.1f}/{100 * t['needless'] / n:4.1f}")
        print(params, " | ".join(cells))


def reply_split(fmt="swift", sets="realA,realB,synth,heldout,style"):
    """Session sends that come from a card's answer check, by how much the route question gave that session."""
    t = table(fmt, sets)
    for s, rows in t.items():
        b = collections.Counter()
        for x in rows:
            if kind_of(x["dest"]) != "session":
                continue
            r = x["r"]
            src = "reply" if r.get("replies", {}).get(x["dest"], 0) >= 0.5 and len(r["replies"]) else "route"
            p = r["dests"].get(x["dest"], 0)
            bucket = "<.05" if p < .05 else "<.1" if p < .1 else "<.2" if p < .2 else "<.3" if p < .3 else ">=.3"
            b[(src, bucket, "ok" if x["right"] else "BAD")] += 1
        print(s, sorted(b.items()))


POLICIES.update({
    "base": lambda r: base_policy()(r),
    # the shipped policy, then one second call: a session send needs both-order pairwise ≥ 0.4 against the route's
    # runner-up and the most recently active session (≥ 0.5 when the route itself gave it < 0.05, i.e. only the card
    # check chose it); a `question` send needs the fits yes ≥ 0.4.
    "best": second_look(session=0.4, intent_fits=0.4, intents=("question",), reply_route=0.05, reply_pair=0.5),
    "pairs_only": second_look(session=0.4),
    "question_fits": second_look(session=0, intent_fits=0.4, intents=("question",)),
    "all_fits": second_look(session=0, intent_fits=0.4),
})
