# D-guest fixes: the review findings and the macOS transfer caveat

Silo branch `engine/d-guest-fixes` (worktree `/Users/polarzero/silo-work/d-guest`), fast-forwarded into Silo `main` at **`38dc9357`**. Nothing pushed, no VM or app started. Source: `reports/d-guest.review.md` (10 findings) plus the merge caveat.

## Commits

| Hash | Subject |
| --- | --- |
| `58e66055` | `fix(engine): harden guest exec streaming, cancellation and replay` (findings 1, 2, 4, 5, 8, 9, 10) |
| `66b00614` | `fix(engine): serialize guest file writes by resolved folder` (finding 3) |
| `e766c383` | `fix(engine): arm guest watches before answering and bound their cost` (findings 6, 7) |
| `101f3288` | `fix(engine): create a macOS transfer job before it waits for its turn` (caveat) |
| `38dc9357` | merge of `main` (twice; re-gated after each) |

## What changed, by finding

1. **P1, Linux exec without stdin.** `Target::plan` now always passes `--stream` (plus `--no-stdin` when there is no input), checked against the pinned CLI source (`exec.rs`: `--stream --no-stdin` runs `exec_stream_with`). Output is live and the host cap applies. Test: `linux_commands_always_stream_so_output_is_live_and_bounded`.
2. **P1, cancel loses the group.** The supervisor (`exec.pl`) now keeps itself outside the command's group: the command is the group leader, so after it exits the group id names exactly its descendants. The `.pid` record is kept while any descendant lives and removed otherwise; `control.pl` `status` removes it once the group is dead. The supervisor forwards TERM/INT/HUP to the group. Cancel now records whether `terminate` failed (`Ok(false)` or an error) and the job finishes as `lost`/Internal ("could not be stopped") instead of Cancelled. Tests: `cancelling_ends_descendants_that_outlive_a_command_that_exited_first`, `a_cancellation_that_could_not_end_the_tree_is_a_failure_not_a_cancellation`.
3. **P1, path aliases.** The guest helper resolves the destination's parent (`Cwd::abs_path`), takes an exclusive `flock` on that folder for the whole write (all replace modes), re-checks the folder identity before committing and commits through the resolved path. Aliases (`./`, `../x/`, symlinked folders) share one lock. Remaining limit, now stated in the code: a program that does not use the helper's lock (an editor, a build) can still slip in between the last check and the rename. Tests: `path_aliases_of_one_file_share_one_compare_and_replace_turn` (8 threads across 4 spellings, 6 rounds, exactly one winner; verified to fail with the lock removed) and `a_write_waits_for_the_folder_lock_whatever_path_it_names`.
4. **P2, macOS env names.** `/usr/bin/env --` and environment names are now restricted to identifiers (`[A-Za-z_][A-Za-z0-9_]*`) on both platforms. Tests: `option_like_environment_names_stay_after_the_end_of_options`, extended `requests_are_validated_before_any_effect`.
5. **P2, drain waits.** `run_collect` supervises exit and pipe completion together (deadline, overflow and cancellation stay live until both are done) and abandons stuck output threads after a short cleanup grace. Sessions use `drain_readers`, which polls the live cancel flag. Tests: `cancelling_after_the_process_exited_but_before_end_of_output_stops_the_run`, `cancelling_after_the_command_exited_but_before_its_output_ended_finishes_the_job` (a process in its own session holds the pipes).
6. **P2, watch readiness.** The helper prints a lone NUL once every baseline is recorded; `start_watch` returns only after it, and reports the helper's error text if it fails to start. Tests: `a_change_made_right_after_the_response_is_never_missed` (no pause), `a_watch_that_cannot_start_says_why_and_gives_its_slot_back`; the startup sleeps were removed from the other watch tests.
7. **P2, watch cost.** See "Deviation" below. Bounded polling: at most 4,096 names per folder, one digest per folder (constant memory), pause grows with look time (0.2 s to 5 s), and at most 16 watches per computer (`busy` beyond that). Tests: `a_huge_folder_is_followed_by_its_own_metadata_at_bounded_cost`, `renames_and_a_folder_created_later_are_reported`, `a_computer_has_a_bounded_number_of_watches`.
8. **P2, exit 255.** The supervisor saves an exit code of 255 in `.exit`; on macOS a 255 from SSH is a guest exit only if the record exists (`control.pl exit`), otherwise the transport error as before. Tests: `exit_255_is_a_guest_exit_only_when_the_supervisor_recorded_it` (pure, with injected lookups), `the_supervisor_records_exit_255_and_a_signal_death_leaves_its_name`.
9. **P2, replay.** An oversized chunk clears the ring and is not kept, so the replay is always a contiguous suffix and `firstRetainedSeq` is one past it. Test: `an_oversized_chunk_clears_the_replay_so_it_stays_a_contiguous_suffix` (small budget, oversized middle and final chunk).
10. **P3, domain checks and cleanup.** `exec_get` checks the job's method (`JobRegistry::method_of`, new) and answers `not_found` for another domain's job; the dispatcher's `operations.job.acknowledge` now calls `forget_finished`. Test: `only_exec_jobs_answer_exec_get_and_acknowledging_drops_the_replay`.
- **Caveat, macOS transfers.** `macos_computers::upload_files` and `prepare_download` accept the job first (`transfer::begin_transfer_job`, now `pub(crate)`), then wait for the computer's turn and probe the alias; a failure there finishes the job with the error (`fail_transfer_job`). The response therefore never waits on the gate. Consequence: those failures now arrive through the job, not the response. Test: `silod/tests/transfers.rs` (own process, global context installed, the operation gate held; both upload and download answer with their job while queued, then fail with the missing-login message through the job). It cannot live in the silod lib tests, which have no installed context.

