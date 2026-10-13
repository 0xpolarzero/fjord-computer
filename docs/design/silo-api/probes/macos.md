# macOS probe results

Run date: 2026-10-13. Scope: B-1, B-3, B-4, B-5, B-7, B-14, B-19, B-23, B-24 (macOS), and B-30 (macOS) from [80 §4(B)](../80-coverage-and-consistency.md).

## Environment and method

- Host: macOS 26.5, build 25F71.
- Guest image: Silo Dev template manifest says macOS 26.6.2, build 25G83, 64 GiB disk. This is the manifest value; this run did not separately capture guest <code>sw_vers</code>.
- Silo: 0.11.1, commit <code>94d81937904af83faf5839e8b28b24e0e1883c8b</code>.
- MicroSandbox dependencies: commit <code>09df3d4b9d832adaede1fb9a198cfc660bfab8cd</code>, pinned in Silo's <code>src-tauri/Cargo.toml</code> and <code>Cargo.lock</code>.
- Silo implementation read: <code>app/SiloUI/src-tauri/src/macos_computers/engine.rs</code> (VM configuration and view) and <code>guest_access.rs</code> (SSH setup). Relevant spec sources: [05](../05-engine-architecture.md), [20](../20-checkpoints-exports-preparation.md), [30](../30-macos-computers.md), [40](../40-desktop-display-computer-use.md), and [50](../50-access-network-files.md).
- Probe source and compact evidence remain in <code>~/silo-probes/macos/src</code> and <code>~/silo-probes/macos/evidence</code>. The main harness is <code>src/Probe.swift</code>; the helper sources are <code>gui_probe.swift</code>, <code>halfclose_server.c</code>, and <code>halfclose_client.py</code>. The app bundle was ad-hoc signed with <code>com.apple.security.virtualization</code> from <code>src/Entitlements.plist</code>. Its agent plist sets <code>LimitLoadToSessionType=Aqua</code>, <code>ProcessType=Interactive</code>, <code>RunAtLoad=true</code>, and <code>KeepAlive=false</code>.
- The disk and auxiliary storage were cloned from the untouched template with <code>cp -c</code>. VM configuration used 4 CPUs, 8 GiB RAM, 2560×1600 at 220 ppi, a Virtio block disk, NAT with pinned MAC <code>02:8e:d9:31:c5:33</code>, Mac trackpad and keyboard, USB screen pointer, host audio, entropy, and a VirtioFS share for B-5. These device settings match Silo's current configuration in <code>engine.rs</code>; the probe used the dedicated serial VM queue required by B-1. The view remained on AppKit's main thread.
- The agent was registered with <code>SMAppService.agent(...).register()</code>, then unregistered at the end. No host privacy/TCC settings changed. The VM window auto-closed after 20 seconds. No lock, logout, sleep, or reboot occurred.

## Results

| Probe | Verdict | Result |
| --- | --- | --- |
| B-1 | CONFIRMED | Serial-queue VM started and attached to VZVirtualMachineView on host macOS 26.5. |
| B-3 | PARTLY | Aqua/Interactive agent and activation-policy calls worked; Dock/Cmd-Tab visibility and login-window behavior were not directly observed. |
| B-4 | PARTLY | Guest NAT SSH/22 reachable; Screen Sharing/5900 refused by the guest. |
| B-5 | CONFIRMED | VirtioFS mounted and supported host-to-guest and guest-to-host file access; no TCC prompt observed. |
| B-7 | PARTLY | Logical and reported allocated sizes measured; APFS per-file private bytes were not exposed. Cleanup recovered aggregate volume space. |
| B-14 | CONFIRMED | Effective sshd SFTP subsystem, MaxSessions, and OpenSSH versions recorded. |
| B-19 | PARTLY | Listener discovery and SSH forwarding/half-close/teardown worked; Git/LFS availability was inconclusive because the guest's Xcode command-line tools were absent. |
| B-23 | CONFIRMED | SSH command under the console user's GUI bootstrap session saw the active display. |
| B-24 (macOS) | BLOCKED | Guest ScreenCapture TCC denied unattended SSH capture without a prompt; no movie was created or retrieved. |
| B-30 (macOS) | PARTLY | A new process restored the saved state and disk clone, resumed, and reconnected SSH; guest uptime continuity was not established. |

