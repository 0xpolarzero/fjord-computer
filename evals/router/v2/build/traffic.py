"""Fjord Computer's routing trace (Sources/FjordComputer/RouterTrace.swift) turned into labelled traffic for the evals.

    python3 -m v2.build.traffic summary [--trace PATH] [--since DATE]
    python3 -m v2.build.traffic export  [--trace PATH] [--since DATE] [--out v2/data/traffic/decisions.jsonl]

The trace (~/Library/Application Support/Fjord Computer/router-trace.jsonl, on this Mac only) has one `decided` line per routed
message, then lines by the same id for how it ended: `picked` (a button on the ask that was the suggestion), `corrected`
(another button; or, later, a send moved elsewhere) and `cancelled` (undone or dismissed). Kinds this doesn't know are
counted and skipped. A partial last line (the app writing as we read), a duplicate `decided` id (the later one wins: it
is what you saw) and a follow-up whose `decided` line was trimmed away are counted, never fatal.

summary prints aggregate numbers only, never message text. export writes one record per decided routing with its
outcome joined and a gold for refits:

    outcome     the Router sent (send, start, intent)          it asked
    kept        intended = its target, ask = forbidden         -
    picked      -                                              intended = the pick, ask = allowed
    corrected   intended = the correction, ask = required      intended = the correction, ask = required
    cancelled   intended = None, ask = required                intended = None, ask = None
    unanswered  -                                              no gold (the ask was never answered)

and, when the fusion ran (rule paths have no inputs), the frozen moment: Jev's answers, BM25, the board facts, the
shipped ranking, sureness and card, Jev's request, and the per-destination features RouteFusion.features computed
(ported below, same names as Swift's weights, plus "sess" as explore/v2_fusion reads it). Output goes only under
v2/data/ (gitignored: it holds your redacted messages).

What explore/v2_fusion's frozen moments have that a trace doesn't: the case's board text (session titles, turns), so
no BM25 recompute (r_*, s_*, cov) and no title families beyond option names; Jev's raw answer (route choice and
confidence: jchoice, jconf); the replay state; `leavesItToYou` (the short-reply rule) and each card's own check (only the
surest per session). The message is the redacted one, so ilong and lenlog can differ slightly from what shipped.
"""
import argparse
import collections
import json
import math
import pathlib
import sys
from datetime import datetime, timezone

V2 = pathlib.Path(__file__).resolve().parents[1]
DATA = V2 / "data"
TRACE = pathlib.Path.home() / "Library/Application Support/Fjord Computer/router-trace.jsonl"
OUT = DATA / "traffic" / "decisions.jsonl"
FOLLOW = ("picked", "corrected", "cancelled")
SENDS = ("send", "start", "intent")
INTENTS = ("question", "compound", "change_lookout")
SURE_BINS = (0.5, 0.7, 0.8, 0.9, 0.93, 0.96)


# ---------------------------------------------------------------- reading

def parse_at(text):
    """An ISO date or datetime (the trace's, or --since) as an aware UTC datetime; None when it isn't one."""
    if not text:
        return None
    try:
        at = datetime.fromisoformat(text.replace("Z", "+00:00"))
    except ValueError:
        return None
    return at if at.tzinfo else at.replace(tzinfo=timezone.utc)


def read(path):
    """The trace's lines as dicts, and what was skipped: lines that aren't JSON objects with a kind and an id."""
    lines, bad = [], 0
    try:
        f = open(path, encoding="utf-8", errors="replace")
    except FileNotFoundError:
        return lines, bad
    with f:
        for raw in f:
            if not raw.strip():
                continue
            try:
                line = json.loads(raw)
            except json.JSONDecodeError:
                bad += 1
                continue
            if not isinstance(line, dict) or not line.get("kind") or not line.get("id"):
                bad += 1
                continue
            lines.append(line)
    return lines, bad


