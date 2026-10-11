"""Writing packets for the three writer families (Router benchmark v2, stage B1).

    python3 v2/build/packets.py [--seed 11] [--per-writer 350]  →  v2/data/packets/{claude,gpt,gemini}.jsonl

Each packet is one writing task (instructions: v2/build/WRITERS.md): a trimmed real board (from a moment the real-moment
episodes don't use, where possible; spread over every session-day group), a mode ("rewrite": a real message and where it
went, to re-phrase as you'd type it in the Router composer; or "goal": something to pursue on that board), an assigned
primary family and flow (balanced over BENCHMARK.md's 16 families and 15 flows, evenly across writers; rewrite 45% /
goal 55%), the contexts that flow needs (armed reply, pills, pin, prediction shown / waved off, @router), and a style
profile from research/behavior.md with three short real example messages of that style from other moments (redacted).
Writers return episodes without `state`; the merger attaches the packet's state by `packet`."""
import argparse
import collections
import json
import random
import re

import episode_common as C

OUT = C.DATA / "packets"
REAL = C.DATA / "episodes" / "raw" / "real.jsonl"
WRITERS = ["claude", "gpt", "gemini"]
REWRITE_SHARE = 0.45

# which flows make sense for each primary family (the family describes the episode's key submit)
COMPAT = {
    "bare-answer": ["single", "ask-pick-follow", "ask-then-typed", "armed-reply", "backlog", "card-arrives-midway",
                    "chain", "prediction-shown", "prediction-waved-off", "correction-after-wrong", "switch-back"],
    "option-pick": ["single", "armed-reply", "ask-pick-follow", "card-arrives-midway", "backlog", "prediction-shown",
                    "correction-after-wrong"],
    "approval": ["single", "armed-reply", "ask-pick-follow", "backlog", "chain", "pinned", "prediction-shown",
                 "correction-after-wrong"],
    "rejection": ["single", "armed-reply", "ask-then-typed", "chain", "backlog", "correction-after-wrong"],
    "topical-follow-up": ["single", "chain", "switch-back", "ask-pick-follow", "prediction-shown",
                          "prediction-waved-off", "pinned", "correction-after-wrong", "new-then-follow"],
    "next-instruction": ["single", "chain", "switch-back", "pinned", "prediction-shown", "prediction-waved-off",
                         "ask-then-typed", "card-arrives-midway", "new-then-follow"],
    "question-to-session": ["single", "chain", "switch-back", "ask-pick-follow", "armed-reply", "prediction-waved-off",
                            "correction-after-wrong", "intent-then-session"],
    "explicit-address": ["single", "switch-back", "backlog", "ask-then-typed", "correction-after-wrong", "chain"],
    "switch": ["single", "switch-back", "backlog", "card-arrives-midway", "ask-pick-follow", "correction-after-wrong"],
    "correction": ["correction-after-wrong", "ask-then-typed"],
    "new-session": ["single", "pill-start", "new-then-follow", "ask-pick-follow", "correction-after-wrong"],
    "lookout-setting": ["single", "intent-then-session", "armed-reply", "ask-pick-follow", "correction-after-wrong"],
    "board-question": ["single", "intent-then-session", "backlog", "ask-then-typed"],
    "compound": ["single", "intent-then-session", "chain", "correction-after-wrong"],
    "paste": ["single", "chain", "switch-back", "ask-pick-follow", "new-then-follow", "armed-reply", "pill-start"],
    "small-talk": ["single", "chain", "ask-then-typed", "armed-reply"],
}
REWRITABLE = {"bare-answer", "option-pick", "approval", "rejection", "topical-follow-up", "next-instruction",
              "question-to-session", "explicit-address", "switch", "correction", "new-session", "paste"}

