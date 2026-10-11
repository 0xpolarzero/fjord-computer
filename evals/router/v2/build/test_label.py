"""Offline tests for the blind-label boundary and label aggregation.

Run from ``evals/router`` with ``python3 -m unittest v2.build.test_label``.
The fixtures are invented boards; no model process or private corpus is needed.
"""

from copy import deepcopy
import json
from pathlib import Path
from tempfile import TemporaryDirectory
import unittest

from .label import (LABELS, ModelCLI, aggregate_labels, annotations, build_gold,
                    current_adjudication, digest, export_anchor, import_anchor,
                    independent_families, jsonl, krippendorff_alpha, latest_labels,
                    merge, parse_labels, prepare, prompt_for, render_events, write_jsonl)
from v2.run.episodes import load_episodes


def label(family, *, intended="session:a", acceptable=None, clarify=None,
          ask="allowed", consequential=False):
    return {"family": family, "intended": intended,
            "acceptable": ["session:a"] if acceptable is None else acceptable,
            "clarify": [] if clarify is None else clarify, "ask": ask,
            "consequential": consequential, "confidence": 3,
            "evidence": "The visible question matches this session."}


def submit(identity, message, target="session:a", *, ask="forbidden", context=None, on=None):
    event = {"id": identity, "kind": "submit", "message": message,
             "context": context or {},
             "gold": {"intended": target, "acceptable": [] if ask == "required" else [target],
                      "clarify": [target] if ask == "required" else [], "ask": ask,
                      "consequential": False, "evidence": "HIDDEN_GOLD"}}
    if on is not None:
        event["on"] = on
    return event


def episode(events):
    return {"schema": 2, "id": "invented-episode", "family": "invented-family",
            "group": "invented-group",
            "provenance": {"source": "real-moment", "writer": "human",
                           "anchors": ["HIDDEN_ANCHOR"], "went_to": "HIDDEN_ACTUAL"},
            "tags": {"primary": "HIDDEN_PRIMARY", "flow": "single", "slices": []},
            "why": "HIDDEN_WHY", "went_to": "HIDDEN_ACTUAL",
            "state": {"now": "2026-01-02T03:04:05Z", "projects": ["Alpha", "Beta"],
                      "sessions": [
                          {"id": "a", "title": "API", "project": "Alpha", "running": False,
                           "activity": "waiting", "summary": "Choose an API name.",
                           "idle_min": 7, "archived": False, "turns": [["name?", "Choose v1 or v2."]]},
                          {"id": "b", "title": "UI", "project": "Beta", "running": False,
                           "activity": "idle", "summary": "Update the button.",
                           "idle_min": 8, "archived": False, "turns": []}],
                      "cards": [{"id": "c1", "session": "a", "kind": "question",
                                 "text": "Which API name?", "options": ["v1", "v2"],
                                 "created_min_ago": 3}], "history": []},
            "events": events}


def view_for(records, identity):
    return next(record["view"] for record in records if record["event_id"] == identity)