def join(lines, since=None):
    """Decided routings by id (the first of a duplicate: a re-ask after "Cancel and send elsewhere" decides again under
    the same id, and the original send's inputs are the example worth keeping), each with its last follow-up (a
    correction after a cancel is where it finally went), and the counts of what didn't join."""
    decided, follow = {}, {}
    stats = collections.Counter()
    for line in lines:
        kind, i = line["kind"], line["id"]
        if kind == "decided" and line.get("path") == "fork":
            stats["forks"] += 1  # a fork you asked for from the page: not a routing of your words
        elif kind == "decided":
            stats["duplicate_ids"] += i in decided
            decided.setdefault(i, line)
        elif kind in FOLLOW:
            follow[i] = line
        else:
            stats["unknown_kind:" + str(kind)] += 1
    stats["orphan_followups"] = sum(i not in decided for i in follow)
    out = []
    for i, d in decided.items():
        at = parse_at(d.get("at"))
        if since and (at is None or at < since):
            continue
        out.append((d, follow.get(i)))
    out.sort(key=lambda t: t[0].get("at") or "")
    return out, stats


# ---------------------------------------------------------------- outcome and gold

def outcome(d, f):
    """What became of a decided routing: kept, picked, corrected, cancelled, unanswered (an ask nobody answered)."""
    if f is not None:
        return f["kind"]
    return "unanswered" if d.get("action") == "ask" else "kept"


def gold(d, f):
    """{intended, ask}: where it finally went and whether asking was forbidden, allowed or required."""
    out, asked = outcome(d, f), d.get("action") == "ask"
    if out == "kept":
        return {"intended": d.get("target"), "ask": "forbidden"}
    if out == "picked":
        return {"intended": f.get("target"), "ask": "allowed"}
    if out == "corrected":
        return {"intended": f.get("target"), "ask": "required"}
    if out == "cancelled":
        # A cancel alone says nothing sure (too late, or a change of mind); sent elsewhere it ends in a correction.
        return {"intended": None, "ask": None}
    return {"intended": None, "ask": None}


# ---------------------------------------------------------------- frozen moment

def session_of(inputs):
    """target -> session id, from the options (a card's answer is its session's)."""
    out = {o["target"]: o["session"] for o in inputs.get("options") or [] if o.get("session")}
    return lambda target: out.get(target) or (target[len("session:"):] if target.startswith("session:") else None)


def target_of(inputs):
    """session id -> its first offered target (RouterTools.Facts.targetOf)."""
    out = {}
    for o in inputs.get("options") or []:
        if o.get("session"):
            out.setdefault(o["session"], o["target"])
    return out


def features(inputs, message):
    """RouteFusion.features from the trace's signals and facts, per route target."""
    route, reply, nxt = inputs.get("route") or {}, inputs.get("reply") or {}, inputs.get("next") or {}
    gates, lexical = inputs.get("gates") or {}, inputs.get("lexical") or {}
    latest, running = inputs.get("latest") or [], set(inputs.get("running") or [])
    idle, told = inputs.get("idle") or {}, inputs.get("lastTold")
    sess = session_of(inputs)
    u = route.get("unclear", 0)
    out = {}
    for target, p in route.items():
        if target == "unclear":
            continue
        x = {"lp": math.log(max(p, 0.001))}
        sid = sess(target)
        if sid:
            rank = latest.index(sid) if sid in latest else None
            if rank is not None and rank <= 2:
                x["fin%d" % rank] = 1
            if sid in running:
                x["run"] = 1
            idle5 = sid not in running and idle.get(sid, math.inf) <= 5
            x["reply"] = reply.get(sid, 0)
            if told == sid:
                x["told0"] = 1
            x["fin0u"] = (rank == 0) * u
            x["idle5u"] = idle5 * u
            x["nxt"] = nxt.get(sid, 0)
            for field, by_id in lexical.items():
                x[field] = by_id.get(sid, 0)
            x["session"] = x["sess"] = 1
        elif target.startswith("new:"):
            x["new"] = 1
        elif target in INTENTS:
            x[target] = 1
            x["ilong"] = int(len(message or "") > 80)
            x["you"] = gates.get("gate_you", 0)
            if target == "compound":
                x["g_c"] = gates.get("gate_compound", 0)
                x["c2"] = gates.get("gate_compound2", 0)
            if target == "change_lookout":
                x["g_s"] = gates.get("gate_setting", 0)
            if target == "question":
                x["g_q"] = gates.get("gate_question", 0)
        out[target] = x
    return out


