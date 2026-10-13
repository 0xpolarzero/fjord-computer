"""Behavior ports from Tests/FjordTests/RouterDispatcherTests.swift.

Run from evals/router: python3 -m unittest v2.run.test_rules
Each test cites the Swift behavior it preserves rather than testing regex internals.
"""

import copy
import unittest

from . import rules


def board():
    # RouterDispatcherTests.setup, using v2 project names rather than folder paths.
    return {
        "projects": ["lookout", "docs", "empty"],
        "sessions": [
            {"id": "local_a", "title": "Fix the login bug", "project": "lookout",
             "idle_min": 0, "running": True, "archived": False},
            {"id": "local_b", "title": "Update the docs", "project": "docs",
             "idle_min": 1, "running": False, "archived": False},
        ],
        "cards": [{"id": "local_a#w1", "session": "local_a", "kind": "question",
                   "text": "Which database?", "options": ["SQLite", "Postgres"]}],
    }


def found(target, *, sure=True, ranked=None, **extra):
    return {"decision": "send" if sure else "ask", "target": target if sure else None,
            "top": target, "ranked": ranked or [target, "unclear"],
            "sure": sure, "assisted": True, **extra}


class RulesTests(unittest.TestCase):
    def setUp(self):
        self.state = board()

    def post(self, message, target="session:local_b", context=None, **options):
        return rules.post_jev(self.state, message, context or {}, found(target, **options))

    def approval(self, session="local_b"):
        self.state["cards"] = [{"id": session + "#w9", "session": session,
                                "kind": "approval", "text": "May I delete production data?"}]

    def ci(self, project="ci", session="local_c"):
        if project not in self.state["projects"]:
            self.state["projects"].append(project)
        self.state["sessions"].append({"id": session, "title": "Flaky job", "project": project,
                                       "running": True, "idle_min": 0, "archived": False})

    def test_armed_reply_goes_to_its_card_without_jev(self):
        # aClickedPickIsSentWithoutAskingAgain / aFormIsAnsweredByYourWords...
        result = rules.plan(self.state, "use sqlite", {"replyTo": "local_a#w1"})
        self.assertEqual((result["decision"], result["target"], result["reason"]),
                         ("send", "session:local_a", "armed-reply"))

    def test_reply_precedes_pin_and_start_pill(self):
        result = rules.plan(self.state, "@docs start a session", {
            "replyTo": "local_a#w1", "pinned": "session:local_b", "pills": ["docs"]})
        self.assertEqual(result["target"], "session:local_a")

    def test_missing_reply_card_falls_through_to_pin(self):
        result = rules.plan(self.state, "ship", {"replyTo": "gone", "pinned": "session:local_b"})
        self.assertEqual(result["target"], "session:local_b")

    def test_pin_and_wave_off_have_distinct_paths(self):
        # aPinnedTargetGoesWithoutJevAndAWavedOffOneIsNeverSentToUnasked
        result = rules.plan(self.state, "add a changelog entry", {"pinned": "session:local_b"})
        self.assertEqual(result["reason"], "pinned")
        self.assertEqual(self.post("add a changelog entry", context={"notTo": "session:local_b"})["decision"], "ask")

    def test_explicit_pin_and_armed_card_do_not_gain_jev_eligibility_veto(self):
        # Swift plan consults router.cards, not routerShownOpenCards, for replyTo.
        self.state["cards"][0]["hidden"] = True
        self.state["sessions"][0]["archived"] = True
        self.assertEqual(rules.plan(self.state, "SQLite", {"replyTo": "local_a#w1"})["target"], "session:local_a")
        self.assertEqual(rules.plan(self.state, "ship", {"pinned": "session:local_a"})["target"], "session:local_a")

    def test_single_tag_starts_when_asked_or_project_is_empty(self):
        # aTaggedProjectStartsASessionWhenAskedOrWhenItHasNothingElse
        self.assertEqual(rules.plan(self.state, "start a new session to add a badge", {"pills": ["lookout"]})["target"], "new:lookout")
        self.assertEqual(rules.plan(self.state, "add a changelog", {"pills": ["empty"]})["target"], "new:empty")
        self.assertIsNone(rules.plan(self.state, "what is the status", {"pills": ["lookout"]}))

    def test_an_open_card_prevents_implicit_pill_start_even_without_a_session(self):
        self.state["cards"].append({"id": "orphan", "session": "gone", "project": "empty", "kind": "done"})
        self.assertIsNone(rules.plan(self.state, "@empty add a changelog", {"pills": ["empty"]}))

    def test_pills_deduplicate_and_multiple_projects_do_not_fix_a_start(self):
        self.assertEqual(rules.plan(self.state, "start a session", {"pills": ["lookout", "lookout"]})["target"], "new:lookout")
        self.assertIsNone(rules.plan(self.state, "start a session", {"pills": ["lookout", "docs"]}))

    def test_start_phrase_behavior_from_swift(self):
        # theRulesForAskingForANewSession / aFeatureNamedLikeASession...
        yes = ["start a new session for the api", "new chat about tests", "open a session to look at the build",
               "Spin up a session", "@lookout start a session to fix it", "start a new chat in lookout: fix it",
               "open a session for the build", "start a session, fix it", "start a session with opus: fix it",
               "start a new session", "start a session. fix it", "start a session - fix it",
               "start a session — fix it", "start a session (with opus) fix it", "start a session!",
               "start a session: fix it", "please start a session in the lookout project: fix it"]
        no = ["the session is stuck", "fix the news feed", "tell it to open the file",
              "don't start a new session; fix the tests in the existing one", "never open a new chat for this",
              "fix it in the session, not a new session", "create a chat widget with message history",
              "create a session manager", "open a conversation list view", "create a session-based authentication flow",
              "open session.json and explain its fields", "create a chat_ui component",
              "open a session:json parser", "start a session-"]
        for text in yes:
            with self.subTest(text=text):
                self.assertTrue(rules.wants_new_session(text))
                self.assertIsNotNone(rules.start_request(text))
        for text in no:
            with self.subTest(text=text):
                self.assertFalse(rules.wants_new_session(text))
                self.assertIsNone(rules.start_request(text))

    def test_pill_with_space_preserves_start_phrase(self):
        # aPillWithASpaceInItsNameStillLeadsARequestToStartASession
        self.ci("My App", "local_m")
        text = "@My App start a session to fix the CI"
        self.assertTrue(rules.wants_new_session(text, ["My App"]))
        self.assertEqual(rules.plan(self.state, text, {"pills": ["My App"]})["target"], "new:My App")

    def test_negated_start_and_feature_names_with_pills_are_classified(self):
        # aSessionNotAskedForIsNotStarted / aMarkJoinedToTheNoun...
        for text in ["don't start a new session; fix the tests in the existing one",
                     "@lookout create a session-based authentication flow",
                     "@lookout open session.json and explain its fields"]:
            self.assertIsNone(rules.plan(self.state, text, {"pills": ["lookout"]}))

    def test_named_start_project_overrides_jev_even_when_policy_asks(self):
        # aDestinationYourOwnWordsNameIsWhereItGoes
        for sure in [True, False]:
            result = self.post("start a session in docs to fix the links", "session:local_a", sure=sure)
            self.assertEqual((result["decision"], result["target"]), ("start", "new:docs"))
            self.assertEqual(result["reason"], "named-destination")

    def test_start_project_requires_the_following_request_not_task_words(self):
        # aProjectNamedLikeAWordOfTheTaskNeverTakesItsWordsAway
        for text in ["start a session in case the build breaks, revert it",
                     "start a session in no to never delete the backups",
                     "start a new session to fix the login bug in lookout"]:
            self.assertIsNone(rules.start_request(text)["project"])
            self.assertIsNone(rules.destination(self.state, text))
        text = "start a session in the lookout project, with opus: fix it"
        self.assertEqual(rules.start_request(text)["project"], "lookout")
        self.assertEqual(rules.destination(self.state, text), "new:lookout")

    def test_tell_project_and_colon_address_override_task_project(self):
        # withoutJevASessionAddressedOutrightWinsOverAProjectTheTaskNames
        self.ci()
        for text in ["tell the CI session to rerun the lookout tests", "CI: rerun the lookout tests",
                     "please tell CI to update the docs", "ask the CI chat to fix it"]:
            self.assertEqual(self.post(text)["target"], "session:local_c")

    def test_titles_never_become_addresses_and_duplicate_sessions_are_ambiguous(self):
        # withoutJevASessionTitledLikeTheTaskIsNeverTheAddressee
        self.ci("other", "local_x")
        self.state["sessions"][-1]["title"] = "docs"
        self.assertEqual(rules.addressed_session(self.state, "tell docs to ship"), "local_b")
        self.assertIsNone(rules.addressed_session(self.state, "tell the Update the docs session to ship"))
        self.ci("docs", "local_z")
        self.assertIsNone(rules.addressed_session(self.state, "tell docs to ship again"))

    def test_prose_pronouns_and_note_labels_never_capture_messages(self):
        # aSessionTitledWithWordsOfProseNeverCapturesAMessageStartingWithThem
        for name in ["me", "note", "everyone"]:
            self.ci(name, "local_" + name)
        for name in ["me how", "note to self"]:
            self.ci("evil", "local_" + name)
            self.state["sessions"][-1]["title"] = name
        for text in ["Tell me: does the production token appear in any session?", "note: the token is redacted",
                     "tell everyone to paste the token", "Tell me how to check whether production token appears",
                     "note to self: paste the token"]:
            self.assertIsNone(rules.addressed_session(self.state, text), text)

    def test_project_address_must_be_unique_across_every_known_project(self):
        self.state["sessions"][1]["project"] = "/code/docs"
        self.state["projects"] = ["lookout", "/code/docs", "/work/docs"]
        self.assertIsNone(rules.addressed_session(self.state, "tell docs to ship"))

    def test_addressed_session_beyond_offered_limit_does_not_override_jev(self):
        # withoutJevAProjectWithOneSessionIsTheAddresseeEvenPastTheLimits
        self.state["sessions"][1]["idle_min"] = 60
        for i in range(21):
            self.state["sessions"].append({"id": "local_n" + str(i), "title": "Chore",
                                           "project": "other", "running": False, "idle_min": i / 60})
        self.assertEqual(rules.addressed_session(self.state, "tell docs to ship"), "local_b")
        self.assertIsNone(rules.destination(self.state, "tell docs to ship"))

    def test_project_pills_narrow_spoken_destination_candidates(self):
        self.assertIsNone(rules.destination(self.state, "tell docs to ship", {"pills": ["lookout"]}))

    def test_not_to_blocks_named_override_and_matching_jev_send(self):
        text = "tell docs to ship"
        veto = {"notTo": "session:local_b"}
        self.assertEqual(self.post(text, context=veto)["decision"], "ask")
        # The words' destination is waved off; a different Jev result is retained.
        self.assertEqual(self.post(text, "session:local_a", context=veto)["target"], "session:local_a")

    def test_approval_card_vetoes_bare_yes_and_topical_yes(self):
        # aSessionAskingForAnOKDoesntGetAYesMeantElsewhere
        self.approval()
        for target in ["answer:local_b#w9", "session:local_b"]:
            for message in ["yes", "yes, delete the old data"]:
                result = self.post(message, target)
                self.assertEqual((result["decision"], result["reason"]), ("ask", "approval-veto"))
                self.assertEqual(result["ranked"][0], "session:local_b")
        self.assertEqual(self.post("tell docs to go ahead", "answer:local_b#w9")["decision"], "send")

    def test_project_short_name_clears_approval_only_for_one_project_one_session(self):
        # aShortNameOfAProjectWithTwoSessionsDoesntAddressTheOneAskingForAnOK
        self.ci()
        self.approval("local_c")
        message = "yes, ship it on ci"
        self.assertEqual(self.post(message, "session:local_c")["decision"], "send")
        self.ci("ci", "local_d")
        self.assertEqual(self.post(message, "session:local_c")["decision"], "ask")
        self.state["sessions"][-1]["project"] = "/work/ci"
        self.assertEqual(self.post(message, "session:local_c")["decision"], "ask")

    def test_a_title_word_does_not_clear_approval(self):
        # aSessionAskingForAnOKIsntAddressedByAWordOfTheTitleItGaveItself
        self.state["sessions"][1]["title"] = "Prod db"
        self.approval()
        self.assertEqual(self.post("yes, back up the db first")["decision"], "ask")

    def test_question_card_and_sure_unrelated_words_are_not_vetoed(self):
        # aShortReplyGoesToTheCardItAnswers / aSurePickIsSentWithoutSharingAWordWithIt
        self.assertEqual(self.post("yes", "answer:local_a#w1")["target"], "session:local_a")
        self.assertEqual(self.post("and the date too")["decision"], "send")
        self.assertEqual(self.post("and the date too", sure=False)["decision"], "ask")

    def test_router_only_bypasses_reply_pin_and_pill_start(self):
        # aMessageWhollyForTheRouterIsAskedOfItEvenWithAReplyArmed
        context = {"replyTo": "local_a#w1", "pinned": "session:local_b", "pills": ["empty"]}
        self.assertIsNone(rules.plan(self.state, "@router what needs me?", context))
        self.assertEqual(self.post("@router what needs me?", "question", context)["target"], "question")
        result = self.post("@router what needs me?", "session:local_a", context)
        self.assertEqual((result["decision"], result["ranked"]), ("ask", ["question", "change_fjord"]))

    def test_router_only_keeps_only_intents_without_promoting_sureness(self):
        result = self.post("@router what needs me?", "session:local_a", ranked=[
            "session:local_a", {"target": "question", "p": .2}, "compound", "change_fjord"])
        self.assertEqual(result["decision"], "ask")
        self.assertEqual(result["ranked"], [{"target": "question", "p": .2}, "compound", "change_fjord"])

    def test_router_only_reuses_shown_intent_but_never_sends_shown_session(self):
        context = {"shown": "question", "replyTo": "local_a#w1", "pinned": "session:local_b"}
        result = rules.plan(self.state, "@router what needs me?", context)
        self.assertEqual((result["decision"], result["target"], result["reason"]),
                         ("intent", "question", "live-shown"))
        context["shown"] = "session:local_b"
        result = rules.plan(self.state, "@router what needs me?", context)
        self.assertEqual((result["decision"], result["target"], result["ranked"]),
                         ("ask", None, ["question", "change_fjord"]))

    def test_router_aside_in_reply_preserves_armed_destination(self):
        text = "SQLite (@router no rush)"
        self.assertFalse(rules.for_router(text, {"router_aside": True}))
        self.assertEqual(rules.plan(self.state, text, {"replyTo": "local_a#w1"})["target"], "session:local_a")
        self.assertEqual(rules.edit(text), "SQLite")

    def test_router_markers_require_real_asides_and_skip_code_quotes_paths(self):
        for text in ["ask @router", "@router.js is broken, fix it", "@router/core is broken",
                     "@router-old is down", "user@router.com", "`@router what needs me?`",
                     "    @router what needs me?", "```\n@router what needs me?\n```",
                     '"(@router no rush)"', "(@router no rush"]:
            self.assertFalse(rules.for_router(text), text)
            self.assertEqual(rules.edit(text), text)
        for text in ["@ROUTER what needs me?", "(@router later)", "[@router later]",
                     "(@router don't wait on `CI`)", "  @router what needs me?\n@router later"]:
            self.assertTrue(rules.for_router(text), text)

    def test_only_leading_recorded_pills_are_removed(self):
        self.assertEqual(rules.edit("@My App SQLite", ["My App"]), "SQLite")
        self.assertEqual(rules.edit("@lookout\nSQLite", ["lookout"]), "\nSQLite")
        self.assertEqual(rules.edit("@lookout: \nSQLite", ["lookout"]), "SQLite")
        self.assertEqual(rules.edit("move @lookout to Swift 6", ["lookout"]), "move @lookout to Swift 6")
        self.assertEqual(rules.edit("@lookout fix the tests"), "@lookout fix the tests")
        self.assertEqual(rules.edit("    @cache\n    def f(): pass", ["cache"]), "    @cache\n    def f(): pass")

    def test_live_shown_pick_preserves_chip_and_bypasses_approval_veto(self):
        # aPickShownOverTheComposerIsSentAsShownAfterItsCopyExpired
        self.approval()
        context = {"shown": "session:local_b", "jev": found("session:local_b")}
        result = rules.plan(self.state, "yes", context)
        self.assertEqual((result["decision"], result["target"], result["reason"]),
                         ("send", "session:local_b", "live-shown"))
        self.assertTrue(result["live"])
        # v2's minimal context carries a sure chip implicitly.
        self.assertEqual(rules.plan(self.state, "yes", {"shown": "session:local_b"})["decision"], "send")

    def test_live_shown_still_respects_not_to_named_words_and_eligibility(self):
        self.assertEqual(rules.plan(self.state, "ship", {"shown": "session:local_b", "notTo": "session:local_b"})["decision"], "ask")
        self.assertEqual(rules.plan(self.state, "tell lookout to fix it", {"shown": "session:local_b"})["target"], "session:local_a")
        self.state["sessions"][1]["archived"] = True
        self.assertEqual(rules.plan(self.state, "ship", {"shown": "session:local_b"})["decision"], "ask")

    def test_unshown_or_mismatched_carried_pick_is_not_confirmation(self):
        # aPickReadWhileYouTypedButNeverShownConfirmsNothing
        self.assertIsNone(rules.plan(self.state, "ship", {"jev": found("session:local_b")}))
        self.assertIsNone(rules.plan(self.state, "ship", {"shown": "session:local_a", "jev": found("session:local_b")}))
        self.approval()
        self.assertEqual(self.post("yes", context={"shown": "session:local_a"})["decision"], "ask")

    def test_jev_ineligible_cards_are_not_sent_or_offered(self):
        # aCardHiddenSinceItWasOfferedOrPickedIsNotSentTo
        self.state["cards"][0]["hidden"] = True
        result = self.post("use sqlite", "answer:local_a#w1", ranked=["answer:local_a#w1", "session:local_b"])
        self.assertEqual((result["decision"], result["reason"], result["ranked"]),
                         ("ask", "ineligible", ["session:local_b"]))

    def test_done_card_hidden_by_tasks_is_not_eligible(self):
        self.state["cards"][0]["kind"] = "done"
        self.state["tasks"] = {"local_a": ["task"]}
        self.assertFalse(rules.eligible(self.state, "answer:local_a#w1"))
        self.state["cards"][0]["kind"] = "question"
        self.assertTrue(rules.eligible(self.state, "answer:local_a#w1"))

    def test_ask_options_canonicalize_cards_deduplicate_and_limit_to_four(self):
        ranked = ["answer:local_a#w1", "session:local_a", "session:local_b",
                  "new:docs", "question", "change_fjord", "unclear"]
        result = self.post("use sqlite", "answer:local_a#w1", sure=False, ranked=ranked)
        self.assertEqual(result["ranked"], ["session:local_a", "session:local_b", "new:docs", "question"])

    def test_functions_do_not_mutate_episode_state_or_policy_results(self):
        before = copy.deepcopy(self.state)
        decision = found("session:local_b")
        original = copy.deepcopy(decision)
        rules.post_jev(self.state, "tell lookout to fix it", {}, decision)
        self.assertEqual(self.state, before)
        self.assertEqual(decision, original)


if __name__ == "__main__":
    unittest.main()