class AggregationTests(unittest.TestCase):
    def test_majority_does_not_union_successful_destinations(self):
        judgments = [
            label("claude", acceptable=["session:a", "session:b"], clarify=["question", "compound"]),
            label("gpt", acceptable=["session:a"], clarify=["session:b", "new:Alpha"]),
            label("gemini", intended="session:b", acceptable=["session:b"],
                  clarify=["session:a", "compound"], ask="forbidden")]
        result = aggregate_labels(judgments, source="real-rewrite")
        self.assertEqual(result["ask"], "allowed")
        self.assertEqual(set(result["acceptable"]), {"session:a", "session:b"})
        self.assertEqual(set(result["clarify"]), {"question", "compound", "new:Alpha"})
        self.assertEqual(result["intended"], "session:a")

    def test_one_acceptance_is_not_successful_gold(self):
        judgments = [label("claude", acceptable=["session:a", "new:Alpha"]),
                     label("gpt"), label("gemini")]
        result = aggregate_labels(judgments, source="goal")
        self.assertEqual(result["acceptable"], ["session:a"])

    def test_duplicate_targets_inside_one_label_are_one_vote(self):
        judgments = [label("claude", acceptable=["session:a", "new:Alpha", "new:Alpha"]),
                     label("gpt"), label("gemini")]
        result = aggregate_labels(judgments, source="goal")
        self.assertNotIn("new:Alpha", result["acceptable"])

    def test_ask_tie_requires_adjudication(self):
        judgments = [label("gpt", acceptable=[], ask="required"),
                     label("gemini", acceptable=[], ask="allowed")]
        with self.assertRaises(ValueError):
            aggregate_labels(judgments, source="goal")

    def test_adjudicator_resolves_ask_tie(self):
        judgments = [label("gpt", acceptable=[], ask="required"),
                     label("gemini", acceptable=[], ask="allowed")]
        adjudication = label("claude", acceptable=[], clarify=["session:a"], ask="required")
        result = aggregate_labels(judgments, source="goal", adjudication=adjudication)
        self.assertEqual(result["ask"], "required")
        self.assertEqual(result["acceptable"], [])

    def test_intended_tie_also_requires_adjudication(self):
        judgments = [label("gpt"), label("gemini", intended="session:b", acceptable=["session:b"])]
        with self.assertRaises(ValueError):
            aggregate_labels(judgments, source="goal")

    def test_adjudication_is_a_vote_not_a_permissive_union(self):
        judgments = [label("gpt", clarify=["session:b"]),
                     label("gemini", intended="session:b", acceptable=["session:b"], clarify=["session:a"])]
        adjudication = label("claude", acceptable=["session:a", "new:Alpha"])
        result = aggregate_labels(judgments, source="goal", adjudication=adjudication)
        self.assertEqual(result["intended"], "session:a")
        self.assertEqual(result["acceptable"], ["session:a"])
        self.assertEqual(result["clarify"], ["session:b"])

    def test_production_can_require_adjudication_despite_a_majority(self):
        judgments = [label("claude"), label("gpt"), label("gemini", ask="forbidden")]
        with self.assertRaises(ValueError):
            aggregate_labels(judgments, source="goal", require_adjudication=True)

    def test_real_historical_intended_does_not_become_observable_acceptance(self):
        judgments = [label(family, clarify=["session:b"]) for family in ("claude", "gpt", "gemini")]
        result = aggregate_labels(judgments, source="real-moment", historical_intended="session:b")
        self.assertEqual(result["intended"], "session:b")
        self.assertEqual(result["acceptable"], ["session:a"])
        self.assertEqual(result["clarify"], ["session:b"])

    def test_scripted_contract_overrides_model_labels_without_mutating_inputs(self):
        judgments = [label(family, intended="question", acceptable=["question"], ask="allowed")
                     for family in ("claude", "gpt", "gemini")]
        deterministic = {"intended": "session:a", "acceptable": ["session:a"], "clarify": [],
                         "ask": "forbidden", "consequential": True,
                         "evidence": "An armed reply determines its session."}
        before = deepcopy((judgments, deterministic))
        result = aggregate_labels(judgments, source="scripted", deterministic_gold=deterministic)
        for field, value in deterministic.items():
            self.assertEqual(result[field], value)
        self.assertEqual((judgments, deterministic), before)