### B-1 — CONFIRMED

The harness creates <code>VZVirtualMachine(configuration:queue:)</code> on <code>com.polarzero.siloprobe.virtual-machine</code>, starts it, then attaches it to a visible <code>VZVirtualMachineView</code>. VM start took 0.441 s.

Raw log excerpt from <code>evidence/agent.log</code>:

> VZ configuration valid save_restore=YES cpu=4 memory_bytes=8589934592 ... NAT_MAC=02:8e:d9:31:c5:33 display=2560x1600@220 audio=host virtiofs=true  
> VM start completed elapsed_s=0.441  
> B1 serial_queue=com.polarzero.siloprobe.virtual-machine attached_to_VZVirtualMachineView=YES view_window_visible=true starting_activation_policy=1

Spec impact: resolves the queue choice in 05 OQ3 for this host version. The VM operations can use a dedicated serial queue while the view remains on AppKit's main thread.

### B-3 — PARTLY

The LaunchAgent started as uid 501 in an Aqua GUI session with <code>ProcessType=Interactive</code>. The accessory-policy app showed its window; setting <code>.regular</code> returned true while it was open. Closing the window set <code>.accessory</code> successfully. The code intentionally left the window open for about 20 seconds. Computer Use could not access the probe app for a visual Dock/Cmd-Tab check, so Dock/Cmd-Tab appearance is INFERRED from the activation-policy transition, not observed. The login-window case was not tested because logging out or switching sessions is prohibited by the probe rules. <code>LimitLoadToSessionType=Aqua</code> implies a GUI-session restriction but does not substitute for that live test.

Raw excerpts:

> launchd_process_type=Interactive plist_session=Aqua; uid=501  
> B3 accessory_window_show=YES setActivationPolicy_regular=true activation_policy_now=0 dock_cmd_tab_expected=YES  
> B3 window_closed=YES setActivationPolicy_accessory=true activation_policy_now=1 dock_cmd_tab_expected=NO  
> SMAppService.unregister status=SMAppServiceStatus(rawValue: 0)

Spec impact: partially settles 05 OQ5 and 30 OQ4. Keep the 95 A-21 regular/accessory rule; retain direct Dock/Cmd-Tab and login-window qualification as open.

### B-4 — PARTLY

From the LaunchAgent, the harness opened IPv4 TCP connections to the guest's NAT address, discovered by matching the pinned MAC in the host DHCP lease file. SSH/22 accepted a connection. Screen Sharing/5900 returned connection refused. No Local Network prompt was recorded in the probe evidence; no host privacy setting was changed. A refused port shows the guest did not accept 5900, not that host Local Network privacy denied it.

Raw excerpts:

> B4 LaunchAgent NAT SSH address=192.168.64.24 port=22 reachable=YES elapsed_s=0.011  
> B4 LaunchAgent NAT ScreenSharing address=192.168.64.24 port=5900 reachable=NO errno=61 Connection refused elapsed_s=1.002

Spec impact: partially settles 05 OQ6 and the macOS NAT access assumptions in 50. Port 22 is reachable from this signed agent on macOS 26.5; guest Screen Sharing availability remains separate and was not confirmed.

### B-5 — CONFIRMED

The guest mounted the read/write VirtioFS share with <code>sudo -n /sbin/mount_virtiofs silo-probe /Volumes/silo-probe</code>. The guest read <code>host-marker.txt</code> and wrote <code>guest-marker.txt</code>; the host observed the guest-created file. No TCC prompt was observed. A later attempt after state restore returned “Resource busy” because the first mount was still present; the initial mount and bidirectional file check succeeded.

Raw excerpt:

> B5 LaunchAgent VirtioFS mount status=0  
> B5 host share guest_marker_exists=true guest_read_status=0

Spec impact: settles the mount/TCC behavior asked in 05 OQ7 for this agent and guest configuration. This is evidence about the probe's added VirtioFS device, not a decision to add a shared-folder API.

### B-7 — PARTLY

Commands used: <code>cp -c</code>, <code>stat -f '%z %b %i'</code>, <code>du -k</code>, and <code>df -k /</code>. The template disk and an immediate APFS clone both reported 68,719,476,736 logical bytes and 55,948,920 512-byte blocks from <code>stat</code>; <code>du</code> reported 27,974,460 KiB for each. The immediate copy changed volume available space by 16 KiB; deleting that measurement clone produced no immediate <code>df</code> change.