def frozen(d):
    """What a fusion refit reads, as far as the trace has it; None when no fusion ran (rules, your own pin)."""
    inputs = d.get("inputs")
    if not inputs or not inputs.get("route"):
        return None
    facts = {k: inputs.get(k) for k in ("latest", "running", "idle", "lastTold")}
    facts["targetOf"] = target_of(inputs)
    facts["message"] = d.get("message") or ""
    return {
        "options": inputs.get("options") or [],
        "reading": {"dests": inputs.get("route") or {}},
        "signals": {k: inputs.get(k) or {} for k in ("route", "reply", "next", "gates", "lexical")},
        "facts": facts,
        "fs": features(inputs, d.get("message")),
        "shipped": {"ranked": inputs.get("ranked") or [], "sureness": inputs.get("sureness"),
                    "sure": bool(inputs.get("sure")), "card": inputs.get("card")},
        "request": inputs.get("request"),
    }


def record(d, f):
    at = parse_at(d.get("at"))
    g = gold(d, f)
    fz = frozen(d)
    if fz is not None:
        g["in_options"] = g["intended"] in fz["fs"] if g["intended"] else None
    return {
        "id": d["id"], "at": d.get("at"), "group": "trace:" + (at.astimezone().date().isoformat() if at else "unknown"),
        "message": d.get("message"), "pills": d.get("pills"), "pinned": d.get("pinned"), "shown": d.get("shown"),
        "notTo": d.get("notTo"), "replyTo": d.get("replyTo"),
        "path": d.get("path"), "action": d.get("action"), "target": d.get("target"),
        "outcome": outcome(d, f),
        "final": {k: (f or {}).get(k) for k in ("target", "index", "from")} if f else None,
        "gold": g, "frozen": fz,
    }


# ---------------------------------------------------------------- summary

def sure_bin(s):
    lo = max((b for b in SURE_BINS if s >= b), default=None)
    return "<%.2f" % SURE_BINS[0] if lo is None else ">=%.2f" % lo


def summary(joined, stats, bad):
    """Aggregate counts only: nothing of any message."""
    by = collections.Counter("%s/%s" % (d.get("path"), d.get("action")) for d, _ in joined)
    asks = [(d, f) for d, f in joined if d.get("action") == "ask"]
    sends = [(d, f) for d, f in joined if d.get("action") in SENDS]
    index = collections.Counter(str(f.get("index")) for _, f in asks if f and f["kind"] in ("picked", "corrected"))
    sure = collections.Counter(sure_bin(d["inputs"]["sureness"]) for d, _ in sends
                               if (d.get("inputs") or {}).get("sureness") is not None)
    later = collections.Counter(outcome(d, f) for d, f in sends)
    return {
        "routings": len(joined),
        "by_path_action": dict(sorted(by.items())),
        "with_inputs": sum(frozen(d) is not None for d, _ in joined),
        "asks": {"n": len(asks), **collections.Counter(outcome(d, f) for d, f in asks),
                 "button_index": dict(sorted(index.items()))},
        "sends": {"n": len(sends), "kept": later["kept"], "corrected_later": later["corrected"],
                  "cancelled_later": later["cancelled"], "sureness": {b: sure[b] for b in sorted(sure)}},
        "skipped": {"bad_lines": bad, **{k: v for k, v in sorted(stats.items()) if v}},
    }


# ---------------------------------------------------------------- main

def write(records, out):
    out.parent.mkdir(parents=True, exist_ok=True)
    with out.open("w") as f:
        f.writelines(json.dumps(r, ensure_ascii=False) + "\n" for r in records)


def inside_data(path):
    try:
        path.resolve().relative_to(DATA.resolve())
        return True
    except ValueError:
        return False


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("command", choices=("summary", "export"))
    parser.add_argument("--trace", type=pathlib.Path, default=TRACE)
    parser.add_argument("--since", help="only routings decided on or after this ISO date or datetime")
    parser.add_argument("--out", type=pathlib.Path, default=OUT)
    args = parser.parse_args(argv)
    since = parse_at(args.since) if args.since else None
    if args.since and since is None:
        parser.error("--since: not an ISO date: %s" % args.since)
    lines, bad = read(args.trace)
    joined, stats = join(lines, since)
    if args.command == "summary":
        print(json.dumps(summary(joined, stats, bad), indent=1))
        return 0
    if not inside_data(args.out):
        parser.error("--out must be under %s (gitignored): the records hold your messages" % DATA)
    records = [record(d, f) for d, f in joined]
    write(records, args.out)
    print(json.dumps({"records": len(records), "with_gold": sum(r["gold"]["intended"] is not None for r in records),
                      "with_frozen": sum(r["frozen"] is not None for r in records), "out": str(args.out)}))
    return 0


if __name__ == "__main__":
    sys.exit(main())
