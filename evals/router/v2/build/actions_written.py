"""Written action cases on real dev boards (v2/ACTIONS.md): templates × boards, as explore/caps_ack.py does, in the owner's
terse style (lowercase, no period, French for about a fifth). Gold is the template's action on the board's target, checked
against the board: a clear case needs its precondition (a worth-a-look card to ack, a running session to stop, a card to
archive), and each set also has boards where it fails (gold: ask, or the plain say the words still carry).

    python3 v2/build/actions_written.py [--seed 31]  →  v2/data/actions/{dev,calib}/written_{ack,stop,configure}.jsonl

Sets: ack 150 (75 clear incl. duplicate titles and unmet, 75 traps: negations, quotes, "seen X, now do Y", instructions
to the session, replies to a card that needs you), stop 150 (stop, interrupt "stop X and do Y", several running, unmet,
traps), configure 100 (archive, reopen, mute/unmute, unmet, traps). Boards are the starting states of real dev episodes
(already redacted); the templates are committed, the filled cases stay in v2/data. Split dev/calib by the board's group."""
import argparse
import collections
import json
import pathlib
import random
import re
import sys

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import actions_common as A  # noqa: E402

DEV = A.V2 / "data" / "episodes" / "dev" / "episodes.jsonl"
FR_SHARE = 0.25
DANGLING = {"a", "an", "and", "the", "of", "for", "with", "to", "in", "on", "at", "by", "from", "or", "vs", "into", "&", "-",
            "de", "la", "le", "les", "et", "du", "des", "pour", "avec", "is", "not", "no", "via"}

DO_EN = ["use the existing helper instead", "revert the last commit", "switch to main first", "run the tests before pushing",
         "don't touch the schema", "just fix the typo and stop there", "commit what you have", "keep it under 50 lines",
         "do the docs first", "drop the refactor, only the fix", "check the logs before changing anything",
         "open a PR instead of pushing to main", "use the real data not the fixture", "ask me before deleting anything"]
DO_FR = ["utilise plutôt le helper existant", "revert le dernier commit", "passe sur main d'abord", "lance les tests avant de push",
         "touche pas au schéma", "commit ce que t'as", "fais la doc d'abord", "garde juste le fix, pas le refacto"]