At checkpoint time, the template, working clone, and checkpoint disk clone each had 68,719,476,736 logical bytes. The two live disk clones each reported 54,379,272 512-byte blocks and <code>du</code> reported 27,189,636 KiB. The saved state file was 2,885,685,248 logical bytes, 5,664,960 reported 512-byte blocks (2,900,459,520 bytes). The auxiliary clone was 33,579,164 logical bytes and 2,904 reported blocks.

After deleting the probe-owned clone, checkpoint, share, and app bundle, <code>df -k /</code> available space rose from 199,830,384 KiB to 206,629,252 KiB: +6,798,868 KiB (about 6.48 GiB) in aggregate. This is volume-level recovery for all deleted probe files, not a per-file private-size measurement. <code>stat</code>/<code>du</code> counted apparent allocation for shared APFS extents and therefore cannot be summed as unique/private bytes here.

Spec impact: B-7 informs 20 OQ3 that a logical size or <code>du</code>/<code>st_blocks</code> total must not be presented as private/reclaimable storage. A per-file APFS private-byte metric was not established, so keep the exact checkpoint size-field semantics open. Full measurements are in <code>evidence/apfs-clone-measurements.txt</code>.

### B-14 — CONFIRMED

The guest commands were <code>sudo -n /usr/sbin/sshd -T</code> filtered for <code>subsystem</code>/<code>maxsessions</code>, then <code>/usr/bin/ssh -V</code> and <code>sudo -n /usr/sbin/sshd -V</code>.

Raw output:

> maxsessions 10  
> subsystem sftp /usr/libexec/sftp-server  
> OpenSSH_10.3p1, LibreSSL 3.3.6  
> OpenSSH_10.3p1, LibreSSL 3.3.6

Spec impact: supplies the guest-specific facts for 50 Q14 and 70 OQ4. The guest provides stock SFTP and ten SSH sessions; this does not establish the Files roots, which remain open.

### B-19 — PARTLY

The harness attempted <code>/usr/bin/git --version</code>, <code>/usr/bin/git lfs version</code>, <code>/usr/bin/which git-lfs</code>, and <code>/usr/bin/git lfs env</code>. The guest returned the Xcode command-line-tools notice (“No developer tools were found, requesting install.”) and status 1. Git and Git LFS availability are therefore inconclusive; this does not prove either is absent. Do not use this as evidence for a workspace root.

Listener discovery used <code>lsof -nP -iTCP -sTCP:LISTEN</code> and <code>netstat -anv -p tcp | grep LISTEN</code>; both worked without <code>/proc</code> and showed SSH on port 22. For the tunnel check, a compiled arm64 loopback service listened on guest port 18080. Host OpenSSH used <code>-N -L 127.0.0.1:19080:127.0.0.1:18080</code> to the guest's port 22. The host client sent 16 bytes, half-closed its write side, received <code>EOF:16</code>, then the test closed the tunnel and listener.

Raw excerpt from <code>evidence/corrected-probes.log</code>:

> ssh_L_forward_ready=1  
> sent=16 shutdown_write=0 reply=EOF:16  
> tunnel_teardown_listener_closed=YES  
> guest_server_stopped=YES

The first Python-based helper did not run because the guest template has no <code>/usr/bin/python3</code>; the corrected C helper was compiled on the host and copied into the guest. The result above is from that corrected run.

Spec impact: listener discovery and <code>ssh -L</code> half-close/teardown evidence settles the mechanism tests in 50 Q10–Q11 for this guest. 50 Q9 remains open for Git/LFS and workspace-root discovery.

### B-23 — CONFIRMED

The host compiled <code>src/gui_probe.swift</code>, copied the helper to <code>/tmp/silo-probe-gui</code>, then ran it over SSH using <code>launchctl asuser</code> and <code>sudo -u silo -H</code>. The command found the console user's GUI bootstrap domain and an active display.

Raw excerpt:

> console_uid=501  
> gui/501 = { type = login; handle = 100002; ... }  
> screen_count=1  
> main_screen=Optional((0.0, 0.0, 1280.0, 800.0))  
> display_id=1 active=1 width=1280 height=800