class BlindRenderingTests(unittest.TestCase):
    def test_visible_input_keeps_context_and_hides_gold_source_and_future(self):
        context = {"replyTo": "c1", "pinned": "session:b", "pills": ["Alpha"],
                   "shown": "session:a", "notTo": "session:b", "router_aside": True,
                   "why": "HIDDEN_CONTEXT"}
        fixture = episode([submit("first", "@router what needs attention?", context=context),
                           submit("future", "HIDDEN_FUTURE_MESSAGE")])
        fixture["state"]["why"] = "HIDDEN_STATE"
        fixture["state"]["sessions"][0]["gold"] = "HIDDEN_SESSION"
        fixture["state"]["cards"][0]["label"] = "HIDDEN_CARD"
        before = deepcopy(fixture)
        visible = view_for(render_events(fixture), "first")
        self.assertEqual(set(visible), {"board", "message", "context"})
        self.assertEqual(visible["message"], "@router what needs attention?")
        for key in ("replyTo", "pinned", "pills", "shown", "notTo", "router_aside"):
            self.assertEqual(visible["context"][key], context[key])
        self.assertNotIn("HIDDEN_", json.dumps(visible))
        self.assertEqual(fixture, before)

    def test_earlier_gold_send_and_board_delta_are_visible(self):
        fixture = episode([
            submit("send", "Use v2."),
            {"id": "delta", "kind": "board", "delta": {
                "cards-": ["c1"], "cards+": [{"id": "c2", "session": "b", "kind": "done",
                                              "text": "Button updated", "options": [], "created_min_ago": 0}],
                "sessions~": [{"id": "b", "summary": "Button update is complete."}]}},
            submit("follow", "Now check the button.", "session:b")])
        visible = view_for(render_events(fixture), "follow")
        board = visible["board"]
        self.assertEqual(board["history"][-1]["you"], "Use v2.")
        self.assertEqual(board["history"][-1]["to"], "session:a")
        first = next(session for session in board["sessions"] if session["id"] == "a")
        self.assertTrue(first["running"])
        self.assertEqual(first["turns"][-1][0], "Use v2.")
        self.assertEqual([card["id"] for card in board["cards"]], ["c2"])
        self.assertEqual(next(session for session in board["sessions"] if session["id"] == "b")["summary"],
                         "Button update is complete.")

    def test_pick_delivers_original_message_before_followup(self):
        fixture = episode([
            submit("ask", "Use the compact name.", ask="required", on={"ask": "pick"}),
            {"id": "pick", "kind": "pick", "target": "session:a"},
            submit("follow", "Add tests.")])
        board = view_for(render_events(fixture), "follow")["board"]
        self.assertEqual(board["history"][-1], {"ago_min": 0, "you": "Use the compact name.", "to": "session:a"})
        self.assertEqual(board["sessions"][0]["turns"][-1][0], "Use the compact name.")

    def test_pick_start_uses_the_runner_launch_identity_for_later_board_updates(self):
        fixture = episode([
            submit("ask", "Start a new check.", "new:Alpha", ask="required", on={"ask": "pick"}),
            {"id": "pick", "kind": "pick", "target": "new:Alpha"},
            {"id": "delta", "kind": "board", "delta": {
                "sessions~": [{"id": "started-pick", "summary": "New check ready."}]}},
            submit("follow", "Use the narrow check.", "session:started-pick")])
        board = view_for(render_events(fixture), "follow")["board"]
        launched = next(session for session in board["sessions"] if session["id"] == "started-pick")
        self.assertEqual(launched["summary"], "New check ready.")
        self.assertEqual(launched["turns"], [["Start a new check.", ""]])

    def test_typed_ordinal_while_ask_waits_is_a_new_message(self):
        fixture = episode([
            submit("ask", "Use the compact name.", ask="required", on={"ask": "typed"}),
            submit("typed", "second", "session:b", context={"pinned": "session:b"}, on={"next": "pick"}),
            {"id": "pick", "kind": "pick", "target": "session:a"},
            submit("follow", "Add tests.")])
        records = render_events(fixture)
        self.assertEqual(view_for(records, "typed")["message"], "second")
        board = view_for(records, "follow")["board"]
        self.assertEqual([(row["you"], row["to"]) for row in board["history"][-2:]],
                         [("second", "session:b"), ("Use the compact name.", "session:a")])

    def test_preceding_gold_delivery_does_not_mutate_an_earlier_view(self):
        fixture = episode([submit("first", "Use v2."), submit("second", "Add tests.")])
        records = render_events(fixture)
        self.assertEqual(view_for(records, "first")["board"]["history"], [])
        self.assertEqual(len(view_for(records, "second")["board"]["history"]), 1)

    def test_renderer_covers_correction_submit_without_showing_it_early(self):
        fixture = episode([
            submit("first", "Use v2.", on={"wrong": "correction"}),
            submit("correction", "No, that was for the UI.", "session:b"),
            submit("follow", "Add tests.")])
        records = render_events(fixture)
        self.assertEqual({record["event_id"] for record in records}, {"first", "correction", "follow"})
        self.assertNotIn("No, that was for the UI.", json.dumps(view_for(records, "first")))
        self.assertEqual([(row["you"], row["to"])
                          for row in view_for(records, "follow")["board"]["history"]],
                         [("Use v2.", "session:a")])

    def test_external_prompt_serializes_only_opaque_identity_and_visible_input(self):
        records = render_events(episode([submit("first", "Use v2.")]))
        record = records[0]
        record.update(private="HIDDEN_PRIVATE", source="HIDDEN_SOURCE", writer="HIDDEN_WRITER",
                      original_gold={"intended": "HIDDEN_INTENDED"}, primary="HIDDEN_PRIMARY")
        prompt = prompt_for(records)
        payload = json.loads(prompt.split("<ROUTER_DATA>\n", 1)[1].split("\n</ROUTER_DATA>", 1)[0])
        self.assertEqual(payload, [{"key": record["key"], **record["view"]}])
        self.assertNotIn("HIDDEN_", prompt)

    def test_adjudication_prompt_hides_raw_label_metadata(self):
        records = render_events(episode([submit("first", "Use v2.")]))
        key = records[0]["key"]
        judgment = label("gpt")
        judgment.update(cost="HIDDEN_COST", prompt="HIDDEN_PROMPT", writer="HIDDEN_WRITER")
        prompt = prompt_for(records, {key: [judgment]})
        self.assertIn("The visible question matches this session.", prompt)
        self.assertNotIn("HIDDEN_", prompt)


