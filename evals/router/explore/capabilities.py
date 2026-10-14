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

# The Router actions added after: each a registry capability in Swift (RouterCapability.all, `outcome`), measured one by one
# and together (`capabilities-x...`, below) before any of them joined the routing text.
EXTRA = {
    "archive": "archive a Router card the user will handle themselves or doesn't need (\"I'll do the theme one myself\", "
               "\"archive the login card\")",
    "reopen": "reopen a Router card the user archived (\"reopen the docs card\")",
    "mute": "mute or unmute a project's sessions in the Router (\"mute microsandbox\")",
    "stop": "stop a running session's current turn (\"stop the CI session\")",
}
# What Fjord's routing text names now: the base list and the extras that passed (docs/design/router-research.md, "Router
# actions from words"). parity.py writes this one for the Swift test.
ADOPTED_EXTRA = ["archive", "reopen"]


def capability_list(extra=()):
    return CAPABILITIES + [EXTRA[k] for k in EXTRA if k in extra]


def change_fjord(extra=()):
    return "Lookout itself does something for the user, without any session: " + "; ".join(capability_list(extra)) + ". " + NOT_THESE


def gate_setting(extra=()):
    return {"type": "noul", "instructions": {
        "question": ("Does `message` ask Lookout itself to do something for the user, without any session: "
                     + "; ".join(capability_list(extra)) + "? Not code to be written, and not a message for a session to do or "
                     "answer something.")}}


CHANGE_FJORD = change_fjord()
GATE_SETTING = gate_setting()


def _scrub(x):
    if isinstance(x, str):
        return redact(x)
    if isinstance(x, list):
        return [_scrub(v) for v in x]
    if isinstance(x, dict):
        return {k: _scrub(v) for k, v in x.items()}
    return x


def make(extra=()):
    gates = {**combo.GATES, "gate_setting": gate_setting(extra)}
    crit = {**I.CRIT_WORDED, "change_fjord": change_fjord(extra)}

    def capabilities(case, rng=None):
        state, q, keymap = combo.combo(case, rng, gates=gates, crit=crit)
        return _scrub(state), _scrub(q), keymap

    return capabilities


def _subsets():
    keys = list(EXTRA)
    for mask in range(1, 1 << len(keys)):
        yield [k for i, k in enumerate(keys) if mask >> i & 1]


# capabilities-o: the four adopted before. capabilities-x: all the extras; capabilities-x-archive-mute: that subset (in
# the order of EXTRA); one name per subset, so a phrase that fails can be dropped and the rest measured again.
FORMATS = {"capabilities-o": make()}


def _placebo():
    """The base list in reverse order: the same meaning, other words in other places, so how much a replay moves on a
    wording change that carries no new capability (the noise the real-data comparison is read against)."""
    base = list(CAPABILITIES)
    CAPABILITIES.reverse()
    try:
        return make()
    finally:
        CAPABILITIES[:] = base


FORMATS["capabilities-placebo"] = _placebo()
for _extra in _subsets():
    FORMATS["capabilities-x" if len(_extra) == len(EXTRA) else "capabilities-x-" + "-".join(_extra)] = make(_extra)
