// This file is generated from JSON Schema metadata using quicktype-core, do not modify it directly.
import Foundation

enum SiloGeneratedMethodKind: String, Codable, Sendable {
    case command
    case job
    case query
    case stream
    case subscription
}

struct SiloGeneratedMethodDescriptor: Equatable, Sendable {
    let name: String
    let kind: SiloGeneratedMethodKind
    let paramsType: String
    let resultType: String
}

struct SiloGeneratedMethodCall<Params: Encodable & Sendable, Result: Decodable & Sendable>: Sendable {
    let name: String
    let kind: SiloGeneratedMethodKind
    let params: Params
}

enum SiloGeneratedMethods {
    static let all: [SiloGeneratedMethodDescriptor] = [
        SiloGeneratedMethodDescriptor(name: "activity.setup.read", kind: .query, paramsType: "common::EmptyParams", resultType: "Vec<computers::ComputerConfigurationProgress>"),
        SiloGeneratedMethodDescriptor(name: "checkpoints.abandonRestore", kind: .job, paramsType: "common::ComputerTargetParams", resultType: "common::JobStartResult"),
        SiloGeneratedMethodDescriptor(name: "checkpoints.create", kind: .job, paramsType: "checkpoints::CheckpointCreateParams", resultType: "common::JobStartResult"),
        SiloGeneratedMethodDescriptor(name: "checkpoints.delete", kind: .job, paramsType: "checkpoints::CheckpointTargetParams", resultType: "common::JobStartResult"),
        SiloGeneratedMethodDescriptor(name: "checkpoints.fork", kind: .job, paramsType: "checkpoints::CheckpointForkParams", resultType: "common::JobStartResult"),
        SiloGeneratedMethodDescriptor(name: "checkpoints.restore", kind: .job, paramsType: "checkpoints::CheckpointTargetParams", resultType: "common::JobStartResult"),
        SiloGeneratedMethodDescriptor(name: "checkpoints.usage", kind: .query, paramsType: "checkpoints::CheckpointUsageParams", resultType: "checkpoints::CheckpointUsage"),
        SiloGeneratedMethodDescriptor(name: "clipboard.read", kind: .command, paramsType: "clipboard::ClipboardReadParams", resultType: "clipboard::ClipboardReadResult"),
        SiloGeneratedMethodDescriptor(name: "clipboard.transfer", kind: .command, paramsType: "clipboard::ClipboardTransferParams", resultType: "clipboard::ClipboardTransferResult"),
        SiloGeneratedMethodDescriptor(name: "clipboard.write", kind: .command, paramsType: "clipboard::ClipboardWriteParams", resultType: "clipboard::ClipboardWriteResult"),
        SiloGeneratedMethodDescriptor(name: "computerUse.approval", kind: .command, paramsType: "computer_use::ComputerUseApprovalParams", resultType: "computer_use::ComputerUseState"),
        SiloGeneratedMethodDescriptor(name: "computerUse.setup", kind: .job, paramsType: "computer_use::ComputerUseSetupParams", resultType: "common::JobStartResult"),
        SiloGeneratedMethodDescriptor(name: "computerUse.state", kind: .query, paramsType: "computer_use::ComputerUseStateParams", resultType: "computer_use::ComputerUseState"),
        SiloGeneratedMethodDescriptor(name: "computers.configuration.change", kind: .job, paramsType: "computers::ComputerConfigurationChangeParams", resultType: "common::JobStartResult"),
        SiloGeneratedMethodDescriptor(name: "computers.configuration.read", kind: .query, paramsType: "computers::ComputerConfigurationReadParams", resultType: "computers::ComputerConfigurationRequest"),
        SiloGeneratedMethodDescriptor(name: "computers.configuration.retry", kind: .job, paramsType: "computers::ComputerConfigurationRetryParams", resultType: "common::JobStartResult"),
        SiloGeneratedMethodDescriptor(name: "computers.create", kind: .job, paramsType: "computers::ComputerCreateParams", resultType: "computers::ComputerCreateResult"),
        SiloGeneratedMethodDescriptor(name: "computers.creation.skipComputerUseWait", kind: .command, paramsType: "computers::ComputerCreationSkipWaitParams", resultType: "()"),
        SiloGeneratedMethodDescriptor(name: "computers.delete", kind: .job, paramsType: "computers::ComputerDeleteParams", resultType: "common::JobStartResult"),
        SiloGeneratedMethodDescriptor(name: "computers.dismissError", kind: .command, paramsType: "computers::ComputerDismissErrorParams", resultType: "computers::ApplicationSource"),
        SiloGeneratedMethodDescriptor(name: "computers.forceStop", kind: .command, paramsType: "computers::ComputerForceStopParams", resultType: "()"),
        SiloGeneratedMethodDescriptor(name: "computers.identities.configure", kind: .job, paramsType: "computers::ComputerIdentitiesParams", resultType: "common::JobStartResult"),
        SiloGeneratedMethodDescriptor(name: "computers.identities.verify", kind: .query, paramsType: "computers::ComputerIdentitiesVerifyParams", resultType: "computers::ComputerIdentitiesVerifyResult"),
        SiloGeneratedMethodDescriptor(name: "computers.launch", kind: .query, paramsType: "computers::ComputerLaunchParams", resultType: "computers::LaunchStatus"),
        SiloGeneratedMethodDescriptor(name: "computers.list", kind: .query, paramsType: "computers::ComputerListParams", resultType: "computers::ComputersListResult"),
        SiloGeneratedMethodDescriptor(name: "computers.restart", kind: .job, paramsType: "common::ComputerTargetParams", resultType: "common::JobStartResult"),
        SiloGeneratedMethodDescriptor(name: "computers.shell", kind: .query, paramsType: "computers::ComputerShellParams", resultType: "computers::ApplicationSource"),
        SiloGeneratedMethodDescriptor(name: "computers.start", kind: .job, paramsType: "common::ComputerTargetParams", resultType: "common::JobStartResult"),
        SiloGeneratedMethodDescriptor(name: "computers.stop", kind: .job, paramsType: "common::ComputerTargetParams", resultType: "common::JobStartResult"),
        SiloGeneratedMethodDescriptor(name: "connections.devices.connect", kind: .command, paramsType: "connections::ConnectDeviceParams", resultType: "connections::Device"),
        SiloGeneratedMethodDescriptor(name: "connections.devices.health", kind: .query, paramsType: "connections::DeviceHealthParams", resultType: "connections::DeviceHealthResult"),
        SiloGeneratedMethodDescriptor(name: "connections.devices.list", kind: .query, paramsType: "common::EmptyParams", resultType: "Vec<connections::Device>"),
        SiloGeneratedMethodDescriptor(name: "connections.devices.remove", kind: .command, paramsType: "connections::DeviceIdParams", resultType: "()"),
        SiloGeneratedMethodDescriptor(name: "connections.keys.revoke", kind: .command, paramsType: "connections::RevokeKeyParams", resultType: "()"),
        SiloGeneratedMethodDescriptor(name: "connections.setEnabled", kind: .command, paramsType: "connections::ConnectionsSetEnabledParams", resultType: "connections::ConnectionsStatus"),
        SiloGeneratedMethodDescriptor(name: "connections.ssh.authorizationCommand", kind: .query, paramsType: "connections::SshAddressParams", resultType: "connections::SshCommandResult"),
        SiloGeneratedMethodDescriptor(name: "connections.ssh.keySetupCommand", kind: .command, paramsType: "connections::SshAddressParams", resultType: "connections::SshCommandResult"),
        SiloGeneratedMethodDescriptor(name: "connections.status", kind: .query, paramsType: "common::EmptyParams", resultType: "connections::ConnectionsStatus"),
        SiloGeneratedMethodDescriptor(name: "desktop.action", kind: .job, paramsType: "desktop::DesktopActionParams", resultType: "common::JobStartResult"),
        SiloGeneratedMethodDescriptor(name: "desktop.connect", kind: .query, paramsType: "desktop::DesktopConnectParams", resultType: "desktop::DesktopConnectResult"),
        SiloGeneratedMethodDescriptor(name: "desktop.status", kind: .query, paramsType: "desktop::DesktopStatusParams", resultType: "desktop::DesktopStatus"),
        SiloGeneratedMethodDescriptor(name: "device.dependencies", kind: .query, paramsType: "device::DependencyReportParams", resultType: "device::DependencyReport"),
        SiloGeneratedMethodDescriptor(name: "device.facts", kind: .query, paramsType: "device::DeviceFactsParams", resultType: "device::DeviceFacts"),
        SiloGeneratedMethodDescriptor(name: "display.close", kind: .command, paramsType: "display::DisplayCloseParams", resultType: "()"),
        SiloGeneratedMethodDescriptor(name: "display.native.attach", kind: .stream, paramsType: "display::NativeDisplayAttachParams", resultType: "display::NativeDisplayMessage"),
        SiloGeneratedMethodDescriptor(name: "display.show", kind: .command, paramsType: "display::DisplayShowParams", resultType: "()"),
        SiloGeneratedMethodDescriptor(name: "display.viewer.audio.set", kind: .command, paramsType: "display::ViewerAudioSetParams", resultType: "()"),
        SiloGeneratedMethodDescriptor(name: "display.viewer.close", kind: .command, paramsType: "display::ViewerConnectionParams", resultType: "()"),
        SiloGeneratedMethodDescriptor(name: "display.viewer.open", kind: .command, paramsType: "common::ComputerTargetParams", resultType: "display::ViewerOpenResult"),
        SiloGeneratedMethodDescriptor(name: "display.viewer.screen.reset", kind: .command, paramsType: "display::ViewerConnectionParams", resultType: "()"),
        SiloGeneratedMethodDescriptor(name: "display.viewer.sound.cancel", kind: .command, paramsType: "display::ViewerConnectionParams", resultType: "()"),
        SiloGeneratedMethodDescriptor(name: "display.viewer.sound.check", kind: .query, paramsType: "display::ViewerConnectionParams", resultType: "display::ViewerSoundCheckResult"),
        SiloGeneratedMethodDescriptor(name: "editor.command", kind: .command, paramsType: "terminal::EditorCommandParams", resultType: "terminal::CommandResult"),
        SiloGeneratedMethodDescriptor(name: "editor.includeNotice", kind: .query, paramsType: "common::EmptyParams", resultType: "Option<String>"),
        SiloGeneratedMethodDescriptor(name: "engine.disconnect", kind: .command, paramsType: "engine::EngineDisconnectParams", resultType: "()"),
        SiloGeneratedMethodDescriptor(name: "engine.handshake", kind: .query, paramsType: "transport::HandshakeParams", resultType: "transport::HandshakeResult"),
        SiloGeneratedMethodDescriptor(name: "engine.shutdown", kind: .job, paramsType: "engine::EngineShutdownParams", resultType: "common::JobStartResult"),
        SiloGeneratedMethodDescriptor(name: "engine.state", kind: .query, paramsType: "engine::EngineStateParams", resultType: "engine::EngineState"),
        SiloGeneratedMethodDescriptor(name: "engine.update.abort", kind: .command, paramsType: "engine::EngineUpdateAbortParams", resultType: "()"),
        SiloGeneratedMethodDescriptor(name: "engine.update.prepare", kind: .job, paramsType: "engine::EngineUpdatePrepareParams", resultType: "common::JobStartResult"),
        SiloGeneratedMethodDescriptor(name: "events.subscribe", kind: .subscription, paramsType: "engine::EventsSubscribeParams", resultType: "engine::EventsSubscribeResult"),
        SiloGeneratedMethodDescriptor(name: "events.unsubscribe", kind: .command, paramsType: "engine::EventsUnsubscribeParams", resultType: "()"),
        SiloGeneratedMethodDescriptor(name: "exports.acknowledge", kind: .command, paramsType: "exports::ExportAcknowledgeParams", resultType: "bool"),
        SiloGeneratedMethodDescriptor(name: "exports.create", kind: .job, paramsType: "exports::ExportCreateParams", resultType: "common::JobStartResult"),
        SiloGeneratedMethodDescriptor(name: "exports.destination.set", kind: .command, paramsType: "exports::ExportDestinationSetParams", resultType: "exports::ExportDestinationResult"),
        SiloGeneratedMethodDescriptor(name: "exports.dismiss", kind: .command, paramsType: "exports::ExportDismissParams", resultType: "bool"),
        SiloGeneratedMethodDescriptor(name: "exports.import", kind: .job, paramsType: "exports::ExportImportParams", resultType: "common::JobStartResult"),
        SiloGeneratedMethodDescriptor(name: "exports.inspect", kind: .job, paramsType: "exports::ExportInspectParams", resultType: "common::JobStartResult"),
        SiloGeneratedMethodDescriptor(name: "exports.state", kind: .query, paramsType: "exports::ExportStateParams", resultType: "exports::BackupState"),
        SiloGeneratedMethodDescriptor(name: "files.download", kind: .job, paramsType: "files::FileDownloadParams", resultType: "common::JobStartResult"),
        SiloGeneratedMethodDescriptor(name: "files.list", kind: .query, paramsType: "files::FileListParams", resultType: "files::FileListResult"),
        SiloGeneratedMethodDescriptor(name: "files.upload", kind: .job, paramsType: "files::FileUploadParams", resultType: "common::JobStartResult"),
        SiloGeneratedMethodDescriptor(name: "github.access.set", kind: .command, paramsType: "github::GitHubAccessSetParams", resultType: "github::GitHubState"),
        SiloGeneratedMethodDescriptor(name: "github.configuration.retry", kind: .command, paramsType: "github::GitHubConfigurationRetryParams", resultType: "github::GitHubState"),
        SiloGeneratedMethodDescriptor(name: "github.configuration.save", kind: .command, paramsType: "github::GitHubConfigurationSaveParams", resultType: "github::GitHubState"),
        SiloGeneratedMethodDescriptor(name: "github.connect", kind: .job, paramsType: "github::GitHubConnectParams", resultType: "common::JobStartResult"),
        SiloGeneratedMethodDescriptor(name: "github.connect.callback", kind: .stream, paramsType: "github::GitHubConnectCallbackParams", resultType: "()"),
        SiloGeneratedMethodDescriptor(name: "github.connect.reopen", kind: .command, paramsType: "github::GitHubConnectReopenParams", resultType: "github::GitHubRepositoriesManageResult"),
        SiloGeneratedMethodDescriptor(name: "github.disconnect", kind: .command, paramsType: "github::GitHubDisconnectParams", resultType: "github::GitHubState"),
        SiloGeneratedMethodDescriptor(name: "github.personalToken.remove", kind: .command, paramsType: "github::GitHubPersonalTokenRemoveParams", resultType: "github::GitHubState"),
        SiloGeneratedMethodDescriptor(name: "github.personalToken.save", kind: .command, paramsType: "github::GitHubPersonalTokenSaveParams", resultType: "github::GitHubState"),
        SiloGeneratedMethodDescriptor(name: "github.repositories.manage", kind: .command, paramsType: "github::GitHubRepositoriesManageParams", resultType: "github::GitHubRepositoriesManageResult"),
        SiloGeneratedMethodDescriptor(name: "github.repositories.refresh", kind: .command, paramsType: "github::GitHubRepositoriesRefreshParams", resultType: "github::GitHubState"),
        SiloGeneratedMethodDescriptor(name: "github.state", kind: .query, paramsType: "github::GitHubStateParams", resultType: "github::GitHubState"),
        SiloGeneratedMethodDescriptor(name: "guest.account", kind: .query, paramsType: "guest::GuestAccountParams", resultType: "guest::GuestAccount"),
        SiloGeneratedMethodDescriptor(name: "guest.exec", kind: .command, paramsType: "guest::GuestExecParams", resultType: "guest::GuestExecResult"),
        SiloGeneratedMethodDescriptor(name: "guest.exec.get", kind: .query, paramsType: "guest::GuestExecGetParams", resultType: "guest::GuestExecGetResult"),
        SiloGeneratedMethodDescriptor(name: "guest.exec.input", kind: .command, paramsType: "guest::GuestExecInputParams", resultType: "()"),
        SiloGeneratedMethodDescriptor(name: "guest.exec.start", kind: .job, paramsType: "guest::GuestExecStartParams", resultType: "common::JobStartResult"),
        SiloGeneratedMethodDescriptor(name: "guest.files.list", kind: .query, paramsType: "guest::GuestFilesListParams", resultType: "guest::GuestFilesListResult"),
        SiloGeneratedMethodDescriptor(name: "guest.files.read", kind: .query, paramsType: "guest::GuestFilesReadParams", resultType: "guest::GuestFilesReadResult"),
        SiloGeneratedMethodDescriptor(name: "guest.files.remove", kind: .command, paramsType: "guest::GuestFilesRemoveParams", resultType: "guest::GuestFilesRemoveResult"),
        SiloGeneratedMethodDescriptor(name: "guest.files.watch", kind: .subscription, paramsType: "guest::GuestFilesWatchParams", resultType: "guest::GuestFilesWatchResult"),
        SiloGeneratedMethodDescriptor(name: "guest.files.write", kind: .command, paramsType: "guest::GuestFilesWriteParams", resultType: "guest::GuestFilesWriteResult"),
        SiloGeneratedMethodDescriptor(name: "guest.prepare", kind: .command, paramsType: "guest::GuestPrepareParams", resultType: "guest::GuestPrepareResult"),
        SiloGeneratedMethodDescriptor(name: "guest.ssh", kind: .stream, paramsType: "guest::GuestSshParams", resultType: "()"),
        SiloGeneratedMethodDescriptor(name: "guest.sshAlias.ensure", kind: .command, paramsType: "guest::GuestSshAliasEnsureParams", resultType: "guest::GuestSshAliasEnsureResult"),
        SiloGeneratedMethodDescriptor(name: "guest.sshAlias.remove", kind: .command, paramsType: "guest::GuestSshAliasRemoveParams", resultType: "()"),
        SiloGeneratedMethodDescriptor(name: "logs.export", kind: .job, paramsType: "logs::LogsExportParams", resultType: "common::JobStartResult"),
        SiloGeneratedMethodDescriptor(name: "logs.query", kind: .query, paramsType: "logs::LogsQueryParams", resultType: "logs::LogPage"),
        SiloGeneratedMethodDescriptor(name: "macos.display.connect", kind: .query, paramsType: "macos::MacosDisplayConnectParams", resultType: "macos::MacosDisplayConnectResult"),
        SiloGeneratedMethodDescriptor(name: "macos.display.resize", kind: .command, paramsType: "macos::MacosDisplayResizeParams", resultType: "macos::MacosDisplayResizeResult"),
        SiloGeneratedMethodDescriptor(name: "macos.display.session", kind: .command, paramsType: "macos::MacosDisplaySessionParams", resultType: "macos::MacosDisplaySessionResult"),
        SiloGeneratedMethodDescriptor(name: "macos.display.stream", kind: .stream, paramsType: "macos::MacosDisplayStreamParams", resultType: "()"),
        SiloGeneratedMethodDescriptor(name: "macos.setup.retry", kind: .job, paramsType: "macos::MacosSetupRetryParams", resultType: "common::JobStartResult"),
        SiloGeneratedMethodDescriptor(name: "macos.template.delete", kind: .command, paramsType: "macos::MacosTemplateDeleteParams", resultType: "()"),
        SiloGeneratedMethodDescriptor(name: "migration.preUpgradeBackup.acknowledgeNotice", kind: .command, paramsType: "common::DeviceParams", resultType: "()"),
        SiloGeneratedMethodDescriptor(name: "migration.preUpgradeBackup.delete", kind: .command, paramsType: "common::DeviceParams", resultType: "()"),
        SiloGeneratedMethodDescriptor(name: "migration.preUpgradeBackup.get", kind: .query, paramsType: "common::DeviceParams", resultType: "migration::PreUpgradeBackupResult"),
        SiloGeneratedMethodDescriptor(name: "migration.preUpgradeBackup.measure", kind: .query, paramsType: "common::DeviceParams", resultType: "migration::PreUpgradeBackupMeasureResult"),
        SiloGeneratedMethodDescriptor(name: "migration.state", kind: .query, paramsType: "common::DeviceParams", resultType: "migration::MigrationState"),
        SiloGeneratedMethodDescriptor(name: "network.open", kind: .command, paramsType: "network::NetworkOpenParams", resultType: "network::NetworkOpenResult"),
        SiloGeneratedMethodDescriptor(name: "network.publish", kind: .command, paramsType: "network::NetworkPublishParams", resultType: "network::NetworkState"),
        SiloGeneratedMethodDescriptor(name: "network.state", kind: .query, paramsType: "network::NetworkStateParams", resultType: "network::NetworkState"),
        SiloGeneratedMethodDescriptor(name: "network.unpublish", kind: .command, paramsType: "network::NetworkUnpublishParams", resultType: "network::NetworkState"),
        SiloGeneratedMethodDescriptor(name: "notifications.list", kind: .query, paramsType: "notifications::NotificationsListParams", resultType: "notifications::NotificationsListResult"),
        SiloGeneratedMethodDescriptor(name: "operations.cancel", kind: .command, paramsType: "operations::CancelJobParams", resultType: "()"),
        SiloGeneratedMethodDescriptor(name: "operations.job.acknowledge", kind: .command, paramsType: "operations::AcknowledgeJobParams", resultType: "()"),
        SiloGeneratedMethodDescriptor(name: "operations.job.get", kind: .query, paramsType: "operations::GetJobParams", resultType: "jobs::JobLookupResult"),
        SiloGeneratedMethodDescriptor(name: "operations.list", kind: .query, paramsType: "operations::OperationsListParams", resultType: "operations::OperationQueue"),
        SiloGeneratedMethodDescriptor(name: "preparation.chatgpt.retry", kind: .command, paramsType: "preparation::ChatGptPreparationRetryParams", resultType: "preparation::ChatGptPreparationStatus"),
        SiloGeneratedMethodDescriptor(name: "preparation.chatgpt.status", kind: .query, paramsType: "preparation::ChatGptPreparationStatusParams", resultType: "preparation::ChatGptPreparationStatus"),
        SiloGeneratedMethodDescriptor(name: "preparation.retry", kind: .command, paramsType: "preparation::PreparationRetryParams", resultType: "preparation::PreparationStatus"),
        SiloGeneratedMethodDescriptor(name: "preparation.status", kind: .query, paramsType: "preparation::PreparationStatusParams", resultType: "preparation::PreparationStatus"),
        SiloGeneratedMethodDescriptor(name: "push.dismiss", kind: .command, paramsType: "push::PushDismissParams", resultType: "()"),
        SiloGeneratedMethodDescriptor(name: "push.repositories", kind: .query, paramsType: "push::PushRepositoriesParams", resultType: "Vec<push::PushRepository>"),
        SiloGeneratedMethodDescriptor(name: "push.start", kind: .job, paramsType: "push::PushStartParams", resultType: "common::JobStartResult"),
        SiloGeneratedMethodDescriptor(name: "push.status", kind: .query, paramsType: "push::PushStatusParams", resultType: "Option<push::PushOperation>"),
        SiloGeneratedMethodDescriptor(name: "secrets.list", kind: .query, paramsType: "common::DeviceParams", resultType: "Vec<secrets::Secret>"),
        SiloGeneratedMethodDescriptor(name: "secrets.remove", kind: .command, paramsType: "secrets::SecretsRemoveParams", resultType: "Vec<secrets::Secret>"),
        SiloGeneratedMethodDescriptor(name: "secrets.retry", kind: .command, paramsType: "secrets::SecretsRetryParams", resultType: "Vec<secrets::Secret>"),
        SiloGeneratedMethodDescriptor(name: "secrets.save", kind: .command, paramsType: "secrets::SecretsSaveParams", resultType: "Vec<secrets::Secret>"),
        SiloGeneratedMethodDescriptor(name: "settings.flush", kind: .command, paramsType: "settings::SettingsFlushParams", resultType: "()"),
        SiloGeneratedMethodDescriptor(name: "settings.read", kind: .query, paramsType: "settings::SettingsReadParams", resultType: "settings::SettingsSnapshot"),
        SiloGeneratedMethodDescriptor(name: "settings.update", kind: .command, paramsType: "settings::SettingsUpdateParams", resultType: "settings::SettingsSnapshot"),
        SiloGeneratedMethodDescriptor(name: "sshAccess.connection", kind: .command, paramsType: "ssh_access::SshAccessConnectionParams", resultType: "ssh_access::SshAccessConnectionResult"),
        SiloGeneratedMethodDescriptor(name: "sshAccess.save", kind: .command, paramsType: "ssh_access::SshAccessSaveParams", resultType: "ssh_access::SshAccessState"),
        SiloGeneratedMethodDescriptor(name: "sshAccess.state", kind: .query, paramsType: "common::DeviceParams", resultType: "ssh_access::SshAccessState"),
        SiloGeneratedMethodDescriptor(name: "storage.read", kind: .query, paramsType: "storage::StorageParams", resultType: "storage::StorageState"),
        SiloGeneratedMethodDescriptor(name: "storage.reclaim", kind: .job, paramsType: "storage::StorageParams", resultType: "common::JobStartResult"),
        SiloGeneratedMethodDescriptor(name: "terminal.command", kind: .query, paramsType: "terminal::TerminalCommandParams", resultType: "terminal::CommandResult"),
        SiloGeneratedMethodDescriptor(name: "updates.check", kind: .command, paramsType: "updates::UpdatesCheckParams", resultType: "updates::UpdateSnapshot"),
        SiloGeneratedMethodDescriptor(name: "updates.download", kind: .job, paramsType: "updates::UpdatesDownloadParams", resultType: "common::JobStartResult"),
        SiloGeneratedMethodDescriptor(name: "updates.focused", kind: .command, paramsType: "updates::UpdatesFocusedParams", resultType: "()"),
        SiloGeneratedMethodDescriptor(name: "updates.setAutomaticChecks", kind: .command, paramsType: "updates::UpdatesSetAutomaticChecksParams", resultType: "updates::UpdateSnapshot"),
        SiloGeneratedMethodDescriptor(name: "updates.state", kind: .query, paramsType: "common::EmptyParams", resultType: "updates::UpdateSnapshot")
    ]

