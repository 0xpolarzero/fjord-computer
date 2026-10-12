"""Cascade (explorer: cascade): when the round-3 best policy (combo-o + fuse3 guarded b1=0.5 b2=0.9) would ask, give
the moment to a bigger model (Claude Haiku via the local Claude Code CLI) and send only when it is confident.

Haiku sees what Lookout knows at send time: the board in Lookout's order (running, then latest finished), each
session's title, project, status, its last message (card) and what the user last told it; the projects (new session);
Lookout's own intents. It answers {"pick": <id> | "ask", "confidence": 0-100}. Everything is redacted first.

python3 -m explore.cascade asks                 how many asks per set
python3 -m explore.cascade call SET [N] [--par 3] ask Haiku about up to N of SET's asks (cached, capped at 300 calls)
python3 -m explore.cascade report               per bar: asks → right / wrong sends; end-to-end tables
"""
import collections
import hashlib
import json
import math
import pathlib
import re
import statistics
import subprocess
import sys
import time
from concurrent.futures import ThreadPoolExecutor

import formats as F
from explore import fuse3
from explore import fusion as Fu
from real.boards import redact

HERE = pathlib.Path(__file__).parent.parent
CACHE = HERE / "runs" / "cascade_haiku.jsonl"
CAP = 300
COUNT = HERE / "runs" / "cascade_calls.txt"   # every CLI call made, against CAP
FMT = "combo-o"
SETS = ("synth", "styleB", "realA", "realB", "heldout")
WHOLE = {"realA": "real", "realB": "real", "styleA": "style", "styleB": "style"}

# real/boards.redact misses some keys (e.g. a 32-hex.16-alnum z.ai key); anything long, mixed letters and digits goes.
_TOKEN = re.compile(r"\b(?=[A-Za-z0-9._\-]*\d)(?=[A-Za-z0-9._\-]*[A-Za-z])[A-Za-z0-9._\-]{28,}\b")


def clean(text, limit=None):
    t = _TOKEN.sub("[redacted]", redact(text or ""))
    t = " ".join(t.split())
    return t if limit is None or len(t) <= limit else t[:limit] + "…"


INTENT_TEXT = {
    "question": "a question to Lookout about the board itself (which sessions are working, done or waiting, what a "
                "session named in the third person is doing); not a question for a session about its own work",
    "change_fjord": "change how Lookout itself behaves (its settings, notifications, inbox, rules); not asking a "
                      "session to build or change code",
    "compound": "requests for two or more different places in one message (Lookout and a session, or two sessions); "
                "not one long message with several points for one session",
}


def prompt(case):
    b = case["board"]
    cards = {}
    for c in b.get("cards", []):
        cards[c["session"]] = c
    told = {}
    for h in sorted(b.get("history", []), key=lambda h: -h["ago_min"]):
        told[h["to"]] = h
    lines = []
    for s in F.sessions_ordered(b):
        st = "working now" if s.get("running") else f"finished {F.ago(s.get('idle_min', 0))}"
        lines.append(f"- id `{s['id']}` · “{clean(s['title'], 90)}” · project {s['project']} · {st}")
        c = cards.get(s["id"])
        said = (c and c["text"]) or s.get("summary") or s.get("activity")
        if said:
            kind = f" ({c['kind']})" if c and c.get("kind") else ""
            lines.append(f"    it last said{kind}: {clean(said, 450)}")
        h = told.get(s["id"])
        if h:
            lines.append(f"    the user last told it ({F.ago(h['ago_min'])}): {clean(h['you'], 250)}")
    projects = ", ".join(f"`new:{p}`" for p in b.get("projects", []))
    intents = "\n".join(f"- `{k}`: {v}" for k, v in INTENT_TEXT.items())
    return f"""You route a message the user typed into Lookout, a Mac app that watches their Claude Code sessions. \
Decide where it goes: one of the sessions below (it becomes that session's next user turn), a new session in a \
project, or Lookout itself. Most messages continue a conversation the user was just having, often with the session \
that finished last, but only pick a session when the message fits it. A wrong send is much worse than asking the user.

Sessions (working ones first, then by how recently they finished):
{chr(10).join(lines)}

New session in a project: {projects}
Lookout itself:
{intents}

The user's message:
<<<
{clean(case['message'], 2000)}
>>>

Answer with JSON only, no prose: {{"pick": "<a session id, new:<project>, question, change_fjord, compound, or ask>", \
"confidence": <0-100, how likely your pick is where the user meant it>}}"""


# ---------------------------------------------------------------- the CLI, cached

SYSTEM = "You are a message router. Answer with one JSON object only."

