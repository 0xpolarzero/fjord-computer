# 80 · Coverage and consistency across sections 05–70

The current spec covers every registered command, emitted backend event, bridge entry and executable mode: **MISSING 0; CONFLICT 0** (§1). Its **146 canonical methods comprise 3 EXISTS + 10 EXISTS (renamed) + 121 EXTENDED + 12 NEW** (§3). All **37 owner decisions and the latest amendments are applied, with 0 open owner decisions** ([95](95-decisions.md); §4 A). Remaining implementation work comprises **33 probes and 9 research items** (§4 B/C).

**Sources and scope.** Silo is `/Users/polarzero/code/projects/microsandbox-workspaces` at `94d81937904af83faf5839e8b28b24e0e1883c8b`. Rust paths `src-tauri/src/…` and UI paths `src/…` below are relative to `app/SiloUI/`; `docs/…` is relative to Silo's root. Spec numbers refer to the files in this directory and their named sections. The binding requirements are [00 §The rules: zero guesses](00-brief.md#the-rules-zero-guesses). This audit uses current 05–70, [05's event catalogue](05-engine-architecture.md#event-catalogue) and [05's job contract](05-engine-architecture.md#job-contract); it replaces the old audit's proposals with those sections' present contracts.

**Latest amendments applied:** [95 §3](95-decisions.md#3-amendments-owner-2026-10-13-later) removes all old-name aliases, legacy API methods and compatibility code paths. Current Tauri/bridge names in the source audit below are historical evidence mapped to canonical methods, not retained protocol aliases. Silo's Tauri UI changes with the engine. The only allowed conversion runs at launch through existing `runtime_migration` (20 migration.*). Job outcomes persist until client acknowledgement, and macOS work waits with Cancel instead of contention refusal (95 §3; 05 #job-contract; 10 §6).

**Host scope, applying 95 §3 over the original brief and A-23:** hosts/controllers are Macs only. Both Linux and macOS computer kinds remain. Linux service, Debian/AppImage updater, headless Linux setup, AppImage guest helper and Linux package-update guard are retired source entries, not current API behavior (95 §3 Linux hosts dropped; 05/30/40/50/60 host scopes). Silo Linux packages stop receiving engine updates.

## 1. Ground truth and coverage

### 1.1 Extraction and counting rules

| Ground-truth set | Source and check | Count |
| --- | --- | ---: |
| Registered commands | Every entry in `generate_handler!`, `src-tauri/src/main.rs:130-290`; one row per registration below, preserving argument fan-out | 159 |
| Backend events | All non-test `.emit`/`.emit_to` sites under `src-tauri/src/`, resolving module constants to emitted names; all 78 sites are cited in §1.3 | 24 names |
| Bridge entries | Every `METHODS` entry, retaining its current access class, `src-tauri/src/remote.rs:236-272` | 35 |
| Executable modes | Three helper branches before the builder and the default application path, `src-tauri/src/main.rs:96-113` | 4 |
| Startup guard | Linux package-update early exit before mode dispatch, `src-tauri/src/main.rs:83-90`; counted separately, not as another executable mode | 1 |

**API** means a canonical method or catalogue event. **ALIAS** is a reserved historical audit classification; there are no retained API aliases after 95 §3. **UI-only** includes client launchers, dialogs, notifications to the client's OS and window chrome. **STARTUP** means an engine duty without a request method. **RETIRED** is the advertised but unserved `repository.push` entry, not a live feature: `remote_access.rs:124-125`, `:180`; 50 §Legacy `repository.push`, 60 §8. **MISSING** means no explicit disposition; **CONFLICT** means incompatible current canonical mappings, not an explicitly pending option in Open questions (05 §10; sections' coverage tables).

| Set | Total | API | ALIAS | UI-only | STARTUP / transport | RETIRED | MISSING | CONFLICT |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Commands (§1.2) | 159 | 123 | 0 | 32 | 4 | 0 | **0** | **0** |
| Emitted event names (§1.3) | 24 | 15 | 0 | 9 | 0 | 0 | **0** | **0** |
| Bridge entries (§1.4) | 35 | 34 | 0 | 0 | 0 | 1 | **0** | **0** |
| Executable modes (§1.5) | 4 | 0 | 0 | 0 | 3 | 1 | **0** | **0** |
| Startup guard (§1.5) | 1 | 0 | 0 | 0 | 0 | 1 | **0** | **0** |
| **All audited entries** | **223** | | | | | | **0** | **0** |

The columns partition each set; a UI-only command may have a separately mapped engine side effect, recorded below. Method and emitted-event counts differ from catalogue and API counts because several registrations share a method, broad state hints split by emitter, and the spec adds methods/events (05 §4.2 D/E; §3).

### 1.2 Every registered command

Registration sources are exact lines of `main.rs`. The linked coverage section supplies the implementation citation and canonical mapping; method ownership is the index in §3. Action/configuration dispatchers retain all their current branches (10 §13; 30 §11).

| # | Registered command | Registration | Current canonical mapping / disposition | Coverage section | Status |
| --- | --- | --- | --- | --- | --- |
| 1 | `desktop::read_desktop_state` | `src-tauri/src/main.rs:131` | `desktop.status` | [40 Coverage table](40-desktop-display-computer-use.md) | API |
| 2 | `desktop::desktop_action` | `src-tauri/src/main.rs:132` | `desktop.action` | [40 Coverage table](40-desktop-display-computer-use.md) | API |
| 3 | `desktop::set_computer_use_approval` | `src-tauri/src/main.rs:133` | `computerUse.approval` | [40 Coverage table](40-desktop-display-computer-use.md) | API |
| 4 | `chatgpt_app::chatgpt_app_status` | `src-tauri/src/main.rs:134` | `preparation.chatgpt.status` | [20 §5 Coverage](20-checkpoints-exports-preparation.md) | API |
| 5 | `chatgpt_app::chatgpt_app_retry` | `src-tauri/src/main.rs:135` | `preparation.chatgpt.retry` | [20 §5 Coverage](20-checkpoints-exports-preparation.md) | API |
| 6 | `preparation::read_preparation_status` | `src-tauri/src/main.rs:136` | `preparation.status` | [20 §5 Coverage](20-checkpoints-exports-preparation.md) | API |
| 7 | `preparation::retry_preparation` | `src-tauri/src/main.rs:137` | `preparation.retry` | [20 §5 Coverage](20-checkpoints-exports-preparation.md) | API |
| 8 | `desktop_viewer::open_desktop` | `src-tauri/src/main.rs:138` | `display.viewer.open` (remote identity check, name) | [40 Coverage table](40-desktop-display-computer-use.md) | API |
| 9 | `desktop_viewer::desktop_viewer_attach` | `src-tauri/src/main.rs:139` | `display.viewer.open` (connect: tunnel, proxy, registry) | [40 Coverage table](40-desktop-display-computer-use.md) | API |
| 10 | `desktop_viewer::desktop_viewer_detach` | `src-tauri/src/main.rs:140` | `display.viewer.close` | [40 Coverage table](40-desktop-display-computer-use.md) | API |
| 11 | `desktop_viewer_media::desktop_viewer_sound_support` | `src-tauri/src/main.rs:141` | `display.viewer.sound.check` | [40 Coverage table](40-desktop-display-computer-use.md) | API |
| 12 | `desktop_viewer_media::desktop_viewer_sound_cancel` | `src-tauri/src/main.rs:142` | `display.viewer.sound.cancel` | [40 Coverage table](40-desktop-display-computer-use.md) | API |
| 13 | `desktop_viewer_media::desktop_viewer_set_audio` | `src-tauri/src/main.rs:143` | `display.viewer.audio.set` | [40 Coverage table](40-desktop-display-computer-use.md) | API |
| 14 | `desktop_viewer_media::desktop_viewer_reset_screen` | `src-tauri/src/main.rs:144` | `display.viewer.screen.reset` | [40 Coverage table](40-desktop-display-computer-use.md) | API |
| 15 | `desktop_viewer::desktop_viewer_clipboard` | `src-tauri/src/main.rs:145` | `clipboard.transfer` (Linux: `action`, `connectionId` required) | [40 Coverage table](40-desktop-display-computer-use.md) | API |
| 16 | `macos_computers::read_macos_computers` | `src-tauri/src/main.rs:146` | `computers.list` (its `macos` member) | [30 §11 Coverage](30-macos-computers.md) | API |
| 17 | `macos_computers::create_macos_computer` | `src-tauri/src/main.rs:147` | `computers.create {kind:"macos"}` (job, `job:<n>`) | [30 §11 Coverage](30-macos-computers.md) | API |
| 18 | `macos_computers::macos_computer_action` | `src-tauri/src/main.rs:148` | action=`start` → `computers.start` (job, `job:<n>`)<br>action=`stop` → `computers.stop` (job, `job:<n>`)<br>action=`force-stop` → `computers.forceStop`<br>action=`delete` → `computers.delete` (job, `job:<n>`)<br>action=`setup` → `macos.setup.retry` (job, `job:<n>`) | [30 §11 Coverage](30-macos-computers.md) | API |
| 19 | `macos_computers::open_macos_display` | `src-tauri/src/main.rs:149` | `display.show` (macOS, local) | [30 §11 Coverage](30-macos-computers.md) | API |
| 20 | `macos_computers::macos_computer_clipboard` | `src-tauri/src/main.rs:150` | `clipboard.transfer` (`action` param, 80 §2 N9) | [30 §11 Coverage](30-macos-computers.md) | API |
| 21 | `macos_computers::delete_macos_template` | `src-tauri/src/main.rs:151` | `macos.template.delete` | [30 §11 Coverage](30-macos-computers.md) | API |
| 22 | `macos_computers::create_macos_checkpoint` | `src-tauri/src/main.rs:152` | `checkpoints.create` (`checkpoints.*` section; job, `job:<n>`) | [30 §11 Coverage](30-macos-computers.md) | API |
| 23 | `macos_computers::restore_macos_checkpoint` | `src-tauri/src/main.rs:153` | `checkpoints.restore` (`checkpoints.*` section; job, `job:<n>`) | [30 §11 Coverage](30-macos-computers.md) | API |
| 24 | `macos_computers::fork_macos_checkpoint` | `src-tauri/src/main.rs:154` | `checkpoints.fork` (`checkpoints.*` section; job, `job:<n>`) | [30 §11 Coverage](30-macos-computers.md) | API |
| 25 | `macos_computers::delete_macos_checkpoint` | `src-tauri/src/main.rs:155` | `checkpoints.delete` (`checkpoints.*` section; job, `job:<n>`) | [30 §11 Coverage](30-macos-computers.md) | API |
| 26 | `macos_remote::remote_macos_snapshot` | `src-tauri/src/main.rs:156` | `computers.list {deviceId}` | [30 §11 Coverage](30-macos-computers.md) | API |
| 27 | `macos_remote::remote_macos_create` | `src-tauri/src/main.rs:157` | `computers.create {kind:"macos", deviceId}` | [30 §11 Coverage](30-macos-computers.md) | API |
| 28 | `macos_remote::remote_macos_action` | `src-tauri/src/main.rs:158` | action=`start` → `computers.start {deviceId}`<br>action=`stop` → `computers.stop {deviceId}`<br>action=`force-stop` → `computers.forceStop {deviceId}`<br>action=`delete` → `computers.delete {deviceId}`<br>action=`setup` → `macos.setup.retry {deviceId}` | [30 §11 Coverage](30-macos-computers.md) | API |
| 29 | `macos_remote_viewer::open_macos_remote_display` | `src-tauri/src/main.rs:159` | UI-only noVNC window; engine session is `macos.display.session` (30 §5) | [30 §11 Coverage](30-macos-computers.md) | UI-only |
| 30 | `macos_remote_viewer::macos_display_session` | `src-tauri/src/main.rs:160` | `macos.display.session` (controller) | [30 §11 Coverage](30-macos-computers.md) | API |
| 31 | `macos_remote_viewer::macos_display_resize` | `src-tauri/src/main.rs:161` | `macos.display.resize` | [30 §11 Coverage](30-macos-computers.md) | API |
| 32 | `app_menu::set_app_menu_state` | `src-tauri/src/main.rs:162` | UI-only, not in API | [60 §8 Coverage](60-connections-settings-services.md) | UI-only |
| 33 | `app_menu::show_app_menu` | `src-tauri/src/main.rs:163` | UI-only, not in API | [60 §8 Coverage](60-connections-settings-services.md) | UI-only |
| 34 | `updates::get_update_state` | `src-tauri/src/main.rs:164` | `updates.state` | [60 §8 Coverage](60-connections-settings-services.md) | API |
| 35 | `updates::check_for_update` | `src-tauri/src/main.rs:165` | `updates.check` | [60 §8 Coverage](60-connections-settings-services.md) | API |
| 36 | `updates::download_update` | `src-tauri/src/main.rs:166` | `updates.download` (job, `job:<n>`) | [60 §8 Coverage](60-connections-settings-services.md) | API |
| 37 | `updates::install_update` | `src-tauri/src/main.rs:167` | `engine.update.prepare` → `engine.shutdown {reason:"update", stopComputers:false}` → installer → restart/resume; abort resumes on failed handoff (95 A-6; 05 §6). Installer path/ownership remains research C-9 | [60 §8 Coverage](60-connections-settings-services.md) | API |
| 38 | `updates::set_update_automatic_checks` | `src-tauri/src/main.rs:168` | `updates.setAutomaticChecks` | [60 §8 Coverage](60-connections-settings-services.md) | API |
| 39 | `updates::open_update_release` | `src-tauri/src/main.rs:169` | client-side, not in API (`UpdateSnapshot.releaseUrl`) | [60 §8 Coverage](60-connections-settings-services.md) | UI-only |
| 40 | `status_panel::open_main` | `src-tauri/src/main.rs:170` | UI-only, not in API | [60 §8 Coverage](60-connections-settings-services.md) | UI-only |
| 41 | `status_panel::take_main_route` | `src-tauri/src/main.rs:171` | UI-only, not in API | [60 §8 Coverage](60-connections-settings-services.md) | UI-only |
| 42 | `status_panel::hide_status` | `src-tauri/src/main.rs:172` | UI-only, not in API | [60 §8 Coverage](60-connections-settings-services.md) | UI-only |
| 43 | `status_panel::resize_status` | `src-tauri/src/main.rs:173` | UI-only, not in API | [60 §8 Coverage](60-connections-settings-services.md) | UI-only |
| 44 | `status_panel::quit_app` | `src-tauri/src/main.rs:174` | client-side Quit, not in API (§6); Cancel / Keep running / Stop and quit (95 A-2; 05 §6) | [60 §8 Coverage](60-connections-settings-services.md) | UI-only |
| 45 | `settings::enable_quit_confirmation` | `src-tauri/src/main.rs:175` | client-side, not in API (§6) | [60 §8 Coverage](60-connections-settings-services.md) | UI-only |
| 46 | `settings::answer_quit_request` | `src-tauri/src/main.rs:176` | client-side, not in API (§6) | [60 §8 Coverage](60-connections-settings-services.md) | UI-only |
| 47 | `tray::update_tray` | `src-tauri/src/main.rs:177` | UI-only, not in API | [60 §8 Coverage](60-connections-settings-services.md) | UI-only |
| 48 | `host_push_operations::start_repository_push` | `src-tauri/src/main.rs:178` | `push.start` | [50 Coverage table](50-access-network-files.md) | API |
| 49 | `host_push_operations::repository_push_status` | `src-tauri/src/main.rs:179` | `push.status` | [50 Coverage table](50-access-network-files.md) | API |
| 50 | `host_push::dismiss_repository_push` | `src-tauri/src/main.rs:180` | `push.dismiss` | [50 Coverage table](50-access-network-files.md) | API |
| 51 | `files::list_computer_directory` | `src-tauri/src/main.rs:181` | `files.list` | [50 Coverage table](50-access-network-files.md) | API |
| 52 | `transfer::choose_upload_files` | `src-tauri/src/main.rs:182` | UI-only, not in API | [50 Coverage table](50-access-network-files.md) | UI-only |
| 53 | `transfer::upload_files` | `src-tauri/src/main.rs:183` | `files.upload` | [50 Coverage table](50-access-network-files.md) | API |
| 54 | `transfer::download_file` | `src-tauri/src/main.rs:184` | `files.download` | [50 Coverage table](50-access-network-files.md) | API |
| 55 | `transfer::cancel_transfer` | `src-tauri/src/main.rs:185` | Existing source mapped to canonical `operations.cancel` | [50 Coverage table](50-access-network-files.md) | API |
| 56 | `network::read_network_state` | `src-tauri/src/main.rs:186` | `network.state` | [50 Coverage table](50-access-network-files.md) | API |
| 57 | `network::save_network_port` | `src-tauri/src/main.rs:187` | `network.publish` | [50 Coverage table](50-access-network-files.md) | API |
| 58 | `network::remove_network_port` | `src-tauri/src/main.rs:188` | `network.unpublish` | [50 Coverage table](50-access-network-files.md) | API |
| 59 | `network::open_network_port` | `src-tauri/src/main.rs:189` | `network.open` | [50 Coverage table](50-access-network-files.md) | API |
| 60 | `ssh_access::read_ssh_access_state` | `src-tauri/src/main.rs:190` | `sshAccess.state` | [50 Coverage table](50-access-network-files.md) | API |
| 61 | `ssh_access::save_ssh_access` | `src-tauri/src/main.rs:191` | `sshAccess.save` | [50 Coverage table](50-access-network-files.md) | API |
| 62 | `ssh_connection::ssh_connection` | `src-tauri/src/main.rs:192` | `sshAccess.connection` | [50 Coverage table](50-access-network-files.md) | API |
| 63 | `secrets::read_secrets_state` | `src-tauri/src/main.rs:193` | `secrets.list` | [50 Coverage table](50-access-network-files.md) | API |
| 64 | `secrets::save_secret` | `src-tauri/src/main.rs:194` | `secrets.save` | [50 Coverage table](50-access-network-files.md) | API |
| 65 | `secrets::remove_secret` | `src-tauri/src/main.rs:195` | `secrets.remove` | [50 Coverage table](50-access-network-files.md) | API |
| 66 | `secrets::retry_secret` | `src-tauri/src/main.rs:196` | `secrets.retry` | [50 Coverage table](50-access-network-files.md) | API |
| 67 | `github::read_github_state` | `src-tauri/src/main.rs:197` | `github.state` | [50 Coverage table](50-access-network-files.md) | API |
| 68 | `github::personal_token::save_github_personal_token` | `src-tauri/src/main.rs:198` | `github.personalToken.save` | [50 Coverage table](50-access-network-files.md) | API |
| 69 | `github::personal_token::remove_github_personal_token` | `src-tauri/src/main.rs:199` | `github.personalToken.remove` | [50 Coverage table](50-access-network-files.md) | API |
| 70 | `github::connect_github` | `src-tauri/src/main.rs:200` | `github.connect` | [50 Coverage table](50-access-network-files.md) | API |
| 71 | `github::cancel_github_connection` | `src-tauri/src/main.rs:201` | Existing source mapped to canonical `operations.cancel` | [50 Coverage table](50-access-network-files.md) | API |
| 72 | `github::reopen_github_authorization` | `src-tauri/src/main.rs:202` | `github.connect.reopen` | [50 Coverage table](50-access-network-files.md) | API |
| 73 | `github::manage_github_repositories` | `src-tauri/src/main.rs:203` | `github.repositories.manage` | [50 Coverage table](50-access-network-files.md) | API |
| 74 | `github::disconnect_github` | `src-tauri/src/main.rs:204` | `github.disconnect` | [50 Coverage table](50-access-network-files.md) | API |
| 75 | `github::set_github_access_enabled` | `src-tauri/src/main.rs:205` | `github.access.set` | [50 Coverage table](50-access-network-files.md) | API |
| 76 | `github::save_github_configuration` | `src-tauri/src/main.rs:206` | `github.configuration.save` | [50 Coverage table](50-access-network-files.md) | API |
| 77 | `github::retry_github_configuration` | `src-tauri/src/main.rs:207` | `github.configuration.retry` | [50 Coverage table](50-access-network-files.md) | API |
| 78 | `github::refresh_github_repositories` | `src-tauri/src/main.rs:208` | `github.repositories.refresh` | [50 Coverage table](50-access-network-files.md) | API |
| 79 | `settings::initialize_settings` | `src-tauri/src/main.rs:209` | STARTUP: initialize settings (05 §7 step 2; 60 §8); read through `settings.read` | [60 §8 Coverage](60-connections-settings-services.md) | STARTUP |
| 80 | `settings::read_settings` | `src-tauri/src/main.rs:210` | `settings.read` | [60 §8 Coverage](60-connections-settings-services.md) | API |
| 81 | `settings::update_settings` | `src-tauri/src/main.rs:211` | `settings.update` | [60 §8 Coverage](60-connections-settings-services.md) | API |
| 82 | `settings::update_onboarding_draft` | `src-tauri/src/main.rs:212` | client-owned draft, not engine API (95 A-5) | [60 §8 Coverage](60-connections-settings-services.md) | UI-only |
| 83 | `settings::import_legacy_theme` | `src-tauri/src/main.rs:213` | no legacy API; conversion only at engine launch through runtime_migration (95 §3) | [60 §8 Coverage](60-connections-settings-services.md) | STARTUP |
| 84 | `settings::flush_settings` | `src-tauri/src/main.rs:214` | `settings.flush` (80 §2 N14; 05 §9.1 agrees) | [60 §8 Coverage](60-connections-settings-services.md) | API |
| 85 | `settings::begin_settings_flush` | `src-tauri/src/main.rs:215` | client-side Quit handshake, not in API (§6) | [60 §8 Coverage](60-connections-settings-services.md) | UI-only |
| 86 | `settings::complete_settings_flush` | `src-tauri/src/main.rs:216` | client-side, not in API (§6); the `finish_exit` it triggers is `engine.shutdown`'s work (05 §6) | [60 §8 Coverage](60-connections-settings-services.md) | UI-only |
| 87 | `settings::cancel_settings_flush` | `src-tauri/src/main.rs:217` | client-side, not in API (§6) | [60 §8 Coverage](60-connections-settings-services.md) | UI-only |
| 88 | `settings::read_shutdown_state` | `src-tauri/src/main.rs:218` | `engine.state` (05) | [60 §8 Coverage](60-connections-settings-services.md) | API |
| 89 | `remote::connections_status` | `src-tauri/src/main.rs:219` | `connections.status` | [60 §8 Coverage](60-connections-settings-services.md) | API |
| 90 | `remote::authorize_device` | `src-tauri/src/main.rs:220` | client-side launcher using `connections.ssh.authorizationCommand` (95 A-22) | [60 §8 Coverage](60-connections-settings-services.md) | UI-only |
| 91 | `remote::setup_device_key` | `src-tauri/src/main.rs:221` | client-side launcher using `connections.ssh.keySetupCommand` (95 A-22) | [60 §8 Coverage](60-connections-settings-services.md) | UI-only |
| 92 | `remote_network::remote_network_state` | `src-tauri/src/main.rs:222` | `network.state` (`deviceId`) | [50 Coverage table](50-access-network-files.md) | API |
| 93 | `remote_ssh_access::remote_ssh_access_state` | `src-tauri/src/main.rs:223` | `sshAccess.state` (`deviceId`) | [50 Coverage table](50-access-network-files.md) | API |
| 94 | `remote_ssh_access::remote_save_ssh_access` | `src-tauri/src/main.rs:224` | `sshAccess.save` (remote computer) | [50 Coverage table](50-access-network-files.md) | API |
| 95 | `remote_network::remote_save_network_port` | `src-tauri/src/main.rs:225` | `network.publish` (remote computer) | [50 Coverage table](50-access-network-files.md) | API |
| 96 | `remote_network::remote_remove_network_port` | `src-tauri/src/main.rs:226` | `network.unpublish` (remote computer) | [50 Coverage table](50-access-network-files.md) | API |
| 97 | `remote_network::remote_open_network_port` | `src-tauri/src/main.rs:227` | `network.open` (remote computer) | [50 Coverage table](50-access-network-files.md) | API |
| 98 | `remote::set_connections_enabled` | `src-tauri/src/main.rs:228` | `connections.setEnabled` | [60 §8 Coverage](60-connections-settings-services.md) | API |
| 99 | `remote::device_list` | `src-tauri/src/main.rs:229` | `connections.devices.list` | [60 §8 Coverage](60-connections-settings-services.md) | API |
| 100 | `remote::connect_device` | `src-tauri/src/main.rs:230` | `connections.devices.connect` | [60 §8 Coverage](60-connections-settings-services.md) | API |
| 101 | `remote::remove_device` | `src-tauri/src/main.rs:231` | `connections.devices.remove` | [60 §8 Coverage](60-connections-settings-services.md) | API |
| 102 | `remote::device_snapshot` | `src-tauri/src/main.rs:232` | `computers.list {deviceId}` (10 §2); retain device-health side effect (60 §1.7); routing topology remains 60 OQ 3 | [60 §8 Coverage](60-connections-settings-services.md) | API |
| 103 | `remote::remote_computer_action` | `src-tauri/src/main.rs:233` | action=`start` (`runtime/remote_ops.rs:162`) → `computers.start {computerId, deviceId}` (10)<br>action=`stop` → `computers.stop {computerId, deviceId}` (10)<br>action=`restart` → `computers.restart {computerId, deviceId}` (10)<br>action=`dismiss-error` → `computers.dismissError {computerId, deviceId}` (10) | [60 §8 Coverage](60-connections-settings-services.md) | API |
| 104 | `remote::remote_checkpoint_action` | `src-tauri/src/main.rs:234` | action=`create` (`remote.rs:1345-1357`) → `checkpoints.create {computerId, deviceId}` (20)<br>action=`fork` → `checkpoints.fork {computerId, deviceId}` (20)<br>action=`restore` → `checkpoints.restore {computerId, deviceId}` (20) | [60 §8 Coverage](60-connections-settings-services.md) | API |
| 105 | `remote::remote_upsert_computer` | `src-tauri/src/main.rs:235` | with `expected` absent (`remote.rs:1692`) → `computers.create {deviceId}` (10)<br>with `expected` set → `computers.configuration.change {deviceId}` (10) | [60 §8 Coverage](60-connections-settings-services.md) | API |
| 106 | `remote::remote_delete_computer` | `src-tauri/src/main.rs:236` | `computers.delete {computerId, deviceId}` (10); emits `notifications.cleared` (§4.2) | [60 §8 Coverage](60-connections-settings-services.md) | API |
| 107 | `system_integrations::read_system_integrations` | `src-tauri/src/main.rs:237` | client-side, not in API (§3) | [60 §8 Coverage](60-connections-settings-services.md) | UI-only |
| 108 | `system_integrations::set_login_item` | `src-tauri/src/main.rs:238` | client-side, not in API (§3); engine autostart → Open questions 7-8 | [60 §8 Coverage](60-connections-settings-services.md) | UI-only |
| 109 | `system_integrations::request_notification_authorization` | `src-tauri/src/main.rs:239` | client-side, not in API (§3) | [60 §8 Coverage](60-connections-settings-services.md) | UI-only |
| 110 | `notifications::deliver_notice` | `src-tauri/src/main.rs:240` | client-side, not in API (§4.2) | [60 §8 Coverage](60-connections-settings-services.md) | UI-only |
| 111 | `notifications::clear_computer_notices` | `src-tauri/src/main.rs:241` | client-side, not in API; engine emits `notifications.cleared` (§4.2) | [60 §8 Coverage](60-connections-settings-services.md) | UI-only |
| 112 | `system_integrations::open_integration_settings` | `src-tauri/src/main.rs:242` | UI-only, not in API (§3) | [60 §8 Coverage](60-connections-settings-services.md) | UI-only |
| 113 | `system_integrations::show_integration_error` | `src-tauri/src/main.rs:243` | UI-only, not in API; engine-originated uses → notices or method errors (§3) | [60 §8 Coverage](60-connections-settings-services.md) | UI-only |
| 114 | `editor::read_editor_include_notice` | `src-tauri/src/main.rs:244` | `editor.includeNotice` | [50 Coverage table](50-access-network-files.md) | API |
| 115 | `applications::list_applications` | `src-tauri/src/main.rs:245` | UI-only, not in API | [50 Coverage table](50-access-network-files.md) | UI-only |
| 116 | `applications::choose_application` | `src-tauri/src/main.rs:246` | UI-only, not in API | [50 Coverage table](50-access-network-files.md) | UI-only |
| 117 | `dependencies::read_dependencies` | `src-tauri/src/main.rs:247` | `device.dependencies` | [20 §5 Coverage](20-checkpoints-exports-preparation.md) | API |
| 118 | `backup_controller::read_backup_state` | `src-tauri/src/main.rs:248` | `exports.state` | [20 §5 Coverage](20-checkpoints-exports-preparation.md) | API |
| 119 | `runtime_migration::read_runtime_migration_state` | `src-tauri/src/main.rs:249` | `migration.state` | [20 §5 Coverage](20-checkpoints-exports-preparation.md) | API |
| 120 | `runtime_migration::retry_runtime_migration` | `src-tauri/src/main.rs:250` | retired runtime trigger; conversion only at launch via runtime_migration (95 §3; 20 §3) | [20 §5 Coverage](20-checkpoints-exports-preparation.md) | STARTUP |
| 121 | `runtime_migration::continue_after_migration_failure` | `src-tauri/src/main.rs:251` | retired runtime trigger; conversion only at launch via runtime_migration (95 §3; 20 §3) | [20 §5 Coverage](20-checkpoints-exports-preparation.md) | STARTUP |
| 122 | `pre_upgrade_backup::read_pre_upgrade_backup` | `src-tauri/src/main.rs:252` | `migration.preUpgradeBackup.get` | [20 §5 Coverage](20-checkpoints-exports-preparation.md) | API |
| 123 | `pre_upgrade_backup::measure_pre_upgrade_backup` | `src-tauri/src/main.rs:253` | `migration.preUpgradeBackup.measure` | [20 §5 Coverage](20-checkpoints-exports-preparation.md) | API |
| 124 | `pre_upgrade_backup::delete_pre_upgrade_backup` | `src-tauri/src/main.rs:254` | `migration.preUpgradeBackup.delete` | [20 §5 Coverage](20-checkpoints-exports-preparation.md) | API |
| 125 | `pre_upgrade_backup::reveal_pre_upgrade_backup` | `src-tauri/src/main.rs:255` | UI-only, not in API. The client reveals `path` | [20 §5 Coverage](20-checkpoints-exports-preparation.md) | UI-only |
| 126 | `pre_upgrade_backup::acknowledge_pre_upgrade_backup_notice` | `src-tauri/src/main.rs:256` | `migration.preUpgradeBackup.acknowledgeNotice` | [20 §5 Coverage](20-checkpoints-exports-preparation.md) | API |
| 127 | `backup_controller::choose_backup_destination` | `src-tauri/src/main.rs:257` | UI-only, not in API. Its side effect is `exports.destination.set` (NEW) | [20 §5 Coverage](20-checkpoints-exports-preparation.md) | UI-only |
| 128 | `backup_controller::choose_backup_archive` | `src-tauri/src/main.rs:258` | UI-only, not in API. The path goes to `exports.inspect` and `exports.import` | [20 §5 Coverage](20-checkpoints-exports-preparation.md) | UI-only |
| 129 | `backup_controller::inspect_backup_archive` | `src-tauri/src/main.rs:259` | `exports.inspect` | [20 §5 Coverage](20-checkpoints-exports-preparation.md) | API |
| 130 | `backup_controller::cancel_backup_inspection` | `src-tauri/src/main.rs:260` | Existing source mapped to canonical `operations.cancel` | [20 §5 Coverage](20-checkpoints-exports-preparation.md) | API |
| 131 | `backup_controller::reveal_backup_archive` | `src-tauri/src/main.rs:261` | UI-only, not in API. The client reveals `operation.archive.archivePath` | [20 §5 Coverage](20-checkpoints-exports-preparation.md) | UI-only |
| 132 | `backup_controller::start_backup` | `src-tauri/src/main.rs:262` | `exports.create` | [20 §5 Coverage](20-checkpoints-exports-preparation.md) | API |
| 133 | `backup_controller::start_restore` | `src-tauri/src/main.rs:263` | `exports.import` | [20 §5 Coverage](20-checkpoints-exports-preparation.md) | API |
| 134 | `backup_controller::cancel_backup_operation` | `src-tauri/src/main.rs:264` | Existing source mapped to canonical `operations.cancel` | [20 §5 Coverage](20-checkpoints-exports-preparation.md) | API |
| 135 | `backup_controller::dismiss_backup_operation` | `src-tauri/src/main.rs:265` | `exports.dismiss` | [20 §5 Coverage](20-checkpoints-exports-preparation.md) | API |
| 136 | `backup_controller::acknowledge_backup_result` | `src-tauri/src/main.rs:266` | `exports.acknowledge` | [20 §5 Coverage](20-checkpoints-exports-preparation.md) | API |
| 137 | `runtime::read_application_state` | `src-tauri/src/main.rs:267` | `computers.list` (Linux part) | [10 §13 Coverage](10-computers-lifecycle.md) | API |
| 138 | `runtime::storage::read_workspace_storage` | `src-tauri/src/main.rs:268` | `storage.read` | [10 §13 Coverage](10-computers-lifecycle.md) | API |
| 139 | `runtime::storage::reclaim_workspace_storage` | `src-tauri/src/main.rs:269` | `storage.reclaim` | [10 §13 Coverage](10-computers-lifecycle.md) | API |
| 140 | `runtime::runtime_logs::query_computer_logs` | `src-tauri/src/main.rs:270` | `logs.query` | [10 §13 Coverage](10-computers-lifecycle.md) | API |
| 141 | `log_export::export_computer_logs` | `src-tauri/src/main.rs:271` | `logs.export` (the save dialog is UI-only; the engine takes `destination`) | [10 §13 Coverage](10-computers-lifecycle.md) | API |
| 142 | `log_export::cancel_log_export` | `src-tauri/src/main.rs:272` | Existing source mapped to canonical `operations.cancel` (every running log-export job; 05 §4.2 F) | [10 §13 Coverage](10-computers-lifecycle.md) | API |
| 143 | `runtime::read_application_shell` | `src-tauri/src/main.rs:273` | `computers.shell` | [10 §13 Coverage](10-computers-lifecycle.md) | API |
| 144 | `runtime::read_computer_configuration` | `src-tauri/src/main.rs:274` | `computers.configuration.read` | [10 §13 Coverage](10-computers-lifecycle.md) | API |
| 145 | `runtime::configure_computer_identities` | `src-tauri/src/main.rs:275` | `computers.identities.configure` | [10 §13 Coverage](10-computers-lifecycle.md) | API |
| 146 | `runtime::verify_computer_identities` | `src-tauri/src/main.rs:276` | `computers.identities.verify` | [10 §13 Coverage](10-computers-lifecycle.md) | API |
| 147 | `runtime::computer_action` | `src-tauri/src/main.rs:277` | `start` → `computers.start`<br>`stop` → `computers.stop`<br>`restart` → `computers.restart`<br>`dismiss-error` → `computers.dismissError`<br>`open-terminal` → UI-only, not in API: it launches an app on the user's screen (§4.1, 00-brief.md "except drawing UI"). It is built on `terminal.command` (50)<br>`open-editor` → UI-only, not in API, for the same reason (§4.1). It is built on `guest.sshAlias.ensure` (50; 80 §2 N10) | [10 §13 Coverage](10-computers-lifecycle.md) | API |
| 148 | `runtime::checkpoints::create_checkpoint` | `src-tauri/src/main.rs:278` | `checkpoints.create` (Linux) | [20 §5 Coverage](20-checkpoints-exports-preparation.md) | API |
| 149 | `runtime::checkpoints::fork_checkpoint` | `src-tauri/src/main.rs:279` | `checkpoints.fork` (Linux) | [20 §5 Coverage](20-checkpoints-exports-preparation.md) | API |
| 150 | `runtime::checkpoints::restore_checkpoint` | `src-tauri/src/main.rs:280` | `checkpoints.restore` (Linux) | [20 §5 Coverage](20-checkpoints-exports-preparation.md) | API |
| 151 | `runtime::checkpoints::delete_checkpoint` | `src-tauri/src/main.rs:281` | `checkpoints.delete` (Linux) | [20 §5 Coverage](20-checkpoints-exports-preparation.md) | API |
| 152 | `runtime::checkpoints::abandon_restore` | `src-tauri/src/main.rs:282` | `checkpoints.abandonRestore` (Linux) | [20 §5 Coverage](20-checkpoints-exports-preparation.md) | API |
| 153 | `runtime::checkpoints::read_checkpoint_usage` | `src-tauri/src/main.rs:283` | `checkpoints.usage` (Linux) | [20 §5 Coverage](20-checkpoints-exports-preparation.md) | API |
| 154 | `runtime::read_setup_activity` | `src-tauri/src/main.rs:284` | `activity.setup.read` | [10 §13 Coverage](10-computers-lifecycle.md) | API |
| 155 | `runtime::read_operation_queue` | `src-tauri/src/main.rs:285` | `operations.list` | [10 §13 Coverage](10-computers-lifecycle.md) | API |
| 156 | `runtime::cancel_operation` | `src-tauri/src/main.rs:286` | `operations.cancel {jobId}`; old gate-id call is retired (95 §3) | [10 §13 Coverage](10-computers-lifecycle.md) | API |
| 157 | `runtime::retry_computer_configuration` | `src-tauri/src/main.rs:287` | `computers.configuration.retry` | [10 §13 Coverage](10-computers-lifecycle.md) | API |
| 158 | `runtime::skip_computer_use_wait` | `src-tauri/src/main.rs:288` | `computers.creation.skipComputerUseWait` | [10 §13 Coverage](10-computers-lifecycle.md) | API |
| 159 | `runtime::change_computer_configuration` | `src-tauri/src/main.rs:289` | `{kind:"upsert", expected:null}` → `computers.create` `{kind:"linux"}`<br>`{kind:"delete"}` → `computers.delete`<br>`{kind:"upsert"}` with `expected`, `reorder`, `batch` → `computers.configuration.change` | [10 §13 Coverage](10-computers-lifecycle.md) | API |

### 1.3 Every emitted backend event

The canonical destination column points only into [05 §4.2 D](05-engine-architecture.md#event-catalogue). The final nine names are UI-only according to 05 §9.3; they are deliberately absent from the catalogue. `silo://application-state-changed` is separated by emit site, rather than assigned one misleading domain. State-hint payload choice remains 05 OQ 18; existing payload events retain their data (05 §4.2 D).

| Emitted name | All emit sites | Canonical event / UI-only disposition | Owning section |
| --- | --- | --- | --- |
| `chatgpt-app-status` | `src-tauri/src/chatgpt_app.rs:1985` | `preparation.chatgpt.changed` | 20 §4 |
| `desktop-clipboard` | `src-tauri/src/viewer_clipboard.rs:254` | UI-only shortcut transfer feedback; API returns `clipboard.transfer` result | 40 §2; 05 §9.3 |
| `desktop:route-requested` | `src-tauri/src/status_panel.rs:160` | UI-only main-window routing | 60 §8; 05 §9.3 |
| `desktop:status-opened` | `src-tauri/src/status_panel.rs:68` | UI-only status-window activation | 60 §8; 05 §9.3 |
| `settings:changed` | `src-tauri/src/settings.rs:759` | `settings.changed` | 60 §2 |
| `settings:flush-request` | `src-tauri/src/settings.rs:962` | UI-only client Quit flush handshake | 60 §6; 05 §9.3 |
| `silo://application-state-changed` | `src-tauri/src/runtime.rs:3348`; `src-tauri/src/runtime.rs:3371`; `src-tauri/src/computer_use.rs:1348`; `src-tauri/src/computer_use.rs:1366`; `src-tauri/src/runtime_migration.rs:961`; `src-tauri/src/runtime_migration.rs:1030`; `src-tauri/src/startup.rs:243`; `src-tauri/src/github_personal_token.rs:247`; `src-tauri/src/desktop.rs:824`; `src-tauri/src/desktop.rs:848`; `src-tauri/src/host_push.rs:92`; `src-tauri/src/host_push.rs:1219`; `src-tauri/src/host_push.rs:1241`; `src-tauri/src/github.rs:266`; `src-tauri/src/github.rs:441`; `src-tauri/src/github.rs:667`; `src-tauri/src/github.rs:820`; `src-tauri/src/github.rs:1137`; `src-tauri/src/github.rs:2585`; `src-tauri/src/github.rs:3069`; `src-tauri/src/backup_controller.rs:413`; `src-tauri/src/host_push_operations.rs:224`; `src-tauri/src/secrets.rs:531`; `src-tauri/src/secrets.rs:777`; `src-tauri/src/secrets.rs:849`; `src-tauri/src/secrets.rs:869`; `src-tauri/src/secrets.rs:929`; `src-tauri/src/runtime/configuration_recovery.rs:604`; `src-tauri/src/runtime/configuration_recovery.rs:646`; `src-tauri/src/runtime/shutdown.rs:127`; `src-tauri/src/runtime/lifecycle_recovery.rs:449`; `src-tauri/src/runtime/checkpoints.rs:804`; `src-tauri/src/runtime/checkpoints.rs:1797`; `src-tauri/src/runtime/checkpoints.rs:2208`; `src-tauri/src/runtime/checkpoints.rs:2493`; `src-tauri/src/runtime/checkpoints.rs:2768`; `src-tauri/src/runtime/remote_ops.rs:49`; `src-tauri/src/runtime/remote_ops.rs:101`; `src-tauri/src/runtime/remote_ops.rs:112`; `src-tauri/src/runtime/remote_ops.rs:127` | `computers.changed`, `checkpoints.changed`, `exports.changed`, `migration.changed`, `github.changed`, `secrets.changed`, `push.changed`; backup running progress also `operations.job.progress` (`source: "backup"`) | 05 §4.2 D/E; 10 §12.2; 20 §4.3; 50 domain events |
| `silo://computer-configuration-progress` | `src-tauri/src/runtime.rs:3586`; `src-tauri/src/runtime.rs:4181`; `src-tauri/src/runtime.rs:4183`; `src-tauri/src/runtime/configuration_recovery.rs:632` | `operations.job.progress`, `source: "setup"` | 05 #job-contract; 10 §3 |
| `silo://desktop-viewer-page` | `src-tauri/src/desktop_viewer.rs:649` | UI-only own webview page-load notification; NEW `display.viewer.page` is a different page-channel contract | 40 §2; 05 §9.3 |
| `silo://editor-include-changed` | `src-tauri/src/editor.rs:1099` | `editor.includeNotice.changed` | 50 §editor.includeNotice.changed |
| `silo://lifecycle-progress` | `src-tauri/src/runtime.rs:3343` | `operations.job.progress`, `source: "lifecycle"` | 05 #job-contract; 10 §4.4 |
| `silo://macos-computers-changed` | `src-tauri/src/macos_computers.rs:668` | `computers.changed` (macOS payload); job progress also `operations.job.progress`, `source: "macos"` | 10 §12.2; 30 §2; 05 #job-contract |
| `silo://menu-command` | `src-tauri/src/app_menu.rs:497` | UI-only native-menu dispatch | 60 §8; 05 §9.3 |
| `silo://network-state-changed` | `src-tauri/src/ssh_access.rs:667`; `src-tauri/src/ssh_access.rs:963`; `src-tauri/src/network.rs:822`; `src-tauri/src/remote_network.rs:541` | `network.changed` | 50 §network.changed |
| `silo://notice` | `src-tauri/src/notifications.rs:126` | `notifications.notice` | 60 §4.2 |
| `silo://operation-queue-changed` | `src-tauri/src/main.rs:299` | `operations.queue.changed` | 10 §6 |
| `silo://pre-upgrade-backup-changed` | `src-tauri/src/pre_upgrade_backup.rs:450`; `src-tauri/src/pre_upgrade_backup.rs:517` | `migration.preUpgradeBackup.changed` | 20 §3 |
| `silo://preparation-status` | `src-tauri/src/preparation.rs:233` | `preparation.changed` | 20 §4 |
| `silo://quit-requested` | `src-tauri/src/settings.rs:1143` | UI-only client confirmation request | 60 §6; 05 §9.3 |
| `silo://shutdown-state-changed` | `src-tauri/src/settings.rs:924`; `src-tauri/src/settings.rs:960` | `engine.shutdown.changed` | 05 §6 |
| `silo://transfer-progress` | `src-tauri/src/transfer.rs:1398`; `src-tauri/src/transfer.rs:1449` | `operations.job.progress`, `source: "transfer"` | 05 #job-contract; 50 §Transfer progress |
| `silo://update-state` | `src-tauri/src/updates.rs:171`; `src-tauri/src/updates.rs:335`; `src-tauri/src/updates.rs:445`; `src-tauri/src/updates.rs:536`; `src-tauri/src/updates.rs:795` | `updates.changed`; download progress also `operations.job.progress`, `source: "update"` | 60 §5.2; 05 #job-contract |
| `silo://viewer-drag` | `src-tauri/src/transfer.rs:1288`; `src-tauri/src/transfer.rs:1291`; `src-tauri/src/transfer.rs:1294` | UI-only OS drag state | 40 §2; 05 §9.3 |
| `silo://viewer-drop` | `src-tauri/src/transfer.rs:1300` | UI-only shell-selected file token; transfer is `files.upload` | 40 §2; 50 §Viewer drag and drop events; 05 §9.3 |

The broad application hint has seven destinations by emitter: runtime, lifecycle/configuration recovery, startup/shutdown, desktop and computer-use sites → `computers.changed`; `runtime/checkpoints.rs` → `checkpoints.changed`; `backup_controller.rs` → `exports.changed`; `runtime_migration.rs` → `migration.changed`; `github.rs`/`github_personal_token.rs` → `github.changed`; `secrets.rs` → `secrets.changed`; `host_push.rs`/`host_push_operations.rs` → `push.changed` (05 §4.2 D, the source sites in the preceding row). No extra canonical event is inferred from the shared emitted name.

### 1.4 Every bridge `METHODS` entry

Access is the code's Read/Change/Stream classification, not the API's Kind. In particular resize stays a Read in v5 while its API kind is command (30 §5, `macos.display.resize`; `remote.rs:270`). The table records current source names only. Changed names are re-exposed under canonical names; no v5 aliases or compatibility dispatch survive (95 §3; 60 §8 Bridge methods).

| `METHODS` entry | Access | Source | Canonical destination | Section | Status |
| --- | --- | --- | --- | --- | --- |
| `handshake` | Read | `src-tauri/src/remote.rs:237` | `engine.handshake` | [05 §engine.handshake](05-engine-architecture.md#enginehandshake) | API |
| `runtime.snapshot` | Read | `src-tauri/src/remote.rs:238` | `computers.list` (Linux member, `deviceId`) | [10 §computers.list](10-computers-lifecycle.md#computerslist) | API |
| `runtime.logs` | Read | `src-tauri/src/remote.rs:239` | `logs.query` | [10 §logs.query](10-computers-lifecycle.md#logsquery) | API |
| `runtime.configuration` | Read | `src-tauri/src/remote.rs:240` | `computers.configuration.read` | [10 §computers.configuration.read](10-computers-lifecycle.md#computersconfigurationread) | API |
| `runtime.action` | Change | `src-tauri/src/remote.rs:241` | `computers.start`, `computers.stop`, `computers.restart`, `computers.dismissError` (dispatch by `action`; 10 §13 / 30 §11) | [10 §computers.start](10-computers-lifecycle.md#computersstart); [10 §computers.stop](10-computers-lifecycle.md#computersstop); [10 §computers.restart](10-computers-lifecycle.md#computersrestart); [10 §computers.dismissError](10-computers-lifecycle.md#computersdismisserror) | API |
| `runtime.upsert` | Change | `src-tauri/src/remote.rs:242` | `computers.create`, `computers.configuration.change` (without/with `expected`; 10 §13) | [10 §computers.create](10-computers-lifecycle.md#computerscreate); [10 §computers.configuration.change](10-computers-lifecycle.md#computersconfigurationchange) | API |
| `runtime.delete` | Change | `src-tauri/src/remote.rs:243` | `computers.delete` | [10 §computers.delete](10-computers-lifecycle.md#computersdelete) | API |
| `desktop.connect` | Read | `src-tauri/src/remote.rs:244` | `desktop.connect` (engine-to-engine only) | [40 §desktop.connect](40-desktop-display-computer-use.md#desktopconnect-engine-internal) | API |
| `desktop.status` | Read | `src-tauri/src/remote.rs:245` | `desktop.status` | [40 §desktop.status](40-desktop-display-computer-use.md#desktopstatus) | API |
| `desktop.action` | Change | `src-tauri/src/remote.rs:246` | `desktop.action` | [40 §desktop.action](40-desktop-display-computer-use.md#desktopaction) | API |
| `chatgpt.status` | Read | `src-tauri/src/remote.rs:247` | `preparation.chatgpt.status` | [20 §preparation.chatgpt.status](20-checkpoints-exports-preparation.md#423-preparationchatgptstatus) | API |
| `chatgpt.retry` | Change | `src-tauri/src/remote.rs:248` | `preparation.chatgpt.retry` | [20 §preparation.chatgpt.retry](20-checkpoints-exports-preparation.md#424-preparationchatgptretry) | API |
| `computerUse.approval` | Change | `src-tauri/src/remote.rs:249` | `computerUse.approval` | [40 §computerUse.approval](40-desktop-display-computer-use.md#computeruseapproval) | API |
| `ssh.access.state` | Read | `src-tauri/src/remote.rs:250` | `sshAccess.state` | [50 §sshAccess.state](50-access-network-files.md#sshaccessstate) | API |
| `ssh.access.connection` | Change | `src-tauri/src/remote.rs:251` | `sshAccess.connection` | [50 §sshAccess.connection](50-access-network-files.md#sshaccessconnection) | API |
| `ssh.access.save` | Change | `src-tauri/src/remote.rs:252` | `sshAccess.save` | [50 §sshAccess.save](50-access-network-files.md#sshaccesssave) | API |
| `files.list` | Read | `src-tauri/src/remote.rs:253` | `files.list` | [50 §files.list](50-access-network-files.md#fileslist) | API |
| `guest.prepare` | Change | `src-tauri/src/remote.rs:254` | `guest.prepare` | [50 §guest.prepare](50-access-network-files.md#guestprepare) | API |
| `guest.ssh` | Stream | `src-tauri/src/remote.rs:255` | `guest.ssh` | [50 §guest.ssh](50-access-network-files.md#guestssh) | API |
| `network.state` | Read | `src-tauri/src/remote.rs:256` | `network.state` | [50 §network.state](50-access-network-files.md#networkstate) | API |
| `network.publish` | Change | `src-tauri/src/remote.rs:257` | `network.publish` | [50 §network.publish](50-access-network-files.md#networkpublish) | API |
| `network.unpublish` | Change | `src-tauri/src/remote.rs:258` | `network.unpublish` | [50 §network.unpublish](50-access-network-files.md#networkunpublish) | API |
| `repository.push.status` | Read | `src-tauri/src/remote.rs:259` | `push.status` | [50 §push.status](50-access-network-files.md#pushstatus) | API |
| `repository.push.start` | Change | `src-tauri/src/remote.rs:260` | `push.start` | [50 §push.start](50-access-network-files.md#pushstart) | API |
| `repository.push` | Change | `src-tauri/src/remote.rs:261` | No canonical method: advertised retired entry; `push.start` is the served replacement, not this dispatch | 50 §Legacy `repository.push`; 60 §8; §5 B-6 | RETIRED |
| `repository.dismiss` | Change | `src-tauri/src/remote.rs:262` | `push.dismiss` | [50 §push.dismiss](50-access-network-files.md#pushdismiss) | API |
| `checkpoint.create` | Change | `src-tauri/src/remote.rs:263` | `checkpoints.create` | [20 §checkpoints.create](20-checkpoints-exports-preparation.md#121-checkpointscreate) | API |
| `checkpoint.fork` | Change | `src-tauri/src/remote.rs:264` | `checkpoints.fork` | [20 §checkpoints.fork](20-checkpoints-exports-preparation.md#123-checkpointsfork) | API |
| `checkpoint.restore` | Change | `src-tauri/src/remote.rs:265` | `checkpoints.restore` | [20 §checkpoints.restore](20-checkpoints-exports-preparation.md#122-checkpointsrestore) | API |
| `macos.snapshot` | Read | `src-tauri/src/remote.rs:266` | `computers.list` (macOS member, `deviceId`) | [10 §computers.list](10-computers-lifecycle.md#computerslist) | API |
| `macos.create` | Change | `src-tauri/src/remote.rs:267` | `computers.create` `{kind:"macos"}` | [10 §computers.create](10-computers-lifecycle.md#computerscreate) | API |
| `macos.action` | Change | `src-tauri/src/remote.rs:268` | `computers.start`, `computers.stop`, `computers.forceStop`, `computers.delete`, `macos.setup.retry` (dispatch by `action`; 10 §13 / 30 §11) | [10 §computers.start](10-computers-lifecycle.md#computersstart); [10 §computers.stop](10-computers-lifecycle.md#computersstop); [10 §computers.forceStop](10-computers-lifecycle.md#computersforcestop); [10 §computers.delete](10-computers-lifecycle.md#computersdelete); [30 §macos.setup.retry](30-macos-computers.md#macossetupretry) | API |
| `macos.display.connect` | Read | `src-tauri/src/remote.rs:269` | `macos.display.connect` | [30 §macos.display.connect](30-macos-computers.md#macosdisplayconnect-owner) | API |
| `macos.display.resize` | Read | `src-tauri/src/remote.rs:270` | `macos.display.resize` | [30 §macos.display.resize](30-macos-computers.md#macosdisplayresize-owner) | API |
| `macos.display.stream` | Stream | `src-tauri/src/remote.rs:271` | `macos.display.stream` | [30 §macos.display.stream](30-macos-computers.md#macosdisplaystream-owner) | API |

### 1.5 Every executable mode and the startup guard

| Mode / branch | Code source | Current disposition | Section |
| --- | --- | --- | --- |
| Default Tauri application | `src-tauri/src/main.rs:113-380` | Split into the engine's startup duties and a UI-only Tauri client; the client calls the same canonical methods in §1.2 | 05 §1.1, §7, §8; 00 §What was decided |
| `--remote-bridge` | `src-tauri/src/main.rs:98`; `remote.rs:1748-1773` | Transport adapter for the methods in §1.4; not a new request method | 05 §1.2, §8; 60 §8 |
| `--remote-guest <device> <computer> [port]` | `src-tauri/src/main.rs:99-102`; `remote.rs:1804-1860` | Transport adapter for `guest.ssh` (SSH and published-port streams) | 05 §1.2; 50 §Transport entry points |
| `--msb-ssh-serve <runtime home> <computer>` | `src-tauri/src/main.rs:103`; `editor.rs:862-902` (constant at `:864`) | RETIRED Linux AppImage host helper; no API branch (95 §3) | 05 §1.2; 50 §Transport entry points |
| Linux package-update guard | `src-tauri/src/main.rs:83-90`; `system_integrations.rs:161-166`, `:194-203` | RETIRED Linux-host source branch; no API behavior (95 §3) | 05 OQ20; B-26 CLOSED |

All four source modes and the early guard have an explicit disposition. The Linux AppImage helper and package-update guard are retired, with no engine path or open owner decision; B-9/B-26 are closed (95 §3; 05 mode mapping). Mac bridge/guest transports remain source seams for canonical methods.

## 2. Consistency sweep of current 05–70

### 2.1 Canonical names and ownership

The index in §3 gives one owning section for each of **146 methods**. Other sections' platform adapters, feature-use notes and coverage rows refer to that owner. This is the rule for shared computer methods (10), checkpoints (20), `clipboard.transfer` (40), `guest.exec` (70), and `guest.prepare`, `guest.ssh`, `guest.sshAlias.*` (50): see their method headings and 30's explicitly labelled platform parts.

The resolved-name ledger below preserves N1–N19 identifiers cited by 05–70. These are confirmations of the current owning sections, not alternate definitions or proposals.

| ID | Current rule | Authoritative section |
| --- | --- | --- |
| N1 | `computers.list` and `computers.create` cover both kinds; `macos.snapshot/create/action` are retired v5 source names, with source action fan-out; no old names are kept on the new wire (95 §3) | 10 §2–4, §13; 30 §2–4, §11 |
| N2 | `device_snapshot` is `computers.list {deviceId}`; former `connections.devices.snapshot` is not another API method; retain its health side effect | 10 §2; 60 §1.7 |
| N3 | Configuration changes use `computers.configuration.change`; no `computers.update` method | 10 §3; 30 §10 resource-edit row |
| N4 | `checkpoints.*` is canonical; existing singular names are source evidence only; the new wire uses plural canonical names (95 §3) | 20 §1.2–1.3, §5 |
| N5 | ChatGPT app status/retry belongs to `preparation.chatgpt.*`; its event is `preparation.chatgpt.changed` | 20 §4.1–4.3; 40 §The ChatGPT for Linux app |
| N6 | Creation wait skip is `computers.creation.skipComputerUseWait` | 10 §3; 40 §Skipping the computer-use wait at creation |
| N7 | `computerUse.state` is the read; `computerUse.approval` is the setter; `computerUse.defaultApproval` names a setting, not a method | 40 §4; 30 §10 |
| N8 | `sshAccess.connection` keeps its managed-access meaning; macOS key authorization is `guest.prepare`, alias material is `guest.sshAlias.ensure` | 50 §sshAccess.connection, §guest.prepare; 30 §7 |
| N9 | `clipboard.transfer` takes `action: paste\|copy`; Linux requires `connectionId`, macOS does not; host-clipboard transfer and remote payload read/write stay distinct | 40 §clipboard.transfer; 30 §6 |
| N10 | SSH alias ensure/remove has one definition in 50 and use notes in 70; params include flattened identity, optional path and Include installation; macOS uses a port-22 relay | 50 §guest.sshAlias.ensure/remove; 70 §1.3; alias-key choice stays 50 Q12 |
| N11 | The sole job contract is 05 #job-contract: six prefixed job spaces, separate gate `id: u64`, separate transport `operationId`; old domain cancels are removed; canonical cancellation takes jobId (95 §3) | 05 §4.2 E/F; 10 §operations.list/cancel |
| N12 | `files.list` is the Files page; `guest.files.*` is programmatic account access, including list/read/write/remove/watch | 50 §files.*; 70 §2.1; 50 Q15's resolved subpart |
| N13 | Update handoff is prepare → saved-engine shutdown → installer → restart/resume; abort resumes saved computers; no separate `updates.install` (95 A-6) | 05 §6; 60 §5.2, OQ 9 |
| N14 | `settings.flush` is retained as a canonical method | 60 §settings.flush; 05 §9.1 |
| N15 | All current event names belong to 05's catalogue; former progress/watch names redirect there; `events.subscribe` carries topics | 05 §4.2 D/E; 10 §12.2 |
| N16 | Per-computer addressing is flattened `computerId` + `deviceId?`; `silo-remote:…` is a Tauri presentation key; clients talk only to their local engine, which routes remote calls (95 A-3) | 10 §0.2; 60 OQ 3 |
| N17 | Wire error codes are snake_case; existing list or explicitly pending extension, never Rust variant spellings on the wire | 05 §4.1; 10 §0.3; 30 OQ 7; 70 Conventions |
| N18 | `engine.handshake` owns version/capability negotiation; the new wire uses `engine.handshake`; old `handshake` is source evidence (95 §3) | 05 §engine.handshake; 60 §1.5 |
| N19 | `computers.forceStop` is macOS-only; `computers.launch` is shared launch status; `guest.exec` has one shape owned by 70 | 10 §computers.forceStop, §12.1; 30 §7/§9; 70 §guest.exec |
| N20 | `repositories` stays on computer rows, with `push.*` ownership and `push.repositories` as the domain read | 10 §1.4; 50 §push.repositories; 50 Q16 resolved |

Historical redirected names, fields/settings, source filenames and domain wildcards are not extra methods. Existing bridge and cancellation command names are mapped to canonical contracts in §1; **no alias or compatibility dispatch is retained** (95 §3). No screen lock or engine recorder methods are specified (95 A-8/A-9); proof is guest/Fjord orchestration. `notifications.list` is now a canonical NEW read (95 A-27). `updates.install` is not a separate method: engine updates use save/shutdown/replace/resume (95 A-6; 05 §6). Engine terminal launch and onboarding-draft commands are removed from the API; clients implement their own behavior through canonical methods (95 A-22/A-5; 60 §§1–2).
### 2.2 Events, jobs and errors

- **Events:** all current API event uses resolve to the **26-row catalogue**, 05 §4.2 D. Viewer-close state remains in its viewer connection lifecycle; 95 A-4 settles sequenced state/event delivery, without choosing an extra viewer-close event (40 OQ4). UI-only emitted names are §1.3. The catalogue remains the one definition; this file maps source emissions and does not define another event catalogue.
- **Jobs:** all **29 job methods** in §3 use 05 #job-contract. `setup:<requestId>` is Linux create/configuration/delete/retry; `transfer:<transferId>` is upload/download; `push:<operationId>` is Host Push; `exports:<BackupState.operationId>` is export/import; `inspect:<requestId>` is inspection; `job:<decimal counter>` is other jobs, including macOS work and guest exec. `OperationEntry.id` remains a `u64` gate admission with NEW optional `jobId`; transport `operationId` is not a job id (05 §4.2 E items 1–2). Remote jobs are addressed on the executing engine with `deviceId` and its `jobId` (05 §4.2 E item 6; 05 OQ 22).
- **Cancellation:** commands that return cancellation as errors finish with `error.code: cancelled`; existing transfer cancellation stays `{status: cancelled}` in `result` (05 §4.2 E item 5/F; `transfer.rs:83-101`). Only canonical `operations.cancel {jobId}` remains; old cancellation commands are source evidence, not callable aliases (95 §3; 05 §4.2 F). Cancel log exports one at a time by job (95 A-30); outcomes are saved to disk, survive engine restarts, and are dropped after a client acknowledges showing them with `operations.job.acknowledge`; unknown cancellation returns `not_found` (95 §3, overriding A-25; 05 #job-contract). Migration runs only at launch; its observable completion/reconnect ordering remains research (95 §3; 20 OQ11).
- **Existing error codes:** `update_in_progress`, `unsupported_remote_operation`, `cancelled`, `already_queued`, `busy`, `not_found`, `incompatible_version`, `internal` (8; `src-tauri/src/bridge_error.rs:4-15`; 05 §4.1).
- **Pending codes:** `not_running`, `open_ssh_missing`, `include_not_writable`, `account_not_migrated`, `timed_out`, `output_too_large`, `stdin_closed`, `permission_denied`, `not_a_file`, `exists`, `changed` (70 Conventions), plus `running_limit`, `needs_personalizing`, `setup_incomplete`, `screen_sharing_unavailable` (30 OQ 7). These **15 distinct codes** are required NEW extensions by 95 A-10, with fixtures; until implemented in Silo, existing String errors map to `internal` (`bridge_error.rs:104-108`; §4 A-10). Internal `NotCancellable`/other Rust variants and macOS `BUSY`/`NOT_READY`/`CANCELLED` message constants are not wire codes (10 §0.3; 20 Shared facts; 30 Conventions).

### 2.3 Mechanical fixes applied during this audit

| File and section | Fix | Evidence for the canonical result |
| --- | --- | --- |
| 10 §operations.cancel | Qualify cancelled-error completion with the existing transfer-data exception | 05 §4.2 E item 5/F; `transfer.rs:83-101` |
| 10 §13 `device_snapshot` row | Replace stale former-name prose with `computers.list`; apply local-engine routing (95 A-3) | 10 §2; 60 §1.7/OQ 3 |
| 30 §6; 40 §clipboard.transfer | State one owner (40), with 30 supplying the macOS adapter | 40 method's Platforms: both; 30 §6 |
| 30 §10 | Replace stale `computerUse.approval.set`; point Files/network/export rows to already specified NEW macOS extensions; mark credential mechanism pending | 40 §computerUse.approval; 50 macOS parity tables/Q5–Q6; 20 §1.5/§2.1 |
| 40 §computerUse.state | Replace stale receipt-reference name with current `computerUse.state` | 30 §10; 40 §4 |
| 50/70 §guest.sshAlias.* | Keep full ensure/remove definitions in 50; move remove's params/result/semantics there; retain alias character/repeat-call/transport rules; turn 70 entries into cited Fjord-use notes | 50 declares domain ownership; 70 §1.3 Router requirement; 00 Shared domains |
| 50 §files.upload | Remove stale claim that transfer cancellation still needs reconciliation | 05 §4.2 E item 5/F explicitly preserve cancelled result data |
| 50 Q16; 60 OQ 2 | Mark repository placement and Tauri/engine coexistence resolved | 10 §1.4; 50 §push.repositories; 00 What was decided; 05 §5.2 |
| 05 §4.2 F log-export row | Replace module-wide cancellation with per-job cancellation (NEW, 95 A-30) | 10 Q5; `log_export.rs:15-25`, `:73-78` |

The catalogue now has 26 events, including NEW `connections.devices.changed` (95 A-4; 05 catalogue; 60 `connections.devices.health`). Behavioral choices are applied from 95, while mechanisms not selected or sourced remain in §4 B/C. Every source question settled by 95 carries a DECIDED marker in 05–70; a retained mechanism question does not reopen the owner requirement.
### 2.4 Applied behavioral findings retained in current sections

These duties have no additional registered command; they are now specified as engine behavior rather than reopened as missing API methods. Each row names the current section and code seam (compare the historical findings in 91 §M1–M3/P1–P7/C1/D7).

| Current behavior | Current specification | Code source |
| --- | --- | --- |
| Unused ChatGPT versions: gated collection and 120 s retry | 20 §Engine behaviour: unused ChatGPT app versions are removed | `src-tauri/src/chatgpt_app.rs:1842-1922`, `:2027-2128` |
| Automatic ChatGPT preparation: start delay, backoff, wake, single worker and lowered priority | 20 §Engine behaviour: automatic ChatGPT app preparation | `src-tauri/src/chatgpt_app/auto.rs:13-152`; `chatgpt_app.rs:2173-2238` |
| Issued GitHub token ledger and independent retirement sweep | 50 §github.* What exists, retiring issued tokens through a ledger | `src-tauri/src/github.rs:1189-1340`, `:2125-2143`, `:2804-2827` |
| Private publishing cache: inherited lock, crash marker, discard/retention and budget | 50 §push.start, private publishing cache | `src-tauri/src/host_push_cache.rs:17`, `:92-178`, `:202-298`; `host_push.rs:1150-1156` |
| LFS transfer/retry before ref publication | 50 §push.start Semantics | `src-tauri/src/host_push.rs:959-1002`, `:1041-1059` |
| Sensitive-output filtering and damaged/oversized record handling, including exports | 10 §logs.query, §logs.export | `src-tauri/src/runtime_logs.rs:374-377`, `:810-882`; `src-tauri/src/log_export.rs:162-192` |
| Working-account preparation, with legacy conversion restricted to launch (95 §3) | 10 §Engine behaviour: working-account preparation; launch-conversion probe B-34 | `src-tauri/src/working_account.rs:3-8`, `:58-65`; `src-tauri/guest/working-account.py:124-219`, `:272-285` |
| Alias folder validation/checks, Include failure and local SSH probe | 50 §guest.sshAlias.ensure; 70 §1.3 use notes | `src-tauri/src/editor.rs:32-99`, `:154-166`, `:409-505` |
| Secrets startup removal/reconciliation/revocation recovery | 50 §secrets.* What exists, Startup recovery | `src-tauri/src/secrets.rs:903-933`, `:524-646`, `:752-780` |
| Protocol equality, not application-release equality | 05 §4.2 G; 60 §1.1/§1.6 and OQ 9 | `src-tauri/src/remote.rs:34-36`, `:2161-2184` |
| Read-triggered passes preserved with NEW autonomous engine timers (95 A-26) | 05 §read-triggered maintenance/OQ 23; 10 §13/Q12; 50 revocations/network repair | `src-tauri/src/runtime.rs:2663-2701`, `:3007-3031`; `src-tauri/src/network.rs:827-836` |

### 2.5 Classification and amendment corrections

Method status describes implemented behavior, not whether the canonical spelling appears in v5. The owning Status lines cite the current command/bridge and identify each missing part; §3 counts the four classes separately (00 §The rules: zero guesses). Dropping aliases requires callers to rename their calls, not rewriting existing domain behavior (95 §3).

| Stale statement | Correct contract | Authority |
| --- | --- | --- |
| Re-exposure or a renamed method is NEW; platform additions do not change its primary class | Existing behavior is EXISTS or EXISTS (renamed); a required missing part makes the method EXTENDED | 00 status definitions; §3 owning-section citations |
| Changed names “remain v5 compatibility aliases” (§1.4), or a current source name is a callable wire alias | Canonical names only; historical names identify source implementations | 95 §3; §1.4 and §§2.1–2.2 |
| Linux hosts run headlessly; Linux service/package update paths remain planned | Hosts/controllers are Macs only; Linux-host paths and B-9/B-26 are retired | 95 §3; 00 scope; README; 05 §3.7 |
| Job results expire after an hour or vanish on restart | Completed outcomes persist on disk across restarts until acknowledgement after showing | 95 §3; 05 job contract |
| macOS contention is refused | Work waits in the operation queue with “Waiting…” and Cancel; admitted state preconditions remain | 95 §3; 10 §6; 30 conventions |
| Quit stops computers, or two-choice confirmation defines the client contract | Fjord asks Cancel / Keep running / Stop and quit; client updates/crashes never stop computers | 95 A-2; 05 §6; 60 §6 |
| One GUI driver requires a screen lock; proof needs an engine recorder | No input lease; recording runs inside the guest with no VM window required | 95 A-8/A-9; 00 scope; 40/70 proof |
| README has 143 methods, 25 events and 37 open decisions, omits 92/95/probes | Current §3 counts, 26 events, 0 open decisions; complete file list and binding-decision reading order | §3–§4; 95; README |

## 3. Unified method index

Sort order is domain, then full method name. **EXISTS** means the same name and behavior exist today. **EXISTS (renamed)** means the behavior exists under a cited current Tauri/bridge name and implementation re-exposes and renames it. **EXTENDED** means a cited existing implementation plus a named, justified NEW part. **NEW** means no current implementation provides the behavior and the owning section cites its requirement. Each canonical method is counted once; EXTENDED takes precedence when a required platform or behavior is missing. New naming, transport framing, addressing or extraction from Tauri alone do not mean NEW behavior (00 §The rules: zero guesses; 95 §3). `desktop.connect` is counted but engine-to-engine only (40 §desktop.connect). UI-only operations, retired source names, catalogue events and pending alternatives are excluded (§1–2).

Platforms name the computer kind unless the row says host-level. “macOS NEW” means a specified extension whose mechanism or fields can still depend on §4; it does not assert that Silo already implements it (50 macOS parity tables; 20 §1.5; 30 §10).

| Method | Kind | Platforms | Status | Owning section |
| --- | --- | --- | --- | --- |
| `activity.setup.read` | query | both; platform differences in owning section | EXTENDED | [10 §activity.setup.read](10-computers-lifecycle.md#activitysetupread) |
| `checkpoints.abandonRestore` | job | both; NEW macOS adapter/projection (20) | EXTENDED | [20 §checkpoints.abandonRestore](20-checkpoints-exports-preparation.md#125-checkpointsabandonrestore) |
| `checkpoints.create` | job | both | EXTENDED | [20 §checkpoints.create](20-checkpoints-exports-preparation.md#121-checkpointscreate) |
| `checkpoints.delete` | job | both | EXTENDED | [20 §checkpoints.delete](20-checkpoints-exports-preparation.md#124-checkpointsdelete) |
| `checkpoints.fork` | job | both | EXTENDED | [20 §checkpoints.fork](20-checkpoints-exports-preparation.md#123-checkpointsfork) |
| `checkpoints.restore` | job | both | EXTENDED | [20 §checkpoints.restore](20-checkpoints-exports-preparation.md#122-checkpointsrestore) |
| `checkpoints.usage` | query | both; NEW macOS adapter/projection (20) | EXTENDED | [20 §checkpoints.usage](20-checkpoints-exports-preparation.md#126-checkpointsusage) |
| `clipboard.read` | command | macOS computer. The Linux parity belongs to the desktop section | EXTENDED | [30 §clipboard.read](30-macos-computers.md#clipboardread--clipboardwrite-macos-computer) |
| `clipboard.transfer` | command | Linux and macOS computers on Mac hosts only (95 §3) | EXTENDED | [40 §clipboard.transfer](40-desktop-display-computer-use.md#clipboardtransfer-linux-viewer-part) |
| `clipboard.write` | command | macOS computer. The Linux parity belongs to the desktop section | EXTENDED | [30 §clipboard.write](30-macos-computers.md#clipboardread--clipboardwrite-macos-computer) |
| `computerUse.approval` | command | both; platform differences in owning section | EXTENDED | [40 §computerUse.approval](40-desktop-display-computer-use.md#computeruseapproval) |
| `computerUse.setup` | job | Linux and macOS computers; Mac hosts only (95 §3); macOS platform extension is NEW (95 A-19) | EXTENDED | [40 §computerUse.setup](40-desktop-display-computer-use.md#computerusesetup) |
| `computerUse.state` | query | Linux and macOS computers on Mac hosts only (95 §3). Linux EXISTS; macOS is NEW | EXTENDED | [40 §computerUse.state](40-desktop-display-computer-use.md#computerusestate) |
| `computers.configuration.change` | job | both; NEW stopped-macOS CPU/memory editing (95 A-12/A-19) | EXTENDED | [10 §computers.configuration.change](10-computers-lifecycle.md#computersconfigurationchange) |
| `computers.configuration.read` | query | both; platform differences in owning section | EXTENDED | [10 §computers.configuration.read](10-computers-lifecycle.md#computersconfigurationread) |
| `computers.configuration.retry` | job | both; platform differences in owning section | EXTENDED | [10 §computers.configuration.retry](10-computers-lifecycle.md#computersconfigurationretry) |
| `computers.create` | job | both | EXTENDED | [10 §computers.create](10-computers-lifecycle.md#computerscreate) |
| `computers.creation.skipComputerUseWait` | command | both; platform differences in owning section | EXTENDED | [10 §computers.creation.skipComputerUseWait](10-computers-lifecycle.md#computerscreationskipcomputerusewait) |
| `computers.delete` | job | both | EXTENDED | [10 §computers.delete](10-computers-lifecycle.md#computersdelete) |
| `computers.dismissError` | command | both; platform differences in owning section | EXTENDED | [10 §computers.dismissError](10-computers-lifecycle.md#computersdismisserror) |
| `computers.forceStop` | command | macOS computers only (10 §computers.forceStop) | EXTENDED | [10 §computers.forceStop](10-computers-lifecycle.md#computersforcestop) |
| `computers.identities.configure` | job | both; platform differences in owning section | EXTENDED | [10 §computers.identities.configure](10-computers-lifecycle.md#computersidentitiesconfigure) |
| `computers.identities.verify` | query | both; platform differences in owning section | EXTENDED | [10 §computers.identities.verify](10-computers-lifecycle.md#computersidentitiesverify) |
| `computers.launch` | query | both computer kinds; host macOS only (95 §3) | EXTENDED | [10 §computers.launch](10-computers-lifecycle.md#121-computerslaunch) |
| `computers.list` | query | both; platform differences in owning section | EXTENDED | [10 §computers.list](10-computers-lifecycle.md#computerslist) |
| `computers.restart` | job | both; platform differences in owning section | EXTENDED | [10 §computers.restart](10-computers-lifecycle.md#computersrestart) |
| `computers.shell` | query | both; platform differences in owning section | EXTENDED | [10 §computers.shell](10-computers-lifecycle.md#computersshell) |
| `computers.start` | job | both | EXTENDED | [10 §computers.start](10-computers-lifecycle.md#computersstart) |
| `computers.stop` | job | both | EXTENDED | [10 §computers.stop](10-computers-lifecycle.md#computersstop) |
| `connections.devices.connect` | command | host-level, Mac only (95 §3) | EXISTS (renamed) | [60 §connections.devices.connect](60-connections-settings-services.md#connectionsdevicesconnect) |
| `connections.devices.health` | query | macOS hosts only; controller's local engine | EXTENDED | [60 §connections.devices.health](60-connections-settings-services.md#connectionsdeviceshealth) |
| `connections.devices.list` | query | host-level, Mac only (95 §3) | EXISTS (renamed) | [60 §connections.devices.list](60-connections-settings-services.md#connectionsdeviceslist) |
| `connections.devices.remove` | command | Mac controllers and owners | EXTENDED | [60 §connections.devices.remove](60-connections-settings-services.md#connectionsdevicesremove) |
| `connections.keys.revoke` | command | macOS hosts only; runs on the owner | NEW | [60 §connections.keys.revoke](60-connections-settings-services.md#connectionskeysrevoke) |
| `connections.setEnabled` | command | host-level, Mac only (95 §3) | EXISTS (renamed) | [60 §connections.setEnabled](60-connections-settings-services.md#connectionssetenabled) |
| `connections.ssh.authorizationCommand` | query | host-level, Mac only (95 §3) | EXISTS (renamed) | [60 §connections.ssh.authorizationCommand](60-connections-settings-services.md#connectionssshauthorizationcommand) |
| `connections.ssh.keySetupCommand` | command | host-level, Mac only (95 §3) | EXISTS (renamed) | [60 §connections.ssh.keySetupCommand](60-connections-settings-services.md#connectionssshkeysetupcommand) |
| `connections.status` | query | macOS hosts only | EXISTS (renamed) | [60 §connections.status](60-connections-settings-services.md#connectionsstatus) |
| `desktop.action` | job | Linux and macOS computers; Mac hosts only (95 §3); macOS platform extension is NEW (95 A-19) | EXTENDED | [40 §desktop.action](40-desktop-display-computer-use.md#desktopaction) |
| `desktop.connect` | query | Linux and macOS computers; Mac hosts only (95 §3); macOS platform extension is NEW (95 A-19) | EXTENDED | [40 §desktop.connect](40-desktop-display-computer-use.md#desktopconnect-engine-internal) |
| `desktop.status` | query | Linux and macOS computers; Mac hosts only (95 §3); macOS platform extension is NEW (95 A-19) | EXTENDED | [40 §desktop.status](40-desktop-display-computer-use.md#desktopstatus) |
| `device.dependencies` | query | Mac hosts only (95 §3), serving both computer kinds | EXISTS (renamed) | [20 §device.dependencies](20-checkpoints-exports-preparation.md#425-devicedependencies) |
| `device.facts` | query | macOS hosts only; local or remote owner | EXTENDED | [60 §device.facts](60-connections-settings-services.md#devicefacts) |
| `display.close` | command | macOS computer | EXTENDED | [30 §display.close](30-macos-computers.md#displayclose-macos-computer-local) |
| `display.native.attach` | stream | both; platform differences in owning section | NEW | [40 §display.native.attach](40-desktop-display-computer-use.md#displaynativeattach) |
| `display.show` | command | macOS computers; local engine window or remote Screen Sharing (30 §5) | EXTENDED | [30 §display.show](30-macos-computers.md#displayshow-macos-computer-local) |
| `display.viewer.audio.set` | command | Linux and macOS computers; Mac hosts only (95 §3); macOS platform extension is NEW (95 A-19) | EXTENDED | [40 §display.viewer.audio.set](40-desktop-display-computer-use.md#displayvieweraudioset) |
| `display.viewer.close` | command | Linux and macOS computers; Mac hosts only (95 §3); macOS platform extension is NEW (95 A-19) | EXTENDED | [40 §display.viewer.close](40-desktop-display-computer-use.md#displayviewerclose) |
| `display.viewer.open` | command | Linux and macOS computers; Mac hosts only (95 §3); macOS platform extension is NEW (95 A-19) | EXTENDED | [40 §display.viewer.open](40-desktop-display-computer-use.md#displayvieweropen) |
| `display.viewer.screen.reset` | command | Linux and macOS computers; Mac hosts only (95 §3); macOS platform extension is NEW (95 A-19) | EXTENDED | [40 §display.viewer.screen.reset](40-desktop-display-computer-use.md#displayviewerscreenreset) |
| `display.viewer.sound.cancel` | command | Linux and macOS computers; Mac hosts only (95 §3); macOS platform extension is NEW (95 A-19) | EXTENDED | [40 §display.viewer.sound.cancel](40-desktop-display-computer-use.md#displayviewersoundcancel) |
| `display.viewer.sound.check` | query | Linux and macOS computers; Mac hosts only (95 §3); macOS platform extension is NEW (95 A-19) | EXTENDED | [40 §display.viewer.sound.check](40-desktop-display-computer-use.md#displayviewersoundcheck) |
| `editor.command` | command | Linux and macOS computers; Mac hosts only (95 §3); macOS platform extension is NEW, justified by 95 A-19 | EXTENDED | [50 §editor.command](50-access-network-files.md#editorcommand) |
| `editor.includeNotice` | query | host-level; Mac controller SSH Include notice (50) | EXISTS (renamed) | [50 §editor.includeNotice](50-access-network-files.md#editorincludenotice) |
| `engine.disconnect` | command | both computer kinds; Mac hosts, local clients only | NEW | [05 §engine.disconnect](05-engine-architecture.md#enginedisconnect) |
| `engine.handshake` | query | both computer kinds; Mac hosts only (95 §3 Linux hosts dropped) | EXTENDED | [05 §engine.handshake](05-engine-architecture.md#enginehandshake) |
| `engine.shutdown` | job | both computer kinds; Mac hosts only (95 §3 Linux hosts dropped) | EXTENDED | [05 §engine.shutdown](05-engine-architecture.md#engineshutdown) |
| `engine.state` | query | both computer kinds; Mac hosts only (95 §3 Linux hosts dropped) | EXTENDED | [05 §engine.state](05-engine-architecture.md#enginestate) |
| `engine.update.abort` | command | both computer kinds; Mac hosts only (95 §3 Linux hosts dropped) | EXTENDED | [05 §engine.update.abort](05-engine-architecture.md#engineupdateabort) |
| `engine.update.prepare` | job | both computer kinds; Mac hosts only (95 §3 Linux hosts dropped) | EXTENDED | [05 §engine.update.prepare](05-engine-architecture.md#engineupdateprepare) |
| `events.subscribe` | subscription | both computer kinds; Mac hosts only (95 §3 Linux hosts dropped) | EXTENDED | [05 §events.subscribe](05-engine-architecture.md#eventssubscribe) |
| `events.unsubscribe` | command | both computer kinds; Mac hosts only (95 §3 Linux hosts dropped) | EXTENDED | [05 §events.unsubscribe](05-engine-architecture.md#eventsunsubscribe) |
| `exports.acknowledge` | command | both, local and remote; macOS NEW, justified by 95 A-19; archive mechanism remains Q4 | EXTENDED | [20 §exports.acknowledge](20-checkpoints-exports-preparation.md#229-exportsacknowledge) |
| `exports.create` | job | both, local and remote; macOS NEW, justified by 95 A-19; archive mechanism remains Q4 | EXTENDED | [20 §exports.create](20-checkpoints-exports-preparation.md#225-exportscreate-export) |
| `exports.destination.set` | command | both, local and remote; macOS NEW, justified by 95 A-19; archive mechanism remains Q4 | EXTENDED | [20 §exports.destination.set](20-checkpoints-exports-preparation.md#222-exportsdestinationset) |
| `exports.dismiss` | command | both, local and remote; macOS NEW, justified by 95 A-19; archive mechanism remains Q4 | EXTENDED | [20 §exports.dismiss](20-checkpoints-exports-preparation.md#228-exportsdismiss) |
| `exports.import` | job | both, local and remote; macOS NEW, justified by 95 A-19; archive mechanism remains Q4 | EXTENDED | [20 §exports.import](20-checkpoints-exports-preparation.md#226-exportsimport) |
| `exports.inspect` | job | both, local and remote; macOS NEW, justified by 95 A-19; archive mechanism remains Q4 | EXTENDED | [20 §exports.inspect](20-checkpoints-exports-preparation.md#223-exportsinspect) |
| `exports.state` | query | both, local and remote. macOS support is NEW, justified by 95 A-19; archive mechanism remains Q4 | EXTENDED | [20 §exports.state](20-checkpoints-exports-preparation.md#221-exportsstate) |
| `files.download` | job | Linux and macOS computers; Mac hosts only (95 §3); macOS extension NEW (95 A-19) | EXTENDED | [50 §files.download](50-access-network-files.md#filesdownload) |
| `files.list` | query | both; platform differences in owning section | EXTENDED | [50 §files.list](50-access-network-files.md#fileslist) |
| `files.upload` | job | both; platform differences in owning section | EXTENDED | [50 §files.upload](50-access-network-files.md#filesupload) |
| `github.access.set` | command | Linux and macOS computers; Mac hosts only (95 §3); macOS extension NEW (95 A-19) | EXTENDED | [50 §github.access.set](50-access-network-files.md#githubaccessset) |
| `github.configuration.retry` | command | Linux and macOS computers; Mac hosts only (95 §3); macOS extension NEW (95 A-19) | EXTENDED | [50 §github.configuration.retry](50-access-network-files.md#githubconfigurationretry) |
| `github.configuration.save` | command | Linux and macOS computers; Mac hosts only (95 §3); macOS extension NEW (95 A-19) | EXTENDED | [50 §github.configuration.save](50-access-network-files.md#githubconfigurationsave) |
| `github.connect` | job | both; platform differences in owning section | EXTENDED | [50 §github.connect](50-access-network-files.md#githubconnect) |
| `github.connect.callback` | stream | Linux and macOS computers; Mac hosts only (95 §3); host-level callback listener | NEW | [50 §github.connect.callback](50-access-network-files.md#githubconnectcallback) |
| `github.connect.reopen` | command | Linux and macOS computers; Mac hosts only (95 §3); macOS extension NEW (95 A-19) | EXTENDED | [50 §github.connect.reopen](50-access-network-files.md#githubconnectreopen) |
| `github.disconnect` | command | Linux and macOS computers; Mac hosts only (95 §3); macOS extension NEW (95 A-19) | EXTENDED | [50 §github.disconnect](50-access-network-files.md#githubdisconnect) |
| `github.personalToken.remove` | command | Linux and macOS computers; Mac hosts only (95 §3); macOS extension NEW (95 A-19) | EXTENDED | [50 §github.personalToken.remove](50-access-network-files.md#githubpersonaltokenremove) |
| `github.personalToken.save` | command | Linux and macOS computers; Mac hosts only (95 §3); macOS extension NEW (95 A-19) | EXTENDED | [50 §github.personalToken.save](50-access-network-files.md#githubpersonaltokensave) |
| `github.repositories.manage` | command | Linux and macOS computers; Mac hosts only (95 §3); macOS extension NEW (95 A-19) | EXTENDED | [50 §github.repositories.manage](50-access-network-files.md#githubrepositoriesmanage) |
| `github.repositories.refresh` | command | Linux and macOS computers; Mac hosts only (95 §3); macOS extension NEW (95 A-19) | EXTENDED | [50 §github.repositories.refresh](50-access-network-files.md#githubrepositoriesrefresh) |
| `github.state` | query | both; platform differences in owning section | EXTENDED | [50 §github.state](50-access-network-files.md#githubstate) |
| `guest.account` | query | both | EXTENDED | [70 §guest.account](70-fjord-needs.md#guestaccount) |
| `guest.exec` | command | both | EXTENDED | [70 §guest.exec](70-fjord-needs.md#guestexec) |
| `guest.exec.get` | query | both | NEW | [70 §guest.exec.get](70-fjord-needs.md#guestexecget) |
| `guest.exec.input` | command | both | NEW | [70 §guest.exec.input](70-fjord-needs.md#guestexecinput) |
| `guest.exec.start` | job | both | EXTENDED | [70 §guest.exec.start](70-fjord-needs.md#guestexecstart) |
| `guest.files.list` | query | both | EXTENDED | [70 §guest.files.list](70-fjord-needs.md#guestfileslist) |
| `guest.files.read` | query | both | EXTENDED | [70 §guest.files.read](70-fjord-needs.md#guestfilesread) |
| `guest.files.remove` | command | both | NEW | [70 §guest.files.remove](70-fjord-needs.md#guestfilesremove) |
| `guest.files.watch` | subscription | both | NEW | [70 §guest.files.watch](70-fjord-needs.md#guestfileswatch) |
| `guest.files.write` | command | both | EXTENDED | [70 §guest.files.write](70-fjord-needs.md#guestfileswrite) |
| `guest.prepare` | command | both; platform differences in owning section | EXTENDED | [50 §guest.prepare](50-access-network-files.md#guestprepare) |
| `guest.ssh` | stream | both; platform differences in owning section | EXTENDED | [50 §guest.ssh](50-access-network-files.md#guestssh) |
| `guest.sshAlias.ensure` | command | both; platform differences in owning section | EXTENDED | [50 §guest.sshAlias.ensure](50-access-network-files.md#guestsshaliasensure) |
| `guest.sshAlias.remove` | command | both; platform differences in owning section | NEW | [50 §guest.sshAlias.remove](50-access-network-files.md#guestsshaliasremove) |
| `logs.export` | job | both, local and remote, through `logs.query` | EXTENDED | [10 §logs.export](10-computers-lifecycle.md#logsexport) |
| `logs.query` | query | both | EXTENDED | [10 §logs.query](10-computers-lifecycle.md#logsquery) |
| `macos.display.connect` | query | macOS (Apple silicon host) | EXISTS | [30 §macos.display.connect](30-macos-computers.md#macosdisplayconnect-owner) |
| `macos.display.resize` | command | macOS (Apple silicon host) | EXISTS | [30 §macos.display.resize](30-macos-computers.md#macosdisplayresize-owner) |
| `macos.display.session` | command | macOS computer; controller client reaches only its local engine (95 A-3) | EXTENDED | [30 §macos.display.session](30-macos-computers.md#macosdisplaysession-controller) |
| `macos.display.stream` | stream | macOS (Apple silicon host) | EXISTS | [30 §macos.display.stream](30-macos-computers.md#macosdisplaystream-owner) |
| `macos.setup.retry` | job | macOS computer | EXTENDED | [30 §macos.setup.retry](30-macos-computers.md#macossetupretry) |
| `macos.template.delete` | command | macOS computer host | EXTENDED | [30 §macos.template.delete](30-macos-computers.md#macostemplatedelete) |
| `migration.preUpgradeBackup.acknowledgeNotice` | command | both; platform differences in owning section | EXTENDED | [20 §migration.preUpgradeBackup.acknowledgeNotice](20-checkpoints-exports-preparation.md#327-migrationpreupgradebackupacknowledgenotice) |
| `migration.preUpgradeBackup.delete` | command | both; platform differences in owning section | EXTENDED | [20 §migration.preUpgradeBackup.delete](20-checkpoints-exports-preparation.md#326-migrationpreupgradebackupdelete) |
| `migration.preUpgradeBackup.get` | query | both; platform differences in owning section | EXTENDED | [20 §migration.preUpgradeBackup.get](20-checkpoints-exports-preparation.md#324-migrationpreupgradebackupget) |
| `migration.preUpgradeBackup.measure` | query | both; platform differences in owning section | EXTENDED | [20 §migration.preUpgradeBackup.measure](20-checkpoints-exports-preparation.md#325-migrationpreupgradebackupmeasure) |
| `migration.state` | query | both; platform differences in owning section | EXTENDED | [20 §migration.state](20-checkpoints-exports-preparation.md#321-migrationstate) |
| `network.open` | command | Linux and macOS computers; Mac hosts only (95 §3); macOS extension NEW (95 A-19) | EXTENDED | [50 §network.open](50-access-network-files.md#networkopen) |
| `network.publish` | command | Linux and macOS computers; Mac hosts only (95 §3); macOS extension NEW (95 A-19) | EXTENDED | [50 §network.publish](50-access-network-files.md#networkpublish) |
| `network.state` | query | both; platform differences in owning section | EXTENDED | [50 §network.state](50-access-network-files.md#networkstate) |
| `network.unpublish` | command | Linux and macOS computers; Mac hosts only (95 §3); macOS extension NEW (95 A-19) | EXTENDED | [50 §network.unpublish](50-access-network-files.md#networkunpublish) |
| `notifications.list` | query | macOS hosts only; optional remote owner via local engine | NEW | [60 §notifications.list](60-connections-settings-services.md#notificationslist) |
| `operations.cancel` | command | both; platform differences in owning section | EXTENDED | [10 §operations.cancel](10-computers-lifecycle.md#operationscancel) |
| `operations.job.acknowledge` | command | both computer kinds; Mac hosts, local or remote engine through the local engine | NEW | [05 §operations.job.acknowledge](05-engine-architecture.md#operationsjobacknowledge) |
| `operations.job.get` | query | both computer kinds; Mac hosts, local or remote engine through the local engine | NEW | [05 §operations.job.get](05-engine-architecture.md#operationsjobget) |
| `operations.list` | query | both; platform differences in owning section | EXTENDED | [10 §operations.list](10-computers-lifecycle.md#operationslist) |
| `preparation.chatgpt.retry` | command | both; platform differences in owning section | EXTENDED | [20 §preparation.chatgpt.retry](20-checkpoints-exports-preparation.md#424-preparationchatgptretry) |
| `preparation.chatgpt.status` | query | both; platform differences in owning section | EXTENDED | [20 §preparation.chatgpt.status](20-checkpoints-exports-preparation.md#423-preparationchatgptstatus) |
| `preparation.retry` | command | both; platform differences in owning section | EXTENDED | [20 §preparation.retry](20-checkpoints-exports-preparation.md#422-preparationretry) |
| `preparation.status` | query | both; platform differences in owning section | EXTENDED | [20 §preparation.status](20-checkpoints-exports-preparation.md#421-preparationstatus) |
| `push.dismiss` | command | Linux and macOS computers; Mac hosts only (95 §3); macOS extension NEW (95 A-19) | EXTENDED | [50 §push.dismiss](50-access-network-files.md#pushdismiss) |
| `push.repositories` | query | both; platform differences in owning section | EXTENDED | [50 §push.repositories](50-access-network-files.md#pushrepositories) |
| `push.start` | job | both; platform differences in owning section | EXTENDED | [50 §push.start](50-access-network-files.md#pushstart) |
| `push.status` | query | Linux and macOS computers; Mac hosts only (95 §3); macOS extension NEW (95 A-19) | EXISTS (renamed) | [50 §push.status](50-access-network-files.md#pushstatus) |
| `secrets.list` | query | both; platform differences in owning section | EXTENDED | [50 §secrets.list](50-access-network-files.md#secretslist) |
| `secrets.remove` | command | Linux and macOS computers; Mac hosts only (95 §3); macOS extension NEW (95 A-19) | EXTENDED | [50 §secrets.remove](50-access-network-files.md#secretsremove) |
| `secrets.retry` | command | Linux and macOS computers; Mac hosts only (95 §3); macOS extension NEW (95 A-19) | EXTENDED | [50 §secrets.retry](50-access-network-files.md#secretsretry) |
| `secrets.save` | command | Linux and macOS computers; Mac hosts only (95 §3); macOS extension NEW (95 A-19) | EXTENDED | [50 §secrets.save](50-access-network-files.md#secretssave) |
| `settings.flush` | command | host-level, Mac only (95 §3) | EXISTS (renamed) | [60 §settings.flush](60-connections-settings-services.md#settingsflush) |
| `settings.read` | query | host-level, Mac only (95 §3) | EXTENDED | [60 §settings.read](60-connections-settings-services.md#settingsread) |
| `settings.update` | command | host-level, Mac only (95 §3) | EXTENDED | [60 §settings.update](60-connections-settings-services.md#settingsupdate) |
| `sshAccess.connection` | command | both; platform differences in owning section | EXTENDED | [50 §sshAccess.connection](50-access-network-files.md#sshaccessconnection) |
| `sshAccess.save` | command | Linux and macOS computers; Mac hosts only (95 §3); macOS extension NEW (95 A-19) | EXTENDED | [50 §sshAccess.save](50-access-network-files.md#sshaccesssave) |
| `sshAccess.state` | query | both; platform differences in owning section | EXTENDED | [50 §sshAccess.state](50-access-network-files.md#sshaccessstate) |
| `storage.read` | query | both; platform differences in owning section | EXTENDED | [10 §storage.read](10-computers-lifecycle.md#storageread) |
| `storage.reclaim` | job | both; platform differences in owning section | EXTENDED | [10 §storage.reclaim](10-computers-lifecycle.md#storagereclaim) |
| `terminal.command` | query | both; platform differences in owning section | EXTENDED | [50 §terminal.command](50-access-network-files.md#terminalcommand) |
| `updates.check` | command | host-level, Mac only (95 §3) | EXTENDED | [60 §updates.check](60-connections-settings-services.md#updatescheck) |
| `updates.download` | job | host-level, Mac only (95 §3) | EXTENDED | [60 §updates.download](60-connections-settings-services.md#updatesdownload) |
| `updates.focused` | command | host-level, Mac only (95 §3) | EXTENDED | [60 §updates.focused](60-connections-settings-services.md#updatesfocused) |
| `updates.setAutomaticChecks` | command | host-level, Mac only (95 §3) | EXTENDED | [60 §updates.setAutomaticChecks](60-connections-settings-services.md#updatessetautomaticchecks) |
| `updates.state` | query | host-level, Mac only (95 §3) | EXTENDED | [60 §updates.state](60-connections-settings-services.md#updatesstate) |

**Index totals:** 146 = 3 EXISTS + 10 EXISTS (renamed) + 121 EXTENDED + 12 NEW. Kinds: 46 query, 65 command, 29 job, 4 stream, 2 subscription (the preceding cited rows). Canonical Status follows the owning method's primary Status; a required platform extension makes the method EXTENDED and does not add a duplicate name.

| Domain | EXISTS | EXISTS (renamed) | EXTENDED | NEW | Total |
| --- | ---: | ---: | ---: | ---: | ---: |
| `activity.*` | 0 | 0 | 1 | 0 | 1 |
| `checkpoints.*` | 0 | 0 | 6 | 0 | 6 |
| `clipboard.*` | 0 | 0 | 3 | 0 | 3 |
| `computerUse.*` | 0 | 0 | 3 | 0 | 3 |
| `computers.*` | 0 | 0 | 16 | 0 | 16 |
| `connections.*` | 0 | 6 | 2 | 1 | 9 |
| `desktop.*` | 0 | 0 | 3 | 0 | 3 |
| `device.*` | 0 | 1 | 1 | 0 | 2 |
| `display.*` | 0 | 0 | 8 | 1 | 9 |
| `editor.*` | 0 | 1 | 1 | 0 | 2 |
| `engine.*` | 0 | 0 | 5 | 1 | 6 |
| `events.*` | 0 | 0 | 2 | 0 | 2 |
| `exports.*` | 0 | 0 | 7 | 0 | 7 |
| `files.*` | 0 | 0 | 3 | 0 | 3 |
| `github.*` | 0 | 0 | 11 | 1 | 12 |
| `guest.*` | 0 | 0 | 9 | 5 | 14 |
| `logs.*` | 0 | 0 | 2 | 0 | 2 |
| `macos.*` | 3 | 0 | 3 | 0 | 6 |
| `migration.*` | 0 | 0 | 5 | 0 | 5 |
| `network.*` | 0 | 0 | 4 | 0 | 4 |
| `notifications.*` | 0 | 0 | 0 | 1 | 1 |
| `operations.*` | 0 | 0 | 2 | 2 | 4 |
| `preparation.*` | 0 | 0 | 4 | 0 | 4 |
| `push.*` | 0 | 1 | 3 | 0 | 4 |
| `secrets.*` | 0 | 0 | 4 | 0 | 4 |
| `settings.*` | 0 | 1 | 2 | 0 | 3 |
| `sshAccess.*` | 0 | 0 | 3 | 0 | 3 |
| `storage.*` | 0 | 0 | 2 | 0 | 2 |
| `terminal.*` | 0 | 0 | 1 | 0 | 1 |
| `updates.*` | 0 | 0 | 5 | 0 | 5 |
| **Total** | **3** | **10** | **121** | **12** | **146** |

## 4. Consolidated Open questions

Question citations mean the final Open questions section in each file: **05 §10**, **10 §14**, **20 §6**, **30 §12**, **40 Open questions**, **50 Open questions**, **60 §9**, **70 Open questions**. Every entry below points to its originating question number; body-section citations supplement those numbers. IDs remain stable for references already in 05–70. Priority is this audit's dependency ordering, with its reason stated, not an owner-approved implementation schedule.

There are **126 numbered source entries** (05:25, 10:13, 20:13, 30:16, 40:15, 50:16, 60:13, 70:15), preserving every original question and adding explicit implementation probes. **0 owner decisions remain open**: all 37 A entries are decided by [95](95-decisions.md). DECIDED source entries can retain an unsourced mechanism or live-test remainder; those are mapped in (B)/(C), not counted as owner decisions. The unnumbered 50 D-cred umbrella repeats its source questions and adds no independent entry (50 Open questions).

### (A) Owner decisions, all decided on 2026-10-13

All 37 entries are DECIDED by [95 Parts 1–2](95-decisions.md), as amended by its later [§3 no-legacy rule](95-decisions.md#3-amendments-owner-2026-10-13-later); **0 open owner decisions**. Historical priority numbers and source-question mappings are preserved. A-24 remains an uncounted historical crossreference; it authorizes no compatibility path. A decision settles only what its text says; residual mechanisms and facts are probes/research in (B)/(C).

| Priority | ID | Applied decision | Sources | Application status |
| --- | --- | --- | --- | --- |
| 1 | A-1 | **DECIDED ([95 A-1](95-decisions.md)):** **Fjord is the app people use.** Silo's app is no longer maintained as a product. Silo (the repo) maintains the engine and keeps shipping it in Silo's app, which gets the engine's changes. When both apps are installed on a Mac, only one engine runs. | 05 OQ1/2; 50 Q3; 60 OQ1/2/7 | Contract applied in the cited source sections; unsourced mechanism details remain in (B)/(C). |
| 2 | A-3 | **DECIDED ([95 A-3](95-decisions.md)):** Remote methods go through the controller's local engine. Clients only talk to their local engine. | 60 OQ3 | Contract applied in the cited source sections; unsourced mechanism details remain in (B)/(C). |
| 3 | A-5 | **DECIDED ([95 A-5](95-decisions.md)):** Local clients are authorized by the same OS user (peer euid), like Silo's socket permissions today. Any such client may change settings. Onboarding drafts stay in the client. The viewer cookie is handed to the client. | 05 OQ11/16; 20 OQ10; 40 OQ1; 60 OQ6 | Contract applied in the cited source sections; unsourced mechanism details remain in (B)/(C). |
| 4 | A-7 | **DECIDED ([95 A-7](95-decisions.md)):** A new local socket keeps the v5 framing and adds request ids for multiplexing. The schema is JSON Schema generated from the Rust types, and the Swift `Codable` client is generated from it. | 05 OQ14/15; 05 §4.2 H | Contract applied in the cited source sections; unsourced mechanism details remain in (B)/(C). |
| 5 | A-4 | **DECIDED ([95 A-4](95-decisions.md)):** Events carry the new state plus a sequence number. Subscriber buffers are bounded; after a gap, or on reconnect, the client re-reads. Remote engines push events through a Stream-class bridge method. | 05 OQ12/13/18; 10 Q8; 30 OQ14; 40 OQ4; 50 Q2; 60 OQ4 | Contract applied in the cited source sections; unsourced mechanism details remain in (B)/(C). |
| 6 | A-25 | **DECIDED ([95 A-25](95-decisions.md)):** **Amended by 95 §3:** job outcomes are saved to disk, survive engine restarts, and are dropped once a client acknowledges showing them; NEW `operations.job.acknowledge`. Cancelling an unknown job still returns `not_found`. | 05 OQ19/21/22; 20 OQ8/11; 30 OQ16 | Contract applied in the cited source sections; unsourced mechanism details remain in (B)/(C). |
| 7 | A-2 | **DECIDED ([95 A-2](95-decisions.md)):** **Quit asks when computers are running:** "Quit Fjord? 2 computers are running: dev, linux-1." with **Cancel / Keep running / Stop and quit**. A Fjord update or crash never stops computers. You stop computers from Computers. | 05 OQ17; 10 Q4; 30 OQ15; 60 OQ5 | Contract applied in the cited source sections; unsourced mechanism details remain in (B)/(C). |
| 8 | A-15 | **DECIDED ([95 A-15](95-decisions.md)):** **macOS computers get a host proxy, as on Linux.** Agents only ever see placeholders. Recommended route: reuse MicroSandbox's patched network engine behind a `VZFileHandleNetworkDeviceAttachment` gateway. Its frame rings and poll loop are the public seam (see [92-macos-proxy-research.md](92-macos-proxy-research.md)), and the guest CA is installed through the root finalization step. A probe must qualify the route first (B-27 below). The limit stated in `docs/SiloUI-SECRETS.md:76` still applies: an allowed server receives the real value. | 50 Q5/Q6; 70 OQ13; 50 D-cred | Contract applied in the cited source sections; unsourced mechanism details remain in (B)/(C). |
| 9 | A-17 | **DECIDED ([95 A-17](95-decisions.md)):** **GitHub sign-in on a host with no screen goes through the controller's browser.** The loopback callback is carried back to the host over the existing SSH connection. | 50 Q1; 50 D-cred | Contract applied in the cited source sections; unsourced mechanism details remain in (B)/(C). |
| 10 | A-8 | **DECIDED ([95 A-8](95-decisions.md)):** **No screen lock.** This keeps Silo's current "no input leases" direction (`docs/SiloUI-DESKTOP-VIEWER-DIRECTION.md:11-14`). | 30 OQ5; 40 OQ9 | Contract applied in the cited source sections; unsourced mechanism details remain in (B)/(C). |
| 11 | A-26 | **DECIDED ([95 A-26](95-decisions.md)):** The engine runs its upkeep on its own timers, without waiting for a client read: secret revocation retries, log expiry, port repair. | 05 OQ23; 10 Q12 | Contract applied in the cited source sections; unsourced mechanism details remain in (B)/(C). |
| 12 | A-6 | **DECIDED ([95 A-6](95-decisions.md)):** **An engine update saves and resumes running computers:** they are paused to disk and resumed after the update, so runs continue. The engine is updated only when its own version changes. | 60 OQ9; 05 §6 | Contract applied in the cited source sections; unsourced mechanism details remain in (B)/(C). |
| 13 | A-23 | **DECIDED ([95 A-23, overridden by §3](95-decisions.md)):** Hosts and controllers are Macs only, running Linux and macOS computers. No Linux engine service, Debian/AppImage updater or headless Linux setup remains; Silo Linux packages receive no further engine updates. B-9/B-26 are closed. | 05 OQ10/20; 60 OQ8 | Contract applied in the cited source sections; unsourced mechanism details remain in (B)/(C). |
| 14 | A-28 | **DECIDED ([95 A-28](95-decisions.md)):** Each client gets its own viewer connection, so one client closing never ends another's viewer. | 40 OQ3 | Contract applied in the cited source sections; unsourced mechanism details remain in (B)/(C). |
| 15 | A-9 | **DECIDED ([95 A-9](95-decisions.md)):** **Proof recordings are made inside the VM:** ffmpeg on Linux (already in the image), the built-in screen recorder on macOS. They work with no window open. | 30 OQ6; 40 OQ10 | Contract applied in the cited source sections; unsourced mechanism details remain in (B)/(C). |
| 16 | A-10 | **DECIDED ([95 A-10](95-decisions.md)):** Stable snake_case error codes for macOS refusals and the new guest, exec and file errors, added to `ErrorCode` and its fixtures. | 30 OQ7; 70 §2.1 pending errors | Contract applied in the cited source sections; unsourced mechanism details remain in (B)/(C). |
| 17 | A-14 | **DECIDED ([95 A-14](95-decisions.md)):** **Another Mac can manage everything on the host,** including GitHub and secrets. Secret values travel over the user's own SSH connection. | 10 Q11; 20 §1.3/§2.1; 30 §3; 50 Remote control | Contract applied in the cited source sections; unsourced mechanism details remain in (B)/(C). |
| 18 | A-16 | **DECIDED ([95 A-16](95-decisions.md)):** **Another Mac can manage everything on the host,** including GitHub and secrets. Secret values travel over the user's own SSH connection. The engine requires explicit `allowAnyDestination` acknowledgement for `*` (95 Part 2, Secrets wildcard). | 50 Q7/Q8; 50 D-cred | Contract applied in the cited source sections; unsourced mechanism details remain in (B)/(C). |
| 19 | A-13 | **DECIDED ([95 A-13](95-decisions.md)):** Records and SSH aliases are keyed by `computerId`; 95 §3 forbids old-name compatibility and permits conversion only in a launch-time `runtime_migration`. | 50 Q12/Q13; 70 §1.3 | Contract applied in the cited source sections; unsourced mechanism details remain in (B)/(C). |
| 20 | A-11 | **DECIDED ([95 A-11](95-decisions.md)):** Records and SSH aliases are keyed by `computerId`; 95 §3 forbids old-name compatibility and permits conversion only in a launch-time `runtime_migration`. | 10 Q10; 50 Conventions and GitHub on macOS | Contract applied in the cited source sections; unsourced mechanism details remain in (B)/(C). |
| 21 | A-37 | **DECIDED ([95 A-37](95-decisions.md)):** Bounded `guest.exec` keeps today's error on stdout overflow, with a configurable cap. Long runs (Triage) use the `guest.exec.start` job. | 30 OQ12; 70 OQ15 | Contract applied in the cited source sections; unsourced mechanism details remain in (B)/(C). |
| 22 | A-38 | **DECIDED ([95 A-38](95-decisions.md)):** Fjord ships a hook script and plugin that can run inside the guest, installed through `guest.files.*`. Nothing in the guest depends on Fjord's macOS binary. | 30 OQ2 | Contract applied in the cited source sections; unsourced mechanism details remain in (B)/(C). |
| 23 | A-19 | **DECIDED ([95 A-19](95-decisions.md)):** **macOS computers get full Linux parity in this API version:** GitHub, secrets, files, ports, terminal and editor, export and import, and start at launch. | 20 OQ4/5; 30 OQ10; 50 Q9(root)/Q14(roots)/Q15 | Contract applied in the cited source sections; unsourced mechanism details remain in (B)/(C). |
| 24 | A-18 | **DECIDED ([95 A-18](95-decisions.md)):** **Automatic checkpoints before unattended runs:** the last **3** per computer are kept. Each is labeled clearly as **automatic** ("Before run: <task>, deleted automatically"), unlike manual checkpoints, which are never deleted automatically. A setting changes the count or turns them off. | 20 OQ1/2/6/7 | Contract applied in the cited source sections; unsourced mechanism details remain in (B)/(C). |
| 25 | A-20 | **DECIDED ([95 A-20](95-decisions.md)):** A remote macOS screen is shown through the existing Screen Sharing stream (today's behaviour). | 30 OQ3 | Contract applied in the cited source sections; unsourced mechanism details remain in (B)/(C). |
| 26 | A-27 | **DECIDED ([95 A-27](95-decisions.md)):** **Only Fjord shows notices.** The engine posts no OS notifications. It keeps the latest notice for each key, so Fjord shows them when it opens. | 60 OQ10 | Contract applied in the cited source sections; unsourced mechanism details remain in (B)/(C). |
| 27 | A-31 | **DECIDED ([95 A-31](95-decisions.md)):** macOS work joins the operation queue (parity); 95 §3 confirms “Waiting…” with Cancel rather than contention refusal. | 10 Q9 | Contract applied in the cited source sections; unsourced mechanism details remain in (B)/(C). |
| 28 | A-21 | **DECIDED ([95 A-21](95-decisions.md)):** **The engine appears in the Dock and ⌘-Tab only while a VM window is open,** as VMPal does. | 30 OQ4; 05 §3.6 | Contract applied in the cited source sections; unsourced mechanism details remain in (B)/(C). |
| 29 | A-22 | **DECIDED ([95 A-22](95-decisions.md)):** The engine returns terminal, editor and browser commands, and clients launch them. The engine needs no Apple Events entitlement. | 05 OQ9; 60 OQ11 | Contract applied in the cited source sections; unsourced mechanism details remain in (B)/(C). |
| 30 | A-12 | **DECIDED ([95 A-12](95-decisions.md)):** The platform state enums stay as they are, in one `computers.list` with `kind`. macOS gets CPU and memory editing (parity). Disks stay fixed after creation, as on Linux. Host limits go in device facts. | 10 Q1/Q6; 20 OQ9; 30 OQ8/OQ9 | Contract applied in the cited source sections; unsourced mechanism details remain in (B)/(C). |
| 31 | A-30 | **DECIDED ([95 A-30](95-decisions.md)):** Log exports are cancelled one at a time, by job. | 10 Q5 | Contract applied in the cited source sections; unsourced mechanism details remain in (B)/(C). |
| 32 | A-32 | **DECIDED ([95 A-32](95-decisions.md)):** The page relay stays limited to `__silo.invoke` calls. | 40 OQ5 | Contract applied in the cited source sections; unsourced mechanism details remain in (B)/(C). |
| 33 | A-33 | **DECIDED ([95 A-33](95-decisions.md)):** The engine enforces the viewer drop's Downloads restriction in `files.upload`. | 40 OQ6 | Contract applied in the cited source sections; unsourced mechanism details remain in (B)/(C). |
| 34 | A-29 | **DECIDED ([95 A-29](95-decisions.md)):** `computers.shell` stays. | 10 Q2 | Contract applied in the cited source sections; unsourced mechanism details remain in (B)/(C). |
| 35 | A-36 | **DECIDED ([95 A-36](95-decisions.md)):** **Removing a connected Mac revokes its key on the host.** | 60 OQ13 | Contract applied in the cited source sections; unsourced mechanism details remain in (B)/(C). |
| 36 | A-35 | **DECIDED ([95 A-35](95-decisions.md)):** Device facts include Remote Login status. | 60 OQ12 | Contract applied in the cited source sections; unsourced mechanism details remain in (B)/(C). |
| 37 | A-34 | **DECIDED ([95 A-34](95-decisions.md)):** The guest desktop port stays hidden. | 40 OQ13 | Contract applied in the cited source sections; unsourced mechanism details remain in (B)/(C). |

A-24 is retained as a legacy umbrella crossreference to A-25, A-28–A-37 and A-8/A-19. Its repository-placement item is settled: 10 §1.4 retains repositories on each computer row and assigns ownership to push.*, while 50 push.repositories remains the query. Do not count the umbrella as another decision.


### (B) Probe results and implementation tests

**37 probe IDs: 8 SETTLED, 15 PARTLY, 10 OPEN, 4 CLOSED; 25 still need implementation evidence.** B-6/B-8 are closed by 95 A-27/A-12; B-9/B-26 are closed because Linux hosts were dropped (95 §3). SETTLED means the stated fact/mechanism is evidenced on the recorded versions, not that a production adapter exists. PARTLY names the remaining evidence; OPEN tests run during implementation. Later Follow-up and Connections (run 2) sections supersede earlier blocked/not-run verdicts without erasing their limits.

Evidence: [macos.md](probes/macos.md), including [Follow-up](probes/macos.md#follow-up); [linux.md](probes/linux.md), including [Follow-up](probes/linux.md#follow-up), [Connections](probes/linux.md#connections) and [Connections (run 2)](probes/linux.md#connections-run-2); [proxy.md](probes/proxy.md). Track summaries: [macOS](probes/macos-track.final.md), [macOS follow-up](probes/macos-followup.final.md), [Linux](probes/linux-track.final.md), [Linux follow-up/Connections](probes/linux-connections.final.md), [Connections run 2](probes/connections.final.md), [proxy](probes/proxy-track.final.md). This revision reads existing evidence only; it runs no VMs/apps/builds and leaves probe records unchanged (00 rules).

| ID | Status | Observed result and remaining evidence | Sources |
| --- | --- | --- | --- |
| B-1 | **SETTLED** | Serial-queue VM attached to a main-thread VZ view on macOS 26.5 ([macos.md §B-1](probes/macos.md#b-1--confirmed)); qualify other supported versions during implementation. | 05 OQ3 |
| B-2 | **OPEN** | Run locked auto-login session start/continuation during implementation; not run under the probe safety rules. | 05 OQ4 |
| B-3 | **PARTLY** | Aqua/Interactive agent and window-dependent regular/Foreground ↔ accessory/UIElement classification passed; login-window exclusion remains OPEN ([macos.md §Environment](probes/macos.md#environment-and-method), [Follow-up §B-3](probes/macos.md#b-3--confirmed-for-app-classification)). | 05 OQ5; 30 OQ4 |
| B-4 | **PARTLY** | Agent NAT SSH passed; Screen Sharing/5900 passed after setup once, then an immediate restart check got no route. Repeated boots and macOS 15 privacy qualification remain OPEN ([macos.md §B-4](probes/macos.md#b-4--partly), [Follow-up §B-4](probes/macos.md#b-4--confirmed-on-one-boot)). | 05 OQ6 |
| B-5 | **SETTLED** | Added VirtioFS device mounted read/write with bidirectional file checks and no observed TCC prompt; no shared-folder API selected ([macos.md §B-5](probes/macos.md#b-5--confirmed)). | 05 OQ7 |
| B-6 | **CLOSED** | 95 A-27: engine posts no OS notifications; no OS-delivery probe required. | 05 OQ8; 60 OQ10 |
| B-7 | **PARTLY** | APFS volume costs measured: initial clone 88 KiB, 1 GiB guest write about 1.04 GiB, saved state 2,755,304 KiB, checkpoint clones 52 KiB. Per-file private/reclaimable bytes remain OPEN ([macos.md Follow-up §B-7](probes/macos.md#b-7--measured-at-volume-level)); apply to 20 retention, retain memory-only sizeBytes. | 20 OQ3 |
| B-8 | **CLOSED** | 95 A-12: disks stay fixed after creation; disk growth is outside this contract. | 30 OQ9 |
| B-9 | **CLOSED** | 95 §3: Linux hosts dropped; no Linux service/cgroup contract remains. | 05 OQ10; 95 §3 |
| B-10 | **OPEN** | Run during implementation after resolving bridge EINVAL: upsert/delete failed before any frame; only original stopped computers remained. Cross-kind collision and creation-wait behavior were not tested ([linux.md Connections (run 2) §B-10](probes/linux.md#b-10--duplicate-name-remote-upsert-and-wait)). | 10 Q7 |
| B-11 | **PARTLY** | First-party Desktop used Include/ProxyCommand, IdentityAgent none, host pinning and forced-off forwarding; Desktop overrode alias BatchMode yes to no. startDirectory remains unsupported; first-party credential/plugin details and macOS integration remain OPEN ([linux.md §B-11](probes/linux.md#b-11--claude-desktop-ssh-alias)). | 30 OQ1; 50 Q4; 70 OQ1 |
| B-12 | **SETTLED** | Guest Claude server/command survived killing its session ProxyCommand; Desktop reconnected and received exit 0 ([linux.md §B-12](probes/linux.md#b-12--proxycommand-disconnect)). | 70 OQ2 |
| B-13 | **SETTLED** | /home/silo was executable overlay storage without noexec, with about 98 GiB free in this computer ([linux.md §B-13](probes/linux.md#b-13--guest-home-mount-and-space)). | 70 OQ3 |
| B-14 | **SETTLED** | macOS guest effective SFTP /usr/libexec/sftp-server, MaxSessions 10, OpenSSH 10.3p1 / LibreSSL 3.3.6 recorded; Files roots stay C-7 ([macos.md §B-14](probes/macos.md#b-14--confirmed)). | 50 Q14; 70 OQ4 |
| B-15 | **PARTLY** | Guest PermissionRequest fired for Desktop SSH AskUserQuestion 5.09 s after SessionStart; user plugin loaded in direct CLI. Full Fjord plugin callbacks, presence and form delivery remain OPEN ([linux.md §B-15](probes/linux.md#b-15--guest-permissionrequest-hook-and-user-plugin), [Follow-up §B-15](probes/linux.md#b-15-permissionrequest-in-claude-code-desktop-ssh)). | 30 OQ2; 70 OQ5/6 |
| B-16 | **PARTLY** | Guest registry/Desktop local_ IDs and Linux task output path observed; local transcript lagged about 1.1 s and stayed 1,168 bytes smaller. Fjord reads guest.files; broader byte-completeness/reconciliation remains OPEN ([linux.md §B-16](probes/linux.md#b-16--transcripts-session-metadata-and-task-folders), [Follow-up §B-16](probes/linux.md#b-16-live-transcript-freshness-and-background-task-output)). | 70 OQ8/9/10 |
| B-17 | **PARTLY** | Exec inherited placeholder/CA; allowed-host invalid x-api-key and non-allowed placeholder passthrough passed. Isolated Authorization rewrite and actual Claude OAuth destinations remain OPEN ([linux.md §B-17](probes/linux.md#b-17--oauth-placeholder-tls-ca-and-msb-exec), [Follow-up §B-17](probes/linux.md#b-17-allowed-host-substitution-to-apianthropiccom)). | 70 OQ11/12 |
| B-18 | **PARTLY** | Fixture all-frame/cookie/media/download/clipboard checks passed; live Selkies loaded HTTP 200 with real cookie/bridge. Native paste and live download/all-frame checks remain OPEN ([linux.md §B-18](probes/linux.md#b-18--wkwebview-security-and-media-checks), [Follow-up §B-18](probes/linux.md#b-18-live-silo-desktop-proxy-in-wkwebview)). | 40 OQ2 |
| B-19 | **SETTLED** | Template lacks usable Git/LFS and Xcode command-line tools, requiring NEW provisioning in 30; lsof/netstat discovery and ssh -L half-close/teardown passed. Roots remain C-7; validate tools after provisioning in B-34 ([macos.md §B-19](probes/macos.md#b-19--partly), [Follow-up §B-19](probes/macos.md#b-19--settled-for-template-tooling)). | 50 Q9/10/11 |
| B-20 | **PARTLY** | Linux guest-local inotify p95 0.321 ms versus 32.291 ms for 30 ms polling; macOS adapter and end-to-end/loss/coalescing qualification remain OPEN ([linux.md §B-20](probes/linux.md#b-20--linux-inotify-against-30-ms-polling)). | 70 OQ14 |
| B-21 | **PARTLY** | Independent current viewers REFUTED: Silo reuses one registry entry, and live Selkies second-client takeover ended the first. A-28 requires NEW engine/streamer work; independent close/resize/clipboard remain OPEN ([linux.md §B-21](probes/linux.md#b-21--two-viewer-clients), [Follow-up §B-18](probes/linux.md#b-18-live-silo-desktop-proxy-in-wkwebview)). | 40 OQ3 |
| B-22 | **PARTLY** | Pre-installed key completed v5 handshake after bundle-copy/link replacement; original-path baseline authenticated then failed EINVAL without a frame. Stable engine/Fjord paths and successful before/after baseline remain OPEN ([linux.md Connections (run 2) §B-22](probes/linux.md#b-22--forced-command-after-bundle-replacement)). | 05 OQ2; 60 OQ1 |
| B-23 | **SETTLED** | SSH through launchctl asuser reached console user GUI context and an active 1280×800 display; this grants no recorder TCC permission ([macos.md §B-23](probes/macos.md#b-23--confirmed)). | 30 OQ13 |
| B-24 | **SETTLED** | Linux ffmpeg captured :1.0 with Silo Xauthority; macOS guest Aqua ScreenCaptureKit/TCC identity finalized and retrieved a 10.23 s H.264 movie without a host viewer. Linux movie lifecycle remains implementation validation ([linux.md §B-24](probes/linux.md#b-24--linux-ffmpeg-screen-capture), [macos.md Follow-up §B-24](probes/macos.md#b-24-macos--confirmed)). | 40 OQ10 |
| B-25 | **OPEN** | Run remote/headless GitHub OAuth callback/state and restricted-key compatibility during implementation; no external-account flow was run (95 A-17; [probe rules §Safety](probes/00-probe-rules.md#safety)). | 50 Q1; 50 D-cred |
| B-26 | **CLOSED** | 95 §3: Linux hosts dropped; no Debian/AppImage service-update coordination remains. | 05 OQ20; 60 OQ8; 95 §3 |
| B-27 | **PARTLY** | FileHandle → gateway → patched SmoltcpNetwork, guest CA, controlled substitution/revocation and sequential isolation passed; frame throughput 42.81 vs NAT 85.64 MB/s. Default DNS, production lifecycle/GitHub/CA delivery and concurrent isolation remain OPEN ([proxy.md §Adapter](probes/proxy.md#adapter-and-commands), [§Results](probes/proxy.md#results), [§NAT comparison](probes/proxy.md#nat-comparison), [§Remaining seam](probes/proxy.md#spec-impact-and-remaining-seam)). | 95 Probe B-27; 50 Q5/Q6; 70 OQ13; 92 §2/§4 |
| B-28 | **PARTLY** | Offline devbox removal left an unrelated localhost key/session intact; no connected peer was tested. Matching owner key revocation, retries/offline refusal and session/reconnect races remain OPEN ([linux.md Connections (run 2) §B-28](probes/linux.md#b-28--controller-removal-key-retention-and-open-session)). | 60 §connections.devices.remove/keys.revoke; 95 A-36; `src-tauri/src/remote.rs:906-959` |
| B-29 | **OPEN** | Run notice restart persistence, expiry/cardinality and concurrent read/subscription reconciliation during implementation; A-27/A-4 settle policy only. | 60 §notifications.list; 95 A-27/A-4 |
| B-30 | **PARTLY** | macOS same boot time/process survived save → SIGKILL → new-process restore/resume; uptime 42→44 s excludes saved interval. Full update hold/release/journal/failure recovery, compatibility and Linux continuity remain OPEN ([macos.md Follow-up §B-30](probes/macos.md#b-30--confirmed-for-saved-guest-state)). | 05 OQ24/§6; 95 A-6; `src-tauri/src/macos_computers/engine.rs:1097-1125`; `src-tauri/src/runtime/checkpoints.rs:704-725`, `:1297-1309` |
| B-31 | **OPEN** | Run missing macOS desktop/display/audio/page/native-frame adapters during implementation; current view/Screen Sharing primitives alone do not prove parity (95 A-19). | 40 OQ14; 95 A-19; 30 §5–6 |
| B-32 | **PARTLY** | Exact-cap/overflow/timeout reproduced; 256/768 KiB and 30/180 s are inferred candidates only. Workload-based numeric limits, stderr/frame bounds remain OPEN ([linux.md §B-32](probes/linux.md#b-32--run_capped-overflow-and-timeout)). | 30 OQ12; 70 OQ15; 95 A-37 |
| B-33 | **OPEN** | Run automatic-kind/settings launch upgrade and dependency-pinned retention/deferred cleanup during implementation; never force-delete manual or pinned records (95 A-18). | 20 OQ12/§1.4; 95 A-18 |
| B-34 | **OPEN** | Run missing macOS lifecycle/resource/identity/queue/log/storage/migration/preparation adapters during implementation, including NEW Git/LFS/Xcode developer-tools provisioning and full dev-computer Xcode setup (30; 95 A-19; [macos.md Follow-up §B-19](probes/macos.md#b-19--settled-for-template-tooling)). | 10 Q13; 20 OQ13; 95 A-19/A-12/A-10/A-14 |
| B-35 | **OPEN** | Run subscriber capacity, slow-client overflow/gap/reconnect and multi-controller Stream admission during implementation (95 A-4). | 05 OQ12/OQ13/OQ18; 95 A-4 |
| B-36 | **OPEN** | Run timer intervals and revocation/log-expiry/port-repair recovery with no connected clients during implementation (95 A-26). | 05 OQ23; 10 Q12; 95 A-26 |
| B-37 | **OPEN** | Run durable outcome/identity/inventory/get/acknowledgement journal and crash/race cases during implementation; separately qualify queue/interrupted-process/output recovery (95 §3). | 05 OQ25/§job contract; 10/20/30 job boundaries; 70 guest.exec.get; 95 §3 Job results |

### (C) Research

9 active research entries, preserving legacy IDs; C-3 is a closed research crossreference and not counted.

| ID | Research and settling evidence | Sources |
| --- | --- | --- |
| C-1 | Obtain the landed microsandbox#1805 native display/input contract for resize/HiDPI/audio/clipboard; then select paths/file descriptors/IOSurfaces for cross-process frames supported by it. | 40 OQ7/8 |
| C-2 | Confirm with Anthropic or test whether CLI sessions can be imported into Desktop SSH sessions; the current prefilled new-session fallback is already stated. | 70 OQ7 |
| C-4 | Specify macOS archive content and version: disk, auxiliary storage, hardware model and optional memory. macOS export/import parity is decided by 95 A-19; exact format and transport are not selected. | 20 OQ4 |
| C-5 | Finish macOS checkpoint bridge parameter adaptation against the shared checkpoints methods and owner dispatch. Shared method names are settled; 20 §1.3 still explicitly leaves bridge params here. | 30 OQ11; 20 §1.3 |
| C-6 | Establish whether a WKWebView scheme handler can provide the authenticated Unix-socket proxy alternative to a bearer cookie crossing the API. Peer-euid authorization and handing the cookie to the client are decided by 95 A-5; the alternative is optional research. | 40 OQ1 |
| C-7 | Specify macOS Files/workspace/Git roots, folder upload/delete behavior, managed-SSH listener/key ownership and relay details; parity and computerId aliases are decided, mechanisms are not. | 50 Q9/Q12/Q13/Q14/Q15; 95 A-13/A-19 |
| C-8 | Specify macOS abandon semantics, explicit fork/import child identity and native-versus-Silo pending-restore representation; automatic checkpoint policy does not answer these API details. | 20 OQ2/OQ6/OQ7; 95 A-18 |
| C-9 | Select stable Mac engine/helper paths and registration, canonical transport protocol number/schema-generator implementation and Mac installer ownership; one engine, length-prefixed framing with request IDs and canonical method names, generated JSON Schema/Swift and save/resume are decided. | 05 OQ1/OQ2/OQ14/OQ15; 60 OQ1/OQ7/OQ9; 95 A-1/A-7/A-6 |
| C-10 | Specify hostBuild warning/setup detail projection and a source-backed Remote Login diagnostic; platform enums, CPU/memory editing, fixed disks and device facts are decided. | 10 Q6; 20 OQ9; 30 OQ8; 60 OQ12; 95 A-12/A-35 |


C-3 is closed as code-reading research: 20 §1.1 Pending restore identifies Restore, Fork and Import setters and the import native-member identity. The remaining API representation detail is not answered by 95 A-18 and is retained in C-8 (20 OQ7).

### Source-entry coverage

Every numbered source entry appears below, including settled entries. All A references mean DECIDED in 95; they are not open tasks. Mixed owner/probe/research entries use several references but are counted once in 126.

| Section | Mapping by question number |
| --- | --- |
| 05 | 1 A1; 2 A1/B22; 3 B1; 4 B2; 5 B3; 6 B4; 7 B5; 8 B6; 9 A22; 10 A23 (overridden by §3; B9 CLOSED); 11 A5; 12 A4/B35; 13 A4/B35; 14 A7/C9; 15 A7/C9; 16 A5; 17 A2; 18 A4; 19 A25/B37; 20 A23 (overridden by §3; B26 CLOSED); 21 A25/B37; 22 A25/B37; 23 A26/B36; 24 B30; 25 B37 |
| 10 | 1 A12; 2 A29; 3 CLOSED; 4 A2; 5 A30; 6 A12; 7 B10; 8 A4; 9 A31 (lock A8); 10 A11; 11 A14; 12 A26/B36; 13 B34 |
| 20 | 1 A18; 2 A18/C8; 3 B7; 4 A19/C4; 5 A19/C4; 6 A18/C8 (import jobId CLOSED); 7 A18/C8 (C3 CLOSED RESEARCH); 8 A25; 9 A12; 10 A5; 11 A25/B37; 12 B33; 13 B34 |
| 30 | 1 B11; 2 A38/B15; 3 A20; 4 A21/B3; 5 A8; 6 A9; 7 A10; 8 A12; 9 A12/B8; 10 A19; 11 C5; 12 A37; 13 B23; 14 A4; 15 A2; 16 A25 |
| 40 | 1 A5/C6; 2 B18; 3 A28/B21; 4 A4; 5 A32; 6 A33; 7 C1; 8 C1; 9 A8; 10 A9/B24; 11 CLOSED; 12 CLOSED; 13 A34; 14 B31; 15 B24 |
| 50 | 1 A17/B25; 2 A4; 3 A1; 4 B11; 5 A15; 6 A15; 7 A16; 8 A16; 9 B19/A19 roots; 10 B19; 11 B19; 12 A13 (relay CLOSED); 13 A13; 14 A19/B14; 15 A19 (programmatic placement CLOSED); 16 CLOSED |
| 60 | 1 A1/B22; 2 CLOSED; 3 A3; 4 A4; 5 A2; 6 A5; 7 A1; 8 A23 (overridden by §3; B26 CLOSED); 9 A6/B30/C9; 10 A27/B29 (B6 CLOSED); 11 A22; 12 A35/C10; 13 A36/B28 |
| 70 | 1 B11; 2 B12; 3 B13; 4 B14; 5 B15; 6 B15; 7 C2; 8 B16; 9 B16; 10 B16; 11 B17; 12 B17; 13 A15; 14 B20; 15 A37/B32 |

## 5. Silo bugs, stale docs and observed contract gaps

These are observations of the pinned code, not changes to Silo. Rows distinguish stale documentation, lost data, current limitations and new engine requirements; a known source limitation is not counted as MISSING API coverage (§1). B1–B18 retain IDs referenced by 05–70; the remote-journal correction follows the table.

| ID | Finding | File:line evidence |
| --- | --- | --- |
| B-1 | Linux pending Restore's `checkpointId` names the native runtime member, not the Silo checkpoint; import has no Silo checkpoint identity | `src-tauri/src/runtime/checkpoints.rs:46-51`, `:1027-1031`, `:1660-1664`, `:2169-2173` |
| B-2 | UI macOS checkpoint-operation schema admits failed/error fields absent from the Rust operation type | `src/features/macos-computers/model/macos-computers.ts:22-27`; `src-tauri/src/macos_computers/checkpoints.rs:127-153` |
| B-3 | Remote macOS String errors all become `internal`, so refusal conditions cannot be distinguished by code | `src-tauri/src/macos_remote.rs:65-92`; `src-tauri/src/bridge_error.rs:104-108` |
| B-4 | macOS doc gap row says nothing triggers pinned-app/LCU upgrading; the Start path already triggers in-place updating | `docs/SiloUI-MACOS-COMPUTERS.md:497`, `:121-129`; `src-tauri/src/macos_computers.rs:1414`; `src-tauri/src/macos_computers/guest_computer_use.rs:430-546` |
| B-5 | Viewer integration plan says nothing is implemented, but clipboard, audio/reset and native file drops exist | `docs/SiloUI-VIEWER-INTEGRATION-PLAN.md:3-5`; `src-tauri/src/viewer_clipboard.rs:250-256`; `src-tauri/src/desktop_viewer_media.rs:305`, `:339`, `:359`; `src-tauri/src/transfer.rs:1279-1305` |
| B-6 | Dead `repository.push` stays advertised in capabilities; unsupported dispatch falls through to String → `internal` | `src-tauri/src/remote.rs:261`, `:2218`, `:2222-2223`; `src-tauri/src/remote_access.rs:124-125`, `:180`; `src-tauri/src/bridge_error.rs:104-108` |
| B-7 | Remote Linux create skips interactive cross-kind name reservation and creation-input wait; its progress callback emits only a state hint | `src-tauri/src/runtime/remote_ops.rs:36-114`, `:100-102`; contrast local interactive setup `src-tauri/src/runtime.rs:4138-4243`, name reservation `:4355-4359` |
| B-8 | Placeholder/projection mismatches: `computerConfigurationOperation` is None; export archive list empty; UI setup-progress revision has no Rust field; guest desktop port is not projected | `src-tauri/src/runtime.rs:4776`, `:3462-3494`; `src-tauri/src/backup_controller.rs:494`; `src/contracts/silo.ts:96`; `src/desktop/linux-desktop-state.ts:78`; `src-tauri/src/desktop.rs:597-607` |
| B-9 | Controller checkpoint wrapper and macOS create command discard results; import returns no identity; Linux fork returns inventory without an explicit child id | `src-tauri/src/remote.rs:1369-1384`; `src-tauri/src/macos_computers.rs:1978-1980`; `src-tauri/src/macos_computers/checkpoints.rs:373-377`; `src-tauri/src/backup_controller.rs:1564-1576`; `src-tauri/src/runtime/checkpoints.rs:1775-1805` |
| B-10 | Start-at-launch selection and the health-watch source are Linux-only | `src-tauri/src/startup.rs:87-101`; `src-tauri/src/runtime.rs:5203-5205`, `:3007-3031` |
| B-11 | macOS snapshot has no host-capacity/limit structure although create applies CPU/memory/disk bounds | `src-tauri/src/macos_computers.rs:104-114`; `src-tauri/src/macos_computers/store.rs:162-196` |
| B-12 | `control.sock` trusts filesystem modes without checking peer credentials before reading/dispatching a request | `src-tauri/src/remote.rs:2031-2049`, `:2073-2125` |
| B-13 | Connection-budget refusal is a bare `{error}` frame with no wire code | `src-tauri/src/remote.rs:2076-2081` |
| B-14 | Secret wildcard acknowledgment is UI-only; Rust accepts `*` directly | `src/features/application/model/secret-configuration.ts:53`; `src-tauri/src/secrets.rs:456-458` |
| B-15 | Removing a saved device clears local state/tunnels but leaves its key in the owner's `authorized_keys` | `src-tauri/src/remote.rs:445-466` |
| B-16 | Device health fields appear in TS and internal bookkeeping, without an exposed engine query/event contract | `src/features/application/model/connections.ts:4-6`; `src-tauri/src/remote.rs:1490-1577` (60 OQ 4) |
| B-17 | Log-export cancel has no per-job argument and advances a module-wide cancellation generation | `src-tauri/src/log_export.rs:15-25`, `:73-78` |
| B-18 | Historical Linux package guard names `silo-ui`; this path is retired from the new engine after 95 §3, with B-9/B-26 closed | `src-tauri/src/main.rs:83-90`; `src-tauri/src/system_integrations.rs:161-166`, `:194-203`; `app/SiloUI/scripts/debian/preinst:8-37` (repo-root path) |
| B-19 | Connections doc overstates protocol equality as release equality; code checks protocol version 5, not app release | `docs/SiloUI-CONNECTIONS.md:103`; `src-tauri/src/remote.rs:34-36`, `:2161-2184` |
| B-20 | Revocation, expired-log cleanup and port-repair retry triggers depend on reads; the headless health read does not run those passes | `src-tauri/src/runtime.rs:2663-2701`, `:2770-2796`, `:3007-3031`, `:13029-13060`; `src-tauri/src/network.rs:729-770`, `:827-836`; `src-tauri/src/health_watch.rs:242-273` (05 OQ 23; 10 Q12) |

B-7 is deliberately narrower than the old audit: remote changes write recovery journals (`src-tauri/src/runtime/remote_ops.rs:94-95`, `:105`), but not the interactive setup path's name/input/progress behavior. No Silo correction is made here (00 §The rules: zero guesses).

The brief's original snapshot said **160** commands; it now records the actual **159** registrations, excluding the extra `#[tauri::command` string inside a test (`src-tauri/src/main.rs:131-289`; `src-tauri/src/remote.rs:3510`; 05 §2.1). This is a stale spec-source count, not a missing command. 90 and 91 were left unchanged as requested; the current behavioral coverage is cited to 05–70 and code, not inferred from their historical verdicts.

## 6. Final counts after decisions and live evidence

**Coverage:** 159 commands; 24 emitted names / 78 sites; 35 existing source bridge entries; 4 source executable modes (1 AppImage helper retired) plus 1 retired Linux-host startup guard; **MISSING 0; CONFLICT 0** (§1). **API:** 146 methods = **3 EXISTS + 10 EXISTS (renamed) + 121 EXTENDED + 12 NEW**, with **26 catalogue events** and **29 job methods** (§2–3). **Questions:** 126 source entries; **37 decided owner items, 0 open owner decisions, 8 settled probes, 15 partial probes, 10 open implementation probes, 4 closed probes, 9 research items** (§4). **Source findings:** 20 rows in §5; pinned code is unchanged.

**Canonical method names added in the decision pass (not a NEW-status count):** `engine.disconnect` (95 A-2), `operations.job.get` (95 §3/A-25), `operations.job.acknowledge` (95 §3), `connections.devices.health` (95 A-4), `connections.keys.revoke` (95 A-36), `device.facts` (95 A-12/A-35), `notifications.list` (95 A-27), `github.connect.callback` (95 A-17), `editor.command` (95 A-22). Definitions and code seams are indexed in §3. Six old names leave the engine API: `connections.ssh.authorize`, `connections.ssh.setupKey` (95 A-22), `settings.onboardingDraft.update` (95 A-5), and `settings.importLegacyTheme`, `migration.retry`, `migration.continueAfterFailure` (95 §3), producing 143 + 9 − 6 = 146 methods. An added canonical name may re-expose existing behavior. Existing methods with required behavior or platform additions are EXTENDED; §3 counts each name once under its verified class.

**Before implementation:** settle the 9 research items in §4(C) for each dependent feature and plan qualification of the 15 PARTLY remainders and 10 OPEN tests during implementation (§4(B)). Qualified guest recording, macOS process save/restore and proxy adapter mechanisms are now specified in 40/05/50; production integration remains NEW. The largest evidence gaps are default proxy DNS/lifecycle, actual Claude OAuth headers/destinations, independent viewers/streamer ownership, stable engine/helper packaging, connected-peer key revocation, full update failure recovery/Linux continuity, macOS tools/parity adapters and durable jobs/events/timers. Research still covers native display, SSH-session import, archives, checkpoint params/abandon/IDs, roots/managed SSH, packaging/schema and host diagnostics. No method is added for internal tools provisioning or guest recording, so API classifications/counts remain unchanged.
