"""A8: where the lexical turns of a session are cut while it works.

Shipped (RouterLexical.turns(tail:working:)): a running session's latest turn has no answer yet, so its last completed
answer sits in the turn before and only counts in f_old. The v2 states mirror that (a running session's latest turn has
said ""). Variants rewrite the turns adapter.past_turns hands to explore.lexical, exactly as a Swift change in
RouterLexical.turns would (every field sees the same turns, so IDF moves with them):

  base      as shipped
  prev      running session, its latest turn without an answer: that turn's said := the turn before's said
  nonempty  any session whose latest turn has no answer: that turn's said := the latest non-empty said before it
  prevonly  as prev, but in f_said alone (f_you / f_old / f_title / the main BM25 keep the shipped turns)
  move      as prev, and the turn before loses its said (the answer moves, f_old no longer counts it too)
  board         every session read from the board fallback (as if no transcript were readable), as shipped
  board_blank   as board, a running session's latest board turn without its cards (cut as the transcript cuts)
"""
import sys

sys.dont_write_bytecode = True

from v2.run import adapter

MODES = ("base", "prev", "nonempty", "prevonly", "move", "board", "board_blank")
_orig = adapter.past_turns
STATE = {"mode": "base"}


def _running(case, sid):
    return any(s["id"] == sid and s.get("running") for s in case.get("board", {}).get("sessions", []))


def rewrite(turns, running, mode):
    if not turns or turns[-1][1] or mode == "base":
        return turns
    if mode in ("prev", "prevonly"):
        if running and len(turns) >= 2:
            return turns[:-1] + [(turns[-1][0], turns[-2][1])]
        return turns
    if mode == "move":
        if running and len(turns) >= 2:
            return turns[:-2] + [(turns[-2][0], ""), (turns[-1][0], turns[-2][1])]
        return turns
    if mode == "nonempty":
        prev = next((said for _, said in reversed(turns[:-1]) if said), "")
        return turns[:-1] + [(turns[-1][0], prev)] if prev else turns
    raise ValueError(mode)


def past_turns(case, sid):
    mode = STATE["mode"]
    if mode.startswith("board"):
        return None
    turns = _orig(case, sid)
    if turns is None or mode == "prevonly":
        return turns
    return rewrite(turns, _running(case, sid), mode)


def install(mode):
    """Call before the RouterSystem loads its modules (adapter.install_lexical reads adapter.past_turns then)."""
    assert mode in MODES, mode
    STATE["mode"] = mode
    adapter.past_turns = past_turns
    if mode == "board_blank":
        from explore import lexical
        orig_bf = lexical.board_fields

        def board_fields(case, s, layout="flat"):
            out = orig_bf(case, s, layout)
            if layout == "turns" and s.get("running"):
                out = out[:-1] + [(out[-1][0], "")]
            return out
        lexical.board_fields = board_fields
    if mode == "prevonly":
        from explore import lexical
        orig_tf = lexical.session_tf

        def session_tf(case, s, cfg):
            if not (cfg["n"] == 1 and cfg["w_you"] == 0 and cfg["w_title"] == 0 and cfg["w_said"] > 0):
                return orig_tf(case, s, cfg)
            saved = lexical.past_turns

            def shifted(c, sid):
                t = saved(c, sid)
                return None if t is None else rewrite(t, _running(c, sid), "prev")
            lexical.past_turns = shifted
            try:
                return orig_tf(case, s, cfg)
            finally:
                lexical.past_turns = saved
        lexical.session_tf = session_tf