def _load_cache():
    out = {}
    if CACHE.exists():
        for l in CACHE.read_text().splitlines():
            if l.strip():
                j = json.loads(l)
                out[j["key"]] = j
    return out


def key_of(case, text):
    return case["id"] + ":" + hashlib.sha256(text.encode()).hexdigest()[:12]


def call_cli(text):
    t0 = time.time()
    import os
    env = {**os.environ, "MAX_THINKING_TOKENS": "0"}
    p = subprocess.run(["claude", "-p", "--model", "haiku", "--output-format", "json", "--no-session-persistence",
                        "--tools", "", "--effort", "low", "--system-prompt", SYSTEM], input=text, env=env, capture_output=True, text=True, timeout=180, cwd="/tmp")
    dt = time.time() - t0
    try:
        out = json.loads(p.stdout)
        res = out.get("result", "")
    except Exception:
        return {"raw": p.stdout[-500:] + p.stderr[-500:], "latency": dt, "pick": None, "conf": 0}
    m = re.search(r"\{.*\}", res, re.S)
    pick, conf = None, 0
    if m:
        try:
            j = json.loads(m.group(0))
            pick, conf = str(j.get("pick")), float(j.get("confidence", 0))
        except Exception:
            pass
    return {"raw": res[:300], "latency": dt, "api_ms": out.get("duration_api_ms"), "cost": out.get("total_cost_usd"),
            "pick": pick, "conf": conf}


# ---------------------------------------------------------------- the round-3 best policy and its asks

_POL = None


def base_policy():
    global _POL
    if _POL is None:
        Fu._patch_reading()
        w, v = fuse3.fitted(FMT)
        _POL = (fuse3.make_guarded(w, v, 0.5, 0.9), w, v)
    return _POL


def rows_of(s):
    import bench
    import run
    cases = bench.load_set(s)
    ids = {c["id"]: c for c in cases}
    rows = [r for r in run.load(f"{FMT}@{WHOLE.get(s, s)}") if r["id"] in ids and r["order"] == 0]
    return [(ids[r["id"]], run.reading(r)) for r in rows]


def decisions(s):
    """[(case, reading, (kind, dest))] by the round-3 best policy."""
    pol = base_policy()[0]
    return [(c, r, pol(r, c)) for c, r in rows_of(s)]


def run_calls(s, n, par=3):
    cache = _load_cache()
    asks = [c for c, r, (k, d) in decisions(s) if k == "ask"]
    todo = []
    for c in asks:
        t = prompt(c)
        if key_of(c, t) not in cache:
            todo.append((c, t))
    todo = todo[:n]
    made = len(COUNT.read_text().split()) if COUNT.exists() else 0
    budget = CAP - made
    if len(todo) > budget:
        print(f"cap: {made} calls made, {budget} left")
        todo = todo[:max(budget, 0)]
    print(f"{s}: {len(asks)} asks, {len(todo)} to call")
    with ThreadPoolExecutor(max(1, min(par, 3))) as ex:
        for (c, t), res in zip(todo, ex.map(lambda ct: call_cli(ct[1]), todo)):
            j = {"key": key_of(c, t), "id": c["id"], "set": s, **res}
            with open(COUNT, "a") as f:
                f.write(c["id"] + "\n")
            if j["pick"] is None and j["latency"] < 2:
                print("  error, not cached:", j["raw"][:120])
                continue
            with open(CACHE, "a") as f:
                f.write(json.dumps(j) + "\n")
            print(f"  {c['id']:18} pick={j['pick']} conf={j['conf']} gold={c['gold']['to']} {j['latency']:.1f}s")


def haiku(case, cache):
    """Haiku's answer for a case, by its current prompt (None if never asked)."""
    return cache.get(key_of(case, prompt(case)))


# ---------------------------------------------------------------- scoring

def tally(items, cache, bar, mode="haiku", w=None):
    """End-to-end on a set: the base decision, and on its asks Haiku's pick when confidence ≥ bar.
    mode 'agree': Haiku's pick must also be in the fusion's top 3 (the ask's own shortlist)."""
    t = collections.Counter()
    for c, r, (k, d) in items:
        gold = set(c["gold"]["to"])
        ask_ok = c["gold"].get("ask_ok") or not gold
        t["n"] += 1
        if k == "ask":
            h = haiku(c, cache)
            t["asks"] += 1
            if h is not None:
                t["asked_haiku"] += 1
                pick = h["pick"]
                ok = pick and pick != "ask" and h["conf"] >= bar
                if ok and mode == "agree":
                    ok = pick in d[:1 if mode == "agree1" else 3]
                if ok and mode == "agree1":
                    ok = bool(d) and pick == d[0]
                if ok:
                    k, d = "send", pick
                    t["c_right" if pick in gold else "c_wrong"] += 1
        if k == "send":
            t["right" if d in gold else "wrong"] += 1
        else:
            t["ask"] += 1
            t["needless"] += not ask_ok
    return t