    static func activitySetupRead(_ params: SiloWireEmptyParams) -> SiloGeneratedMethodCall<SiloWireEmptyParams, [SiloWireComputerConfigurationProgress]> {
        SiloGeneratedMethodCall<SiloWireEmptyParams, [SiloWireComputerConfigurationProgress]>(name: "activity.setup.read", kind: .query, params: params)
    }

    static func checkpointsAbandonRestore(_ params: SiloWireComputerTargetParams) -> SiloGeneratedMethodCall<SiloWireComputerTargetParams, SiloWireJobStartResult> {
        SiloGeneratedMethodCall<SiloWireComputerTargetParams, SiloWireJobStartResult>(name: "checkpoints.abandonRestore", kind: .job, params: params)
    }

    static func checkpointsCreate(_ params: SiloWireCheckpointCreateParams) -> SiloGeneratedMethodCall<SiloWireCheckpointCreateParams, SiloWireJobStartResult> {
        SiloGeneratedMethodCall<SiloWireCheckpointCreateParams, SiloWireJobStartResult>(name: "checkpoints.create", kind: .job, params: params)
    }

    static func checkpointsDelete(_ params: SiloWireCheckpointTargetParams) -> SiloGeneratedMethodCall<SiloWireCheckpointTargetParams, SiloWireJobStartResult> {
        SiloGeneratedMethodCall<SiloWireCheckpointTargetParams, SiloWireJobStartResult>(name: "checkpoints.delete", kind: .job, params: params)
    }