class ResponseParsingTests(unittest.TestCase):
    def setUp(self):
        self.records = render_events(episode([submit("first", "Use v2."),
                                             submit("second", "Add tests.", "session:b")]))
        self.responses = [{"key": record["key"], **label("gpt", intended=target, acceptable=[target])}
                          for record, target in zip(self.records, ("session:a", "session:b"))]

    def parse(self, responses):
        return parse_labels(json.dumps({"labels": responses}), self.records)

    def test_response_order_is_matched_by_opaque_key(self):
        parsed = self.parse(list(reversed(self.responses)))
        self.assertEqual(parsed[self.records[0]["key"]]["intended"], "session:a")
        self.assertEqual(parsed[self.records[1]["key"]]["intended"], "session:b")

    def test_duplicate_key_does_not_replace_a_missing_event(self):
        with self.assertRaisesRegex(ValueError, "duplicate"):
            self.parse([self.responses[0], self.responses[0]])

    def test_missing_event_rejects_the_entire_batch(self):
        with self.assertRaisesRegex(ValueError, "omitted"):
            self.parse(self.responses[:1])

    def test_unknown_response_key_rejects_the_batch(self):
        responses = deepcopy(self.responses)
        responses[0]["key"] = "unknown-response-key"
        with self.assertRaises(ValueError):
            self.parse(responses)

    def test_destinations_must_exist_on_the_visible_board(self):
        for field in ("intended", "acceptable", "clarify"):
            with self.subTest(field=field):
                responses = deepcopy(self.responses)
                responses[0][field] = "session:absent" if field == "intended" else ["session:absent"]
                with self.assertRaisesRegex(ValueError, "absent"):
                    self.parse(responses)

    def test_confidence_is_an_integer_from_one_through_four(self):
        for confidence in (0, 5, True, 2.0, "3"):
            with self.subTest(confidence=confidence):
                responses = deepcopy(self.responses)
                responses[0]["confidence"] = confidence
                with self.assertRaisesRegex(ValueError, "confidence"):
                    self.parse(responses)

    def test_unknown_intended_is_permitted_without_fabricating_a_target(self):
        responses = deepcopy(self.responses)
        responses[0].update(intended="unknown", acceptable=[], clarify=[], ask="required")
        parsed = self.parse(responses)
        self.assertEqual(parsed[self.records[0]["key"]]["intended"], "unknown")


