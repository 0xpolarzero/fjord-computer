# viewers-streamer

Silo worktree `~/silo-work/viewers-streamer`, branch `engine/viewers-streamer` from Silo `main@6ab2c975`. No push. No VM, app or network was used; nothing was live-validated.

Goal: let two clients view the same Linux computer's desktop independently, closing the guest half of B-21 / A-28 (the engine half is on `engine/d-display`).

## Decision

A guest-side patch of the pinned Selkies 2.0.0 `websockets_mode.py`, source-hash guarded like the two existing patches. No per-client port, path or process. Evidence is the pinned source (hash-checked against the existing display patch); the note with line references is `docs/research/selkies-multiclient-admission-2026-10-14.md` in the Silo repo.

What 2.0.0 does with a second page:
- **Eviction.** A page whose first `SETTINGS` names `primary` while a live page holds it sends the holder `KILL ...` and closes it with `Superseded by new client`. The web client reads "superseded" as final and stops reconnecting. This is the B-18 termination.
- **Debounce.** Separately, `RECONNECT_DEBOUNCE_MS = 500` is applied per source IP. Every Silo viewer reaches the guest from its own loopback, so a second viewer opening within 500 ms is refused with code 4029 and only retries after the client's 5 s reload timer. The harness reproduced the refusal (152 ms). This is a second blocker the engine-only fix would have hit.
- **Documented multi-page mechanisms are read-only.** Shared viewers (`?role=viewer`, `#shared`) and secure-mode viewer tokens admit any number of pages, each with its own bounded relay, but refuse keyboard, mouse, clipboard writes, resize and audio control, and the page blocks audio/video pipeline control in shared mode. Secure mode allows one `mk_control` writer at a time.

Options considered:

| Option | Verdict |
|---|---|
| Shared viewer for every later client | Rejected: read-only, and the engine does not know which client is first. |
| Secure mode with a token table | Rejected as primary: one writer at a time, token table to keep in step with engine connections. |
| One Selkies process per client (port or path) | Rejected: N encoders, clipboard monitors, cursor captures and RandR writers on one X screen. |
| Patch admission | Chosen. Reuses upstream's viewer fan-out (per-client bounded `_VideoRelay`, keyframe throttle, per-socket pause, owner-only backpressure), leaves the web client untouched (no minified JS patched) and adds no routing. |

## What the patch does (`guest/patch-selkies-multiclient.py`, applied after the display patch)

| Case | Behavior |
|---|---|
| First page | Holds the primary display as before. |
| Later page asks for a held display | It becomes a peer (role `viewer` plus a peer mark), so every upstream viewer rule applies. It additionally may send keyboard, mouse, clipboard, `START_AUDIO`/`STOP_AUDIO`, and size (`r,`) and density (`s,`) requests addressed to the one primary display. Encoder, fps, bitrate and `cmd` messages from a peer are dropped quietly. The screen is shared: requests run through the existing serialized `reconfigure_displays` and the last accepted one wins; pages adapt with the web client's existing "diverged" handling. The engine's "Reset screen" therefore works from any viewer. |
| Holder leaves, or a reload overlaps its predecessor | The oldest peer takes the display at once: no restart, fresh acknowledgement state, role controller; its handler picks up the display id on its next message. With no peer, the old 3 s grace teardown applies. |
| Audio | Per page. `STOP_AUDIO` removes only that page from the audio fan-out and the `AUDIO_STARTED/STOPPED` replies; the capture stops with its last listener. A lone page behaves as before. |
| `START_VIDEO` from a peer | Gets `VIDEO_STARTED` (a controller-mode page expects it; a shared page ignores it). |
| Debounce | Set to 0. |
| Secure mode | Admission and handover are skipped (Silo does not use it). |

## Commits (branch `engine/viewers-streamer`)

| Hash | Message |
|---|---|
| `d94fb3a3` | `feat(guest): let a second page join a held Selkies display` |
| `742bad1e` | `feat(desktop): install the multi-client patch as desktop recipe 5` |
| `56bb0ca5` | `docs(desktop): describe independent viewers and recipe 5` |