    static func checkpointsFork(_ params: SiloWireCheckpointForkParams) -> SiloGeneratedMethodCall<SiloWireCheckpointForkParams, SiloWireJobStartResult> {
        SiloGeneratedMethodCall<SiloWireCheckpointForkParams, SiloWireJobStartResult>(name: "checkpoints.fork", kind: .job, params: params)
    }

    static func checkpointsRestore(_ params: SiloWireCheckpointTargetParams) -> SiloGeneratedMethodCall<SiloWireCheckpointTargetParams, SiloWireJobStartResult> {
        SiloGeneratedMethodCall<SiloWireCheckpointTargetParams, SiloWireJobStartResult>(name: "checkpoints.restore", kind: .job, params: params)
    }

    static func checkpointsUsage(_ params: SiloWireCheckpointUsageParams) -> SiloGeneratedMethodCall<SiloWireCheckpointUsageParams, SiloWireCheckpointUsage> {
        SiloGeneratedMethodCall<SiloWireCheckpointUsageParams, SiloWireCheckpointUsage>(name: "checkpoints.usage", kind: .query, params: params)
    }

    static func clipboardRead(_ params: SiloWireComputerTargetParams) -> SiloGeneratedMethodCall<SiloWireComputerTargetParams, SiloWireClipboardContent> {
        SiloGeneratedMethodCall<SiloWireComputerTargetParams, SiloWireClipboardContent>(name: "clipboard.read", kind: .command, params: params)
    }