# (category, n, need, gold, en templates, fr templates)
# need: done (a worth-a-look card on a unique title), dup (a title two sessions share, with a worth-a-look card),
# dup_proj (the same, in different projects), all (two worth-a-look cards or more), nocard (idle, no open card),
# needsyou (a card that needs you), running / running_one / running_multi, idle (not running), carded (any open card),
# proj (a project), lookout (the lookout project on the board), bare (any board).
ACK = [
    ("seen", 46, "done", "ack",
     ["seen {t}", "ok seen {t}", "{t} seen", "got it on {t}", "read {t}, thx", "mark {t} as seen", "seen the {t} one",
      "ok read the {t} summary", "noted for {t}", "looked at {t}, clear it", "done reading {t}", "k seen {t}",
      "{t}: seen, nothing to do", "saw {t}, all good", "ack {t}", "{t} ok i read it", "yep seen {t}", "mark {t} read"],
     ["vu {t}", "ok vu pour {t}", "lu {t}", "c'est vu pour {t}", "marque {t} comme vu", "j'ai lu {t}", "{t} vu merci"]),
    ("seen-all", 4, "all", "ack_all",
     ["mark everything seen", "read all of them, clear the cards", "seen all the reports"],
     ["tout vu, marque tout comme lu"]),
    ("dup-project", 8, "dup_proj", "ack",
     ["seen {t} in {p}", "seen the {p} {t}", "{t} in {p}: read it", "mark the {p} {t} card seen"],
     ["vu {t} dans {p}"]),
    ("dup-bare", 7, "dup", "ack_dup",
     ["seen {t}", "ok read {t}", "mark {t} as seen", "got it on {t}"],
     ["vu {t}"]),
    ("unmet", 10, "nocard", "unmet",
     ["seen {t}", "ok read {t}", "mark {t} as seen", "got it on {t}, thx"],
     ["vu {t}", "lu {t}"]),
    ("negation", 15, "done", "say",
     ["haven't seen {t} yet, tell it to wait", "not read {t} yet, hold off on pushing", "didn't look at {t} yet, don't merge",
      "haven't read the {t} summary, wait for me", "{t} not seen yet, don't push"],
     ["pas encore lu {t}, attends avant de push", "j'ai pas vu {t}, attends-moi"]),
    ("quoted", 12, "done", "say",
     ["{t} said \"seen 12 files\" but there are 40, check again", "in {t} it says \"got it\" but nothing changed, look again",
      "{t}: you wrote \"read the docs\" but you didn't, read them", "{t} printed \"seen\" for every row, why"],
     ["{t} a écrit \"vu\" mais rien n'a changé, regarde encore"]),
    ("seen-then-do", 20, "done_or_needsyou", "reply",
     ["seen {t}, now push it", "read {t}, go ahead and merge", "ok seen {t}, now fix the failing test",
      "got it {t}, commit and push", "seen it {t}, next do the docs", "{t} read it, ship it"],
     ["vu {t}, push maintenant", "lu {t}, tu peux merge"]),
    ("to-session", 15, "done", "say",
     ["{t}: mark the old tests as skipped", "tell {t} to ack the webhook before processing",
      "{t}: add a 'seen' flag to the notifications", "{t} make the read receipts work again", "ask {t} to mark the PR as ready"],
     ["{t}: ajoute un flag 'vu' aux notifs", "dis à {t} de marquer la PR comme ready"]),
    ("reply-needs-you", 13, "needsyou", "reply",
     ["got it {t}, yes go", "ok {t}, do option 2", "seen your question {t}, yes", "{t} read it, go with the first one"],
     ["ok vu {t}, vas-y"]),
]
STOP = [
    ("stop", 22, "running", "stop",
     ["stop {t}", "kill {t}", "stop the {t} session", "{t} stop", "halt {t}", "abort {t}", "stop {t} now",
      "cancel what {t} is doing", "{t} is going the wrong way, stop it", "stop {t} pls"],
     ["arrête {t}", "stop {t} stp", "coupe {t}", "{t} arrête-toi"]),
    ("stop-several", 15, "running_multi", "stop",
     ["stop {t}", "kill {t}", "stop the {t} one", "{t} stop", "abort {t}, the others are fine"],
     ["arrête {t}", "coupe {t}, laisse les autres"]),
    ("stop-bare-one", 4, "running_one", "stop_bare", ["stop", "stop it", "kill it"], ["arrête"]),
    ("stop-bare-several", 4, "running_multi", "stop_bare", ["stop", "stop it", "kill it"], ["arrête"]),
    ("interrupt", 30, "running", "interrupt",
     ["stop {t} and {y}", "{t} wait, {y}", "hold on {t}, {y}", "stop {t}, {y} instead", "{t}: stop, {y}",
      "interrupt {t}: {y}", "{t} stop stop, {y}"],
     ["arrête {t} et {yf}", "{t} attends, {yf}", "stop {t}, {yf} plutôt"]),
    ("interrupt-several", 15, "running_multi", "interrupt",
     ["stop {t} and {y}", "{t} wait, {y}", "hold on {t}, {y}", "stop {t}, {y} instead"],
     ["{t} attends, {yf}"]),
    ("unmet-stop", 8, "idle", "unmet", ["stop {t}", "kill {t}", "stop the {t} session"], ["arrête {t}"]),
    ("unmet-stop-do", 7, "idle", "reply", ["stop {t} and {y}", "{t} wait, {y}", "hold on {t}, {y}"], ["{t} attends, {yf}"]),
    ("stop-using", 15, "idle", "say",
     ["{t}: stop using lodash in the code", "tell {t} to stop using the deprecated API", "{t} stop writing comments everywhere",
      "{t}: stop adding new deps", "{t} stop mocking the db in tests"],
     ["{t}: arrête d'utiliser lodash", "dis à {t} d'arrêter les commentaires partout"]),
    ("stop-button", 4, "idle", "say",
     ["{t}: the stop button is broken again", "{t} the stop button doesn't do anything", "{t}: stop button still broken"],
     ["{t}: le bouton stop marche toujours pas"]),
    ("stop-button-bare", 4, "lookout", "lookout",
     ["the stop button in the router doesn't work", "stop button is broken", "the stop button does nothing"],
     ["le bouton stop marche pas"]),
    ("dont-stop", 6, "running", "say_only",
     ["{t} don't stop, keep going", "{t}: no need to stop, carry on", "{t} don't stop at the first failure, do them all"],
     ["{t} t'arrête pas, continue"]),
    ("why-stopped", 6, "idle", "why",
     ["why did {t} stop?", "{t} stopped, why?", "why did {t} stop halfway"], ["pourquoi {t} s'est arrêté ?"]),
    ("dev-server", 4, "idle", "say",
     ["{t}: stop the dev server and restart it", "{t} kill the dev server on 3000"], ["{t}: arrête le serveur de dev"]),
    ("dev-server-bare", 2, "bare", "notrouter", ["stop the dev server and restart it"], ["arrête le serveur de dev"]),
    ("resume", 4, "idle", "reply",
     ["stopped {t} by mistake, resume it", "{t} continue where you stopped"], ["{t} reprends là où t'en étais"]),
]
CONFIGURE = [
    ("archive", 24, "carded", "archive",
     ["archive the {t} card", "I'll do {t} myself", "drop the {t} card", "{t} is mine, archive it", "no need for {t}, archive",
      "archive {t}", "i'll handle {t} by hand"],
     ["archive {t}", "je m'occupe de {t} moi-même", "vire la carte {t}"]),
    ("archive-unmet", 6, "nocard", "unmet", ["archive the {t} card", "archive {t}"], ["vire la carte {t}"]),
    ("reopen", 15, "nocard", "reopen",
     ["reopen the {t} card", "bring back {t}", "archived {t} by mistake, reopen it", "unarchive {t}"],
     ["rouvre la carte {t}", "remets {t}"]),
    ("mute", 19, "proj", "mute",
     ["mute {p}", "silence {p} for now", "{p} is too noisy, mute it", "mute the {p} project",
      "stop notifications from {p}", "stop showing me {p} for today"],
     ["mute {p}", "coupe les notifs de {p}"]),
    ("unmute", 6, "proj", "unmute", ["unmute {p}", "bring {p} back in the router"], ["réactive {p}"]),
    ("to-session", 18, "idle", "say",
     ["{t}: archive the old logs in the repo", "tell {t} to archive old branches", "{t}: mute the warnings in the build",
      "ask {t} to mute the noisy test output", "{t}: reopen the issue and fix it", "tell {t} to reopen the PR and rebase"],
     ["{t}: archive les vieux logs", "{t}: coupe les warnings du build"]),
    ("bare", 12, "bare", "notrouter",
     ["archive the old branches", "mute the warnings", "reopen the issue about the crash", "mute the audio in the demo video",
      "archive old logs in the repo"],
     ["archive les vieilles branches"]),
]
SETS = {"ack": ACK, "stop": STOP, "configure": CONFIGURE}
assert sum(c[1] for c in ACK) == 150 and sum(c[1] for c in STOP) == 150 and sum(c[1] for c in CONFIGURE) == 100