FLOW_SPEC = {
    "single": "One submit. Add an on.ask pick branch unless ask is forbidden.",
    "ask-pick-follow": "Submit 1 is the kind of message a careful router might ask about; on.ask → a pick event of the "
                       "intended target; then a follow-up submit (about a minute later) that belongs with what you just "
                       "picked (e.g. 'also run the tests').",
    "ask-then-typed": "Submit 1 is vague; on.ask → a NEW submit where you ignore the ask card and retype the message "
                      "more explicitly (a typed message while an ask waits is a new message, never a pick).",
    "correction-after-wrong": "Submit 1 is plausibly misroutable; on.wrong → a correction submit as you would type it "
                              "after seeing it land in the wrong place ('no, that was for the lcu one', 'wrong session, "
                              "send it to the inbox bug'), whose gold is the right target; on.ask → a pick.",
    "chain": "2–4 submits to the same session (follow-ups while it works or right after it finishes), with board "
             "events between them when the session finishes or other sessions change.",
    "switch-back": "A → B → A: talk to one session, switch to another for one message, come back to the first.",
    "card-arrives-midway": "Talk to one session; a board event adds a new card from another session (grounded in that "
                           "session's summary/turns; list it in provenance.synthetic); then either answer the new card "
                           "or keep going with the first session (say which in the gold evidence).",
    "backlog": "3–5 submits clearing older waiting sessions one after another, mostly terse or anaphoric replies "
               "('yes push it', 'commit', 'what failed?'), targets not always the most recent card.",
    "new-then-follow": "Start a new session (gold new:<project>), then a follow-up to it; the started session's id is "
                       "'started-<event id of the start submit>', so the follow-up gold is session:started-e1.",
    "armed-reply": "Reply armed on a card: context.replyTo = that card's id. Usually the message is for that card's "
                   "session; sometimes (C4) it is plainly for elsewhere (a Lookout setting, another session) — then "
                   "gold is where YOU meant it to go.",
    "pill-start": "One @project pill: context.pills = [project]. A start phrase or a task for that project (gold "
                  "new:<project>), or, when the project has a matching session, words that continue it.",
    "pinned": "You clicked a prediction chip first: context.pinned = the target. Gold is that target.",
    "prediction-shown": "A sure live prediction chip was shown for these exact words: context.shown = the target it "
                        "showed; you send as shown (gold = shown) or, in a minority, the chip was wrong and gold differs.",
    "prediction-waved-off": "You dismissed the live prediction with Esc: context.notTo = the target you waved off; gold "
                            "is somewhere else (or an ask).",
    "intent-then-session": "First a message for Lookout itself (change_lookout or question), then a message for a "
                           "session on the board.",
}
FAMILY_SPEC = {
    "bare-answer": "a short answer to a question a session asked ('postgres', 'the second', 'yes, both')",
    "option-pick": "picks one of a card's options, by label, content or ordinal",
    "approval": "approves what a session asks or proposes ('yes push it', 'go ahead', 'lgtm')",
    "rejection": "declines or stops what a session proposes ('no don't push', 'skip that')",
    "topical-follow-up": "continues the topic a session just reported on, often anaphoric ('and the docs too?')",
    "next-instruction": "a new piece of work for an existing session after it finished",
    "question-to-session": "a question to a session about its own work ('did the tests pass?', 'why 3 retries?')",
    "explicit-address": "names its destination ('tell the lcu one to…', 'inbox bug: …', 'back to the router evals: …')",
    "switch": "goes to a different existing session than your previous message, unnamed",
    "correction": "corrects a wrong delivery by the Router ('no, that was for…')",
    "new-session": "starts new work that belongs in a new session (maybe near a similar sibling)",
    "lookout-setting": "asks Lookout itself to change a setting, category, group, rule or inbox mark (target change_lookout)",
    "board-question": "asks Lookout about the board ('what's waiting on me?', 'is the CI one done?') (target question)",
    "compound": "a Lookout part plus a session part in one message (target compound)",
    "paste": "a pasted error, log, stack trace or URL, with or without a line of text",
    "small-talk": "a fragment or pleasantry with no clear destination ('hmm', 'thanks', 'wait')",
}
STYLE_SPEC = {
    "terse continuation": "1–6 words, no capital or punctuation needed, leans on what the session just said",
    "technical paste": "pasted code, error lines, logs, paths or URLs, often with a one-line ask",
    "direct address": "names the project, product or session it is about (Lookout, LCU, Silo, msb, 'the CI one')",
    "French/code-switching": "French, or French mixed with English technical words (about 3% of your traffic)",
    "typo-heavy": "fast typing: typos, missing words, no punctuation, lowercase",
    "detailed constraints": "a longer instruction with explicit constraints (keep it minimal, don't touch X, only Y)",
    "blunt correction": "short and blunt, opens with no / wait / actually / stop",
}
STYLE_WEIGHTS = {"terse continuation": 22, "technical paste": 12, "direct address": 14, "French/code-switching": 8,
                 "typo-heavy": 14, "detailed constraints": 16, "blunt correction": 14}