    static func clipboardTransfer(_ params: SiloWireClipboardTransferParams) -> SiloGeneratedMethodCall<SiloWireClipboardTransferParams, SiloWireClipboardTransferResult> {
        SiloGeneratedMethodCall<SiloWireClipboardTransferParams, SiloWireClipboardTransferResult>(name: "clipboard.transfer", kind: .command, params: params)
    }

    static func clipboardWrite(_ params: SiloWireClipboardWriteParams) -> SiloGeneratedMethodCall<SiloWireClipboardWriteParams, SiloNull> {
        SiloGeneratedMethodCall<SiloWireClipboardWriteParams, SiloNull>(name: "clipboard.write", kind: .command, params: params)
    }

    static func computerUseApproval(_ params: SiloWireComputerUseApprovalParams) -> SiloGeneratedMethodCall<SiloWireComputerUseApprovalParams, SiloWireComputerUseState> {
        SiloGeneratedMethodCall<SiloWireComputerUseApprovalParams, SiloWireComputerUseState>(name: "computerUse.approval", kind: .command, params: params)
    }

    static func computerUseSetup(_ params: SiloWireComputerTargetParams) -> SiloGeneratedMethodCall<SiloWireComputerTargetParams, SiloWireJobStartResult> {
        SiloGeneratedMethodCall<SiloWireComputerTargetParams, SiloWireJobStartResult>(name: "computerUse.setup", kind: .job, params: params)
    }

    static func computerUseState(_ params: SiloWireComputerUseStateParams) -> SiloGeneratedMethodCall<SiloWireComputerUseStateParams, SiloWireComputerUseState> {
        SiloGeneratedMethodCall<SiloWireComputerUseStateParams, SiloWireComputerUseState>(name: "computerUse.state", kind: .query, params: params)
    }

    static func computersConfigurationChange(_ params: SiloWireComputerConfigurationChangeParams) -> SiloGeneratedMethodCall<SiloWireComputerConfigurationChangeParams, SiloWireJobStartResult> {
        SiloGeneratedMethodCall<SiloWireComputerConfigurationChangeParams, SiloWireJobStartResult>(name: "computers.configuration.change", kind: .job, params: params)
    }

    static func computersConfigurationRead(_ params: SiloWireDeviceParams) -> SiloGeneratedMethodCall<SiloWireDeviceParams, SiloWireComputerConfigurationRequest> {
        SiloGeneratedMethodCall<SiloWireDeviceParams, SiloWireComputerConfigurationRequest>(name: "computers.configuration.read", kind: .query, params: params)
    }

    static func computersConfigurationRetry(_ params: SiloWireComputerConfigurationRetryParams) -> SiloGeneratedMethodCall<SiloWireComputerConfigurationRetryParams, SiloWireJobStartResult> {
        SiloGeneratedMethodCall<SiloWireComputerConfigurationRetryParams, SiloWireJobStartResult>(name: "computers.configuration.retry", kind: .job, params: params)
    }

    static func computersCreate(_ params: SiloWireComputerCreateParams) -> SiloGeneratedMethodCall<SiloWireComputerCreateParams, SiloWireComputerCreateResult> {
        SiloGeneratedMethodCall<SiloWireComputerCreateParams, SiloWireComputerCreateResult>(name: "computers.create", kind: .job, params: params)
    }

    static func computersCreationSkipComputerUseWait(_ params: SiloWireComputerCreationSkipWaitParams) -> SiloGeneratedMethodCall<SiloWireComputerCreationSkipWaitParams, SiloNull> {
        SiloGeneratedMethodCall<SiloWireComputerCreationSkipWaitParams, SiloNull>(name: "computers.creation.skipComputerUseWait", kind: .command, params: params)
    }

    static func computersDelete(_ params: SiloWireComputerDeleteParams) -> SiloGeneratedMethodCall<SiloWireComputerDeleteParams, SiloWireJobStartResult> {
        SiloGeneratedMethodCall<SiloWireComputerDeleteParams, SiloWireJobStartResult>(name: "computers.delete", kind: .job, params: params)
    }

    static func computersDismissError(_ params: SiloWireComputerTargetParams) -> SiloGeneratedMethodCall<SiloWireComputerTargetParams, SiloWireApplicationSource> {
        SiloGeneratedMethodCall<SiloWireComputerTargetParams, SiloWireApplicationSource>(name: "computers.dismissError", kind: .command, params: params)
    }

    static func computersForceStop(_ params: SiloWireComputerTargetParams) -> SiloGeneratedMethodCall<SiloWireComputerTargetParams, SiloNull> {
        SiloGeneratedMethodCall<SiloWireComputerTargetParams, SiloNull>(name: "computers.forceStop", kind: .command, params: params)
    }

    static func computersIdentitiesConfigure(_ params: SiloWireComputerIdentitiesParams) -> SiloGeneratedMethodCall<SiloWireComputerIdentitiesParams, SiloWireJobStartResult> {
        SiloGeneratedMethodCall<SiloWireComputerIdentitiesParams, SiloWireJobStartResult>(name: "computers.identities.configure", kind: .job, params: params)
    }

    static func computersIdentitiesVerify(_ params: SiloWireComputerIdentitiesParams) -> SiloGeneratedMethodCall<SiloWireComputerIdentitiesParams, Bool> {
        SiloGeneratedMethodCall<SiloWireComputerIdentitiesParams, Bool>(name: "computers.identities.verify", kind: .query, params: params)
    }

    static func computersLaunch(_ params: SiloWireDeviceParams) -> SiloGeneratedMethodCall<SiloWireDeviceParams, SiloWireLaunchStatus> {
        SiloGeneratedMethodCall<SiloWireDeviceParams, SiloWireLaunchStatus>(name: "computers.launch", kind: .query, params: params)
    }

    static func computersList(_ params: SiloWireComputerListParams) -> SiloGeneratedMethodCall<SiloWireComputerListParams, SiloWireComputersListResult> {
        SiloGeneratedMethodCall<SiloWireComputerListParams, SiloWireComputersListResult>(name: "computers.list", kind: .query, params: params)
    }

    static func computersRestart(_ params: SiloWireComputerTargetParams) -> SiloGeneratedMethodCall<SiloWireComputerTargetParams, SiloWireJobStartResult> {
        SiloGeneratedMethodCall<SiloWireComputerTargetParams, SiloWireJobStartResult>(name: "computers.restart", kind: .job, params: params)
    }

    static func computersShell(_ params: SiloWireComputerShellParams) -> SiloGeneratedMethodCall<SiloWireComputerShellParams, SiloWireApplicationSource> {
        SiloGeneratedMethodCall<SiloWireComputerShellParams, SiloWireApplicationSource>(name: "computers.shell", kind: .query, params: params)
    }

    static func computersStart(_ params: SiloWireComputerTargetParams) -> SiloGeneratedMethodCall<SiloWireComputerTargetParams, SiloWireJobStartResult> {
        SiloGeneratedMethodCall<SiloWireComputerTargetParams, SiloWireJobStartResult>(name: "computers.start", kind: .job, params: params)
    }

    static func computersStop(_ params: SiloWireComputerTargetParams) -> SiloGeneratedMethodCall<SiloWireComputerTargetParams, SiloWireJobStartResult> {
        SiloGeneratedMethodCall<SiloWireComputerTargetParams, SiloWireJobStartResult>(name: "computers.stop", kind: .job, params: params)
    }

    static func connectionsDevicesConnect(_ params: SiloWireConnectDeviceParams) -> SiloGeneratedMethodCall<SiloWireConnectDeviceParams, SiloWireDevice> {
        SiloGeneratedMethodCall<SiloWireConnectDeviceParams, SiloWireDevice>(name: "connections.devices.connect", kind: .command, params: params)
    }

    static func connectionsDevicesHealth(_ params: SiloWireEmptyParams) -> SiloGeneratedMethodCall<SiloWireEmptyParams, SiloWireDeviceHealthResult> {
        SiloGeneratedMethodCall<SiloWireEmptyParams, SiloWireDeviceHealthResult>(name: "connections.devices.health", kind: .query, params: params)
    }

    static func connectionsDevicesList(_ params: SiloWireEmptyParams) -> SiloGeneratedMethodCall<SiloWireEmptyParams, [SiloWireDevice]> {
        SiloGeneratedMethodCall<SiloWireEmptyParams, [SiloWireDevice]>(name: "connections.devices.list", kind: .query, params: params)
    }

    static func connectionsDevicesRemove(_ params: SiloWireDeviceIdParams) -> SiloGeneratedMethodCall<SiloWireDeviceIdParams, SiloNull> {
        SiloGeneratedMethodCall<SiloWireDeviceIdParams, SiloNull>(name: "connections.devices.remove", kind: .command, params: params)
    }

    static func connectionsKeysRevoke(_ params: SiloWireRevokeKeyParams) -> SiloGeneratedMethodCall<SiloWireRevokeKeyParams, SiloNull> {
        SiloGeneratedMethodCall<SiloWireRevokeKeyParams, SiloNull>(name: "connections.keys.revoke", kind: .command, params: params)
    }