# A clear case's title must not read as part of the request: "vu fix the failing test" reads as an instruction, "stop agent
# completion notifications" as a mute. Those titles still appear in traps and unmet cases.
CLEAR = {"ack", "ack_dup", "stop", "interrupt", "archive", "reopen"}
IMPERATIVE = {"fix", "add", "make", "run", "check", "verify", "migrate", "update", "remove", "implement", "investigate",
              "review", "test", "build", "create", "stop", "mute", "archive", "reopen", "debug", "refactor", "clean", "write",
              "use", "move", "rename", "set", "enable", "disable", "delete", "merge", "push", "ship", "release", "deploy",
              "port", "install", "research", "find", "show", "hide", "drop", "revert", "rebase", "commit", "open", "close",
              "plan", "explore", "compare", "measure", "audit", "draft", "rewrite", "replace", "restore", "keep"}
OVERLAP = ("notif", "warning", "log", "mute", "archive", "seen", "read", "stop")


def misreads(title):
    words = title.strip().lower().split()
    return not words or words[0].strip(",:") in IMPERATIVE or any(w in title.lower() for w in OVERLAP)


# ------------------------------------------------------------------------------------------------- the board

def live(state):
    return [s for s in state["sessions"] if not s.get("archived")]


# Folders of probe and test sessions (/tmp, scripted checks): not projects you'd mute.
TEST_FOLDERS = {"scratch", "proj", "e2e", "hook", "tmp", "baseline"}
PROBE = re.compile(r"^\s*(bounded probe|call the mcp__|reply with exactly|say exactly|respond with exactly)", re.I)