STYLE_FOR = {"paste": "technical paste", "correction": "blunt correction", "explicit-address": "direct address"}


def style_ok(style, fam, flow):
    """Style profiles that can carry this family/flow (a blunt correction can't ask a board question)."""
    if style == "blunt correction":
        return fam in {"correction", "rejection"} or flow in {"correction-after-wrong", "ask-then-typed"}
    if style == "technical paste":
        return fam in {"paste", "next-instruction", "question-to-session", "new-session", "topical-follow-up", "switch",
                       "explicit-address", "correction"}
    if style == "terse continuation":
        return fam not in {"new-session", "compound", "paste"}
    if style == "detailed constraints":
        return fam not in {"small-talk", "bare-answer", "option-pick"}
    return True


def assign(n, rng):
    """(family, flow) slots, families and flows both near-even: alternate between the scarcest family and flow."""
    fam_n, flow_n = collections.Counter(), collections.Counter()
    by_flow = collections.defaultdict(list)
    for fam, flows in COMPAT.items():
        for fl in flows:
            by_flow[fl].append(fam)
    slots = []
    for i in range(n):
        if i % 2:
            fl = min(C.FLOWS, key=lambda f: (flow_n[f], rng.random()))
            fam = min(by_flow[fl], key=lambda f: (fam_n[f], rng.random()))
        else:
            fam = min(C.FAMILIES, key=lambda f: (fam_n[f], rng.random()))
            fl = min(COMPAT[fam], key=lambda f: (flow_n[f], rng.random()))
        fam_n[fam] += 1
        flow_n[fl] += 1
        slots.append((fam, fl))
    return slots


def finished_order(state):
    """Sessions not running, most recently finished first."""
    return sorted([s for s in state["sessions"] if not s.get("running") and not s.get("archived")],
                  key=lambda s: s.get("idle_min", 1e9))


def pick_rank(rng, n):
    ranks = [0, 1, 2] + list(range(3, max(n, 4)))
    weights = [36, 32, 18] + [13 / max(n - 3, 1)] * max(n - 3, 1)
    return min(rng.choices(ranks[:len(weights)], weights=weights)[0], max(n - 1, 0))


def card_fits(fam, flow, state):
    cards = state["cards"]
    kinds = collections.Counter(c["kind"] for c in cards)
    if fam == "option-pick":
        return any(c.get("options") for c in cards) or any(re.search(r"\bor\b", c["text"]) and c["kind"] == "asks"
                                                           for c in cards)
    if fam == "approval":
        return kinds["approval"] + kinds["plan"] > 0 or any(C.WANTS.search(c["text"]) for c in cards)
    if fam in {"bare-answer", "rejection"}:
        return kinds["asks"] + kinds["question"] + kinds["approval"] + kinds["plan"] > 0
    if flow == "backlog":
        return len(cards) >= 4
    if flow in {"armed-reply", "card-arrives-midway"}:
        return len(cards) >= 1
    if fam == "correction" or flow == "correction-after-wrong":
        projects = collections.Counter(s["project"] for s in state["sessions"])
        return any(v >= 2 for v in projects.values())
    return True


def sdesc(s):
    return f'session:{s["id"]} "{s["title"]}" ({s["project"]}, idle {round(s.get("idle_min", 0))} min)'


