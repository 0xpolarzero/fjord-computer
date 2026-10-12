# Router routing cases

One case per line in `cases/*.jsonl`. A case is a board (what Lookout shows when you type), a message you send, and
what a good router does with it.

```json
{
  "id": "follow-up-yes-01",
  "tags": ["reply", "short", "one-waiting"],
  "why": "Only one session waits on a yes/no question; 'yes go ahead' answers it.",
  "board": {
    "projects": ["lookout", "lcu", "silo"],
    "sessions": [
      {"id": "s1", "title": "Settings page polish", "project": "lookout", "running": false,
       "activity": "", "summary": "Proposed moving the CI poller off the main thread", "idle_min": 4},
      {"id": "s2", "title": "Faster window resize", "project": "lookout", "running": true,
       "activity": "Running the test suite", "summary": "", "idle_min": 0}
    ],
    "cards": [
      {"id": "c1", "session": "s1", "kind": "asks", "text": "Should I make that change?",
       "options": ["Yes", "No"]}
    ],
    "history": [
      {"ago_min": 12, "you": "move the CI poller off the main thread if it's cheap", "to": "s1"}
    ]
  },
  "message": "yes go ahead",
  "gold": {"to": ["s1"], "ask_ok": false}
}
```

## Board

- `projects`: folder names Lookout knows (every one can be a new session's project).
- `sessions`: Claude Code sessions not archived. `running`: a turn is under way. `activity`: the live line while
  running. `summary`: what the last turn did (when not running). `idle_min`: minutes since its last activity.
- `cards`: open cards. `kind` is one of `question` (stopped on a multiple-choice question; give `options`), `plan`
  (stopped on a plan to approve), `asks` (its last message asks you something), `approval` (asks your OK for something
  consequential: push, publish, delete, spend), `done` (finished), `stuck` (finished blocked). `text` is the card's
  text: the session's question, plan summary or last message, as the session wrote it.
- `history`: your earlier messages, newest last. `to`: where it went (a session id, `new:<project>`, or an intent).
  `corrected_from` (optional): the Router first suggested that, and you picked `to` instead.

## Gold

- `to`: every acceptable destination. A session id (a reply to its card counts as the session), `new:<project>`,
  `change_lookout` (change Lookout itself: inbox categories, groups, settings), `question` (a question about what is
  going on now, for Lookout to answer, not for a session), `compound` (several different things in one message).
  Empty: no destination is right; the router must ask.
- `ask_ok`: true when asking you is a fine answer too (the message is ambiguous enough that a careful human assistant
  would check). False: the message plainly says where it goes, and asking is a miss.

A wrong send is the worst outcome (your words land in the wrong session). A needless ask costs you a click.

## Writing good cases

- Boards look like real ones: 3–25 sessions, often several in the same project with related topics; most cards are
  `done`; a few wait on you. Titles are what Claude Code names sessions ("Quick bug fix", "Settings page polish").
- Messages are what you would really type: short, lowercase, typos, "it", "that", "yes", replies to a question by
  its content, references by topic rather than title, pasted errors, sometimes French.
- Gold is what a careful human assistant who sees the same board would do. When in doubt, `ask_ok: true`.