def titled(s):
    """A title you'd name a session by (not a probe's prompt)."""
    return 3 <= len(s["title"]) <= 50 and "<" not in s["title"] and "\n" not in s["title"] and not PROBE.match(s["title"])


def key(title):
    return title.strip().lower()


def cards_of(state, sid, kinds=None):
    cs = [c for c in state["cards"] if c["session"] == sid and (kinds is None or c["kind"] in kinds)]
    return sorted(cs, key=lambda c: c.get("created_min_ago", 0))       # latest first


class Board:
    def __init__(self, episode):
        self.ep, self.state = episode, episode["state"]
        self.live = live(self.state)
        self.by_title = collections.defaultdict(list)
        for s in self.live:
            self.by_title[key(s["title"])].append(s)
        self.running = [s for s in self.live if s.get("running") and not s.get("waits_on_you")]

    def unique(self, s):
        return titled(s) and len(self.by_title[key(s["title"])]) == 1

    def pool(self, need):
        L = self.live
        if need == "done":
            return [s for s in L if self.unique(s) and not s.get("running") and cards_of(self.state, s["id"], {"done"})]
        if need == "needsyou":
            return [s for s in L if self.unique(s) and cards_of(self.state, s["id"], A.NEEDS_YOU)]
        if need == "done_or_needsyou":
            return self.pool("done") + self.pool("needsyou")
        if need in ("dup", "dup_proj"):
            out = []
            for s in L:
                same = self.by_title[key(s["title"])]
                if not titled(s) or len(same) < 2 or s.get("running") or not cards_of(self.state, s["id"], {"done"}):
                    continue
                if need == "dup_proj" and sum(o["project"] == s["project"] for o in same) > 1:
                    continue
                out.append(s)
            return out
        if need == "nocard":
            return [s for s in L if self.unique(s) and not s.get("running") and not s.get("waits_on_you")
                    and not cards_of(self.state, s["id"])]
        if need == "carded":
            return [s for s in L if self.unique(s) and cards_of(self.state, s["id"])]
        if need == "running":
            return [s for s in self.running if self.unique(s)]
        if need == "running_one":
            return self.running if len(self.running) == 1 else []
        if need == "running_multi":
            return [s for s in self.running if self.unique(s)] if len(self.running) >= 2 else []
        if need == "idle":
            return [s for s in L if self.unique(s) and not s.get("running") and not s.get("waits_on_you")]
        if need == "all":
            return [None] if sum(1 for c in self.state["cards"] if c["kind"] == "done") >= 2 else []
        if need == "proj":
            return [None] if self.projects() else []
        if need == "lookout":
            return [None] if any(s["project"] == "lookout" for s in L) else []
        if need == "bare":
            return [None]
        raise ValueError(need)

    def projects(self):
        return sorted({s["project"] for s in self.live if s.get("project") and s["project"] not in TEST_FOLDERS
                       and " " not in s["project"] and not re.search(r"probe|test", s["project"])})


def ref(board, s, rng):
    """How you'd name the session: its title, or the first words when nothing else on the board starts that way."""
    title = s["title"].strip().rstrip(".")
    words = title.split()
    if len(words) > 3 and rng.random() < 0.4:
        for k in (2, 3, 4):
            prefix = " ".join(words[:k]).rstrip(",:;-—")
            if words[k - 1].lower().strip(",:;") in DANGLING or prefix.count("(") != prefix.count(")"):
                continue
            if len(prefix) >= 8 and not any(o is not s and key(o["title"]).startswith(prefix.lower()) for o in board.live):
                title = prefix
                break
    return title.lower() if rng.random() < 0.5 else title