class ResumeTests(unittest.TestCase):
    def test_later_failure_does_not_erase_a_successful_label(self):
        success = {"key": "opaque", "fingerprint": "current", "family": "gpt", "role": "independent",
                   "status": "ok", "label": label("gpt")}
        failure = {**success, "status": "error", "label": None}
        successes, attempted = latest_labels([success, failure])
        identity = ("opaque", "current", "gpt", "independent")
        self.assertEqual(successes[identity], success)
        self.assertEqual(attempted, {identity})

    def test_stale_view_success_is_not_reused_for_a_new_fingerprint(self):
        stale = {"key": "opaque", "fingerprint": "old", "family": "gpt", "role": "independent",
                 "status": "ok", "label": label("gpt")}
        current = {**stale, "fingerprint": "new", "status": "error"}
        successes, attempted = latest_labels([stale, current])
        self.assertNotIn(("opaque", "new", "gpt", "independent"), successes)
        self.assertIn(("opaque", "old", "gpt", "independent"), successes)
        self.assertIn(("opaque", "new", "gpt", "independent"), attempted)

    def test_latest_success_replaces_older_success_for_the_same_view_and_role(self):
        older = {"key": "opaque", "fingerprint": "current", "family": "gpt", "role": "independent",
                 "status": "ok", "label": label("gpt")}
        newer = {**older, "label": label("gpt", ask="forbidden")}
        successes, _ = latest_labels([older, newer])
        self.assertEqual(successes[("opaque", "current", "gpt", "independent")]["label"]["ask"], "forbidden")


class CLIIsolationTests(unittest.TestCase):
    def test_gemini_dotenv_search_stops_in_the_confined_working_directory(self):
        LABELS.mkdir(parents=True, exist_ok=True)
        with TemporaryDirectory(prefix="test-label-cli-", dir=LABELS) as directory:
            cli = ModelCLI(Path(directory))
            dotenv = cli.cwd / ".gemini" / ".env"
            self.assertTrue(dotenv.is_file())
            self.assertEqual(dotenv.read_text(), "")
            self.assertTrue(dotenv.resolve().is_relative_to(Path(directory).resolve()))
            cli.close()


class HumanAnchorTests(unittest.TestCase):
    def setUp(self):
        LABELS.mkdir(parents=True, exist_ok=True)
        self.temporary = TemporaryDirectory(prefix="test-label-", dir=LABELS)
        self.addCleanup(self.temporary.cleanup)
        self.directory = Path(self.temporary.name)
        self.records = render_events(episode([submit("first", "Use v2.")]))

    def filled_anchor(self, *, destination="session:a", ask="forbidden"):
        path = export_anchor(self.records, directory=self.directory, count=1)
        text = path.read_text().replace("Destination: \n", f"Destination: {destination}\n")
        text = text.replace("Ask: \n", f"Ask: {ask}\n")
        text = text.replace("Consequential: \n", "Consequential: true\n")
        path.write_text(text)
        return path

    def test_blind_export_and_filled_import_round_trip(self):
        path = self.filled_anchor()
        self.assertNotIn("HIDDEN_", path.read_text())
        self.assertEqual(import_anchor(self.records, directory=self.directory), 1)
        rows = jsonl(self.directory / "raw.jsonl")
        self.assertEqual(len(rows), 1)
        self.assertEqual((rows[0]["family"], rows[0]["role"], rows[0]["status"]), ("human", "human", "ok"))
        self.assertEqual(rows[0]["label"]["intended"], "session:a")
        self.assertEqual(rows[0]["label"]["acceptable"], ["session:a"])
        self.assertEqual(rows[0]["label"]["ask"], "forbidden")
        self.assertTrue(rows[0]["label"]["consequential"])

    def test_incremental_export_preserves_filled_answers(self):
        path = self.filled_anchor()
        filled = path.read_text()
        self.assertEqual(export_anchor(self.records, directory=self.directory, count=1), path)
        self.assertEqual(path.read_text(), filled)

    def test_blank_form_imports_no_answers(self):
        export_anchor(self.records, directory=self.directory, count=1)
        self.assertEqual(import_anchor(self.records, directory=self.directory), 0)
        self.assertEqual(jsonl(self.directory / "raw.jsonl"), [])

    def test_changed_visible_input_rejects_stale_human_answers(self):
        self.filled_anchor()
        changed = deepcopy(self.records)
        changed[0]["fingerprint"] = "f" * 64
        with self.assertRaisesRegex(ValueError, "stale"):
            import_anchor(changed, directory=self.directory)

    def test_partly_filled_answer_is_rejected(self):
        self.filled_anchor(ask="")
        with self.assertRaisesRegex(ValueError, "both Destination and Ask"):
            import_anchor(self.records, directory=self.directory)

    def test_human_destination_is_validated_against_the_same_visible_board(self):
        self.filled_anchor(destination="session:absent")
        with self.assertRaisesRegex(ValueError, "absent"):
            import_anchor(self.records, directory=self.directory)