Spec impact: settles the session-access mechanism in 30 OQ13. An SSH command can enter the console user's GUI context with <code>launchctl asuser</code> and see its active screen.

### B-24 (macOS) — BLOCKED

With the host VM view closed, the guest ran <code>uid=$(/usr/bin/id -u silo); sudo -n /bin/launchctl asuser $uid /usr/bin/sudo -u silo -H /usr/sbin/screencapture -V 4 /tmp/silo-proof.mov 2>&1; echo screencapture_status=$?</code>. It returned status 1; no file existed for either SCP or SSH retrieval. Guest TCC logs identified <code>kTCCServiceScreenCapture</code>, said the service “does not allow prompting; returning denied,” and logged the generic screencapture error “The user declined TCCs.” No user decline was observed; the TCC service denied without presenting a prompt. The attempt made through the SSH GUI bootstrap context also failed. A malformed follow-up command caused by local shell expansion is excluded from this conclusion; the two harness attempts and their TCC log entries are the valid evidence.

Spec impact: 40 OQ10 and 95 A-9 need to state that built-in guest recording requires Screen Capture authorization for the capturing app/session. This SSH-launched CLI could not request that permission, so no recording or retrieval path was qualified. No host privacy setting was changed.

### B-30 (macOS) — PARTLY

The first LaunchAgent paused the VM, saved state, then created APFS clones of disk and auxiliary storage. It was killed with SIGKILL at 16:54:47 UTC. Re-registration returned <code>SMAppServiceStatus(rawValue: 1)</code>, but the job was not running, so I unregistered the agent and launched the replacement directly from the signed app bundle at 16:55:39 UTC. That new process built the same VZ configuration from the saved state and disk/auxiliary clones, restored and resumed the VM, and reconnected SSH. The replacement process was a different PID from the killed process.

Timings from <code>evidence/agent.log</code>:

> pause 0.014 s  
> saveMachineStateTo 2.390 s  
> APFS disk and auxiliary clones 0.241 s  
> restoreMachineStateFrom 7.695 s  
> resume 0.550 s  
> SSH readiness after resume 3.468 s

Before save, <code>kern.boottime</code> was Tue Oct 13 09:48:34 2026 and <code>uptime</code> reported “up 2 mins.” After restore, <code>kern.boottime</code> was Tue Oct 13 09:54:16 2026 and <code>uptime</code> again reported “up 2 mins”; the SSH probe printed <code>B30_SSH_RECONNECTED</code> with status 0. Because the boot-time value changed and the human-readable uptime was rounded identically, this run does not prove that guest uptime continued without reset.

Spec impact: this confirms one cross-process save/restore/resume/SSH-reconnect path relevant to 05 §6 and OQ24 under 95 A-6. It does not qualify the full update transaction, failure recovery, journal replay, or continuous uptime. The VM was stopped after checks and the LaunchAgent remained unregistered.

## Cleanup

The probe VM stopped successfully. <code>launchctl</code> reported no service for <code>com.polarzero.siloprobe.agent</code>; the probe process was absent. The clone, checkpoint (including the saved-state file), share fixture, and signed app bundle were deleted. Source and evidence remain at <code>~/silo-probes/macos</code> (592 KiB by <code>du -sk</code>). The final check showed 196 GiB available with <code>df -g /</code>.

## Follow-up

Track: <code>macos-followup</code>. The harness reuses the first run's <code>~/silo-probes/macos/src/Probe.swift</code> and the same 25G83 template through an APFS clone. Host: macOS 26.5 build 25F71. Guest: macOS 26.6.2 build 25G83. Guest SIP was disabled. The clone and all TCC changes stayed inside the disposable guest; no host privacy settings or template files were changed. Source and raw evidence remain under <code>~/silo-probes/macos-followup</code>.