# ------------------------------------------------------------------------------------------------- gold

def reply(board, s, method="template"):
    """A message for the session: an answer to its card that needs you (a form takes only the answer), else a say."""
    cs = cards_of(board.state, s["id"], A.NEEDS_YOU)
    if cs:
        c = cs[0]
        acc = [f"answer:card:{c['id']}"] + ([] if c["kind"] in A.FORMS else [f"say:session:{s['id']}"])
        return f"answer:card:{c['id']}", acc
    return f"say:session:{s['id']}", [f"say:session:{s['id']}"]


def make_gold(kind, board, s, p, cat):
    st = board.state
    ev = f"written {cat}: {kind}"
    if kind == "ack":
        c = cards_of(st, s["id"], {"done"})[0]
        return A.gold(f"ack:card:{c['id']}", [f"ack:card:{c['id']}"], st, evidence=ev)
    if kind == "ack_all":
        return A.gold("ack:card:*", ["ack:card:*"], st, evidence=ev)
    if kind == "ack_dup":
        same = [o for o in board.by_title[key(s["title"])] if not o.get("running") and cards_of(st, o["id"], {"done"})]
        acc = [f"ack:card:{cards_of(st, o['id'], {'done'})[0]['id']}" for o in [s] + [o for o in same if o is not s]]
        return A.gold(acc[0], acc, st, evidence=ev + f" ({len(acc)} same-titled worth-a-look cards)")
    if kind == "unmet":
        return A.gold(f"say:session:{s['id']}", [], st, ask="required", precondition="unmet", evidence=ev)
    if kind in ("say", "say_only"):
        intended, acc = reply(board, s)          # a message to a session with a card that needs you also answers it
        return A.gold(intended, acc, st, evidence=ev)
    if kind == "reply":
        intended, acc = reply(board, s)
        unmet = cat.startswith("unmet")
        return A.gold(intended, acc, st, evidence=ev, precondition="unmet" if unmet else "met")
    if kind == "stop":
        return A.gold(f"stop:session:{s['id']}", [f"stop:session:{s['id']}"], st, evidence=ev)
    if kind == "stop_bare":
        if len(board.running) == 1:
            return A.gold(f"stop:session:{s['id']}", [f"stop:session:{s['id']}"], st, evidence=ev + " (one running)")
        return A.gold(f"stop:session:{s['id']}", [], st, ask="required",
                      clarify=[f"stop:session:{o['id']}" for o in board.running if o is not s],
                      evidence=ev + f" ({len(board.running)} running: which?)")
    if kind == "interrupt":
        return A.gold(f"interrupt:session:{s['id']}", [f"interrupt:session:{s['id']}"], st, evidence=ev)
    if kind == "why":
        intended, acc = reply(board, s)
        return A.gold(intended, acc + ["ask_fjord"], st, evidence=ev)
    if kind == "notrouter":
        acc = [f"say:session:{o['id']}" for o in sorted(board.live, key=lambda o: o.get("idle_min") or 0)]
        acc += [f"start:new:{x}" for x in st["projects"]]
        return A.gold(acc[0], acc, st, evidence=ev + " (any session or a new one; only a Router action is wrong)")
    if kind == "lookout":
        acc = [f"say:session:{o['id']}" for o in sorted(board.live, key=lambda o: o.get("idle_min") or 0)
               if o["project"] == "lookout"] + ["start:new:lookout"]
        return A.gold(acc[0], acc, st, evidence=ev + " (a Fjord bug: a lookout session or a new one)")
    if kind == "archive":
        c = cards_of(st, s["id"])[0]
        return A.gold(f"archive:card:{c['id']}", [f"archive:card:{c['id']}"], st, evidence=ev)
    if kind == "reopen":
        return A.gold(f"reopen:session:{s['id']}", [f"reopen:session:{s['id']}"], st, evidence=ev)
    if kind in ("mute", "unmute"):
        return A.gold(f"{kind}:project:{p}", [f"{kind}:project:{p}"], st, evidence=ev)
    raise ValueError(kind)