def fmt_t(s, t):
    n = t["n"]
    pc = lambda k: 100 * t[k] / n
    return (f"{s:8} n={n:4} right={pc('right'):5.1f} wrong={pc('wrong'):4.1f} ask={pc('ask'):5.1f} "
            f"needless={pc('needless'):5.1f} | asks {t['asks']} (haiku {t['asked_haiku']}): "
            f"+{t['c_right']} right, +{t['c_wrong']} wrong")


def report(modes=("haiku", "agree", "agree1")):
    cache = _load_cache()
    dec = {s: decisions(s) for s in SETS}
    lat = [j["latency"] for j in cache.values()]
    if lat:
        print(f"calls {len(lat)}  latency median {statistics.median(lat):.1f}s p90 "
              f"{sorted(lat)[int(.9 * len(lat)) - 1]:.1f}s  api median "
              f"{statistics.median([j['api_ms'] or 0 for j in cache.values()]) / 1000:.1f}s  cost "
              f"${sum(j.get('cost') or 0 for j in cache.values()):.2f}")
    print("base (round-3 best):")
    for s in SETS:
        print("  " + fmt_t(s, tally(dec[s], {}, 101)))
    # among asked: per confidence bar, right / wrong / gold-in-pick stats
    for mode in modes:
        for bar in (80, 90):
            print(f"{mode} bar={bar}:")
            for s in SETS:
                print("  " + fmt_t(s, tally(dec[s], cache, bar, mode)))


def asks_summary():
    for s in SETS:
        d = decisions(s)
        a = [c for c, r, (k, x) in d if k == "ask"]
        g = collections.Counter("none" if not c["gold"]["to"] else
                                "intent" if set(c["gold"]["to"]) & set(Fu.INTENTS) else
                                "new" if any(x.startswith("new:") for x in c["gold"]["to"]) else "sess" for c in a)
        print(s, len(d), "asks", len(a), dict(g), "needless", sum(not c["gold"].get("ask_ok") and bool(c["gold"]["to"]) for c in a))


def main():
    cmd = sys.argv[1]
    if cmd == "asks":
        asks_summary()
    elif cmd == "prompt":
        import bench
        c = {x["id"]: x for s in ("real", "style", "heldout", "synth") for x in bench.load_set(s)}[sys.argv[2]]
        print(prompt(c))
    elif cmd == "call":
        n = int(sys.argv[3]) if len(sys.argv) > 3 and sys.argv[3].isdigit() else 10 ** 6
        par = int(sys.argv[sys.argv.index("--par") + 1]) if "--par" in sys.argv else 3
        run_calls(sys.argv[2], n, par)
    elif cmd == "fuse":
        fuse_report()
    elif cmd == "show":
        show(sys.argv[2], float(sys.argv[3]))
    elif cmd == "bars":
        by_bar(sys.argv[2].split(","))
    elif cmd == "report":
        report()



def by_bar(sets):
    """Of the base policy's asks Haiku saw: per confidence bar, sends (right) alone / when the pick is in the fusion's
    top 3 / when it is the fusion's top."""
    cache = _load_cache()
    rows = []
    for s in sets:
        for c, r, (k, x) in decisions(s):
            h = haiku(c, cache) if k == "ask" else None
            if h:
                rows.append((h["pick"], h["conf"], set(c["gold"]["to"]), x, h["latency"]))
    print(sets, "asked", len(rows), "latency median", round(statistics.median(r[4] for r in rows), 1),
          collections.Counter("ask" if p == "ask" else "right" if p in g else "wrong" for p, cf, g, x, _ in rows))
    for bar in (50, 60, 70, 75, 80, 85, 90, 95):
        s = [(p in g, p in x[:3], bool(x) and p == x[0]) for p, cf, g, x, _ in rows if p not in ("ask", None) and cf >= bar]
        a = [r for r in s if r[1]]
        b = [r for r in s if r[2]]
        print(f"  bar {bar}: alone {sum(r[0] for r in s)}/{len(s)} right  | in top3 {sum(r[0] for r in a)}/{len(a)}"
              f"  | = top1 {sum(r[0] for r in b)}/{len(b)}")