Files (Silo `app/SiloUI/`):
- New `src-tauri/guest/patch-selkies-multiclient.py`.
- `patch-selkies-display-scaling.py` gains a `later` list so it accepts the multi-client module as already patched. It runs at every repair and image check, so this is required.
- `setup-desktop.sh` adds the patch to `install_streamer`, `provision_image_desktop`, `image_desktop_problem` and the existing-install refresh path, and pins the lock to recipe 5.
- `desktop-streamer-lock.json`: `recipeVersion` 5. `desktop-service.py`: `STREAMER_RECIPE_VERSIONS` 1 to 5, current 5.
- `engine/src/desktop.rs`: bundles the patch as `SILO_SELKIES_MULTICLIENT_PATCH_SOURCE`.
- Tests: new `scripts/test_selkies_multiclient_patch.py`; changes in `test_selkies_display_patch.py`, `test_desktop_recipe.py`, `test_desktop_service.py`.
- Docs: `docs/SiloUI-DESKTOP.md` (new section "Several viewers of one computer (recipe 5)"), `docs/README.md`, the research note, and the changeset `.changeset/desktop-several-viewers.md`.

## Recipe mechanism

`recipeVersion` 4 to 5. Existing computers on a v4 receipt get `updateAvailable: true` from the helper and from the host's receipt check in `desktop.rs` (no code change needed there), so the viewer shows "Update desktop" (`setup-desktop.sh update-streamer`, desktop stopped, needs network for the pinned `.deb`). New computers and the image-provision path get recipe 5 directly. **No guest image rebuild is needed:** the v4 image carries the unmodified upstream package and every patch runs inside the computer. If a rebuild is ever wanted, the command is unchanged (`node app/SiloUI/scripts/build-guest-image.mjs arm64` and `amd64`, see `docs/SiloUI-GUEST-IMAGES.md`); I did not run it.

## Tests and gate

- `python3 -I scripts/test_selkies_multiclient_patch.py`: 30 tests, OK. Synthetic guards; the pinned hash chain pristine, display, multi-client with compilation; the module accepting both patches in order and re-runs; and 20 behavior tests that import the patched `websockets_mode.py` (stubbing only `prometheus_client`, `watchdog`, the sound server, input handler and capture start) and drive the **real patched `ws_handler`** with fake sockets: second and third page admitted, holder not killed, simultaneous opens accepted, peer input gating, alternating resizes from both pages through the real `_handle_resize`, handover to the oldest peer, reload overlap, takeover of a dead holder, lone-page teardown, per-page audio (stop, last listener, start, chunk fan-out, cleanup), secure mode. Mutation checks (no demotion, no handover, global audio, debounce kept, no peer input) each fail the expected tests. Needs the Selkies 2.0.0 checkout the sibling patch tests use plus aiohttp, aiofiles, msgpack, Pillow and psutil; the handler class skips without them.
- Other Python suites: `test_selkies_display_patch.py` 16 OK, `test_selkies_client_patch.py` 4 OK, `test_desktop_service.py` 83 OK, `test_desktop_recipe.py` 23 OK (about 100 s), `test_guest_publication.py` 12 OK, `node --test scripts/build-guest-image.test.mjs scripts/guest-image-lock.test.mjs` pass.
- Rust: `cargo +1.94.0 test -p silo-engine --lib --locked desktop` 145 passed, 4 ignored (the existing ignored ones), including the new `the_installer_script_fits_in_one_guest_argument`. `cargo +1.94.0 fmt --all --check` clean. I did not run the whole workspace suite; the Rust change is one `include_str!` entry and two tests.
- Run from `app/SiloUI` with `CARGO_TARGET_DIR=~/silo-work/viewers-streamer/target CARGO_BUILD_JOBS=3`. Note: the shell's `python3` alias (Python.framework 3.12) has the dependencies; `/opt/homebrew/bin/python3` does not.

## Deviations and decisions

