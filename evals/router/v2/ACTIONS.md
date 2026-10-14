# Router actions in gold (data side)

The Router redesign decides an **action** on a target, not only a destination. Gold carries the action next to the
destination fields today's runner and `run/score.py` read, so the same files load in both.

## Action targets

| action | meaning | precondition on the board |
|---|---|---|
| `say:session:<id>` | deliver the words to the session as your message (queued if it is running) | the session is listed |
| `answer:card:<card>` | the words answer that card: a form (`question`, `plan`) is filled, a turn card that needs you (`asks`, `approval`, `stuck`) gets the reply and resolves | the card is open |
| `approve:card:<card>` | yes to a plan or approval card, nothing else said | the card is open, kind `plan` or `approval` |
| `ack:card:<card>` | mark a worth-a-look card seen (`mark_seen`); nothing reaches the session | the card is open, kind `done` |
| `stop:session:<id>` | stop the running turn; nothing else is sent | the session is running (not waiting on a form) |
| `interrupt:session:<id>` | stop the running turn and send the words as the next message | the session is running |
| `start:new:<folder>` | start a session in that folder with the words | the folder is a known project |
| `configure` | change Fjord itself: settings, Triage, and the proposal class below | |
| `ask_fjord` | a read-only question to Fjord about the board | |

A target without a prefix means `say` (`session:<id>` = `say:session:<id>`). `<card>` ids contain `#`; split on the
first two colons only. `ack:card:*` means every worth-a-look card on the board ("mark everything seen").

**Proposal class** (`configure` family; the Router proposes, the user applies from the history):
`archive:card:<card>`, `reopen:session:<id>` (the session's latest archived card; boards don't list archived cards),
`mute:project:<folder>`, `unmute:project:<folder>`. Gold that names one also lists `configure` as acceptable, so a
system that only knows the class is right on class.

## Gold fields

Each submit's `gold` keeps the legacy fields and adds:

```json
"gold": {"intended": "<legacy target>", "acceptable": ["<legacy>"], "clarify": [], "ask": "required|allowed|forbidden",
         "consequential": false, "evidence": "…",
         "intended_action": "<action target>", "acceptable_actions": ["<action target>"], "clarify_actions": [],
         "precondition": "met|unmet", "label_method": "mined|template|mechanical"}
```

Legacy projection (what today's runner sees): `say`/`answer`/`approve`/`interrupt` → `session:<the card's session>`;
`ack`, `stop`, `configure` and the proposal class → `change_fjord`; `ask_fjord` → `question`; `start:new:<f>` → `new:<f>`.
Where the projection would make a wrong action right, the legacy `acceptable` drops it: an `interrupt` gold has legacy
`acceptable: []` (a plain send queues behind the running turn, which is what the user did not want; `say` is not
acceptable). Soft-gold `views` get the same action fields.

Precondition unmet (the words name an action the board can't take: "seen X" when X has no worth-a-look card, "stop X"
when X is idle, "archive the X card" when X has none): `ask: required`, `acceptable_actions: []`, `intended_action` the
`say` to the named session (the ask card's right first option). An unmet stop that also says what to do ("stop X and
use Y") is a plain `say` with `ask: allowed`.

`consequential` keeps its legacy meaning (the message's own stakes). A wrong `stop` or `interrupt` can't be undone, so
the scorer that reads action gold should charge it as consequential whatever the gold says.

Mined messages: a clicked option is rendered as its label without "(Recommended)" (`provenance.typed: false`); a bare
stop button press with nothing typed after is rendered "stop" (`provenance.message_rendered: true`).

Equivalences used in gold: on a turn card that needs you (`asks`, `approval`, `stuck`) `answer:card` and `say:session`
deliver the same words, so both are acceptable (`answer` intended); on a form (`question`, `plan`) only `answer`.

## Sets (`v2/data/actions/`, gitignored)

| file | source | gold |
|---|---|---|
| `{dev,calib,sealed}/mined.jsonl` | transcripts: answered AskUserQuestion forms, interrupts (`build/actions_mine.py`) | by construction: the card answered, the session interrupted |
| `{dev,calib}/written_{ack,stop,configure}.jsonl` | templates × real dev boards (`build/actions_written.py`) | by template and board precondition |
| `dev/relabel_real.jsonl` | dev real moments, unchanged messages (`build/actions_relabel.py`) | mechanical: needs-you card → `answer`, else `say`, new → `start`, after an interrupt → `interrupt` |

Splits are by group (`<session>:<day>`). Mined episodes follow the frozen benchmark split (`episodes/groups.json`), so a
group sealed there is in `actions/sealed/` (outside `episodes/sealed`, which `seal.py` reads whole; explorers must not
read it either); groups that are new since the freeze are split dev/calib by hash. Written sets use dev boards only and
split their boards' groups dev/calib by hash (2:1). Real data never leaves the machine; only code and this spec are
committed.