    static func connectionsSetEnabled(_ params: SiloWireConnectionsSetEnabledParams) -> SiloGeneratedMethodCall<SiloWireConnectionsSetEnabledParams, SiloWireConnectionsStatus> {
        SiloGeneratedMethodCall<SiloWireConnectionsSetEnabledParams, SiloWireConnectionsStatus>(name: "connections.setEnabled", kind: .command, params: params)
    }

    static func connectionsSshAuthorizationCommand(_ params: SiloWireSSHAddressParams) -> SiloGeneratedMethodCall<SiloWireSSHAddressParams, SiloWireSSHCommandResult> {
        SiloGeneratedMethodCall<SiloWireSSHAddressParams, SiloWireSSHCommandResult>(name: "connections.ssh.authorizationCommand", kind: .query, params: params)
    }

    static func connectionsSshKeySetupCommand(_ params: SiloWireSSHAddressParams) -> SiloGeneratedMethodCall<SiloWireSSHAddressParams, SiloWireSSHCommandResult> {
        SiloGeneratedMethodCall<SiloWireSSHAddressParams, SiloWireSSHCommandResult>(name: "connections.ssh.keySetupCommand", kind: .command, params: params)
    }

    static func connectionsStatus(_ params: SiloWireEmptyParams) -> SiloGeneratedMethodCall<SiloWireEmptyParams, SiloWireConnectionsStatus> {
        SiloGeneratedMethodCall<SiloWireEmptyParams, SiloWireConnectionsStatus>(name: "connections.status", kind: .query, params: params)
    }

    static func desktopAction(_ params: SiloWireDesktopActionParams) -> SiloGeneratedMethodCall<SiloWireDesktopActionParams, SiloWireJobStartResult> {
        SiloGeneratedMethodCall<SiloWireDesktopActionParams, SiloWireJobStartResult>(name: "desktop.action", kind: .job, params: params)
    }

    static func desktopConnect(_ params: SiloWireDesktopConnectParams) -> SiloGeneratedMethodCall<SiloWireDesktopConnectParams, SiloWireDesktopConnectResult> {
        SiloGeneratedMethodCall<SiloWireDesktopConnectParams, SiloWireDesktopConnectResult>(name: "desktop.connect", kind: .query, params: params)
    }

    static func desktopStatus(_ params: SiloWireComputerTargetParams) -> SiloGeneratedMethodCall<SiloWireComputerTargetParams, SiloWireDesktopStatus> {
        SiloGeneratedMethodCall<SiloWireComputerTargetParams, SiloWireDesktopStatus>(name: "desktop.status", kind: .query, params: params)
    }

    static func deviceDependencies(_ params: SiloWireDependencyReportParams) -> SiloGeneratedMethodCall<SiloWireDependencyReportParams, SiloWireDependencyReport> {
        SiloGeneratedMethodCall<SiloWireDependencyReportParams, SiloWireDependencyReport>(name: "device.dependencies", kind: .query, params: params)
    }

    static func deviceFacts(_ params: SiloWireDeviceParams) -> SiloGeneratedMethodCall<SiloWireDeviceParams, SiloWireDeviceFacts> {
        SiloGeneratedMethodCall<SiloWireDeviceParams, SiloWireDeviceFacts>(name: "device.facts", kind: .query, params: params)
    }

    static func displayClose(_ params: SiloWireComputerTargetParams) -> SiloGeneratedMethodCall<SiloWireComputerTargetParams, SiloNull> {
        SiloGeneratedMethodCall<SiloWireComputerTargetParams, SiloNull>(name: "display.close", kind: .command, params: params)
    }

    static func displayNativeAttach(_ params: SiloWireNativeDisplayAttachParams) -> SiloGeneratedMethodCall<SiloWireNativeDisplayAttachParams, SiloWireNativeDisplayMessage> {
        SiloGeneratedMethodCall<SiloWireNativeDisplayAttachParams, SiloWireNativeDisplayMessage>(name: "display.native.attach", kind: .stream, params: params)
    }

    static func displayShow(_ params: SiloWireComputerTargetParams) -> SiloGeneratedMethodCall<SiloWireComputerTargetParams, SiloNull> {
        SiloGeneratedMethodCall<SiloWireComputerTargetParams, SiloNull>(name: "display.show", kind: .command, params: params)
    }

    static func displayViewerAudioSet(_ params: SiloWireViewerAudioSetParams) -> SiloGeneratedMethodCall<SiloWireViewerAudioSetParams, SiloNull> {
        SiloGeneratedMethodCall<SiloWireViewerAudioSetParams, SiloNull>(name: "display.viewer.audio.set", kind: .command, params: params)
    }

    static func displayViewerClose(_ params: SiloWireViewerConnectionParams) -> SiloGeneratedMethodCall<SiloWireViewerConnectionParams, SiloNull> {
        SiloGeneratedMethodCall<SiloWireViewerConnectionParams, SiloNull>(name: "display.viewer.close", kind: .command, params: params)
    }

    static func displayViewerOpen(_ params: SiloWireComputerTargetParams) -> SiloGeneratedMethodCall<SiloWireComputerTargetParams, SiloWireViewerOpenResult> {
        SiloGeneratedMethodCall<SiloWireComputerTargetParams, SiloWireViewerOpenResult>(name: "display.viewer.open", kind: .command, params: params)
    }

    static func displayViewerScreenReset(_ params: SiloWireViewerConnectionParams) -> SiloGeneratedMethodCall<SiloWireViewerConnectionParams, SiloNull> {
        SiloGeneratedMethodCall<SiloWireViewerConnectionParams, SiloNull>(name: "display.viewer.screen.reset", kind: .command, params: params)
    }

    static func displayViewerSoundCancel(_ params: SiloWireViewerConnectionParams) -> SiloGeneratedMethodCall<SiloWireViewerConnectionParams, SiloNull> {
        SiloGeneratedMethodCall<SiloWireViewerConnectionParams, SiloNull>(name: "display.viewer.sound.cancel", kind: .command, params: params)
    }

    static func displayViewerSoundCheck(_ params: SiloWireViewerConnectionParams) -> SiloGeneratedMethodCall<SiloWireViewerConnectionParams, SiloWireViewerSoundCheckResult> {
        SiloGeneratedMethodCall<SiloWireViewerConnectionParams, SiloWireViewerSoundCheckResult>(name: "display.viewer.sound.check", kind: .query, params: params)
    }

    static func editorCommand(_ params: SiloWireEditorCommandParams) -> SiloGeneratedMethodCall<SiloWireEditorCommandParams, SiloWireCommandResult> {
        SiloGeneratedMethodCall<SiloWireEditorCommandParams, SiloWireCommandResult>(name: "editor.command", kind: .command, params: params)
    }

    static func editorIncludeNotice(_ params: SiloWireEmptyParams) -> SiloGeneratedMethodCall<SiloWireEmptyParams, String?> {
        SiloGeneratedMethodCall<SiloWireEmptyParams, String?>(name: "editor.includeNotice", kind: .query, params: params)
    }

    static func engineDisconnect(_ params: SiloWireEmptyParams) -> SiloGeneratedMethodCall<SiloWireEmptyParams, SiloNull> {
        SiloGeneratedMethodCall<SiloWireEmptyParams, SiloNull>(name: "engine.disconnect", kind: .command, params: params)
    }

    static func engineHandshake(_ params: SiloWireHandshakeParams) -> SiloGeneratedMethodCall<SiloWireHandshakeParams, SiloWireHandshakeResult> {
        SiloGeneratedMethodCall<SiloWireHandshakeParams, SiloWireHandshakeResult>(name: "engine.handshake", kind: .query, params: params)
    }

    static func engineShutdown(_ params: SiloWireEngineShutdownParams) -> SiloGeneratedMethodCall<SiloWireEngineShutdownParams, SiloWireJobStartResult> {
        SiloGeneratedMethodCall<SiloWireEngineShutdownParams, SiloWireJobStartResult>(name: "engine.shutdown", kind: .job, params: params)
    }

    static func engineState(_ params: SiloWireEmptyParams) -> SiloGeneratedMethodCall<SiloWireEmptyParams, SiloWireEngineState> {
        SiloGeneratedMethodCall<SiloWireEmptyParams, SiloWireEngineState>(name: "engine.state", kind: .query, params: params)
    }

    static func engineUpdateAbort(_ params: SiloWireEmptyParams) -> SiloGeneratedMethodCall<SiloWireEmptyParams, SiloNull> {
        SiloGeneratedMethodCall<SiloWireEmptyParams, SiloNull>(name: "engine.update.abort", kind: .command, params: params)
    }

    static func engineUpdatePrepare(_ params: SiloWireEmptyParams) -> SiloGeneratedMethodCall<SiloWireEmptyParams, SiloWireJobStartResult> {
        SiloGeneratedMethodCall<SiloWireEmptyParams, SiloWireJobStartResult>(name: "engine.update.prepare", kind: .job, params: params)
    }

    static func eventsSubscribe(_ params: SiloWireEventsSubscribeParams) -> SiloGeneratedMethodCall<SiloWireEventsSubscribeParams, SiloWireEventsSubscribeResult> {
        SiloGeneratedMethodCall<SiloWireEventsSubscribeParams, SiloWireEventsSubscribeResult>(name: "events.subscribe", kind: .subscription, params: params)
    }

    static func eventsUnsubscribe(_ params: SiloWireEventsUnsubscribeParams) -> SiloGeneratedMethodCall<SiloWireEventsUnsubscribeParams, SiloNull> {
        SiloGeneratedMethodCall<SiloWireEventsUnsubscribeParams, SiloNull>(name: "events.unsubscribe", kind: .command, params: params)
    }

