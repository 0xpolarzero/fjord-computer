Appended the follow-up results to [macos.md](/Users/polarzero/code/projects/lookout/docs/design/silo-api/probes/macos.md:159). The VM, clone, checkpoint, and built apps are cleaned up; 191 GiB is available, and the retrieved [guest recording](/Users/polarzero/silo-probes/macos-followup/evidence/guest-screen.mov) is retained.

- **B-3 — CONFIRMED:** Open window reported regular/Foreground; closed window reported accessory/UIElement. No visual Dock or Cmd-Tab screenshot was retained.
- **B-4 — CONFIRMED ON ONE BOOT:** The LaunchAgent reached port 5900 after Silo’s setup; a later immediate check got no route, so repeatability remains open.
- **B-7 — MEASURED:** Initial clone cost 88 KiB; the 1 GiB guest write used about 1.04 GiB; checkpoint state used 2,755,304 KiB and its disk/auxiliary clone 52 KiB. Per-file private extents remain unmeasured.
- **B-19 — SETTLED:** No usable Git or Git LFS is installed; a public HTTPS clone failed locally because Xcode command-line tools are absent.
- **B-24 — CONFIRMED:** ScreenCaptureKit produced a 10.23-second, 1280×800 movie of 1,056,640 bytes with no viewer window open; Apple documents `userDeclined` as missing Screen Recording permission ([Apple docs](https://developer.apple.com/documentation/screencapturekit/error-constants)).
- **B-30 — CONFIRMED:** `kern.boottime` and the same guest process survived save, host-process kill, and restore; uptime advanced 42 to 44 seconds while host time advanced about 50 seconds.

Review the full method and evidence in the [Follow-up section](/Users/polarzero/code/projects/lookout/docs/design/silo-api/probes/macos.md:159).