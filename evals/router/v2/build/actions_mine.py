"""Real action gold from your transcripts (v2/ACTIONS.md): the board at the moment you answered a session's
AskUserQuestion form, approved or sent back an ExitPlanMode plan, or interrupted a running turn, rebuilt with states.py.

    python3 v2/build/actions_mine.py [--cache DIR ...]   →  v2/data/actions/{dev,calib,sealed}/mined.jsonl

- answer: one episode per answered form; the message is your answer as you'd type it to the Router (several questions
  one line each). An option you clicked is its label (`typed: false`), an answer you wrote is your text (`typed: true`),
  a form with both is `typed: "mixed"`. Gold `answer:card:<the form's card>`, only (a form takes no plain message).
  A form you dismissed counts only when you then typed the answer within 5 minutes.
- plan: ExitPlanMode → `approve:card` when approved, `answer:card` with your feedback when sent back.
- interrupt: a turn you interrupted, on the board just before (the session running). The message is the one you typed
  within two minutes after (or queued before and sent by interrupting): `interrupt:session:<id>` when it says anything
  more than stop, `stop:session:<id>` when it is a bare stop/wait. With no message, the episode's message is "stop",
  rendered (`typed: false`), gold `stop:session:<id>`, and an ask is required when several sessions run. `say` is never
  acceptable for these.
Turn cards' kinds come from triage answers already cached (no Jev call); a miss leaves the card `done`, as
states.py --no-jev does. Everything is redacted; only counts are printed (sealed: totals only)."""
import argparse
import collections
import hashlib
import json
import os
import pathlib
import re
import sys
from datetime import datetime

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import actions_common as A  # noqa: E402
import episode_common as C  # noqa: E402
import states as S  # noqa: E402
import triage as T  # noqa: E402

PROBE_CWD = re.compile(r"^/(private/)?tmp/")
BARE_STOP = re.compile(r"^\s*(stop|wait|hold on|hold|pause|no+|nope|cancel|abort|halt|attends?|arr[êe]te|stop it|"
                       r"stop stop|wait wait)\s*[.!]*\s*$", re.I)
AFTER_S = 120
DISMISSED_S = 300


def cache_only(dirs):
    """jev.ask that only reads cached answers (either key order) from `dirs`; a miss raises (triage leaves `done`)."""
    def ask(state, questions, model="jev-latest", cache=True, sample=0):
        body = {"model": model, "state": state, "questions": questions}
        for sort in (True, False):
            raw = json.dumps(body, sort_keys=sort)
            digest = hashlib.sha256((raw + f"#{sample}").encode()).hexdigest()
            for d in dirs:
                path = pathlib.Path(d) / digest[:2] / f"{digest}.json"
                if path.exists():
                    return json.loads(path.read_text())
        raise LookupError("not cached")
    return ask


def answer_text(fm):
    """(message, typed) for an answered form: per question the label you clicked or the text you wrote."""
    ans = fm.get("answers") or {}
    parts, kinds = [], []
    for q in fm["input"].get("questions") or []:
        if not isinstance(q, dict):
            continue
        labels = [o.get("label") for o in q.get("options") or [] if isinstance(o, dict)]
        a = ans.get(q.get("question"))
        if a is None:
            continue
        vals = a if isinstance(a, list) else [a]
        joined = ", ".join(str(v) for v in vals)
        clicked = joined in labels or all(str(v).strip() in labels for v in
                                          (vals if isinstance(a, list) else joined.split(",")))
        # A clicked label as you'd type it: without the "(Recommended)" the session tagged it with.
        parts.append(re.sub(r"\s*\(Recommended\)", "", joined, flags=re.I) if clicked else joined)
        kinds.append(not clicked)
    if not parts:
        text = S.form_answer_text(fm)
        return (text, True) if text else (None, None)
    typed = True if all(kinds) else False if not any(kinds) else "mixed"
    return "\n".join(parts), typed