- **Peers may resize.** The P3-viewers text asks to serialize accepted screen changes and keep both viewers alive after alternating or simultaneous resize. Allowing it keeps "Reset screen" working from any viewer and matches today's single-viewer behavior (a connecting viewer sizes the screen to its window). A peer opening therefore resizes the guest to its window, like a first viewer does. If live testing shows thrash, drop `"r,", "s,"` from `SILO_PEER_EXTRA_PREFIXES` in the patch (and its hash): the screen then follows the holder alone.
- **Per-page audio is not a Selkies feature;** it is an addition (the engine's mute/`setAudioActive` would otherwise stop everyone's sound).
- **Debounce disabled** (`RECONNECT_DEBOUNCE_MS = 0`), an upstream protection against reconnect floods, justified because every page reaches the guest from its loopback.
- **Install-script size.** The staged install script is one `sh -c` argument and Linux caps a single argument at 131072 bytes. It was 107 KB; it is now 123,495 bytes, 7.5 KB under the cap. Any further growth of the bundled guest files needs a different transport (stdin, or `base64`+`tar`). The unit test fails at 126,976.
- The P3-viewers plan named `scripts/test_selkies_multiclient_patch.py` and `guest/setup-desktop.sh` changes; both done. It also listed a "one-command harness against the checksum-pinned payload with two real Selkies clients"; that needs a guest and was not possible here (see below).
- `desktop.rs` hunks are far from the `engine/d-display` hunks (`git merge-tree` of the two is clean).

## Engine contract (registry on `engine/d-display`)

No per-client port, path, header or cookie is needed. Every engine entry keeps connecting to guest `127.0.0.1:6901` with the same Basic credentials, on its own tunnel and its own `/api/websockets` connection.

1. **Capability gate.** Independent viewers exist only on a computer whose `desktop.status` is `backend == "selkies"`, `updateRequired == false` and `updateAvailable == false` (recipe 5). On a recipe 1 to 4 computer a second viewer still evicts the first and cannot reconnect. Recommended: `display.viewer.open` for a second concurrent entry on such a computer should refuse with a message such as "Update the desktop to view it from two places." rather than create the entry. D-display's registry does not check this today. The guest status carries no explicit recipe field; the two update flags are enough.
2. **Open order.** The first page to send `SETTINGS` for the primary display holds it and keeps encoder control; later pages are peers. The engine does not choose roles and needs no ordering, and concurrent opens are accepted.
3. **Page-level operations keep their meaning per connection.** `clipboard.read/write`, shortcuts, `display.viewer.audio.set` and sound check act on that page; audio mute and `setAudioActive(false)` no longer stop other viewers. `display.viewer.screen.reset` works from any connection and resizes the shared screen for all (the next window resize of that page hands the size back, as today).
4. **Acknowledgement caveat.** The bridge's `resetScreen`/`sendFrames` acknowledgement means the page sent the frames, not that the guest applied them. For a peer on a recipe 4 computer that is irrelevant (the computer is gated by item 1).
5. **Reconnect.** A page whose socket closes reloads after about 5 s; if it was the holder and a peer exists, the peer already owns the display, and the reloaded page joins as a peer.

## What the next tracks need to know

- **Live qualification is still owed (B-21 and B-18).** The patch and tests prove the server logic against the real 2.0.0 handler; they do not prove real H.264 frames to two WebKit pages, concurrent resize rendering, clipboard round trips or audio playback. Run on a recipe 5 computer: open two viewers; close each in turn and confirm the survivor keeps rendering and typing; alternate window resizes and "Reset screen" from each; mute and unmute from each; open a third; close the holder and confirm the next page can resize and change settings; engine restart; Keep-running quit. Do not advertise independent viewers until this passes.
- **Assumptions to watch live:** a controller-mode page demoted to peer renders without ever receiving `VIDEO_STARTED` at connect (its default is active); it ignores having its `SETTINGS` and acknowledgements dropped; a peer joining triggers a `PIPELINE_RESETTING` and an IDR for the whole stream (a slow peer's skip-ahead can also request IDRs for everyone: upstream viewer behavior).
- **Throughput.** Sixteen engine entries mean sixteen relays on one encoder; measure CPU and memory with three to four clients before raising expectations.
- **Held keys.** A peer that leaves while holding a key is not force-released by the departure rule (it does not hold input authority in Selkies' sense); the input handler's heartbeat sweep heals it.
- **Licence.** Selkies is MPL-2.0. The patch is source, applied in the computer, and the image still redistributes the unmodified package; no notice change was needed, but the owner may want the patch listed in `THIRD-PARTY-NOTICES.md` next to the other modifications.
- The report files in the Lookout repo's `docs/design/silo-api/reports/` are untracked; I did not commit this one.