class IncrementalIntegrationTests(unittest.TestCase):
    """Exercise files, annotation identities and merge without starting a CLI."""

    def setUp(self):
        LABELS.mkdir(parents=True, exist_ok=True)
        self.temporary = TemporaryDirectory(prefix="test-label-integration-", dir=LABELS)
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.inputs = self.root / "episodes"
        self.inputs.mkdir()
        self.directory = self.root / "labels"
        self.output = self.root / "labelled"

    def source(self, name, *, source="real-moment", writer="human"):
        fixture = episode([submit("first", "Use v2.", context={"replyTo": "c1"})])
        fixture["provenance"].update(source=source, writer=writer)
        path = self.inputs / name
        write_jsonl(path, [fixture])
        return path, fixture

    def prepare(self, paths=None):
        return prepare(paths or [str(self.inputs / "*.jsonl")], directory=self.directory)

    @staticmethod
    def raw_label(record, family, *, role="independent", **fields):
        judgment = label(family, **fields)
        judgment.pop("family")
        return {"key": record["key"], "fingerprint": record["fingerprint"],
                "family": family, "role": role, "status": "ok", "label": judgment}

    def test_duplicate_episode_ids_are_scoped_to_file_and_row(self):
        first, fixture = self.source("a.jsonl", source="scripted", writer="scripted")
        write_jsonl(first, [fixture, fixture])
        self.source("b.jsonl", source="scripted", writer="scripted")
        records = self.prepare()
        self.assertEqual(len(records), 3)
        self.assertEqual(len({record["key"] for record in records}), 3)
        self.assertEqual(len({record["episode_id"] for record in records}), 3)
        self.assertEqual({record["original_episode_id"] for record in records}, {fixture["id"]})
        self.assertEqual(sorted(record["input_index"] for record in records), [1, 1, 2])
        build_gold(records, directory=self.directory)
        self.assertEqual(merge(records, directory=self.directory, output=self.output)["labelled_episodes"], 3)
        merged = load_episodes([self.output / "a.jsonl", self.output / "b.jsonl"])
        self.assertEqual(len({item["id"] for item in merged}), 3)

    def test_failure_ledgers_are_excluded_before_parsing(self):
        self.source("real.jsonl")
        (self.inputs / "written_gpt_failures.jsonl").write_text("Not an episode or JSON.\n")
        records = self.prepare()
        self.assertEqual(len(records), 1)
        status = jsonl(self.directory / "input_status.jsonl")
        self.assertEqual(len(status), 1)
        self.assertIn("excluded", status[0]["status"])

    def test_incomplete_last_jsonl_row_is_deferred_until_complete(self):
        path, fixture = self.source("growing.jsonl")
        partial = json.dumps(fixture)[:80]
        path.write_text(json.dumps(fixture) + "\n" + partial)
        self.assertEqual(len(jsonl(path, growing=True)), 1)
        self.assertEqual(len(self.prepare()), 1)
        with self.assertRaises(ValueError):
            jsonl(path)
        path.write_text(json.dumps(fixture) + "\n" + json.dumps(fixture) + "\n")
        self.assertEqual(len(self.prepare()), 2)

    def test_growing_mode_does_not_hide_malformed_completed_rows(self):
        path = self.inputs / "bad.jsonl"
        path.write_text('{"schema":\n')
        with self.assertRaises(ValueError):
            jsonl(path, growing=True)

    def test_scripted_gold_merges_into_runner_loadable_episodes(self):
        self.source("scripted.jsonl", source="scripted", writer="scripted")
        records = self.prepare()
        golds = build_gold(records, directory=self.directory)
        self.assertEqual(golds[0]["status"], "ready")
        self.assertEqual(merge(records, directory=self.directory, output=self.output),
                         {"labelled_episodes": 1, "pending_episodes": 0})
        merged = load_episodes(self.output / "scripted.jsonl")
        self.assertEqual(len(merged), 1)
        for event in merged[0]["events"]:
            if event["kind"] == "submit":
                self.assertIn(event["gold"]["ask"], ("required", "allowed", "forbidden"))
        self.assertEqual(merged[0]["events"][0]["gold"], records[0]["original_gold"])

    def test_merge_rechecks_source_changed_after_preparation(self):
        path, fixture = self.source("scripted.jsonl", source="scripted", writer="scripted")
        records = self.prepare()
        build_gold(records, directory=self.directory)
        fixture["events"][0]["message"] = "Use v1 instead."
        write_jsonl(path, [fixture])
        self.assertEqual(merge(records, directory=self.directory, output=self.output),
                         {"labelled_episodes": 0, "pending_episodes": 1})
        self.assertEqual(jsonl(self.output / "scripted.jsonl"), [])

    def test_two_agreeing_real_labels_still_leave_third_family_pending(self):
        self.source("real.jsonl")
        records = self.prepare()
        write_jsonl(self.directory / "raw.jsonl", [self.raw_label(records[0], family)
                                                    for family in ("claude", "gpt")])
        golds = build_gold(records, directory=self.directory)
        self.assertEqual(golds[0]["status"], "pending")
        self.assertIsNone(golds[0]["gold"])
        self.assertEqual((golds[0]["independent_labels"], golds[0]["expected_independent"]), (2, 3))

    def test_writer_is_excluded_and_other_two_need_a_current_adjudicator(self):
        self.source("written_claude.jsonl", source="goal", writer="claude")
        records = self.prepare()
        record = records[0]
        self.assertEqual(independent_families(record), ("gpt", "gemini"))
        rows = [self.raw_label(record, "claude", intended="question", acceptable=["question"]),
                self.raw_label(record, "gpt"), self.raw_label(record, "gemini")]
        write_jsonl(self.directory / "raw.jsonl", rows)
        gold = build_gold(records, directory=self.directory)[0]
        self.assertEqual((gold["status"], gold["independent_labels"]), ("pending", 2))
        independent = annotations(record, latest_labels(rows)[0])
        self.assertEqual([judgment["family"] for judgment in independent], ["gpt", "gemini"])
        adjudication = self.raw_label(record, "claude", role="adjudicator")
        adjudication["judgments_sha256"] = digest(independent)
        write_jsonl(self.directory / "raw.jsonl", rows + [adjudication])
        gold = build_gold(records, directory=self.directory)[0]
        self.assertEqual(gold["status"], "ready")
        self.assertTrue(gold["adjudicated"])
        self.assertEqual(gold["gold"]["intended"], "session:a")

    def test_changed_independent_labels_invalidate_cached_adjudication(self):
        self.source("real.jsonl")
        record = self.prepare()[0]
        rows = [self.raw_label(record, family) for family in ("claude", "gpt", "gemini")]
        judgments = annotations(record, latest_labels(rows)[0])
        adjudication = self.raw_label(record, "claude", role="adjudicator")
        adjudication["judgments_sha256"] = digest(judgments)
        successes, _ = latest_labels(rows + [adjudication])
        self.assertEqual(current_adjudication(record, judgments, successes), adjudication["label"])
        changed = deepcopy(judgments)
        changed[0]["confidence"] = 4
        self.assertIsNone(current_adjudication(record, changed, successes))

    def test_blank_human_consequence_retains_previous_boolean(self):
        self.source("real.jsonl")
        records = self.prepare()
        record = records[0]
        human = self.raw_label(record, "human", role="human")
        human["consequential_explicit"] = False
        write_jsonl(self.directory / "raw.jsonl", [human])
        for previous in (True, False):
            with self.subTest(previous=previous):
                gold = {**record["original_gold"], "consequential": previous}
                write_jsonl(self.directory / "gold.jsonl", [{"key": record["key"],
                             "fingerprint": record["fingerprint"], "status": "ready", "gold": gold}])
                result = build_gold(records, directory=self.directory)[0]
                self.assertEqual(result["status"], "ready")
                self.assertIs(result["gold"]["consequential"], previous)

    def test_blank_human_consequence_without_evidence_remains_pending(self):
        self.source("real.jsonl")
        records = self.prepare()
        human = self.raw_label(records[0], "human", role="human")
        human["consequential_explicit"] = False
        write_jsonl(self.directory / "raw.jsonl", [human])
        result = build_gold(records, directory=self.directory)[0]
        self.assertEqual(result["status"], "pending")
        self.assertIsNone(result["gold"])
        self.assertIn("omits consequence", result["reason"])

    def test_stale_prior_boolean_cannot_resolve_blank_human_consequence(self):
        self.source("real.jsonl")
        records = self.prepare()
        record = records[0]
        human = self.raw_label(record, "human", role="human")
        human["consequential_explicit"] = False
        write_jsonl(self.directory / "raw.jsonl", [human])
        write_jsonl(self.directory / "gold.jsonl", [{"key": record["key"], "fingerprint": "stale",
                     "status": "ready", "gold": {**record["original_gold"], "consequential": True}}])
        self.assertEqual(build_gold(records, directory=self.directory)[0]["status"], "pending")