def episode(kind, s, now, state, gold, message, typed, extra, group):
    tags = {"primary": kind, "flow": "single", "lang": C.lang(message),
            "slices": sorted({kind, "typed" if typed is True else "clicked" if typed is False else "mixed"} | set(extra.get("slices", [])))}
    return {"schema": 2, "id": f"act-mined-{s.short}-{kind}-{int(now)}", "family": kind, "group": group,
            "provenance": {"source": "real-moment", "set": "actions-mined", "writer": "human", "writer_model": "real transcript",
                           "state_fidelity": "transcript", "synthetic": ["message"] if typed is False else [],
                           "typed": typed, **{k: v for k, v in extra.items() if k != "slices"}},
            "tags": tags, "state": state,
            "events": [{"id": "e1", "kind": "submit", "message": message, "context": dict(A.CONTEXT), "gold": gold}]}


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--cache", nargs="*", default=[str(HERE.parents[1] / "cache")],
                    help="Jev cache folders to read triage answers from (read-only)")
    args = ap.parse_args()
    T.jev.ask = cache_only(args.cache)

    files = S.load_files()
    sessions = [S.Session(f) for f in files if f["entry"] == "claude-desktop"]
    sessions = [s for s in sessions if s.start is not None]
    cards = {s.id: S.cards_of(s) for s in sessions}
    dropped = collections.Counter()
    found = collections.Counter()
    todo = []          # (kind, session, now, target, payload)

    for f in files:
        if f["entry"] != "claude-desktop":
            sess = S.Session(f)
            found["interrupt (all)"] += sum(t["interrupted"] for t in sess.turns)
            dropped["interrupt: CLI session, not on Fjord's board"] += sum(t["interrupted"] for t in sess.turns)
            found["AskUserQuestion (all)"] += sum(fm["name"] == "AskUserQuestion" for fm in sess.forms)
            dropped["AskUserQuestion: CLI session"] += sum(fm["name"] == "AskUserQuestion" for fm in sess.forms)

    for s in sessions:
        probe = bool(PROBE_CWD.match(s.cwd or "")) or S.automated(s)
        rejected_forms = []
        for fm in s.forms:
            name = fm["name"]
            found[f"{name} (all)"] += 1
            if probe:
                dropped[f"{name}: probe/test session (/tmp or scripted)"] += 1
                continue
            if fm["tb"] == float("inf"):
                dropped[f"{name}: never answered"] += 1
                continue
            if name == "ExitPlanMode":
                if not fm["error"]:
                    todo.append(("plan", s, fm["tb"], fm, {"approved": True}))
                elif "doesn't want to proceed" in fm["result"]:
                    nxt = [p for p in s.human if fm["tb"] - 5 < p["typed"] < fm["tb"] + DISMISSED_S]
                    if nxt:
                        todo.append(("plan", s, fm["tb"], fm, {"approved": False, "text": nxt[0]["text"]}))
                    else:
                        dropped["ExitPlanMode: sent back with no feedback"] += 1
                else:
                    dropped["ExitPlanMode: tool error"] += 1
                continue
            if fm["error"]:
                rejected_forms.append(fm)
                if "doesn't want to proceed" in fm["result"]:
                    nxt = [p for p in s.human if fm["tb"] - 5 < p["typed"] < fm["tb"] + DISMISSED_S]
                    if nxt:
                        todo.append(("answer", s, fm["tb"], fm, {"text": nxt[0]["text"], "dismissed": True}))
                    else:
                        dropped["AskUserQuestion: dismissed, nothing typed after"] += 1
                else:
                    dropped["AskUserQuestion: tool error (stream closed)"] += 1
                continue
            todo.append(("answer", s, fm["tb"], fm, {}))
        for turn in s.turns:
            if not turn["interrupted"]:
                continue
            found["interrupt (all)"] += 1
            if probe:
                dropped["interrupt: probe/test session"] += 1
                continue
            end = turn["end"]
            if any(abs(fm["tb"] - end) < 3 for fm in rejected_forms):
                dropped["interrupt: a dismissed form (counted with the forms)"] += 1
                continue
            nxt = [p for p in s.human if turn["start"] < p["typed"] <= end + AFTER_S]
            todo.append(("interrupt", s, end, turn, {"next": nxt[0] if nxt else None}))

    # Boards, then the turn cards' kinds from cached triage.
    built, need = [], {}
    for kind, s, t, obj, extra in todo:
        if kind == "interrupt" and extra["next"] is not None:
            now = min(t, extra["next"]["typed"]) - 1e-3
        else:
            now = t - 1e-3
        st, open_cards, facts = S.board(sessions, cards, now)
        for sess, c in open_cards:
            if "turn" in c and c["turn"]["final"]:
                need[c["id"]] = (sess, c)
        built.append((kind, s, now, obj, extra, st, open_cards, facts))
    ids = sorted(need)
    items = [(S.redact(need[c][1]["turn"]["final"]), S.redact(need[c][0].title_at(need[c][1]["created"])), need[c][0].project)
             for c in ids]
    triaged = {cid: r for cid, r in zip(ids, T.triage_many(items)) if r is not None} if items else {}
    triage_stats = {"turn cards": len(ids), "kind from cache": len(triaged)}

    out = collections.defaultdict(list)
    frozen = A.frozen()
    for kind, s, now, obj, extra, st, open_cards, facts in built:
        st["cards"] = [S.card_json(sess, c, now, triaged) for sess, c in sorted(open_cards, key=lambda x: x[1]["created"])]
        state = C.trim_state(st)
        row = next((r for r in state["sessions"] if r["id"] == s.short), None)
        group = f"{s.short}:{datetime.fromtimestamp(now, S.TZ).date().isoformat()}"
        if kind in ("answer", "plan"):
            cid = f"{s.short}#w{int(obj['ta'] * 1000)}"
            if not any(c["id"] == cid for c in state["cards"]):
                dropped[f"{kind}: form card not on the board"] += 1
                continue
            if kind == "plan" and extra.get("approved"):
                message, typed = "approve", False
                g = A.gold(f"approve:card:{cid}", [f"approve:card:{cid}", f"answer:card:{cid}"], state, method="mined",
                           evidence="you approved this plan")
            else:
                if "text" in extra:
                    message, typed = extra["text"], True
                else:
                    message, typed = answer_text(obj)
                if not message:
                    dropped[f"{kind}: empty answer"] += 1
                    continue
                g = A.gold(f"answer:card:{cid}", [f"answer:card:{cid}"], state, method="mined",
                           evidence="you answered this form" + (" (dismissed it, then typed)" if extra.get("dismissed") else ""))
            message = C.redact(message).strip()
            ep = episode("answer-card" if kind == "answer" else "plan-card", s, now, state, g, message, typed,
                         {"card_kind": "question" if kind == "answer" else "plan", "dismissed": bool(extra.get("dismissed"))},
                         group)
        else:
            if row is None or not row.get("running"):
                dropped["interrupt: session not running on the board (waiting on a form or not listed)"] += 1
                continue
            p = extra["next"]
            running = [r["id"] for r in state["sessions"] if r.get("running")]
            target = s.short
            if p is None:
                message, typed = "stop", False
                bare, several = True, len(running) > 1
            else:
                message, typed = C.redact(p["text"]).strip(), True
                bare, several = bool(BARE_STOP.match(message)), False
            if bare:
                g = A.gold(f"stop:session:{target}", [] if several else [f"stop:session:{target}"], state,
                           ask="required" if several else "allowed", method="mined",
                           clarify=[f"stop:session:{r}" for r in running if r != target] if several else (),
                           evidence="you interrupted this turn" + (" and typed nothing" if p is None else " with a bare stop"))
                fam = "stop"
            else:
                g = A.gold(f"interrupt:session:{target}", [f"interrupt:session:{target}"], state, method="mined",
                           evidence="you interrupted this turn and sent this")
                fam = "interrupt"
            gap = None if p is None else round(p["typed"] - obj["end"])
            ep = episode(fam, s, now, state, g, message, typed,
                         {"interrupt_gap_s": gap, "turn_s": round(obj["end"] - obj["start"]),
                          "last_in_session": obj is s.turns[-1], "message_rendered": p is None,
                          "slices": (["several-running"] if len(running) > 1 else ["one-running"])
                          + (["stopped-within-5s"] if obj["end"] - obj["start"] < 5 else [])}, group)
        split = frozen.get(group) or A.hash_split(group)
        ep["provenance"]["split_rule"] = "frozen" if group in frozen else "hash"
        out[split].append(ep)

    for split in ("dev", "calib", "sealed"):
        eps = sorted(out.get(split, []), key=lambda e: e["state"]["now"])
        A.write(A.OUT / split / "mined.jsonl", eps)
    report = {"found": dict(found), "dropped": dict(dropped), "triage": triage_stats}
    for split in ("dev", "calib", "sealed"):
        eps = out.get(split, [])
        report[split] = {"episodes": len(eps), "groups": len({e["group"] for e in eps}),
                         "by_family": dict(collections.Counter(e["family"] for e in eps))}
        if split != "sealed":
            report[split]["typed"] = dict(collections.Counter(str(e["provenance"]["typed"]) for e in eps))
    leaks = sum(len(C.leaks(json.dumps(e, ensure_ascii=False))) for eps in out.values() for e in eps)
    report["leak_scan_hits"] = leaks
    print(json.dumps(report, indent=1))


if __name__ == "__main__":
    main()