## Gate

`cargo test --locked --no-fail-fast` from `app/SiloUI` on the merged tip, and `cargo +1.94.0 fmt --all --check` (clean).

- `silo-api` 30, `silo-ui` 71, `silod` lib 182, all silod integration tests (including the new `transfers`), all pass.
- `silo-engine` lib: 2,603 passed, 1 timing failure (`dependencies::tests::version_probe_accepts_the_output_limit...`, load-sensitive, as in the d-guest report); rerun serially: all 31 `dependencies` tests pass. An earlier tip had one engine lib run abort with no named failure; a serial rerun passed (2,562/2,562).
- On the first tip, `silod` lib had 3 failures in `methods::access`/`methods::display`. They fail the same way on the pre-change base (checked by stashing my work) and pass when run filtered; they are parallel-run flakiness, not from this change.
- No registry sqlite fixture was committed (`src-tauri/engine/engine/` is ignored and was removed).

## Deviation: no inotify

The brief asked for inotify/FSEvents "where feasible". I did not ship it. The guest helper is Perl, which has no core inotify or kqueue binding, so it would be raw `syscall()` numbers per architecture, and this machine can run the helper only on macOS: the Linux path could not be exercised, and a wrong event path fails silently (no events), which is worse than polling. What is delivered is bounded polling plus the readiness fix, which closes the correctness gap. A native adapter needs a Linux runner to validate; the contract is unchanged (`start_watch` already returns after arming), so it can replace `watch` in `files.pl` later. Known limits of the bounded poll: a folder over 4,096 entries reports additions and removals but not in-place rewrites; each subscription still runs its own helper (capped at 16 per computer).

## Notes for the next tracks

- A retained `.pid` record (descendants outlived the command) stays until a cancellation, `status` or the group dying removes it; a pid reused as a new group before then could be signalled by a later `kill`. The window is narrow and only exists for runs that leave descendants.
- If the supervisor itself is SIGKILLed (not TERM/INT/HUP), the command's group is no longer in the supervisor's group and survives; cancellation and timeouts go through the pid record and are unaffected.
- Not verified live (no VM): the real `msb exec --stream --no-stdin` round trip, and the guest-side behaviour under the real `agentd`.