def goal_for(fam, flow, state, rng):
    """A goal grounded on the board: what you want, never the words. Returns (goal, target_hint)."""
    fin = finished_order(state)
    cards = state["cards"]
    if flow == "armed-reply":  # the armed card must be the destination's (lookout-setting stays a C4 case)
        fin = [s for s in fin if any(c["session"] == s["id"] for c in cards)] or fin
    if flow == "pill-start":  # a pill names a project Lookout knows
        fin = [s for s in fin if s["project"] in state["projects"]] or fin
    sessions = {s["id"]: s for s in state["sessions"]}
    running = [s for s in state["sessions"] if s.get("running")]

    def card_of(pred):
        cs = [c for c in cards if pred(c) and c["session"] in sessions]
        cs.sort(key=lambda c: c.get("created_min_ago", 0))
        return cs[min(pick_rank(rng, len(cs)), len(cs) - 1)] if cs else None

    def recent():
        if not fin:
            return rng.choice(state["sessions"])
        return fin[pick_rank(rng, len(fin))]

    if fam == "option-pick":
        c = card_of(lambda c: c.get("options")) or card_of(lambda c: c["kind"] in {"asks", "question"})
        if c:
            return (f'Answer card {c["id"]} of {sdesc(sessions[c["session"]])} by choosing one of its options '
                    f'(by label, content or ordinal, as you would type it).', "session:" + c["session"])
    if fam == "approval":
        c = card_of(lambda c: c["kind"] in {"approval", "plan"}) or card_of(lambda c: bool(C.WANTS.search(c["text"])))
        if c:
            return (f'Approve what card {c["id"]} of {sdesc(sessions[c["session"]])} asks or proposes.',
                    "session:" + c["session"])
    if fam == "rejection":
        c = card_of(lambda c: c["kind"] in {"approval", "plan", "asks", "question"})
        if c:
            return (f'Decline or redirect what card {c["id"]} of {sdesc(sessions[c["session"]])} proposes.',
                    "session:" + c["session"])
    if fam == "bare-answer":
        c = card_of(lambda c: c["kind"] in {"asks", "question", "approval"})
        if c:
            return (f'Give a short answer to card {c["id"]} of {sdesc(sessions[c["session"]])}.', "session:" + c["session"])
    if fam == "new-session":
        known = state["projects"] or ["scratch"]
        busy = [p for p in dict.fromkeys(s["project"] for s in state["sessions"]) if p in known]
        p = rng.choice(busy) if busy and rng.random() < .89 else rng.choice(known)
        sib = [s for s in state["sessions"] if s["project"] == p][:3]
        sibs = "; siblings on the board: " + ", ".join(sdesc(s) for s in sib) if sib else ""
        return (f'Start new work in project "{p}" that belongs in a NEW session (plausible next work for that project '
                f'given the board; it may sit close to a sibling but must be distinct){sibs}.', "new:" + p)
    if fam == "lookout-setting":
        near = [s for s in state["sessions"] if s["project"] == "lookout"]
        trap = f' A session building Lookout is on the board ({sdesc(near[0])}); the setting must still be for Lookout ' \
               f'itself, not that session.' if near and rng.random() < .4 else ""
        return ("Ask Lookout to change one of its own settings, categories, groups, rules or inbox marks (notifications, "
                "Jev labels, a category for some kind of card, mark some cards read, ...), plausibly motivated by this "
                "board." + trap, "change_lookout")
    if fam == "board-question":
        return ("Ask Lookout a read-only question about this board (what's waiting, which session did X, is Y done, "
                "what failed), answerable from the board.", "question")
    if fam == "compound":
        s = recent()
        return (f'In one message, ask Lookout to change something about itself AND tell {sdesc(s)} to do its next step.',
                "compound")
    if fam == "small-talk":
        s = recent()
        return (f'React to what {sdesc(s)} just reported with a fragment or pleasantry, not an instruction.',
                "session:" + s["id"])
    if fam == "explicit-address":
        s = fin[min(1 + pick_rank(rng, max(len(fin) - 1, 1)), len(fin) - 1)] if len(fin) > 1 else recent()
        return (f'Give {sdesc(s)} its next instruction or question, naming it the way you would (project, product or a '
                f'word of its topic — never its id).', "session:" + s["id"])
    if fam == "switch":
        s = fin[min(1 + pick_rank(rng, max(len(fin) - 1, 1)), len(fin) - 1)] if len(fin) > 1 else recent()
        return (f'Switch to {sdesc(s)} (not the most recent session) and give it a follow-up, without naming it.',
                "session:" + s["id"])
    if fam == "correction":
        projects = collections.defaultdict(list)
        for s in fin:
            projects[s["project"]].append(s)
        pairs = [v for v in projects.values() if len(v) >= 2]
        if pairs:
            a, b = rng.sample(rng.choice(pairs), 2)
            return (f'Send {sdesc(a)} a message that the Router could plausibly deliver to its sibling {sdesc(b)}; '
                    f'then correct the wrong delivery.', "session:" + a["id"])
    if fam == "paste":
        s = running[0] if running and rng.random() < .25 else recent()
        return (f'Paste an error, log excerpt or URL relevant to {sdesc(s)}\'s work (keep it consistent with its '
                f'summary and turns; do not invent new facts about it), with or without a line of text.',
                "session:" + s["id"])
    s = running[0] if running and rng.random() < .2 else recent()
    what = {"topical-follow-up": "follow up on what it just reported",
            "next-instruction": "give it the next piece of work",
            "question-to-session": "ask it a question about its own work"}.get(fam, "follow up")
    return f"{what.capitalize()} — {sdesc(s)}.", "session:" + s["id"]