    static func exportsAcknowledge(_ params: SiloWireExportAcknowledgeParams) -> SiloGeneratedMethodCall<SiloWireExportAcknowledgeParams, Bool> {
        SiloGeneratedMethodCall<SiloWireExportAcknowledgeParams, Bool>(name: "exports.acknowledge", kind: .command, params: params)
    }

    static func exportsCreate(_ params: SiloWireExportCreateParams) -> SiloGeneratedMethodCall<SiloWireExportCreateParams, SiloWireJobStartResult> {
        SiloGeneratedMethodCall<SiloWireExportCreateParams, SiloWireJobStartResult>(name: "exports.create", kind: .job, params: params)
    }

    static func exportsDestinationSet(_ params: SiloWireExportDestinationSetParams) -> SiloGeneratedMethodCall<SiloWireExportDestinationSetParams, SiloWireExportDestinationResult> {
        SiloGeneratedMethodCall<SiloWireExportDestinationSetParams, SiloWireExportDestinationResult>(name: "exports.destination.set", kind: .command, params: params)
    }

    static func exportsDismiss(_ params: SiloWireExportDismissParams) -> SiloGeneratedMethodCall<SiloWireExportDismissParams, Bool> {
        SiloGeneratedMethodCall<SiloWireExportDismissParams, Bool>(name: "exports.dismiss", kind: .command, params: params)
    }

    static func exportsImport(_ params: SiloWireExportImportParams) -> SiloGeneratedMethodCall<SiloWireExportImportParams, SiloWireJobStartResult> {
        SiloGeneratedMethodCall<SiloWireExportImportParams, SiloWireJobStartResult>(name: "exports.import", kind: .job, params: params)
    }

    static func exportsInspect(_ params: SiloWireExportInspectParams) -> SiloGeneratedMethodCall<SiloWireExportInspectParams, SiloWireJobStartResult> {
        SiloGeneratedMethodCall<SiloWireExportInspectParams, SiloWireJobStartResult>(name: "exports.inspect", kind: .job, params: params)
    }

    static func exportsState(_ params: SiloWireExportStateParams) -> SiloGeneratedMethodCall<SiloWireExportStateParams, SiloWireBackupState> {
        SiloGeneratedMethodCall<SiloWireExportStateParams, SiloWireBackupState>(name: "exports.state", kind: .query, params: params)
    }

    static func filesDownload(_ params: SiloWireFileDownloadParams) -> SiloGeneratedMethodCall<SiloWireFileDownloadParams, SiloWireJobStartResult> {
        SiloGeneratedMethodCall<SiloWireFileDownloadParams, SiloWireJobStartResult>(name: "files.download", kind: .job, params: params)
    }

    static func filesList(_ params: SiloWireFileListParams) -> SiloGeneratedMethodCall<SiloWireFileListParams, SiloWireFileListResult> {
        SiloGeneratedMethodCall<SiloWireFileListParams, SiloWireFileListResult>(name: "files.list", kind: .query, params: params)
    }

    static func filesUpload(_ params: SiloWireFileUploadParams) -> SiloGeneratedMethodCall<SiloWireFileUploadParams, SiloWireJobStartResult> {
        SiloGeneratedMethodCall<SiloWireFileUploadParams, SiloWireJobStartResult>(name: "files.upload", kind: .job, params: params)
    }

    static func githubAccessSet(_ params: SiloWireGitHubAccessSetParams) -> SiloGeneratedMethodCall<SiloWireGitHubAccessSetParams, SiloWireGitHubState> {
        SiloGeneratedMethodCall<SiloWireGitHubAccessSetParams, SiloWireGitHubState>(name: "github.access.set", kind: .command, params: params)
    }

    static func githubConfigurationRetry(_ params: SiloWireGitHubConfigurationRetryParams) -> SiloGeneratedMethodCall<SiloWireGitHubConfigurationRetryParams, SiloWireGitHubState> {
        SiloGeneratedMethodCall<SiloWireGitHubConfigurationRetryParams, SiloWireGitHubState>(name: "github.configuration.retry", kind: .command, params: params)
    }

    static func githubConfigurationSave(_ params: SiloWireGitHubConfigurationSaveParams) -> SiloGeneratedMethodCall<SiloWireGitHubConfigurationSaveParams, SiloWireGitHubState> {
        SiloGeneratedMethodCall<SiloWireGitHubConfigurationSaveParams, SiloWireGitHubState>(name: "github.configuration.save", kind: .command, params: params)
    }

    static func githubConnect(_ params: SiloWireDeviceParams) -> SiloGeneratedMethodCall<SiloWireDeviceParams, SiloWireJobStartResult> {
        SiloGeneratedMethodCall<SiloWireDeviceParams, SiloWireJobStartResult>(name: "github.connect", kind: .job, params: params)
    }

    static func githubConnectCallback(_ params: SiloWireGitHubConnectCallbackParams) -> SiloGeneratedMethodCall<SiloWireGitHubConnectCallbackParams, SiloNull> {
        SiloGeneratedMethodCall<SiloWireGitHubConnectCallbackParams, SiloNull>(name: "github.connect.callback", kind: .stream, params: params)
    }

    static func githubConnectReopen(_ params: SiloWireDeviceParams) -> SiloGeneratedMethodCall<SiloWireDeviceParams, SiloWireGitHubRepositoriesManageResult> {
        SiloGeneratedMethodCall<SiloWireDeviceParams, SiloWireGitHubRepositoriesManageResult>(name: "github.connect.reopen", kind: .command, params: params)
    }

    static func githubDisconnect(_ params: SiloWireDeviceParams) -> SiloGeneratedMethodCall<SiloWireDeviceParams, SiloWireGitHubState> {
        SiloGeneratedMethodCall<SiloWireDeviceParams, SiloWireGitHubState>(name: "github.disconnect", kind: .command, params: params)
    }

    static func githubPersonalTokenRemove(_ params: SiloWireDeviceParams) -> SiloGeneratedMethodCall<SiloWireDeviceParams, SiloWireGitHubState> {
        SiloGeneratedMethodCall<SiloWireDeviceParams, SiloWireGitHubState>(name: "github.personalToken.remove", kind: .command, params: params)
    }

    static func githubPersonalTokenSave(_ params: SiloWireGitHubPersonalTokenSaveParams) -> SiloGeneratedMethodCall<SiloWireGitHubPersonalTokenSaveParams, SiloWireGitHubState> {
        SiloGeneratedMethodCall<SiloWireGitHubPersonalTokenSaveParams, SiloWireGitHubState>(name: "github.personalToken.save", kind: .command, params: params)
    }

    static func githubRepositoriesManage(_ params: SiloWireDeviceParams) -> SiloGeneratedMethodCall<SiloWireDeviceParams, SiloWireGitHubRepositoriesManageResult> {
        SiloGeneratedMethodCall<SiloWireDeviceParams, SiloWireGitHubRepositoriesManageResult>(name: "github.repositories.manage", kind: .command, params: params)
    }

    static func githubRepositoriesRefresh(_ params: SiloWireDeviceParams) -> SiloGeneratedMethodCall<SiloWireDeviceParams, SiloWireGitHubState> {
        SiloGeneratedMethodCall<SiloWireDeviceParams, SiloWireGitHubState>(name: "github.repositories.refresh", kind: .command, params: params)
    }

    static func githubState(_ params: SiloWireDeviceParams) -> SiloGeneratedMethodCall<SiloWireDeviceParams, SiloWireGitHubState> {
        SiloGeneratedMethodCall<SiloWireDeviceParams, SiloWireGitHubState>(name: "github.state", kind: .query, params: params)
    }

    static func guestAccount(_ params: SiloWireGuestAccountParams) -> SiloGeneratedMethodCall<SiloWireGuestAccountParams, SiloWireGuestAccount> {
        SiloGeneratedMethodCall<SiloWireGuestAccountParams, SiloWireGuestAccount>(name: "guest.account", kind: .query, params: params)
    }

    static func guestExec(_ params: SiloWireGuestExecParams) -> SiloGeneratedMethodCall<SiloWireGuestExecParams, SiloWireGuestExecResult> {
        SiloGeneratedMethodCall<SiloWireGuestExecParams, SiloWireGuestExecResult>(name: "guest.exec", kind: .command, params: params)
    }

    static func guestExecGet(_ params: SiloWireGuestExecGetParams) -> SiloGeneratedMethodCall<SiloWireGuestExecGetParams, SiloWireGuestExecGetResult> {
        SiloGeneratedMethodCall<SiloWireGuestExecGetParams, SiloWireGuestExecGetResult>(name: "guest.exec.get", kind: .query, params: params)
    }

    static func guestExecInput(_ params: SiloWireGuestExecInputParams) -> SiloGeneratedMethodCall<SiloWireGuestExecInputParams, SiloNull> {
        SiloGeneratedMethodCall<SiloWireGuestExecInputParams, SiloNull>(name: "guest.exec.input", kind: .command, params: params)
    }

    static func guestExecStart(_ params: SiloWireGuestExecStartParams) -> SiloGeneratedMethodCall<SiloWireGuestExecStartParams, SiloWireJobStartResult> {
        SiloGeneratedMethodCall<SiloWireGuestExecStartParams, SiloWireJobStartResult>(name: "guest.exec.start", kind: .job, params: params)
    }

    static func guestFilesList(_ params: SiloWireGuestFilesListParams) -> SiloGeneratedMethodCall<SiloWireGuestFilesListParams, SiloWireGuestFilesListResult> {
        SiloGeneratedMethodCall<SiloWireGuestFilesListParams, SiloWireGuestFilesListResult>(name: "guest.files.list", kind: .query, params: params)
    }

