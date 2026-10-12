# What a Router card lists as asked: sentences + Jev vs one Haiku call

A turn that needs you lists the questions its final message asks. Before (`OLD`, shipped until 0155c3e): the message cut
into sentences, those with a question mark or an asking phrase offered to Jev as `s<i>` yes/no questions, kept at ≥ 0.6,
lead-ins ending in ":" dropped. After (`NEW`): the brief's Haiku call returns `{brief, asks: [{question, options}]}`
(RouterBrief.swift `asksRules`, `schema`, `read`).

## Method

- 199 real turn-final messages from the user's transcripts (Claude app and CLI, KEEP projects, no agent- or probe-started
  sessions), redacted (`real/boards.py` `redact`) before any model saw them, stratified by cheap heuristics used for
  sampling only: lead-ins 40, numbered questions 40, option lists 39, questions buried in narration 40, asks nothing 40.
- OLD: `v2/build/triage.py`'s port of the sentences, candidates and bundle, Jev via `jev.py`.
- NEW: the app's own system prompt, context and schema read from the Swift source at run time, `claude -p --json-schema`
  with Haiku, then the app's validation (`read`).
- Judge: Opus (`claude -p`), blind A/B per turn: a verdict per listed item, the asks each list misses, the asks whose
  choices are dropped or split off. Spot-check of 16 judgements: 3 disagreements, none changing the direction.
- "Cards" = turns Jev's triage put in asks or approval (135): those that list asks in the app.

## Results (NEW = the prompt as of e37118b)

| | OLD all (199) | NEW all | OLD cards (135) | NEW cards |
|---|---|---|---|---|
| fake items (lead-in, narration, duplicate, fragment) | 73 | 4 | 50 | 1 |
| — lead-ins | 7 | 0 | 7 | 0 |
| distorted items | 7 | 5 | 7 | 5 |
| missed asks | 44 | 5 | 39 | 5 |
| option errors (dropped + split) | 30 | 0 | 30 | 0 |
| invented options | 0 | 1 | 0 | 1 |
| messages with any error | **82** | **15** | **68** | **12** |
| asks-nothing messages given a list | 10 | 3 | 1 | 0 |
| asking messages given no list | 7 | 0 | 4 | 0 |
| NEW call failures | | 0 | | 0 |

The first NEW prompt (0155c3e) had 20 messages with errors (17 on cards), 14 missed asks: mostly requests to do
something and report back, which the tuned prompt counts as asks. OLD's counts move by a few between runs: the judge
reads each pair again when the NEW list changes.

NEW's remaining mistakes are single cases: who would act changed, a request reworded as an offer, a list narrowed to
the candidates the session named, a closing offer listed where the judge saw none.

## Rerun after a prompt change

```sh
cd evals/router/v2/asks_eval
python3 new.py && python3 judge.py && python3 score.py --mistakes
```

Full pipeline: `sample.py → old.py → new.py → judge.py → score.py`. Data stays in `v2/data/asks_eval/` (gitignored); run
`leakcheck.py` before committing anything here.