| Probe | Follow-up verdict |
|---|---|
| B-3 | CONFIRMED: the app changed from regular/Foreground with the VM window to accessory/UIElement after close. |
| B-4 | CONFIRMED once: the Silo Screen Sharing setup loaded <code>screensharingd</code> and the LaunchAgent reached port 5900. A later immediate check raced and got no route. |
| B-7 | MEASURED: initial APFS clone cost 88 KiB; the 1 GiB guest write consumed about 1.04 GiB; checkpoint state consumed 2,755,304 KiB and another disk/auxiliary clone cost 52 KiB. |
| B-19 | SETTLED: no working Git or Git LFS is installed; a public HTTPS clone fails locally because the Xcode command-line tools are absent. |
| B-24 | CONFIRMED: guest ScreenCaptureKit recorded and retrieved a 10.23 s, 1280×800 movie, 1,056,640 bytes, with no host viewer window open. |
| B-30 | CONFIRMED: boot time and the same guest process survived a save, host-process SIGKILL, and restore into a new process; guest uptime advanced 2 seconds while host time advanced about 50 seconds. |

### B-24 (macOS) — CONFIRMED

The guest setup used the copied Silo helper from <code>/Users/polarzero/code/projects/microsandbox-workspaces/app/SiloUI/src-tauri/guest/macos/silo-computer-use.zsh</code> to derive a <code>csreq</code> and grant <code>kTCCServiceScreenCapture</code> to the recorder. It also wrote the matching <code>ScreenCaptureApprovals.plist</code> ledger. Guest <code>csrutil status</code> reported SIP disabled.