    static func guestFilesRead(_ params: SiloWireGuestFilesReadParams) -> SiloGeneratedMethodCall<SiloWireGuestFilesReadParams, SiloWireGuestFilesReadResult> {
        SiloGeneratedMethodCall<SiloWireGuestFilesReadParams, SiloWireGuestFilesReadResult>(name: "guest.files.read", kind: .query, params: params)
    }

    static func guestFilesRemove(_ params: SiloWireGuestFilesRemoveParams) -> SiloGeneratedMethodCall<SiloWireGuestFilesRemoveParams, SiloWireGuestFilesRemoveResult> {
        SiloGeneratedMethodCall<SiloWireGuestFilesRemoveParams, SiloWireGuestFilesRemoveResult>(name: "guest.files.remove", kind: .command, params: params)
    }

    static func guestFilesWatch(_ params: SiloWireGuestFilesWatchParams) -> SiloGeneratedMethodCall<SiloWireGuestFilesWatchParams, SiloWireGuestFilesWatchResult> {
        SiloGeneratedMethodCall<SiloWireGuestFilesWatchParams, SiloWireGuestFilesWatchResult>(name: "guest.files.watch", kind: .subscription, params: params)
    }

    static func guestFilesWrite(_ params: SiloWireGuestFilesWriteParams) -> SiloGeneratedMethodCall<SiloWireGuestFilesWriteParams, SiloWireGuestFilesWriteResult> {
        SiloGeneratedMethodCall<SiloWireGuestFilesWriteParams, SiloWireGuestFilesWriteResult>(name: "guest.files.write", kind: .command, params: params)
    }

    static func guestPrepare(_ params: SiloWireGuestPrepareParams) -> SiloGeneratedMethodCall<SiloWireGuestPrepareParams, SiloWireGuestPrepareResult> {
        SiloGeneratedMethodCall<SiloWireGuestPrepareParams, SiloWireGuestPrepareResult>(name: "guest.prepare", kind: .command, params: params)
    }

    static func guestSsh(_ params: SiloWireGuestSshParams) -> SiloGeneratedMethodCall<SiloWireGuestSshParams, SiloNull> {
        SiloGeneratedMethodCall<SiloWireGuestSshParams, SiloNull>(name: "guest.ssh", kind: .stream, params: params)
    }

    static func guestSshAliasEnsure(_ params: SiloWireGuestSshAliasEnsureParams) -> SiloGeneratedMethodCall<SiloWireGuestSshAliasEnsureParams, SiloWireGuestSshAliasEnsureResult> {
        SiloGeneratedMethodCall<SiloWireGuestSshAliasEnsureParams, SiloWireGuestSshAliasEnsureResult>(name: "guest.sshAlias.ensure", kind: .command, params: params)
    }

    static func guestSshAliasRemove(_ params: SiloWireComputerTargetParams) -> SiloGeneratedMethodCall<SiloWireComputerTargetParams, SiloNull> {
        SiloGeneratedMethodCall<SiloWireComputerTargetParams, SiloNull>(name: "guest.sshAlias.remove", kind: .command, params: params)
    }

    static func logsExport(_ params: SiloWireLogsExportParams) -> SiloGeneratedMethodCall<SiloWireLogsExportParams, SiloWireJobStartResult> {
        SiloGeneratedMethodCall<SiloWireLogsExportParams, SiloWireJobStartResult>(name: "logs.export", kind: .job, params: params)
    }

    static func logsQuery(_ params: SiloWireLogsQueryParams) -> SiloGeneratedMethodCall<SiloWireLogsQueryParams, SiloWireLogPage> {
        SiloGeneratedMethodCall<SiloWireLogsQueryParams, SiloWireLogPage>(name: "logs.query", kind: .query, params: params)
    }

    static func macosDisplayConnect(_ params: SiloWireMacosDisplayConnectParams) -> SiloGeneratedMethodCall<SiloWireMacosDisplayConnectParams, SiloWireMacosDisplayConnectResult> {
        SiloGeneratedMethodCall<SiloWireMacosDisplayConnectParams, SiloWireMacosDisplayConnectResult>(name: "macos.display.connect", kind: .query, params: params)
    }

    static func macosDisplayResize(_ params: SiloWireMacosDisplayResizeParams) -> SiloGeneratedMethodCall<SiloWireMacosDisplayResizeParams, SiloWireMacosDisplayResizeResult> {
        SiloGeneratedMethodCall<SiloWireMacosDisplayResizeParams, SiloWireMacosDisplayResizeResult>(name: "macos.display.resize", kind: .command, params: params)
    }

    static func macosDisplaySession(_ params: SiloWireMacosDisplaySessionParams) -> SiloGeneratedMethodCall<SiloWireMacosDisplaySessionParams, SiloWireMacosDisplaySessionResult> {
        SiloGeneratedMethodCall<SiloWireMacosDisplaySessionParams, SiloWireMacosDisplaySessionResult>(name: "macos.display.session", kind: .command, params: params)
    }

    static func macosDisplayStream(_ params: SiloWireMacosDisplayConnectParams) -> SiloGeneratedMethodCall<SiloWireMacosDisplayConnectParams, SiloNull> {
        SiloGeneratedMethodCall<SiloWireMacosDisplayConnectParams, SiloNull>(name: "macos.display.stream", kind: .stream, params: params)
    }

    static func macosSetupRetry(_ params: SiloWireComputerTargetParams) -> SiloGeneratedMethodCall<SiloWireComputerTargetParams, SiloWireJobStartResult> {
        SiloGeneratedMethodCall<SiloWireComputerTargetParams, SiloWireJobStartResult>(name: "macos.setup.retry", kind: .job, params: params)
    }

    static func macosTemplateDelete(_ params: SiloWireDeviceParams) -> SiloGeneratedMethodCall<SiloWireDeviceParams, SiloNull> {
        SiloGeneratedMethodCall<SiloWireDeviceParams, SiloNull>(name: "macos.template.delete", kind: .command, params: params)
    }

    static func migrationPreUpgradeBackupAcknowledgeNotice(_ params: SiloWireDeviceParams) -> SiloGeneratedMethodCall<SiloWireDeviceParams, SiloNull> {
        SiloGeneratedMethodCall<SiloWireDeviceParams, SiloNull>(name: "migration.preUpgradeBackup.acknowledgeNotice", kind: .command, params: params)
    }

    static func migrationPreUpgradeBackupDelete(_ params: SiloWireDeviceParams) -> SiloGeneratedMethodCall<SiloWireDeviceParams, SiloNull> {
        SiloGeneratedMethodCall<SiloWireDeviceParams, SiloNull>(name: "migration.preUpgradeBackup.delete", kind: .command, params: params)
    }

    static func migrationPreUpgradeBackupGet(_ params: SiloWireDeviceParams) -> SiloGeneratedMethodCall<SiloWireDeviceParams, SiloWirePreUpgradeBackup?> {
        SiloGeneratedMethodCall<SiloWireDeviceParams, SiloWirePreUpgradeBackup?>(name: "migration.preUpgradeBackup.get", kind: .query, params: params)
    }

    static func migrationPreUpgradeBackupMeasure(_ params: SiloWireDeviceParams) -> SiloGeneratedMethodCall<SiloWireDeviceParams, UInt64?> {
        SiloGeneratedMethodCall<SiloWireDeviceParams, UInt64?>(name: "migration.preUpgradeBackup.measure", kind: .query, params: params)
    }

    static func migrationState(_ params: SiloWireDeviceParams) -> SiloGeneratedMethodCall<SiloWireDeviceParams, SiloWireMigrationState> {
        SiloGeneratedMethodCall<SiloWireDeviceParams, SiloWireMigrationState>(name: "migration.state", kind: .query, params: params)
    }

    static func networkOpen(_ params: SiloWireNetworkOpenParams) -> SiloGeneratedMethodCall<SiloWireNetworkOpenParams, SiloWireNetworkOpenResult> {
        SiloGeneratedMethodCall<SiloWireNetworkOpenParams, SiloWireNetworkOpenResult>(name: "network.open", kind: .command, params: params)
    }

    static func networkPublish(_ params: SiloWireNetworkPublishParams) -> SiloGeneratedMethodCall<SiloWireNetworkPublishParams, SiloWireNetworkState> {
        SiloGeneratedMethodCall<SiloWireNetworkPublishParams, SiloWireNetworkState>(name: "network.publish", kind: .command, params: params)
    }

    static func networkState(_ params: SiloWireDeviceParams) -> SiloGeneratedMethodCall<SiloWireDeviceParams, SiloWireNetworkState> {
        SiloGeneratedMethodCall<SiloWireDeviceParams, SiloWireNetworkState>(name: "network.state", kind: .query, params: params)
    }

    static func networkUnpublish(_ params: SiloWireNetworkUnpublishParams) -> SiloGeneratedMethodCall<SiloWireNetworkUnpublishParams, SiloWireNetworkState> {
        SiloGeneratedMethodCall<SiloWireNetworkUnpublishParams, SiloWireNetworkState>(name: "network.unpublish", kind: .command, params: params)
    }

    static func notificationsList(_ params: SiloWireDeviceParams) -> SiloGeneratedMethodCall<SiloWireDeviceParams, [SiloWireNotice]> {
        SiloGeneratedMethodCall<SiloWireDeviceParams, [SiloWireNotice]>(name: "notifications.list", kind: .query, params: params)
    }

    static func operationsCancel(_ params: SiloWireCancelJobParams) -> SiloGeneratedMethodCall<SiloWireCancelJobParams, SiloNull> {
        SiloGeneratedMethodCall<SiloWireCancelJobParams, SiloNull>(name: "operations.cancel", kind: .command, params: params)
    }