def ask_table(s):
    """Per ask Haiku saw: the fusion's top, P, calibrated sureness, Haiku's pick and confidence, gold."""
    pol, w, v = base_policy()
    cache = _load_cache()
    out = []
    for c, r, (k, x) in decisions(s):
        h = haiku(c, cache) if k == "ask" else None
        if not h:
            continue
        fs = fuse3.features(r, c)
        if not fs:
            continue
        P = Fu.probs(fs, w)
        top, p = Fu.confidence(r, c, fs, w, v)
        out.append(dict(case=c, top=top, P=P[top], conf=p, second=sorted(P.values())[-2] if len(P) > 1 else 0,
                        hpick=h["pick"], hconf=h["conf"] / 100, hP=P.get(h["pick"], 0), gold=set(c["gold"]["to"]),
                        ask_ok=c["gold"].get("ask_ok") or not c["gold"]["to"]))
    return out


def _lg(x):
    x = min(max(x, 1e-3), 1 - 1e-3)
    return math.log(x / (1 - x))


def hfeats(t):
    agree = t["hpick"] == t["top"]
    return [1, _lg(t["conf"]), _lg(t["P"]), agree, agree * t["hconf"], (not agree and t["hpick"] != "ask") * t["hconf"]]


HNAMES = ["bias", "lconf", "lP", "agree", "agree_hconf", "other_hconf"]


def fit_gate(train):
    """Logistic on the asks of `train`: is the fusion's top right, given its sureness and what Haiku said?"""
    import numpy as np
    from scipy.optimize import minimize
    X = np.array([hfeats(t) for t in train], float)
    y = np.array([t["top"] in t["gold"] for t in train], float)

    def lg(v):
        p = 1 / (1 + np.exp(-(X @ v)))
        L = -(y * np.log(p + 1e-12) + (1 - y) * np.log(1 - p + 1e-12)).sum() + (v[1:] @ v[1:]) / 2
        g = X.T @ (p - y)
        g[1:] += v[1:]
        return L, g
    return minimize(lg, np.zeros(X.shape[1]), jac=True, method="L-BFGS-B").x


def gate_p(v, t):
    return 1 / (1 + math.exp(-sum(a * b for a, b in zip(v, hfeats(t)))))


def fuse_report(train=("realA",)):
    """Haiku's answer as a feature: fitted on the asks of `train` (Haiku answered 80 realA asks), the fusion's top is
    sent when the gate's p clears a bar; scored on every set's asks, and end to end."""
    tabs = {s: ask_table(s) for s in SETS if s != "synth"}
    v = fit_gate([t for s in train for t in tabs[s]])
    print("gate", dict(zip(HNAMES, [round(float(x), 2) for x in v])))
    # simple rule, no fitting: Haiku agrees with the fusion's top at confidence ≥ hb and the fusion's sureness ≥ cb
    rules = [("fitted", b, lambda t, b=b: gate_p(v, t) >= b) for b in (0.6, 0.7, 0.8, 0.9)]
    rules += [(f"agree h≥{hb} c≥{cb}", None, lambda t, hb=hb, cb=cb: t["hpick"] == t["top"] and t["hconf"] >= hb and t["conf"] >= cb)
              for hb in (0.8, 0.9) for cb in (0, 0.6, 0.7, 0.8)]
    rules += [(f"fusion alone c≥{cb}", None, lambda t, cb=cb: t["conf"] >= cb and t["top"] not in Fu.INTENTS) for cb in (0.6, 0.7, 0.8)]
    for name, b, rule in rules:
        print(f"{name} {b or ''}: " + "  ".join(
            f"{s}: +{sum(t['top'] in t['gold'] for t in ts if rule(t))}/-{sum(t['top'] not in t['gold'] for t in ts if rule(t))}"
            f" of {len(ts)}" for s, ts in tabs.items()))


def show(s, bar=80):
    cache = _load_cache()
    for c, r, (k, x) in decisions(s):
        h = haiku(c, cache) if k == "ask" else None
        if h and h["pick"] not in ("ask", None) and h["conf"] >= bar:
            ok = h["pick"] in c["gold"]["to"]
            ranks = {d: i for i, d in enumerate(sess["id"] for sess in F.sessions_ordered(c["board"]))}
            print(f"{'OK ' if ok else 'BAD'} {c['id']:16} {c['gold'].get('label')} conf={h['conf']:.0f} "
                  f"pick#{ranks.get(h['pick'], h['pick'])} gold#{[ranks.get(g, g) for g in c['gold']['to']]} "
                  f"fus={[ranks.get(d, d) for d in x]} :: {clean(c['message'], 110)!r}")


if __name__ == "__main__":
    main()