The guest's <code>screencapture -v -V10</code> did not create a file. The corrected SSH-launched attempt was attributed by TCC to <code>com.apple.sshd-keygen-wrapper</code>, and the direct Apple <code>screencapture</code> LaunchAgent attempt still returned exit 1 with no file. A ScreenCaptureKit app launched from SSH first returned <code>SCStreamError</code> -3801. Apple's documentation defines <code>userDeclined</code> as the app lacking Screen Recording permission; the guest TCC log showed the SSH responsibility and denial rather than a user clicking a prompt ([Apple ScreenCaptureKit error constants](https://developer.apple.com/documentation/screencapturekit/error-constants)).

The successful fallback ran the recorder as its own guest Aqua LaunchAgent, with its own Silo-style TCC row. The guest TCC log then showed <code>accessing=com.polarzero.siloprobe.recorder</code>, <code>subject=com.polarzero.siloprobe.recorder</code>, and <code>authValue=2 authReason=4</code>. Recorder output reported a 1280×800 display and a 10.0-second capture. After finalization, guest <code>stat</code> and host <code>ffprobe</code> reported a 1,056,640-byte H.264 movie, 1280×800, 10.233333 seconds. The recorder API's <code>recordedFileSize</code> field printed 687,109 bytes; the finalized on-disk size is the artifact size reported above. SHA-256: <code>ceeb2735dc56ac9ecedbf9ba022ec5a1f0766b136081b990e5e3d642db6d252b</code>. The retrieved artifact is <code>~/silo-probes/macos-followup/evidence/guest-screen.mov</code>.

Spec impact: this closes 40 OQ10 and supplies the guest-side path for 95 A-9. The recorder must run in the guest under the identity whose TCC row was granted; an SSH-launched CLI did not qualify.

### B-4 — CONFIRMED ON ONE BOOT

The copied Silo guest setup granted the same ScreenCapture, Accessibility, and PostEvent rows for <code>com.apple.screensharing.agent</code> and <code>com.apple.screensharing.daemon</code>, then ran Silo's <code>launchctl enable system/com.apple.screensharing</code> and conditional <code>bootstrap system</code> sequence. At 17:19:06Z, the host LaunchAgent's TCP probe reported <code>192.168.64.26:5900 reachable=YES</code> in 0.001 s. Guest <code>launchctl print system/com.apple.screensharing</code> showed state <code>running</code> and the stock <code>screensharingd</code> executable.

A later restart's probe ran in the same second as the TCC daemon restart; it saw no route and the job was not running. The cause of that failure is unresolved, and reachability was not repeatable on every boot. The successful run closes the requested enable-and-reach sequence for 05 OQ6 once; repeatability across guest restarts remains open.

### B-30 — CONFIRMED FOR SAVED GUEST STATE

Before save, the guest reported <code>kern.boottime={sec=1791912171,usec=174161}</code> (Tue Oct 13 10:22:51 2026), uptime 42 seconds, and survivor PID 920 running <code>/bin/sleep 3600</code>. The host paused in 0.007 s, saved with <code>saveMachineStateTo</code> in 2.279 s, and cloned disk plus auxiliary storage in 0.241 s. The host sent SIGKILL to LaunchAgent PID 5886 at 17:24:14Z; it was gone by 17:24:15Z. LaunchAgent PID 6367 started at 17:24:15Z; restore took 6.708 s, resume 0.484 s, and SSH readiness 1.184 s.

After restore, <code>kern.boottime</code> was identical, uptime was 44 seconds, and PID 920 was still alive with the original start time. SSH reconnected successfully. Host time advanced about 50 seconds from the pre-save sample while guest uptime advanced only 2 seconds. This establishes saved clock/process continuity, while showing that time spent in the saved/stopped interval is not added to guest uptime. It closes the narrow process restore question in 05 §6/OQ24 and 95 A-6; it does not prove a full update transaction or crash recovery.

### B-7 — MEASURED AT VOLUME LEVEL

The host sampled <code>df -k /</code> around each operation and sampled <code>du -sk</code> plus <code>stat</code> for the template, clone, state file, and checkpoint. The initial <code>cp -c</code> template disk/auxiliary clone reduced available space by 88 KiB. A synced 1,073,741,824-byte guest random write consumed 1,090,856 KiB in the instrumented free-space pair (about 1.04 GiB). Separately printed <code>df</code> samples were 201,407,848 and 200,316,912 KiB, an 80 KiB sampling difference from the instrumented pair during host-volume activity.

Saving the checkpoint state consumed 2,755,304 KiB of volume space. The state file was 2,818,576,384 logical bytes, 2,824,982,528 allocated bytes by <code>stat</code>, and 2,758,772 KiB by <code>du</code>. Creating a second <code>cp -c</code> disk/auxiliary clone consumed 52 KiB. <code>du</code> reported 28,181,136 KiB for the checkpoint disk and 30,941,360 KiB for the checkpoint tree. These per-path allocation totals are not exclusive APFS extent counts and cannot be summed as private bytes; the free-space deltas are the physical-cost measurements for each operation. See <code>evidence/b7-apfs-followup.txt</code>.

Spec impact: this supplies operation-level costs for 20 OQ3 but leaves per-file APFS private-byte reporting open. A logical disk size, <code>du</code>, or <code>st_blocks</code> total is not a private/reclaimable-size metric.

### B-19 — SETTLED FOR TEMPLATE TOOLING

The guest has <code>/usr/bin/git</code> as Apple's developer-tools shim, but <code>git --version</code> exits 1 with “No developer tools were found.” <code>xcode-select -p</code> has no active developer directory. No executable Git was found in Homebrew, <code>/usr/local</code>, CommandLineTools, or Xcode paths. No <code>git-lfs</code> executable was found in the matching locations, so there is no Git or Git LFS version to report.

With prompts and global/system Git configuration disabled, <code>/usr/bin/git clone --depth=1 https://github.com/octocat/Hello-World.git</code> also exits 1 on the local developer-tools shim before Git can perform HTTPS transport. No credentials were supplied. This establishes that a clone cannot run in the template as provisioned; it does not test GitHub network reachability after installing Git. This closes the tooling part of 50 Q9–Q11, not workspace-root discovery.

### B-3 — CONFIRMED FOR APP CLASSIFICATION

With the host VM window open, the SiloProbe app switched to <code>NSApplication.ActivationPolicy.regular</code> (raw value 0). A separate observer read <code>NSRunningApplication.activationPolicy=0</code> and <code>lsappinfo</code> returned <code>ApplicationType="Foreground"</code>. After closing the VM window, the app switched to accessory (raw value 1); the separate observer read <code>activationPolicy=1</code> and <code>ApplicationType="UIElement"</code>. These are the OS classifications used for Dock and Cmd-Tab eligibility. This closes the policy/type question in 05 OQ5 and 30 OQ4; no visual screenshot of the Dock or Cmd-Tab switcher was retained.

### Follow-up cleanup

The follow-up VM stopped after the restore checks. The host LaunchAgent was booted out and its process exited. The 64 GiB APFS working clone, checkpoint/state file, share fixture, and built app bundles were deleted; no probe process remains. Source and evidence remain at <code>~/silo-probes/macos-followup</code> (1,228 KiB by <code>du -sk</code>), including the retrieved 1,056,640-byte movie. Post-cleanup <code>df -g /</code> checks showed 191–192 GiB available. The original template and first-run <code>~/silo-probes/macos</code> artifacts remain untouched.
