"""Format `capabilities-o`: `combo-o` with `change_fjord` described by what Lookout can do locally.

A reviewer's proposal: the shipped criterion ("change how Lookout itself behaves: its settings, notifications, inbox
categories, rules or groups") never says Lookout can mark a card you have seen as seen, so "seen the docs" goes to the
docs session. Here one capability list is the single source of the `change_fjord` criterion AND the `gate_setting` text,
and it names the acknowledgements. Everything else (destinations, the other intents, the other gates, the next-message
checks, option order) is combo-o's, byte for byte, so only the requests that carry these two texts differ.

Everything that reaches Jev is scrubbed with real.boards.redact first (keys, tokens, account numbers); on already
redacted boards that is the identity.

Used as: python3 bench.py capabilities-o ...; python3 -m v2.run.episodes ... --format capabilities-o
"""
from explore import combo
from explore import intents as I
from real.boards import redact

# What Lookout does by itself, no session involved. The acknowledgement items are the point of this format.
CAPABILITIES = [
    "turn a setting on or off, including its notifications",
    "change Triage's inbox categories, rules or groups",
    "mark a Router card the user has seen or read as seen (a worth-a-look card: \"seen the docs\", \"got it\", "
    "\"I read the headlines\")",
    "mark things in the inbox as done or seen",
]
NOT_THESE = ("Not asking a session to build or change code, and not a message for a session to act on (an instruction "
             "or a reply addressed to it, even one that mentions what the user has seen)")

CHANGE_FJORD = "Lookout itself does something for the user, without any session: " + "; ".join(CAPABILITIES) + ". " + NOT_THESE

GATE_SETTING = {"type": "noul", "instructions": {
    "question": ("Does `message` ask Lookout itself to do something for the user, without any session: "
                 + "; ".join(CAPABILITIES) + "? Not code to be written, and not a message for a session to do or "
                 "answer something.")}}


def _scrub(x):
    if isinstance(x, str):
        return redact(x)
    if isinstance(x, list):
        return [_scrub(v) for v in x]
    if isinstance(x, dict):
        return {k: _scrub(v) for k, v in x.items()}
    return x


GATES = {**combo.GATES, "gate_setting": GATE_SETTING}
CRIT = {**I.CRIT_WORDED, "change_fjord": CHANGE_FJORD}


def capabilities(case, rng=None):
    state, q, keymap = combo.combo(case, rng, gates=GATES, crit=CRIT)
    return _scrub(state), _scrub(q), keymap


FORMATS = {"capabilities-o": capabilities}
