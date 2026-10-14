# Fjord: agent tools in computers, 2026-10-14

## Built
- **Client regenerated** from Silo main (819367b3) with `scripts/generate-engine-client.sh --write`: `SiloWireAgentToolsStatus`/`State`, `DesktopStatus.agentTools`, `DesktopAction.setupAgentTools`, `ErrorCode.credentialAccessDenied`. Schema snapshot and manifest updated.
- `Sources/Fjord/AgentTools.swift`: `AgentToolsAdvice` (wording, "Set up" vs "Update"), `AgentToolsSetup` (status, `setUp` as a `desktop.action setup-agent-tools` job polled to its end, `ensureReady` gate), `AgentToolsFailure`.
- **Computers**: an "Agent tools" panel on the Overview (status, versions, missing tools, Set up/Update button, progress, errors); loaded for running computers. Model state is keyed by `GuestReference.key`.
- **Router "Runs on"**: the guest-folder prompt shows the tools status with a Set up/Update button (Linux); starting a session in a computer runs the gate first and sets the tools up automatically, with progress in the model (`RouterMCP.ensureGuestAgentTools`).
- **Triage "Run in a computer"**: the action editor shows the same row; `ComputerRunCoordinator` gates before the workspace is touched, sets tools up (progress written as the run detail), else fails clearly.
- **macOS computers**: Silo only installs through its developer-tools step, so the gate refuses with a message to retry that setup; no action is sent.
- **credential_access_denied**: `EngineErrorText` maps it to "Silo's engine isn't allowed to use its saved GitHub sign-in. Open Keychain Access to allow it, or connect GitHub again." and the socket client treats it as a known code (job errors and request errors).
- **Mock**: `desktop.status` (per-computer `mockAgentTools`, default ready), `desktop.action setup-agent-tools` (job, becomes ready unless `nextJobFailure`), `agentToolsSetupRequests`.
- New shot `computer-agent-tools` (linux-1, outdated).

## Tests
`Tests/FjordTests/AgentToolsTests.swift` (11): wording, status and Set up/Update in the model, failed setup, gate pass/setup/mac refusal, Triage sets up before the workspace, Triage mac refusal before checkpoint, Router path through the model, the credential message on all three paths. `swift build` clean; `scripts/test.sh` run once at the end (see the summary for the result). Note: Triage tests use a cloned computer id because Triage's active-computer set is process-wide.

## Notes
- Router and Triage both set up automatically (no confirm prompt): the Router start comes from an agent tool call with no UI to ask in; the offer lives in the Runs on prompt, the action editor and Computers.
- Not verified live (no real guest).
- Remote owners: Router start still requires a local owner (existing limitation); the gate passes the deviceId through.