    static func operationsJobAcknowledge(_ params: SiloWireAcknowledgeJobParams) -> SiloGeneratedMethodCall<SiloWireAcknowledgeJobParams, SiloNull> {
        SiloGeneratedMethodCall<SiloWireAcknowledgeJobParams, SiloNull>(name: "operations.job.acknowledge", kind: .command, params: params)
    }

    static func operationsJobGet(_ params: SiloWireGetJobParams) -> SiloGeneratedMethodCall<SiloWireGetJobParams, SiloWireJobLookupResult> {
        SiloGeneratedMethodCall<SiloWireGetJobParams, SiloWireJobLookupResult>(name: "operations.job.get", kind: .query, params: params)
    }

    static func operationsList(_ params: SiloWireOperationsListParams) -> SiloGeneratedMethodCall<SiloWireOperationsListParams, SiloWireOperationQueue> {
        SiloGeneratedMethodCall<SiloWireOperationsListParams, SiloWireOperationQueue>(name: "operations.list", kind: .query, params: params)
    }

    static func preparationChatgptRetry(_ params: SiloWireDeviceParams) -> SiloGeneratedMethodCall<SiloWireDeviceParams, SiloWireChatGptPreparationStatus> {
        SiloGeneratedMethodCall<SiloWireDeviceParams, SiloWireChatGptPreparationStatus>(name: "preparation.chatgpt.retry", kind: .command, params: params)
    }

    static func preparationChatgptStatus(_ params: SiloWireDeviceParams) -> SiloGeneratedMethodCall<SiloWireDeviceParams, SiloWireChatGptPreparationStatus> {
        SiloGeneratedMethodCall<SiloWireDeviceParams, SiloWireChatGptPreparationStatus>(name: "preparation.chatgpt.status", kind: .query, params: params)
    }

    static func preparationRetry(_ params: SiloWireEmptyParams) -> SiloGeneratedMethodCall<SiloWireEmptyParams, SiloWirePreparationStatus> {
        SiloGeneratedMethodCall<SiloWireEmptyParams, SiloWirePreparationStatus>(name: "preparation.retry", kind: .command, params: params)
    }

    static func preparationStatus(_ params: SiloWireEmptyParams) -> SiloGeneratedMethodCall<SiloWireEmptyParams, SiloWirePreparationStatus> {
        SiloGeneratedMethodCall<SiloWireEmptyParams, SiloWirePreparationStatus>(name: "preparation.status", kind: .query, params: params)
    }

    static func pushDismiss(_ params: SiloWirePushDismissParams) -> SiloGeneratedMethodCall<SiloWirePushDismissParams, SiloNull> {
        SiloGeneratedMethodCall<SiloWirePushDismissParams, SiloNull>(name: "push.dismiss", kind: .command, params: params)
    }

    static func pushRepositories(_ params: SiloWirePushRepositoriesParams) -> SiloGeneratedMethodCall<SiloWirePushRepositoriesParams, [SiloWirePushRepository]> {
        SiloGeneratedMethodCall<SiloWirePushRepositoriesParams, [SiloWirePushRepository]>(name: "push.repositories", kind: .query, params: params)
    }

    static func pushStart(_ params: SiloWirePushStartParams) -> SiloGeneratedMethodCall<SiloWirePushStartParams, SiloWireJobStartResult> {
        SiloGeneratedMethodCall<SiloWirePushStartParams, SiloWireJobStartResult>(name: "push.start", kind: .job, params: params)
    }

    static func pushStatus(_ params: SiloWirePushStatusParams) -> SiloGeneratedMethodCall<SiloWirePushStatusParams, SiloWirePushOperation?> {
        SiloGeneratedMethodCall<SiloWirePushStatusParams, SiloWirePushOperation?>(name: "push.status", kind: .query, params: params)
    }

    static func secretsList(_ params: SiloWireDeviceParams) -> SiloGeneratedMethodCall<SiloWireDeviceParams, [SiloWireSecret]> {
        SiloGeneratedMethodCall<SiloWireDeviceParams, [SiloWireSecret]>(name: "secrets.list", kind: .query, params: params)
    }

    static func secretsRemove(_ params: SiloWireSecretIdParams) -> SiloGeneratedMethodCall<SiloWireSecretIdParams, [SiloWireSecret]> {
        SiloGeneratedMethodCall<SiloWireSecretIdParams, [SiloWireSecret]>(name: "secrets.remove", kind: .command, params: params)
    }

    static func secretsRetry(_ params: SiloWireSecretIdParams) -> SiloGeneratedMethodCall<SiloWireSecretIdParams, [SiloWireSecret]> {
        SiloGeneratedMethodCall<SiloWireSecretIdParams, [SiloWireSecret]>(name: "secrets.retry", kind: .command, params: params)
    }

    static func secretsSave(_ params: SiloWireSecretsSaveParams) -> SiloGeneratedMethodCall<SiloWireSecretsSaveParams, [SiloWireSecret]> {
        SiloGeneratedMethodCall<SiloWireSecretsSaveParams, [SiloWireSecret]>(name: "secrets.save", kind: .command, params: params)
    }

    static func settingsFlush(_ params: SiloWireEmptyParams) -> SiloGeneratedMethodCall<SiloWireEmptyParams, SiloNull> {
        SiloGeneratedMethodCall<SiloWireEmptyParams, SiloNull>(name: "settings.flush", kind: .command, params: params)
    }

    static func settingsRead(_ params: SiloWireEmptyParams) -> SiloGeneratedMethodCall<SiloWireEmptyParams, SiloWireSettingsSnapshot> {
        SiloGeneratedMethodCall<SiloWireEmptyParams, SiloWireSettingsSnapshot>(name: "settings.read", kind: .query, params: params)
    }

    static func settingsUpdate(_ params: SiloWireSettingsUpdateParams) -> SiloGeneratedMethodCall<SiloWireSettingsUpdateParams, SiloWireSettingsSnapshot> {
        SiloGeneratedMethodCall<SiloWireSettingsUpdateParams, SiloWireSettingsSnapshot>(name: "settings.update", kind: .command, params: params)
    }

    static func sshAccessConnection(_ params: SiloWireSSHAccessConnectionParams) -> SiloGeneratedMethodCall<SiloWireSSHAccessConnectionParams, String?> {
        SiloGeneratedMethodCall<SiloWireSSHAccessConnectionParams, String?>(name: "sshAccess.connection", kind: .command, params: params)
    }

    static func sshAccessSave(_ params: SiloWireSSHAccessSaveParams) -> SiloGeneratedMethodCall<SiloWireSSHAccessSaveParams, SiloWireSSHAccessState> {
        SiloGeneratedMethodCall<SiloWireSSHAccessSaveParams, SiloWireSSHAccessState>(name: "sshAccess.save", kind: .command, params: params)
    }

    static func sshAccessState(_ params: SiloWireDeviceParams) -> SiloGeneratedMethodCall<SiloWireDeviceParams, SiloWireSSHAccessState> {
        SiloGeneratedMethodCall<SiloWireDeviceParams, SiloWireSSHAccessState>(name: "sshAccess.state", kind: .query, params: params)
    }

    static func storageRead(_ params: SiloWireStorageParams) -> SiloGeneratedMethodCall<SiloWireStorageParams, SiloWireStorageState> {
        SiloGeneratedMethodCall<SiloWireStorageParams, SiloWireStorageState>(name: "storage.read", kind: .query, params: params)
    }

    static func storageReclaim(_ params: SiloWireStorageParams) -> SiloGeneratedMethodCall<SiloWireStorageParams, SiloWireJobStartResult> {
        SiloGeneratedMethodCall<SiloWireStorageParams, SiloWireJobStartResult>(name: "storage.reclaim", kind: .job, params: params)
    }

    static func terminalCommand(_ params: SiloWireTerminalCommandParams) -> SiloGeneratedMethodCall<SiloWireTerminalCommandParams, SiloWireCommandResult> {
        SiloGeneratedMethodCall<SiloWireTerminalCommandParams, SiloWireCommandResult>(name: "terminal.command", kind: .query, params: params)
    }

    static func updatesCheck(_ params: SiloWireEmptyParams) -> SiloGeneratedMethodCall<SiloWireEmptyParams, SiloWireUpdateSnapshot> {
        SiloGeneratedMethodCall<SiloWireEmptyParams, SiloWireUpdateSnapshot>(name: "updates.check", kind: .command, params: params)
    }

    static func updatesDownload(_ params: SiloWireEmptyParams) -> SiloGeneratedMethodCall<SiloWireEmptyParams, SiloWireJobStartResult> {
        SiloGeneratedMethodCall<SiloWireEmptyParams, SiloWireJobStartResult>(name: "updates.download", kind: .job, params: params)
    }

    static func updatesFocused(_ params: SiloWireEmptyParams) -> SiloGeneratedMethodCall<SiloWireEmptyParams, SiloNull> {
        SiloGeneratedMethodCall<SiloWireEmptyParams, SiloNull>(name: "updates.focused", kind: .command, params: params)
    }

    static func updatesSetAutomaticChecks(_ params: SiloWireUpdatesSetAutomaticChecksParams) -> SiloGeneratedMethodCall<SiloWireUpdatesSetAutomaticChecksParams, SiloWireUpdateSnapshot> {
        SiloGeneratedMethodCall<SiloWireUpdatesSetAutomaticChecksParams, SiloWireUpdateSnapshot>(name: "updates.setAutomaticChecks", kind: .command, params: params)
    }

    static func updatesState(_ params: SiloWireEmptyParams) -> SiloGeneratedMethodCall<SiloWireEmptyParams, SiloWireUpdateSnapshot> {
        SiloGeneratedMethodCall<SiloWireEmptyParams, SiloWireUpdateSnapshot>(name: "updates.state", kind: .query, params: params)
    }
}