def contexts_for(fam, flow, state, target, rng):
    """What the Router composer carries; the writer fills the exact values in event.context."""
    out = {}
    cards = [c for c in state["cards"]]
    if flow == "armed-reply":
        tc = [c for c in cards if target and target.startswith("session:") and c["session"] == target[8:]]
        tc.sort(key=lambda c: c.get("created_min_ago", 0))
        if tc:
            out["replyTo"] = tc[0]["id"]
        elif cards:
            out["replyTo"] = sorted(cards, key=lambda c: c.get("created_min_ago", 0))[0]["id"]
            out["note"] = ("C4: the armed card is NOT where your words are meant to go; write the message for its real "
                           "destination as someone who forgot the reply chip was armed")
    if flow == "pill-start":
        out["pills"] = [target[4:] if target and target.startswith("new:") else
                        next((s["project"] for s in state["sessions"] if target and s["id"] == target[8:]), "")]
    if flow == "pinned":
        out["pinned"] = target
    if flow == "prediction-shown":
        out["shown"] = target
    if flow == "prediction-waved-off":
        fin = [s for s in finished_order(state) if not target or "session:" + s["id"] != target]
        if fin:
            out["notTo"] = "session:" + fin[0]["id"]
    if fam in {"lookout-setting", "board-question"} and rng.random() < .35:
        out["@router"] = "whole message for the Router: begin it with '@router'"
    elif fam in {"next-instruction", "topical-follow-up", "question-to-session"} and rng.random() < .06:
        out["router_aside"] = "include an @router aside in parentheses, e.g. '(@router no rush)'; set router_aside true"
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--seed", type=int, default=11)
    ap.add_argument("--per-writer", type=int, default=350)
    args = ap.parse_args()
    rng = random.Random(args.seed)
    moments = C.load_moments()
    by_id = {m["id"]: m for m in moments}
    real_used = set()
    if REAL.exists():
        for line in REAL.open():
            real_used.update(json.loads(line)["provenance"]["anchors"])
    fams = {m["id"]: C.family_of(m) for m in moments}
    styles = {m["id"]: C.styles_of(m) for m in moments}
    ok = [m for m in moments if len(m["message"] or "") <= 20000 and
          (m["went_to"][4:] in m["state"]["projects"] if m["went_to"].startswith("new:")
           else any(s["id"] == m["went_to"] for s in m["state"]["sessions"]))]
    n = args.per_writer * len(WRITERS)
    slots = assign(n, rng)
    slots.sort()
    # deal round-robin over (family, flow)-sorted slots: per writer, families/flows differ by at most ~1
    dealt = {w: [] for w in WRITERS}
    for i, slot in enumerate(slots):
        dealt[WRITERS[(i + i // len(WRITERS)) % len(WRITERS)]].append(slot)
    # modes: per writer 45% rewrite, spread over rewritable families
    plan = []
    for w in WRITERS:
        mine = list(dealt[w])
        rng.shuffle(mine)
        k = round(len(mine) * REWRITE_SHARE)
        elig = [i for i, (fam, _) in enumerate(mine) if fam in REWRITABLE]
        per_fam = collections.defaultdict(list)
        for i in elig:
            per_fam[mine[i][0]].append(i)
        chosen = set()
        while len(chosen) < k and any(per_fam.values()):
            for fam in sorted(per_fam, key=lambda f: rng.random()):
                if per_fam[fam] and len(chosen) < k:
                    chosen.add(per_fam[fam].pop())
        for i, (fam, flow) in enumerate(mine):
            plan.append((w, fam, flow, "rewrite" if i in chosen else "goal"))
    # moments: rewrites first (they need a matching message), unused by real episodes and other packets first,
    # least-used group first
    use = collections.Counter()
    group_use = collections.Counter()
    rng.shuffle(plan)
    plan.sort(key=lambda p: p[3] != "rewrite")

    def rewrite_ok(m, fam, flow):
        f = fams[m["id"]]
        new = m["went_to"].startswith("new:")
        if flow == "armed-reply" and not any(c["session"] == m["went_to"] for c in m["state"]["cards"]):
            return False
        if fam == "explicit-address":
            return not new and m["flags"]["transition"] == "switch"
        if fam == "correction":
            return not new and card_fits(fam, flow, m["state"])
        if flow in {"new-then-follow", "pill-start"}:
            return new
        if fam == "switch":
            return f == "switch" or (not new and m["flags"]["transition"] == "switch")
        return f == fam and (fam == "new-session") == new

    packets = {w: [] for w in WRITERS}
    for w, fam, flow, mode in plan:
        if mode == "rewrite":
            pool = [m for m in ok if rewrite_ok(m, fam, flow)]
            if not pool:
                mode = "goal"
        if mode == "goal":
            pool = [m for m in ok if card_fits(fam, flow, m["state"])] or ok
        pool.sort(key=lambda m: (use[m["id"]], m["id"] in real_used, group_use[m["group"]], rng.random()))
        m = pool[0]
        use[m["id"]] += 1
        group_use[m["group"]] += 1
        state = C.trim_state(m["state"])
        if mode == "rewrite":
            t = m["went_to"]
            target = t if t.startswith("new:") else "session:" + t
            task = {"real": {"moment": m["id"], "message": C.redact(m["message"]), "went_to": target,
                             "transition": m["flags"]["transition"], "recency_rank": m["flags"].get("recency_rank"),
                             "heuristic_family": fams[m["id"]], "sent_while_running": m["flags"]["running_target"]}}
        else:
            goal, target = goal_for(fam, flow, state, rng)
            task = {"goal": goal, "target_hint": target}
        # style: family-bound for a few families, else weighted; the moment's own style for rewrites when it has one
        own = [x for x in styles[m["id"]] if style_ok(x, fam, flow)] if mode == "rewrite" else []
        if fam in STYLE_FOR and rng.random() < .7:
            style = STYLE_FOR[fam]
        elif own and rng.random() < .35:
            style = rng.choice(own)
        else:
            fit = [x for x in STYLE_WEIGHTS if style_ok(x, fam, flow)]
            style = rng.choices(fit, weights=[STYLE_WEIGHTS[x] for x in fit])[0]
        ex_pool = [x for x in moments if style in styles[x["id"]] and x["group"] != m["group"]
                   and len(x["message"]) <= (400 if style == "technical paste" else 220)]
        examples = [C.cap(x["message"], 300) for x in rng.sample(ex_pool, min(3, len(ex_pool)))]
        packets[w].append({
            "writer": w, "mode": mode, "source": "real-rewrite" if mode == "rewrite" else "goal",
            "family": fam, "family_spec": FAMILY_SPEC[fam], "flow": flow, "flow_spec": FLOW_SPEC[flow],
            "contexts": contexts_for(fam, flow, state, target, rng),
            "style": {"profile": style, "description": STYLE_SPEC[style], "examples": examples},
            **task,
            "anchor": {"moment": m["id"], "group": m["group"], "now": state["now"]},
            "state": state})
    OUT.mkdir(parents=True, exist_ok=True)
    summary = {}
    for w in WRITERS:
        rows = sorted(packets[w], key=lambda p: (p["family"], p["flow"], p["mode"]))
        rng.shuffle(rows)
        with (OUT / f"{w}.jsonl").open("w") as f:
            for i, p in enumerate(rows, 1):
                p = {"packet": f"pk-{w}-{i:03d}", "episode_id": f"ep-{'rw' if p['mode'] == 'rewrite' else 'goal'}-{w}-{i:03d}",
                     **p}
                f.write(json.dumps(p, ensure_ascii=False) + "\n")
        summary[w] = {"packets": len(rows), "modes": collections.Counter(p["mode"] for p in rows),
                      "families": len({p["family"] for p in rows}), "flows": len({p["flow"] for p in rows})}
    reused_real = sum(1 for w in WRITERS for p in packets[w] if p["anchor"]["moment"] in real_used)
    print(json.dumps({"writers": summary, "moments_distinct": len(use), "moments_reused_across_packets":
                      sum(1 for v in use.values() if v > 1), "packets_on_real_episode_moments": reused_real,
                      "groups": len(group_use), "groups_total": len({m["group"] for m in moments})},
                     indent=1, default=dict))


if __name__ == "__main__":
    main()