# ------------------------------------------------------------------------------------------------- building

def build(name, spec, boards, rng, per_board=2):
    used = collections.Counter()
    seen = set()
    out = []
    n = 0
    for cat, count, need, kind, en, fr in spec:
        for _ in range(count):
            order = sorted((i for i in range(len(boards)) if used[i] < per_board), key=lambda i: (used[i], rng.random()))
            for i in order:
                b = boards[i]
                pool = b.pool(need)
                if kind in CLEAR:
                    pool = [x for x in pool if x is None or not misreads(x["title"])]
                if not pool:
                    continue
                s = rng.choice(pool)
                if need == "running_one":
                    s = b.running[0]
                if need == "running_multi" and kind == "stop_bare":
                    s = rng.choice(b.running)
                projects = b.projects()
                p = None
                if need in ("proj",):
                    p = rng.choice(projects)
                elif "{p}" in "".join(en + fr) and s is not None:
                    p = s["project"]
                lang = "fr" if fr and rng.random() < FR_SHARE else "en"
                template = rng.choice(fr if lang == "fr" else en)
                t = ref(b, s, rng) if s is not None else ""
                message = template.format(t=t, p=p or "", y=rng.choice(DO_EN), yf=rng.choice(DO_FR))
                if (b.ep["id"], s and s["id"], message.lower()) in seen:
                    continue
                seen.add((b.ep["id"], s and s["id"], message.lower()))
                g = make_gold(kind, b, s, p, cat)
                used[i] += 1
                n += 1
                slices = [name, cat, lang, g["precondition"]]
                if len(b.running) >= 2:
                    slices.append("several-running")
                if s is not None and t != t.lower() and t.lower() != s["title"].strip().lower().rstrip("."):
                    slices.append("title-prefix")
                out.append({
                    "schema": 2, "id": f"act-{name}-{n:03d}-{cat}", "family": cat, "group": f"act:{b.ep['group']}",
                    "provenance": {"source": "written-action", "set": f"actions-{name}", "writer": "template",
                                   "writer_model": "v2/build/actions_written.py", "state_fidelity": "transcript",
                                   "synthetic": ["message"], "board": b.ep["id"], "template": template, "typed": True},
                    "tags": {"primary": cat, "flow": "single", "lang": lang, "slices": sorted(set(slices))},
                    "state": b.state,
                    "events": [{"id": "e1", "kind": "submit", "message": message, "context": dict(A.CONTEXT), "gold": g}]})
                break
            else:
                raise SystemExit(f"{name}: no board left for {cat} ({need})")
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--seed", type=int, default=31)
    args = ap.parse_args()
    eps = [json.loads(line) for line in open(DEV)]
    boards = [Board(e) for e in eps if e["provenance"]["source"] == "real-moment"]
    report = {}
    for k, (name, spec) in enumerate(SETS.items()):
        rng = random.Random(args.seed + k)
        cases = build(name, spec, boards, rng)
        parts = collections.defaultdict(list)
        for e in cases:
            parts[A.hash_split(e["group"][4:])].append(e)
        for split in ("dev", "calib"):
            A.write(A.OUT / split / f"written_{name}.jsonl", parts[split])
        report[name] = {split: {"cases": len(parts[split]), "groups": len({e["group"] for e in parts[split]}),
                                "actions": dict(collections.Counter(e["events"][0]["gold"]["intended_action"].split(":")[0]
                                                                    + ("/ask" if e["events"][0]["gold"]["ask"] == "required" else "")
                                                                    for e in parts[split]))}
                        for split in ("dev", "calib")}
        report[name]["fr"] = sum(e["tags"]["lang"] == "fr" for e in cases)
        report[name]["boards"] = len({e["provenance"]["board"] for e in cases})
    print(json.dumps(report, indent=1))


if __name__ == "__main__":
    main()