class AgreementTests(unittest.TestCase):
    def test_alpha_is_one_when_all_annotators_agree_on_varying_categories(self):
        self.assertEqual(krippendorff_alpha([["allowed"] * 3, ["required"] * 3]), 1.0)

    def test_alpha_can_be_negative_for_systematic_disagreement(self):
        self.assertAlmostEqual(krippendorff_alpha([["allowed", "required"], ["required", "allowed"]]), -0.5)

    def test_unpaired_annotations_do_not_create_agreement_evidence(self):
        self.assertIsNone(krippendorff_alpha([["allowed"], ["required"], []]))

    def test_missing_writer_family_is_not_a_category(self):
        self.assertEqual(krippendorff_alpha([["allowed", None, "allowed"],
                                            [None, "required", "required"]]), 1.0)

    def test_alpha_weights_unequal_numbers_of_annotators_by_coincidences(self):
        self.assertAlmostEqual(krippendorff_alpha([["allowed", "allowed", "allowed"],
                                                  ["allowed", "required"],
                                                  ["required", "required"]]), 0.5)

    def test_alpha_does_not_depend_on_unit_or_annotator_order(self):
        units = [["required", "allowed", "allowed"], ["forbidden", "forbidden"], ["allowed", "required"]]
        self.assertAlmostEqual(krippendorff_alpha(units), krippendorff_alpha([list(reversed(unit)) for unit in reversed(units)]))


if __name__ == "__main__":
    unittest.main()
