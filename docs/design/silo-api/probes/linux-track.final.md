Saved the full evidence and limitations in [linux.md](/Users/polarzero/code/projects/lookout/docs/design/silo-api/probes/linux.md).

- B-11 — **CONFIRMED** — Claude Desktop connected through Silo’s SSH alias and ProxyCommand.
- B-12 — **CONFIRMED** — Claude and its command survived a ProxyCommand interruption; Desktop reconnected.
- B-13 — **CONFIRMED** — `/home/silo` is executable overlay storage with about 98 GiB free.
- B-15 — **PARTLY** — The user plugin loaded and SessionStart ran in direct guest CLI; Desktop SSH hook callbacks remain unverified.
- B-16 — **PARTLY** — Found both transcripts and session metadata; live transcript freshness and task directory remain unverified.
- B-17 — **PARTLY** — The placeholder and CA path were present, but substitution at the Anthropic destination was not proven.
- B-18 — **PARTLY** — WebKit checks passed against a local fixture; the live Silo proxy and native paste prompt were not tested.
- B-20 (Linux) — **CONFIRMED** — Inotify p95 was 0.321 ms versus 32.291 ms for 30 ms polling.
- B-21 — **REFUTED** — Silo reuses one viewer for a second attach, so it cannot provide independent same-computer clients.
- B-24 (Linux) — **CONFIRMED** — Guest ffmpeg captured display `:1.0` to a 1440×900 JPEG.
- B-32 — **PARTLY** — Overflow and timeout behavior were reproduced; proposed numeric limits are inferred, not current `run_capped` defaults.

`e2e-relay` is stopped and its startup memory is restored to 32 GiB. The original memory ceiling was not separately captured; the restored 48 GiB ceiling matches Silo’s new-computer default. Host configs were restored and the synthetic secret was removed.