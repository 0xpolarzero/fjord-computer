// This file was generated from JSON Schema using quicktype, do not modify it directly.
// To parse the JSON, add this file to your project and do:
//
//   let siloWireAcknowledgeJobParams = try? JSONDecoder().decode(SiloWireAcknowledgeJobParams.self, from: jsonData)
//   let siloWireApplicationComputer = try? JSONDecoder().decode(SiloWireApplicationComputer.self, from: jsonData)
//   let siloWireApplicationSource = try? JSONDecoder().decode(SiloWireApplicationSource.self, from: jsonData)
//   let siloWireApprovalMode = try? JSONDecoder().decode(SiloWireApprovalMode.self, from: jsonData)
//   let siloWireArchive = try? JSONDecoder().decode(SiloWireArchive.self, from: jsonData)
//   let siloWireArchiveInspectionResult = try? JSONDecoder().decode(SiloWireArchiveInspectionResult.self, from: jsonData)
//   let siloWireAttentionLevel = try? JSONDecoder().decode(SiloWireAttentionLevel.self, from: jsonData)
//   let siloWireBackupAvailability = try? JSONDecoder().decode(SiloWireBackupAvailability.self, from: jsonData)
//   let siloWireBackupOperation = try? JSONDecoder().decode(SiloWireBackupOperation.self, from: jsonData)
//   let siloWireBackupOperationKind = try? JSONDecoder().decode(SiloWireBackupOperationKind.self, from: jsonData)
//   let siloWireBackupOutcome = try? JSONDecoder().decode(SiloWireBackupOutcome.self, from: jsonData)
//   let siloWireBackupPhase = try? JSONDecoder().decode(SiloWireBackupPhase.self, from: jsonData)
//   let siloWireBackupState = try? JSONDecoder().decode(SiloWireBackupState.self, from: jsonData)
//   let siloWireCancelJobParams = try? JSONDecoder().decode(SiloWireCancelJobParams.self, from: jsonData)
//   let siloWireChatGptPreparationStatus = try? JSONDecoder().decode(SiloWireChatGptPreparationStatus.self, from: jsonData)
//   let siloWireCheckpoint = try? JSONDecoder().decode(SiloWireCheckpoint.self, from: jsonData)
//   let siloWireCheckpointCreateParams = try? JSONDecoder().decode(SiloWireCheckpointCreateParams.self, from: jsonData)
//   let siloWireCheckpointCreatedResult = try? JSONDecoder().decode(SiloWireCheckpointCreatedResult.self, from: jsonData)
//   let siloWireCheckpointForkParams = try? JSONDecoder().decode(SiloWireCheckpointForkParams.self, from: jsonData)
//   let siloWireCheckpointKind = try? JSONDecoder().decode(SiloWireCheckpointKind.self, from: jsonData)
//   let siloWireCheckpointReason = try? JSONDecoder().decode(SiloWireCheckpointReason.self, from: jsonData)
//   let siloWireCheckpointScope = try? JSONDecoder().decode(SiloWireCheckpointScope.self, from: jsonData)
//   let siloWireCheckpointTargetParams = try? JSONDecoder().decode(SiloWireCheckpointTargetParams.self, from: jsonData)
//   let siloWireCheckpointUsage = try? JSONDecoder().decode(SiloWireCheckpointUsage.self, from: jsonData)
//   let siloWireCheckpointUsageEntry = try? JSONDecoder().decode(SiloWireCheckpointUsageEntry.self, from: jsonData)
//   let siloWireCheckpointUsageParams = try? JSONDecoder().decode(SiloWireCheckpointUsageParams.self, from: jsonData)
//   let siloWireClientMetadata = try? JSONDecoder().decode(SiloWireClientMetadata.self, from: jsonData)
//   let siloWireClipboardAction = try? JSONDecoder().decode(SiloWireClipboardAction.self, from: jsonData)
//   let siloWireClipboardContent = try? JSONDecoder().decode(SiloWireClipboardContent.self, from: jsonData)
//   let siloWireClipboardTransferContent = try? JSONDecoder().decode(SiloWireClipboardTransferContent.self, from: jsonData)
//   let siloWireClipboardTransferParams = try? JSONDecoder().decode(SiloWireClipboardTransferParams.self, from: jsonData)
//   let siloWireClipboardTransferResult = try? JSONDecoder().decode(SiloWireClipboardTransferResult.self, from: jsonData)
//   let siloWireClipboardTransferStatus = try? JSONDecoder().decode(SiloWireClipboardTransferStatus.self, from: jsonData)
//   let siloWireClipboardWritableContent = try? JSONDecoder().decode(SiloWireClipboardWritableContent.self, from: jsonData)
//   let siloWireClipboardWriteParams = try? JSONDecoder().decode(SiloWireClipboardWriteParams.self, from: jsonData)
//   let siloWireCommandResult = try? JSONDecoder().decode(SiloWireCommandResult.self, from: jsonData)
//   let siloWireComputerAttention = try? JSONDecoder().decode(SiloWireComputerAttention.self, from: jsonData)
//   let siloWireComputerConfiguration = try? JSONDecoder().decode(SiloWireComputerConfiguration.self, from: jsonData)
//   let siloWireComputerConfigurationChange = try? JSONDecoder().decode(SiloWireComputerConfigurationChange.self, from: jsonData)
//   let siloWireComputerConfigurationChangeParams = try? JSONDecoder().decode(SiloWireComputerConfigurationChangeParams.self, from: jsonData)
//   let siloWireComputerConfigurationProgress = try? JSONDecoder().decode(SiloWireComputerConfigurationProgress.self, from: jsonData)
//   let siloWireComputerConfigurationRequest = try? JSONDecoder().decode(SiloWireComputerConfigurationRequest.self, from: jsonData)
//   let siloWireComputerConfigurationRetryParams = try? JSONDecoder().decode(SiloWireComputerConfigurationRetryParams.self, from: jsonData)
//   let siloWireComputerCreateParams = try? JSONDecoder().decode(SiloWireComputerCreateParams.self, from: jsonData)
//   let siloWireComputerCreateResult = try? JSONDecoder().decode(SiloWireComputerCreateResult.self, from: jsonData)
//   let siloWireComputerCreationSkipWaitParams = try? JSONDecoder().decode(SiloWireComputerCreationSkipWaitParams.self, from: jsonData)
//   let siloWireComputerDeleteParams = try? JSONDecoder().decode(SiloWireComputerDeleteParams.self, from: jsonData)
//   let siloWireComputerIdentitiesParams = try? JSONDecoder().decode(SiloWireComputerIdentitiesParams.self, from: jsonData)
//   let siloWireComputerIdentity = try? JSONDecoder().decode(SiloWireComputerIdentity.self, from: jsonData)
//   let siloWireComputerKind = try? JSONDecoder().decode(SiloWireComputerKind.self, from: jsonData)
//   let siloWireComputerListParams = try? JSONDecoder().decode(SiloWireComputerListParams.self, from: jsonData)
//   let siloWireComputerShellParams = try? JSONDecoder().decode(SiloWireComputerShellParams.self, from: jsonData)
//   let siloWireComputerTargetParams = try? JSONDecoder().decode(SiloWireComputerTargetParams.self, from: jsonData)
//   let siloWireComputerUseApprovalApplyState = try? JSONDecoder().decode(SiloWireComputerUseApprovalApplyState.self, from: jsonData)
//   let siloWireComputerUseApprovalParams = try? JSONDecoder().decode(SiloWireComputerUseApprovalParams.self, from: jsonData)
//   let siloWireComputerUseApprovalState = try? JSONDecoder().decode(SiloWireComputerUseApprovalState.self, from: jsonData)
//   let siloWireComputerUseCause = try? JSONDecoder().decode(SiloWireComputerUseCause.self, from: jsonData)
//   let siloWireComputerUseCompatibility = try? JSONDecoder().decode(SiloWireComputerUseCompatibility.self, from: jsonData)
//   let siloWireComputerUseInstallState = try? JSONDecoder().decode(SiloWireComputerUseInstallState.self, from: jsonData)
//   let siloWireComputerUseState = try? JSONDecoder().decode(SiloWireComputerUseState.self, from: jsonData)
//   let siloWireComputerUseStateParams = try? JSONDecoder().decode(SiloWireComputerUseStateParams.self, from: jsonData)
//   let siloWireComputersChangedPayload = try? JSONDecoder().decode(SiloWireComputersChangedPayload.self, from: jsonData)
//   let siloWireComputersListResult = try? JSONDecoder().decode(SiloWireComputersListResult.self, from: jsonData)
//   let siloWireConflictPolicy = try? JSONDecoder().decode(SiloWireConflictPolicy.self, from: jsonData)
//   let siloWireConnectDeviceParams = try? JSONDecoder().decode(SiloWireConnectDeviceParams.self, from: jsonData)
//   let siloWireConnectionsSetEnabledParams = try? JSONDecoder().decode(SiloWireConnectionsSetEnabledParams.self, from: jsonData)
//   let siloWireConnectionsStatus = try? JSONDecoder().decode(SiloWireConnectionsStatus.self, from: jsonData)
//   let siloWireDependencyCheck = try? JSONDecoder().decode(SiloWireDependencyCheck.self, from: jsonData)
//   let siloWireDependencyReport = try? JSONDecoder().decode(SiloWireDependencyReport.self, from: jsonData)
//   let siloWireDependencyReportParams = try? JSONDecoder().decode(SiloWireDependencyReportParams.self, from: jsonData)
//   let siloWireDependencyStatus = try? JSONDecoder().decode(SiloWireDependencyStatus.self, from: jsonData)
//   let siloWireDesktopAction = try? JSONDecoder().decode(SiloWireDesktopAction.self, from: jsonData)
//   let siloWireDesktopActionParams = try? JSONDecoder().decode(SiloWireDesktopActionParams.self, from: jsonData)
//   let siloWireDesktopConfiguration = try? JSONDecoder().decode(SiloWireDesktopConfiguration.self, from: jsonData)
//   let siloWireDesktopConnectParams = try? JSONDecoder().decode(SiloWireDesktopConnectParams.self, from: jsonData)
//   let siloWireDesktopConnectResult = try? JSONDecoder().decode(SiloWireDesktopConnectResult.self, from: jsonData)
//   let siloWireDesktopStatus = try? JSONDecoder().decode(SiloWireDesktopStatus.self, from: jsonData)
//   let siloWireDevice = try? JSONDecoder().decode(SiloWireDevice.self, from: jsonData)
//   let siloWireDeviceAddress = try? JSONDecoder().decode(SiloWireDeviceAddress.self, from: jsonData)
//   let siloWireDeviceAddressKind = try? JSONDecoder().decode(SiloWireDeviceAddressKind.self, from: jsonData)
//   let siloWireDeviceCapacity = try? JSONDecoder().decode(SiloWireDeviceCapacity.self, from: jsonData)
//   let siloWireDeviceFacts = try? JSONDecoder().decode(SiloWireDeviceFacts.self, from: jsonData)
//   let siloWireDeviceHealth = try? JSONDecoder().decode(SiloWireDeviceHealth.self, from: jsonData)
//   let siloWireDeviceHealthResult = try? JSONDecoder().decode(SiloWireDeviceHealthResult.self, from: jsonData)
//   let siloWireDeviceIdParams = try? JSONDecoder().decode(SiloWireDeviceIdParams.self, from: jsonData)
//   let siloWireDeviceParams = try? JSONDecoder().decode(SiloWireDeviceParams.self, from: jsonData)
//   let siloWireDisplayAxis = try? JSONDecoder().decode(SiloWireDisplayAxis.self, from: jsonData)
//   let siloWireDownloadOutcome = try? JSONDecoder().decode(SiloWireDownloadOutcome.self, from: jsonData)
//   let siloWireEditorCommandParams = try? JSONDecoder().decode(SiloWireEditorCommandParams.self, from: jsonData)
//   let siloWireEmptyParams = try? JSONDecoder().decode(SiloWireEmptyParams.self, from: jsonData)
//   let siloWireEngineShutdownParams = try? JSONDecoder().decode(SiloWireEngineShutdownParams.self, from: jsonData)
//   let siloWireEngineState = try? JSONDecoder().decode(SiloWireEngineState.self, from: jsonData)
//   let siloWireEngineUpdatePrepareFinishedResult = try? JSONDecoder().decode(SiloWireEngineUpdatePrepareFinishedResult.self, from: jsonData)
//   let siloWireErrorCode = try? JSONDecoder().decode(SiloWireErrorCode.self, from: jsonData)
//   let siloWireErrorContractSchema = try? JSONDecoder().decode(SiloWireErrorContractSchema.self, from: jsonData)
//   let siloWireErrorObject = try? JSONDecoder().decode(SiloWireErrorObject.self, from: jsonData)
//   let siloWireEventEnvelope = try? JSONDecoder().decode(SiloWireEventEnvelope.self, from: jsonData)
//   let siloWireEventsSubscribeParams = try? JSONDecoder().decode(SiloWireEventsSubscribeParams.self, from: jsonData)
//   let siloWireEventsSubscribeResult = try? JSONDecoder().decode(SiloWireEventsSubscribeResult.self, from: jsonData)
//   let siloWireEventsUnsubscribeParams = try? JSONDecoder().decode(SiloWireEventsUnsubscribeParams.self, from: jsonData)
//   let siloWireExportAcknowledgeParams = try? JSONDecoder().decode(SiloWireExportAcknowledgeParams.self, from: jsonData)
//   let siloWireExportCreateParams = try? JSONDecoder().decode(SiloWireExportCreateParams.self, from: jsonData)
//   let siloWireExportDestinationResult = try? JSONDecoder().decode(SiloWireExportDestinationResult.self, from: jsonData)
//   let siloWireExportDestinationSetParams = try? JSONDecoder().decode(SiloWireExportDestinationSetParams.self, from: jsonData)
//   let siloWireExportDismissParams = try? JSONDecoder().decode(SiloWireExportDismissParams.self, from: jsonData)
//   let siloWireExportImportParams = try? JSONDecoder().decode(SiloWireExportImportParams.self, from: jsonData)
//   let siloWireExportInspectParams = try? JSONDecoder().decode(SiloWireExportInspectParams.self, from: jsonData)
//   let siloWireExportStateParams = try? JSONDecoder().decode(SiloWireExportStateParams.self, from: jsonData)
//   let siloWireFileDownloadParams = try? JSONDecoder().decode(SiloWireFileDownloadParams.self, from: jsonData)
//   let siloWireFileEntry = try? JSONDecoder().decode(SiloWireFileEntry.self, from: jsonData)
//   let siloWireFileEntryKind = try? JSONDecoder().decode(SiloWireFileEntryKind.self, from: jsonData)
//   let siloWireFileListParams = try? JSONDecoder().decode(SiloWireFileListParams.self, from: jsonData)
//   let siloWireFileListResult = try? JSONDecoder().decode(SiloWireFileListResult.self, from: jsonData)
//   let siloWireFileUploadParams = try? JSONDecoder().decode(SiloWireFileUploadParams.self, from: jsonData)
//   let siloWireFreshness = try? JSONDecoder().decode(SiloWireFreshness.self, from: jsonData)
//   let siloWireGetJobParams = try? JSONDecoder().decode(SiloWireGetJobParams.self, from: jsonData)
//   let siloWireGitHubAccessSetParams = try? JSONDecoder().decode(SiloWireGitHubAccessSetParams.self, from: jsonData)
//   let siloWireGitHubAuthenticationMethod = try? JSONDecoder().decode(SiloWireGitHubAuthenticationMethod.self, from: jsonData)
//   let siloWireGitHubComputerOperation = try? JSONDecoder().decode(SiloWireGitHubComputerOperation.self, from: jsonData)
//   let siloWireGitHubComputerOperationStatus = try? JSONDecoder().decode(SiloWireGitHubComputerOperationStatus.self, from: jsonData)
//   let siloWireGitHubConfiguration = try? JSONDecoder().decode(SiloWireGitHubConfiguration.self, from: jsonData)
//   let siloWireGitHubConfigurationRetryParams = try? JSONDecoder().decode(SiloWireGitHubConfigurationRetryParams.self, from: jsonData)
//   let siloWireGitHubConfigurationSaveParams = try? JSONDecoder().decode(SiloWireGitHubConfigurationSaveParams.self, from: jsonData)
//   let siloWireGitHubConnectCallbackParams = try? JSONDecoder().decode(SiloWireGitHubConnectCallbackParams.self, from: jsonData)
//   let siloWireGitHubConnectionState = try? JSONDecoder().decode(SiloWireGitHubConnectionState.self, from: jsonData)
//   let siloWireGitHubDeviceIdentity = try? JSONDecoder().decode(SiloWireGitHubDeviceIdentity.self, from: jsonData)
//   let siloWireGitHubIdentity = try? JSONDecoder().decode(SiloWireGitHubIdentity.self, from: jsonData)
//   let siloWireGitHubPersonalToken = try? JSONDecoder().decode(SiloWireGitHubPersonalToken.self, from: jsonData)
//   let siloWireGitHubPersonalTokenSaveParams = try? JSONDecoder().decode(SiloWireGitHubPersonalTokenSaveParams.self, from: jsonData)
//   let siloWireGitHubPersonalTokenState = try? JSONDecoder().decode(SiloWireGitHubPersonalTokenState.self, from: jsonData)
//   let siloWireGitHubPolicy = try? JSONDecoder().decode(SiloWireGitHubPolicy.self, from: jsonData)
//   let siloWireGitHubRepositoriesManageResult = try? JSONDecoder().decode(SiloWireGitHubRepositoriesManageResult.self, from: jsonData)
//   let siloWireGitHubRepositoryCatalogStatus = try? JSONDecoder().decode(SiloWireGitHubRepositoryCatalogStatus.self, from: jsonData)
//   let siloWireGitHubRepositoryMode = try? JSONDecoder().decode(SiloWireGitHubRepositoryMode.self, from: jsonData)
//   let siloWireGitHubRepositoryPolicy = try? JSONDecoder().decode(SiloWireGitHubRepositoryPolicy.self, from: jsonData)
//   let siloWireGitHubState = try? JSONDecoder().decode(SiloWireGitHubState.self, from: jsonData)
//   let siloWireGuestAccount = try? JSONDecoder().decode(SiloWireGuestAccount.self, from: jsonData)
//   let siloWireGuestAccountParams = try? JSONDecoder().decode(SiloWireGuestAccountParams.self, from: jsonData)
//   let siloWireGuestEnvVar = try? JSONDecoder().decode(SiloWireGuestEnvVar.self, from: jsonData)
//   let siloWireGuestExecExitedEvent = try? JSONDecoder().decode(SiloWireGuestExecExitedEvent.self, from: jsonData)
//   let siloWireGuestExecFinishedResult = try? JSONDecoder().decode(SiloWireGuestExecFinishedResult.self, from: jsonData)
//   let siloWireGuestExecGetParams = try? JSONDecoder().decode(SiloWireGuestExecGetParams.self, from: jsonData)
//   let siloWireGuestExecGetResult = try? JSONDecoder().decode(SiloWireGuestExecGetResult.self, from: jsonData)
//   let siloWireGuestExecInputParams = try? JSONDecoder().decode(SiloWireGuestExecInputParams.self, from: jsonData)
//   let siloWireGuestExecOutput = try? JSONDecoder().decode(SiloWireGuestExecOutput.self, from: jsonData)
//   let siloWireGuestExecOutputEvent = try? JSONDecoder().decode(SiloWireGuestExecOutputEvent.self, from: jsonData)
//   let siloWireGuestExecParams = try? JSONDecoder().decode(SiloWireGuestExecParams.self, from: jsonData)
//   let siloWireGuestExecResult = try? JSONDecoder().decode(SiloWireGuestExecResult.self, from: jsonData)
//   let siloWireGuestExecStartParams = try? JSONDecoder().decode(SiloWireGuestExecStartParams.self, from: jsonData)
//   let siloWireGuestExecState = try? JSONDecoder().decode(SiloWireGuestExecState.self, from: jsonData)
//   let siloWireGuestExecStream = try? JSONDecoder().decode(SiloWireGuestExecStream.self, from: jsonData)
//   let siloWireGuestExecUser = try? JSONDecoder().decode(SiloWireGuestExecUser.self, from: jsonData)
//   let siloWireGuestFileEntry = try? JSONDecoder().decode(SiloWireGuestFileEntry.self, from: jsonData)
//   let siloWireGuestFileKind = try? JSONDecoder().decode(SiloWireGuestFileKind.self, from: jsonData)
//   let siloWireGuestFileReplace = try? JSONDecoder().decode(SiloWireGuestFileReplace.self, from: jsonData)
//   let siloWireGuestFilesChangedPayload = try? JSONDecoder().decode(SiloWireGuestFilesChangedPayload.self, from: jsonData)
//   let siloWireGuestFilesListParams = try? JSONDecoder().decode(SiloWireGuestFilesListParams.self, from: jsonData)
//   let siloWireGuestFilesListResult = try? JSONDecoder().decode(SiloWireGuestFilesListResult.self, from: jsonData)
//   let siloWireGuestFilesReadParams = try? JSONDecoder().decode(SiloWireGuestFilesReadParams.self, from: jsonData)
//   let siloWireGuestFilesReadResult = try? JSONDecoder().decode(SiloWireGuestFilesReadResult.self, from: jsonData)
//   let siloWireGuestFilesRemoveParams = try? JSONDecoder().decode(SiloWireGuestFilesRemoveParams.self, from: jsonData)
//   let siloWireGuestFilesRemoveResult = try? JSONDecoder().decode(SiloWireGuestFilesRemoveResult.self, from: jsonData)
//   let siloWireGuestFilesWatchParams = try? JSONDecoder().decode(SiloWireGuestFilesWatchParams.self, from: jsonData)
//   let siloWireGuestFilesWatchResult = try? JSONDecoder().decode(SiloWireGuestFilesWatchResult.self, from: jsonData)
//   let siloWireGuestFilesWriteParams = try? JSONDecoder().decode(SiloWireGuestFilesWriteParams.self, from: jsonData)
//   let siloWireGuestFilesWriteResult = try? JSONDecoder().decode(SiloWireGuestFilesWriteResult.self, from: jsonData)
//   let siloWireGuestPrepareParams = try? JSONDecoder().decode(SiloWireGuestPrepareParams.self, from: jsonData)
//   let siloWireGuestPrepareResult = try? JSONDecoder().decode(SiloWireGuestPrepareResult.self, from: jsonData)
//   let siloWireGuestSshAliasEnsureParams = try? JSONDecoder().decode(SiloWireGuestSshAliasEnsureParams.self, from: jsonData)
//   let siloWireGuestSshAliasEnsureResult = try? JSONDecoder().decode(SiloWireGuestSshAliasEnsureResult.self, from: jsonData)
//   let siloWireGuestSshParams = try? JSONDecoder().decode(SiloWireGuestSshParams.self, from: jsonData)
//   let siloWireGuestSshPurpose = try? JSONDecoder().decode(SiloWireGuestSshPurpose.self, from: jsonData)
//   let siloWireHandshakeParams = try? JSONDecoder().decode(SiloWireHandshakeParams.self, from: jsonData)
//   let siloWireHandshakeResult = try? JSONDecoder().decode(SiloWireHandshakeResult.self, from: jsonData)
//   let siloWireIncompatibleVersionDiagnostics = try? JSONDecoder().decode(SiloWireIncompatibleVersionDiagnostics.self, from: jsonData)
//   let siloWireJobContractSchema = try? JSONDecoder().decode(SiloWireJobContractSchema.self, from: jsonData)
//   let siloWireJobFinished = try? JSONDecoder().decode(SiloWireJobFinished.self, from: jsonData)
//   let siloWireJobId = try? JSONDecoder().decode(SiloWireJobId.self, from: jsonData)
//   let siloWireJobLookupResult = try? JSONDecoder().decode(SiloWireJobLookupResult.self, from: jsonData)
//   let siloWireJobOutcome = try? JSONDecoder().decode(SiloWireJobOutcome.self, from: jsonData)
//   let siloWireJobOutcomeChunk = try? JSONDecoder().decode(SiloWireJobOutcomeChunk.self, from: jsonData)
//   let siloWireJobProgress = try? JSONDecoder().decode(SiloWireJobProgress.self, from: jsonData)
//   let siloWireJobStartResult = try? JSONDecoder().decode(SiloWireJobStartResult.self, from: jsonData)
//   let siloWireJobState = try? JSONDecoder().decode(SiloWireJobState.self, from: jsonData)
//   let siloWireJobTerminalResultsSchema = try? JSONDecoder().decode(SiloWireJobTerminalResultsSchema.self, from: jsonData)
//   let siloWireLaunchPass = try? JSONDecoder().decode(SiloWireLaunchPass.self, from: jsonData)
//   let siloWireLaunchStatus = try? JSONDecoder().decode(SiloWireLaunchStatus.self, from: jsonData)
//   let siloWireLifecycleProgress = try? JSONDecoder().decode(SiloWireLifecycleProgress.self, from: jsonData)
//   let siloWireLifecycleStep = try? JSONDecoder().decode(SiloWireLifecycleStep.self, from: jsonData)
//   let siloWireLinuxComputerState = try? JSONDecoder().decode(SiloWireLinuxComputerState.self, from: jsonData)
//   let siloWireLogEntry = try? JSONDecoder().decode(SiloWireLogEntry.self, from: jsonData)
//   let siloWireLogPage = try? JSONDecoder().decode(SiloWireLogPage.self, from: jsonData)
//   let siloWireLogSource = try? JSONDecoder().decode(SiloWireLogSource.self, from: jsonData)
//   let siloWireLogsExportParams = try? JSONDecoder().decode(SiloWireLogsExportParams.self, from: jsonData)
//   let siloWireLogsQueryParams = try? JSONDecoder().decode(SiloWireLogsQueryParams.self, from: jsonData)
//   let siloWireMacosComputer = try? JSONDecoder().decode(SiloWireMacosComputer.self, from: jsonData)
//   let siloWireMacosComputerCreateRequest = try? JSONDecoder().decode(SiloWireMacosComputerCreateRequest.self, from: jsonData)
//   let siloWireMacosComputerState = try? JSONDecoder().decode(SiloWireMacosComputerState.self, from: jsonData)
//   let siloWireMacosComputersState = try? JSONDecoder().decode(SiloWireMacosComputersState.self, from: jsonData)
//   let siloWireMacosDisplayConnectParams = try? JSONDecoder().decode(SiloWireMacosDisplayConnectParams.self, from: jsonData)
//   let siloWireMacosDisplayConnectResult = try? JSONDecoder().decode(SiloWireMacosDisplayConnectResult.self, from: jsonData)
//   let siloWireMacosDisplayResizeParams = try? JSONDecoder().decode(SiloWireMacosDisplayResizeParams.self, from: jsonData)
//   let siloWireMacosDisplayResizeResult = try? JSONDecoder().decode(SiloWireMacosDisplayResizeResult.self, from: jsonData)
//   let siloWireMacosDisplaySessionParams = try? JSONDecoder().decode(SiloWireMacosDisplaySessionParams.self, from: jsonData)
//   let siloWireMacosDisplaySessionResult = try? JSONDecoder().decode(SiloWireMacosDisplaySessionResult.self, from: jsonData)
//   let siloWireMacosHostLimits = try? JSONDecoder().decode(SiloWireMacosHostLimits.self, from: jsonData)
//   let siloWireMacosJobProgress = try? JSONDecoder().decode(SiloWireMacosJobProgress.self, from: jsonData)
//   let siloWireMacosResourceConfiguration = try? JSONDecoder().decode(SiloWireMacosResourceConfiguration.self, from: jsonData)
//   let siloWireMethodContractSchema = try? JSONDecoder().decode(SiloWireMethodContractSchema.self, from: jsonData)
//   let siloWireMethodName = try? JSONDecoder().decode(SiloWireMethodName.self, from: jsonData)
//   let siloWireMethodParams = try? JSONDecoder().decode(SiloWireMethodParams.self, from: jsonData)
//   let siloWireMethodResults = try? JSONDecoder().decode(SiloWireMethodResults.self, from: jsonData)
//   let siloWireMigrationState = try? JSONDecoder().decode(SiloWireMigrationState.self, from: jsonData)
//   let siloWireNativeDisplayAttachParams = try? JSONDecoder().decode(SiloWireNativeDisplayAttachParams.self, from: jsonData)
//   let siloWireNativeDisplayMessage = try? JSONDecoder().decode(SiloWireNativeDisplayMessage.self, from: jsonData)
//   let siloWireNetworkComputer = try? JSONDecoder().decode(SiloWireNetworkComputer.self, from: jsonData)
//   let siloWireNetworkOpenParams = try? JSONDecoder().decode(SiloWireNetworkOpenParams.self, from: jsonData)
//   let siloWireNetworkOpenResult = try? JSONDecoder().decode(SiloWireNetworkOpenResult.self, from: jsonData)
//   let siloWireNetworkPublishParams = try? JSONDecoder().decode(SiloWireNetworkPublishParams.self, from: jsonData)
//   let siloWireNetworkScheme = try? JSONDecoder().decode(SiloWireNetworkScheme.self, from: jsonData)
//   let siloWireNetworkState = try? JSONDecoder().decode(SiloWireNetworkState.self, from: jsonData)
//   let siloWireNetworkUnpublishParams = try? JSONDecoder().decode(SiloWireNetworkUnpublishParams.self, from: jsonData)
//   let siloWireNotice = try? JSONDecoder().decode(SiloWireNotice.self, from: jsonData)
//   let siloWireNoticeCategory = try? JSONDecoder().decode(SiloWireNoticeCategory.self, from: jsonData)
//   let siloWireNoticeComputer = try? JSONDecoder().decode(SiloWireNoticeComputer.self, from: jsonData)
//   let siloWireNotificationsClearedPayload = try? JSONDecoder().decode(SiloWireNotificationsClearedPayload.self, from: jsonData)
//   let siloWireOperation = try? JSONDecoder().decode(SiloWireOperation.self, from: jsonData)
//   let siloWireOperationEntry = try? JSONDecoder().decode(SiloWireOperationEntry.self, from: jsonData)
//   let siloWireOperationKind = try? JSONDecoder().decode(SiloWireOperationKind.self, from: jsonData)
//   let siloWireOperationKind2 = try? JSONDecoder().decode(SiloWireOperationKind2.self, from: jsonData)
//   let siloWireOperationQueue = try? JSONDecoder().decode(SiloWireOperationQueue.self, from: jsonData)
//   let siloWireOperationStatus = try? JSONDecoder().decode(SiloWireOperationStatus.self, from: jsonData)
//   let siloWireOperationsListParams = try? JSONDecoder().decode(SiloWireOperationsListParams.self, from: jsonData)
//   let siloWirePendingRestore = try? JSONDecoder().decode(SiloWirePendingRestore.self, from: jsonData)
//   let siloWirePreUpgradeBackup = try? JSONDecoder().decode(SiloWirePreUpgradeBackup.self, from: jsonData)
//   let siloWirePreparationStatus = try? JSONDecoder().decode(SiloWirePreparationStatus.self, from: jsonData)
//   let siloWirePreparationTask = try? JSONDecoder().decode(SiloWirePreparationTask.self, from: jsonData)
//   let siloWirePreparationTaskState = try? JSONDecoder().decode(SiloWirePreparationTaskState.self, from: jsonData)
//   let siloWireProtocolRange = try? JSONDecoder().decode(SiloWireProtocolRange.self, from: jsonData)
//   let siloWirePublishedPort = try? JSONDecoder().decode(SiloWirePublishedPort.self, from: jsonData)
//   let siloWirePublishedPortState = try? JSONDecoder().decode(SiloWirePublishedPortState.self, from: jsonData)
//   let siloWirePushDismissParams = try? JSONDecoder().decode(SiloWirePushDismissParams.self, from: jsonData)
//   let siloWirePushOperation = try? JSONDecoder().decode(SiloWirePushOperation.self, from: jsonData)
//   let siloWirePushOperationStatus = try? JSONDecoder().decode(SiloWirePushOperationStatus.self, from: jsonData)
//   let siloWirePushRepositoriesParams = try? JSONDecoder().decode(SiloWirePushRepositoriesParams.self, from: jsonData)
//   let siloWirePushRepository = try? JSONDecoder().decode(SiloWirePushRepository.self, from: jsonData)
//   let siloWirePushStartParams = try? JSONDecoder().decode(SiloWirePushStartParams.self, from: jsonData)
//   let siloWirePushStatusParams = try? JSONDecoder().decode(SiloWirePushStatusParams.self, from: jsonData)
//   let siloWirePushTarget = try? JSONDecoder().decode(SiloWirePushTarget.self, from: jsonData)
//   let siloWireReclaimEntry = try? JSONDecoder().decode(SiloWireReclaimEntry.self, from: jsonData)
//   let siloWireReclaimTrigger = try? JSONDecoder().decode(SiloWireReclaimTrigger.self, from: jsonData)
//   let siloWireRemoteLoginStatus = try? JSONDecoder().decode(SiloWireRemoteLoginStatus.self, from: jsonData)
//   let siloWireRequestEnvelope = try? JSONDecoder().decode(SiloWireRequestEnvelope.self, from: jsonData)
//   let siloWireResponseEnvelope = try? JSONDecoder().decode(SiloWireResponseEnvelope.self, from: jsonData)
//   let siloWireRestorePhase = try? JSONDecoder().decode(SiloWireRestorePhase.self, from: jsonData)
//   let siloWireResumingComputer = try? JSONDecoder().decode(SiloWireResumingComputer.self, from: jsonData)
//   let siloWireRevokeKeyParams = try? JSONDecoder().decode(SiloWireRevokeKeyParams.self, from: jsonData)
//   let siloWireSecret = try? JSONDecoder().decode(SiloWireSecret.self, from: jsonData)
//   let siloWireSecretIdParams = try? JSONDecoder().decode(SiloWireSecretIdParams.self, from: jsonData)
//   let siloWireSecretSaveAction = try? JSONDecoder().decode(SiloWireSecretSaveAction.self, from: jsonData)
//   let siloWireSecretSaveRequest = try? JSONDecoder().decode(SiloWireSecretSaveRequest.self, from: jsonData)
//   let siloWireSecretState = try? JSONDecoder().decode(SiloWireSecretState.self, from: jsonData)
//   let siloWireSecretsSaveParams = try? JSONDecoder().decode(SiloWireSecretsSaveParams.self, from: jsonData)
//   let siloWireSettingsSnapshot = try? JSONDecoder().decode(SiloWireSettingsSnapshot.self, from: jsonData)
//   let siloWireSettingsUpdateParams = try? JSONDecoder().decode(SiloWireSettingsUpdateParams.self, from: jsonData)
//   let siloWireSettingsValues = try? JSONDecoder().decode(SiloWireSettingsValues.self, from: jsonData)
//   let siloWireShutdownChangedPayload = try? JSONDecoder().decode(SiloWireShutdownChangedPayload.self, from: jsonData)
//   let siloWireShutdownPhase = try? JSONDecoder().decode(SiloWireShutdownPhase.self, from: jsonData)
//   let siloWireShutdownReason = try? JSONDecoder().decode(SiloWireShutdownReason.self, from: jsonData)
//   let siloWireSSHAccessComputer = try? JSONDecoder().decode(SiloWireSSHAccessComputer.self, from: jsonData)
//   let siloWireSSHAccessComputerState = try? JSONDecoder().decode(SiloWireSSHAccessComputerState.self, from: jsonData)
//   let siloWireSSHAccessConnectionParams = try? JSONDecoder().decode(SiloWireSSHAccessConnectionParams.self, from: jsonData)
//   let siloWireSSHAccessSaveParams = try? JSONDecoder().decode(SiloWireSSHAccessSaveParams.self, from: jsonData)
//   let siloWireSSHAccessState = try? JSONDecoder().decode(SiloWireSSHAccessState.self, from: jsonData)
//   let siloWireSSHAddressParams = try? JSONDecoder().decode(SiloWireSSHAddressParams.self, from: jsonData)
//   let siloWireSSHCommandResult = try? JSONDecoder().decode(SiloWireSSHCommandResult.self, from: jsonData)
//   let siloWireStorageParams = try? JSONDecoder().decode(SiloWireStorageParams.self, from: jsonData)
//   let siloWireStorageState = try? JSONDecoder().decode(SiloWireStorageState.self, from: jsonData)
//   let siloWireTemplateSummary = try? JSONDecoder().decode(SiloWireTemplateSummary.self, from: jsonData)
//   let siloWireTerminalCommandParams = try? JSONDecoder().decode(SiloWireTerminalCommandParams.self, from: jsonData)
//   let siloWireTheme = try? JSONDecoder().decode(SiloWireTheme.self, from: jsonData)
//   let siloWireTransferDirection = try? JSONDecoder().decode(SiloWireTransferDirection.self, from: jsonData)
//   let siloWireTransferProgress = try? JSONDecoder().decode(SiloWireTransferProgress.self, from: jsonData)
//   let siloWireTransferState = try? JSONDecoder().decode(SiloWireTransferState.self, from: jsonData)
//   let siloWireUnexpectedComputerChange = try? JSONDecoder().decode(SiloWireUnexpectedComputerChange.self, from: jsonData)
//   let siloWireUnfinishedRestore = try? JSONDecoder().decode(SiloWireUnfinishedRestore.self, from: jsonData)
//   let siloWireUpdateProgressData = try? JSONDecoder().decode(SiloWireUpdateProgressData.self, from: jsonData)
//   let siloWireUpdateSnapshot = try? JSONDecoder().decode(SiloWireUpdateSnapshot.self, from: jsonData)
//   let siloWireUpdatesSetAutomaticChecksParams = try? JSONDecoder().decode(SiloWireUpdatesSetAutomaticChecksParams.self, from: jsonData)
//   let siloWireUploadOrigin = try? JSONDecoder().decode(SiloWireUploadOrigin.self, from: jsonData)
//   let siloWireUploadOutcome = try? JSONDecoder().decode(SiloWireUploadOutcome.self, from: jsonData)
//   let siloWireViewerAudioSetParams = try? JSONDecoder().decode(SiloWireViewerAudioSetParams.self, from: jsonData)
//   let siloWireViewerConnectionParams = try? JSONDecoder().decode(SiloWireViewerConnectionParams.self, from: jsonData)
//   let siloWireViewerCookie = try? JSONDecoder().decode(SiloWireViewerCookie.self, from: jsonData)
//   let siloWireViewerOpenResult = try? JSONDecoder().decode(SiloWireViewerOpenResult.self, from: jsonData)
//   let siloWireViewerPageEvent = try? JSONDecoder().decode(SiloWireViewerPageEvent.self, from: jsonData)
//   let siloWireViewerSoundCheckResult = try? JSONDecoder().decode(SiloWireViewerSoundCheckResult.self, from: jsonData)
//   let siloWireSiloAPI = try? JSONDecoder().decode(SiloWireSiloAPI.self, from: jsonData)

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

import Foundation

/// Mirrors `app/SiloUI/src-tauri/engine/src/backup_controller.rs::BackupState`, with
/// the API's remembered destination field added for a client-owned folder picker.
// MARK: - SiloWireBackupState
struct SiloWireBackupState: Codable, Equatable, Sendable {
    var archives: [SiloWireArchive]
    var availability: SiloWireBackupAvailability
    var availabilityMessage: String? = nil
    var destination: String? = nil
    var operation: SiloWireOperationClass? = nil
    var operationId: String? = nil
    var resultUnseen: Bool? = nil
    var snapshotId: String

    enum CodingKeys: String, CodingKey {
        case archives = "archives"
        case availability = "availability"
        case availabilityMessage = "availabilityMessage"
        case destination = "destination"
        case operation = "operation"
        case operationId = "operationId"
        case resultUnseen = "resultUnseen"
        case snapshotId = "snapshotId"
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWireArchive
struct SiloWireArchive: Codable, Equatable, Sendable {
    var archivePath: String
    var checkpointName: String? = nil
    var completedLabel: String
    var computers: [String]
    var destination: String
    var name: String
    var size: String

    enum CodingKeys: String, CodingKey {
        case archivePath = "archivePath"
        case checkpointName = "checkpointName"
        case completedLabel = "completedLabel"
        case computers = "computers"
        case destination = "destination"
        case name = "name"
        case size = "size"
    }
}

enum SiloWireBackupAvailability: String, Codable, Equatable, Sendable {
    case available = "available"
    case unavailable = "unavailable"
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWireOperationClass
struct SiloWireOperationClass: Codable, Equatable, Sendable {
    var archive: SiloWireArchive
    var canCancel: Bool? = nil
    var indeterminate: Bool? = nil
    var kind: SiloWireBackupOperationKindEnum
    var operation: SiloWireBackupOperationKind
    var phases: [SiloWireBackupPhase]? = nil
    var progress: Int? = nil
    var runningNames: [String]
    var targetName: String? = nil
    var detail: String? = nil
    var message: String? = nil
    var outcome: SiloWireBackupOutcome? = nil
    var title: String? = nil

    enum CodingKeys: String, CodingKey {
        case archive = "archive"
        case canCancel = "canCancel"
        case indeterminate = "indeterminate"
        case kind = "kind"
        case operation = "operation"
        case phases = "phases"
        case progress = "progress"
        case runningNames = "runningNames"
        case targetName = "targetName"
        case detail = "detail"
        case message = "message"
        case outcome = "outcome"
        case title = "title"
    }
}

enum SiloWireBackupOperationKindEnum: String, Codable, Equatable, Sendable {
    case result = "result"
    case running = "running"
}

enum SiloWireBackupOperationKind: String, Codable, Equatable, Sendable {
    case backup = "backup"
    case restore = "restore"
}

enum SiloWireBackupOutcome: String, Codable, Equatable, Sendable {
    case cancelled = "cancelled"
    case failed = "failed"
    case success = "success"
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWireBackupPhase
struct SiloWireBackupPhase: Codable, Equatable, Sendable {
    var detail: String
    var title: String
    var tone: String

    enum CodingKeys: String, CodingKey {
        case detail = "detail"
        case title = "title"
        case tone = "tone"
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWireCancelJobParams
struct SiloWireCancelJobParams: Codable, Equatable, Sendable {
    var deviceId: String? = nil
    var jobId: String

    enum CodingKeys: String, CodingKey {
        case deviceId = "deviceId"
        case jobId = "jobId"
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWireChatGptPreparationStatus
struct SiloWireChatGptPreparationStatus: Codable, Equatable, Sendable {
    var state: SiloWireChatGptPreparationStatusState
    var receivedBytes: UInt64? = nil
    var totalBytes: UInt64? = nil
    var path: String? = nil
    var version: String? = nil
    var reason: String? = nil
    var retryable: Bool? = nil

    enum CodingKeys: String, CodingKey {
        case state = "state"
        case receivedBytes = "receivedBytes"
        case totalBytes = "totalBytes"
        case path = "path"
        case version = "version"
        case reason = "reason"
        case retryable = "retryable"
    }
}

enum SiloWireChatGptPreparationStatusState: String, Codable, Equatable, Sendable {
    case downloading = "downloading"
    case extracting = "extracting"
    case failed = "failed"
    case idle = "idle"
    case ready = "ready"
    case verifying = "verifying"
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWireCheckpointCreateParams
struct SiloWireCheckpointCreateParams: Codable, Equatable, Sendable {
    var computerId: String
    var deviceId: String? = nil
    var kind: SiloWireCheckpointKind? = nil
    var name: String

    enum CodingKeys: String, CodingKey {
        case computerId = "computerId"
        case deviceId = "deviceId"
        case kind = "kind"
        case name = "name"
    }
}

enum SiloWireCheckpointKind: String, Codable, Equatable, Sendable {
    case automatic = "automatic"
    case manual = "manual"
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWireCheckpointForkParams
struct SiloWireCheckpointForkParams: Codable, Equatable, Sendable {
    var checkpointId: String? = nil
    var computerId: String
    var deviceId: String? = nil
    var newName: String

    enum CodingKeys: String, CodingKey {
        case checkpointId = "checkpointId"
        case computerId = "computerId"
        case deviceId = "deviceId"
        case newName = "newName"
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWireCheckpointTargetParams
struct SiloWireCheckpointTargetParams: Codable, Equatable, Sendable {
    var checkpointId: String
    var computerId: String
    var deviceId: String? = nil

    enum CodingKeys: String, CodingKey {
        case checkpointId = "checkpointId"
        case computerId = "computerId"
        case deviceId = "deviceId"
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWireCheckpointUsage
struct SiloWireCheckpointUsage: Codable, Equatable, Sendable {
    var checkpoints: [SiloWireCheckpointUsageEntry]
    var totalBytes: UInt64? = nil

    enum CodingKeys: String, CodingKey {
        case checkpoints = "checkpoints"
        case totalBytes = "totalBytes"
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWireCheckpointUsageEntry
struct SiloWireCheckpointUsageEntry: Codable, Equatable, Sendable {
    var deleteBlocker: String? = nil
    var id: String
    var sizeBytes: UInt64? = nil
    var usedBy: [String]? = nil

    enum CodingKeys: String, CodingKey {
        case deleteBlocker = "deleteBlocker"
        case id = "id"
        case sizeBytes = "sizeBytes"
        case usedBy = "usedBy"
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWireCheckpointUsageParams
struct SiloWireCheckpointUsageParams: Codable, Equatable, Sendable {
    var computerId: String
    var deviceId: String? = nil

    enum CodingKeys: String, CodingKey {
        case computerId = "computerId"
        case deviceId = "deviceId"
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

/// The specification does not yet fix the exact fields of all clipboard
/// payloads. This tagged union keeps text and PNG bytes explicit.
// MARK: - SiloWireClipboardContent
struct SiloWireClipboardContent: Codable, Equatable, Sendable {
    var kind: SiloWireClipboardContentKind
    var text: String? = nil
    var bytes: [Int]? = nil
    var mime: String? = nil

    enum CodingKeys: String, CodingKey {
        case kind = "kind"
        case text = "text"
        case bytes = "bytes"
        case mime = "mime"
    }
}

enum SiloWireClipboardContentKind: String, Codable, Equatable, Sendable {
    case empty = "empty"
    case image = "image"
    case text = "text"
    case tooLarge = "too-large"
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWireClipboardTransferParams
struct SiloWireClipboardTransferParams: Codable, Equatable, Sendable {
    var action: SiloWireClipboardAction
    var computerId: String
    var connectionId: String? = nil
    var deviceId: String? = nil

    enum CodingKeys: String, CodingKey {
        case action = "action"
        case computerId = "computerId"
        case connectionId = "connectionId"
        case deviceId = "deviceId"
    }
}

enum SiloWireClipboardAction: String, Codable, Equatable, Sendable {
    case copy = "copy"
    case paste = "paste"
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWireClipboardTransferResult
struct SiloWireClipboardTransferResult: Codable, Equatable, Sendable {
    var action: SiloWireClipboardAction
    var content: SiloWireClipboardTransferContent? = nil
    var message: String? = nil
    var status: SiloWireClipboardTransferStatus

    enum CodingKeys: String, CodingKey {
        case action = "action"
        case content = "content"
        case message = "message"
        case status = "status"
    }
}

enum SiloWireClipboardTransferContent: String, Codable, Equatable, Sendable {
    case image = "image"
    case text = "text"
}

enum SiloWireClipboardTransferStatus: String, Codable, Equatable, Sendable {
    case busy = "busy"
    case computerEmpty = "computer-empty"
    case copied = "copied"
    case deviceEmpty = "device-empty"
    case failed = "failed"
    case notConnected = "not-connected"
    case pasted = "pasted"
    case tooLarge = "too-large"
    case unsupported = "unsupported"
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWireClipboardWriteParams
struct SiloWireClipboardWriteParams: Codable, Equatable, Sendable {
    var computerId: String
    var content: SiloWireClipboardWritableContent
    var deviceId: String? = nil

    enum CodingKeys: String, CodingKey {
        case computerId = "computerId"
        case content = "content"
        case deviceId = "deviceId"
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWireClipboardWritableContent
struct SiloWireClipboardWritableContent: Codable, Equatable, Sendable {
    var kind: SiloWireClipboardTransferContent
    var text: String? = nil
    var bytes: [Int]? = nil
    var mime: String? = nil

    enum CodingKeys: String, CodingKey {
        case kind = "kind"
        case text = "text"
        case bytes = "bytes"
        case mime = "mime"
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWireCommandResult
struct SiloWireCommandResult: Codable, Equatable, Sendable {
    var argv: [String]

    enum CodingKeys: String, CodingKey {
        case argv = "argv"
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWireComputerConfigurationChangeParams
struct SiloWireComputerConfigurationChangeParams: Codable, Equatable, Sendable {
    var change: SiloWireComputerConfigurationChange
    var deviceId: String? = nil
    var requestId: String? = nil
    var retryComputerId: String? = nil

    enum CodingKeys: String, CodingKey {
        case change = "change"
        case deviceId = "deviceId"
        case requestId = "requestId"
        case retryComputerId = "retryComputerId"
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWireComputerConfigurationChange
struct SiloWireComputerConfigurationChange: Codable, Equatable, Sendable {
    var configuration: SiloWireComputerConfiguration? = nil
    var expected: SiloWireConfiguration? = nil
    var kind: SiloWireComputerConfigurationChangeKind
    var computerId: String? = nil
    var expectedOrder: [String]? = nil
    var order: [String]? = nil
    var changes: [SiloWireComputerConfigurationChange]? = nil
    var cpus: UInt64? = nil
    var memoryGiB: UInt64? = nil
    var requestId: String? = nil

    enum CodingKeys: String, CodingKey {
        case configuration = "configuration"
        case expected = "expected"
        case kind = "kind"
        case computerId = "computerId"
        case expectedOrder = "expectedOrder"
        case order = "order"
        case changes = "changes"
        case cpus = "cpus"
        case memoryGiB = "memoryGiB"
        case requestId = "requestId"
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

/// Mirrors `app/SiloUI/src-tauri/engine/src/runtime.rs::ComputerConfiguration`
/// (lines 304-319), including rejection of unknown fields.
// MARK: - SiloWireComputerConfiguration
struct SiloWireComputerConfiguration: Codable, Equatable, Sendable {
    var cpus: Int
    var desktop: SiloWireDesktopConfiguration? = nil
    var id: String
    var maxCPUs: Int
    var maxMemoryGiB: Int
    var memoryGiB: Int
    var name: String
    var runtimeStorageGiB: Int
    var workspaceStorageGiB: Int

    enum CodingKeys: String, CodingKey {
        case cpus = "cpus"
        case desktop = "desktop"
        case id = "id"
        case maxCPUs = "maxCPUs"
        case maxMemoryGiB = "maxMemoryGiB"
        case memoryGiB = "memoryGiB"
        case name = "name"
        case runtimeStorageGiB = "runtimeStorageGiB"
        case workspaceStorageGiB = "workspaceStorageGiB"
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

/// Mirrors `app/SiloUI/src-tauri/engine/src/desktop.rs::DesktopConfiguration`.
// MARK: - SiloWireDesktopConfiguration
struct SiloWireDesktopConfiguration: Codable, Equatable, Sendable {
    var builtIn: Bool? = nil
    var startWithComputer: Bool? = nil

    enum CodingKeys: String, CodingKey {
        case builtIn = "builtIn"
        case startWithComputer = "startWithComputer"
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

/// Mirrors `app/SiloUI/src-tauri/engine/src/runtime.rs::ComputerConfiguration`
/// (lines 304-319), including rejection of unknown fields.
///
/// Optimistic state check for a stopped macOS computer's resource edit.
// MARK: - SiloWireConfiguration
struct SiloWireConfiguration: Codable, Equatable, Sendable {
    var cpus: UInt64
    var desktop: SiloWireDesktopConfiguration? = nil
    var id: String? = nil
    var maxCPUs: Int? = nil
    var maxMemoryGiB: Int? = nil
    var memoryGiB: UInt64
    var name: String? = nil
    var runtimeStorageGiB: Int? = nil
    var workspaceStorageGiB: Int? = nil
    var diskGiB: UInt64? = nil

    enum CodingKeys: String, CodingKey {
        case cpus = "cpus"
        case desktop = "desktop"
        case id = "id"
        case maxCPUs = "maxCPUs"
        case maxMemoryGiB = "maxMemoryGiB"
        case memoryGiB = "memoryGiB"
        case name = "name"
        case runtimeStorageGiB = "runtimeStorageGiB"
        case workspaceStorageGiB = "workspaceStorageGiB"
        case diskGiB = "diskGiB"
    }
}

enum SiloWireComputerConfigurationChangeKind: String, Codable, Equatable, Sendable {
    case batch = "batch"
    case delete = "delete"
    case macosResources = "macosResources"
    case reorder = "reorder"
    case upsert = "upsert"
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

/// Mirrors `app/SiloUI/src-tauri/engine/src/runtime.rs::ComputerConfigurationProgress`
/// (lines 3343 and 3462-3494), including its explicit `type` field.
// MARK: - SiloWireComputerConfigurationProgress
struct SiloWireComputerConfigurationProgress: Codable, Equatable, Sendable {
    var computer: String
    var diagnostic: String? = nil
    var downloadedBytes: UInt64? = nil
    var elapsedSeconds: UInt64
    var exitCode: Int32? = nil
    var failureCode: String? = nil
    var fraction: Int? = nil
    var level: String
    var message: String
    var partial: Bool? = nil
    var phase: String
    var requestId: String
    var safeForDisplay: Bool
    var schemaVersion: Int
    var step: String
    var timestamp: UInt64
    var totalBytes: UInt64? = nil
    var type: String

    enum CodingKeys: String, CodingKey {
        case computer = "computer"
        case diagnostic = "diagnostic"
        case downloadedBytes = "downloadedBytes"
        case elapsedSeconds = "elapsedSeconds"
        case exitCode = "exitCode"
        case failureCode = "failureCode"
        case fraction = "fraction"
        case level = "level"
        case message = "message"
        case partial = "partial"
        case phase = "phase"
        case requestId = "requestId"
        case safeForDisplay = "safeForDisplay"
        case schemaVersion = "schemaVersion"
        case step = "step"
        case timestamp = "timestamp"
        case totalBytes = "totalBytes"
        case type = "type"
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

/// Mirrors `app/SiloUI/src-tauri/engine/src/runtime.rs::ComputerConfigurationRequest`
/// (lines 297-302).
// MARK: - SiloWireComputerConfigurationRequest
struct SiloWireComputerConfigurationRequest: Codable, Equatable, Sendable {
    var computers: [SiloWireComputerConfiguration]
    var schemaVersion: Int

    enum CodingKeys: String, CodingKey {
        case computers = "computers"
        case schemaVersion = "schemaVersion"
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWireComputerConfigurationRetryParams
struct SiloWireComputerConfigurationRetryParams: Codable, Equatable, Sendable {
    var deviceId: String? = nil
    var requestId: String? = nil
    var retryComputerId: String? = nil

    enum CodingKeys: String, CodingKey {
        case deviceId = "deviceId"
        case requestId = "requestId"
        case retryComputerId = "retryComputerId"
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWireComputerCreateParams
struct SiloWireComputerCreateParams: Codable, Equatable, Sendable {
    var configuration: SiloWireComputerConfiguration? = nil
    var deviceId: String? = nil
    var kind: SiloWireComputerKind
    var requestId: String? = nil
    var request: SiloWireMacosComputerCreateRequest? = nil

    enum CodingKeys: String, CodingKey {
        case configuration = "configuration"
        case deviceId = "deviceId"
        case kind = "kind"
        case requestId = "requestId"
        case request = "request"
    }
}

enum SiloWireComputerKind: String, Codable, Equatable, Sendable {
    case linux = "linux"
    case macos = "macos"
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWireMacosComputerCreateRequest
struct SiloWireMacosComputerCreateRequest: Codable, Equatable, Sendable {
    var cpus: UInt64
    var diskGiB: UInt64
    var memoryGiB: UInt64
    var name: String

    enum CodingKeys: String, CodingKey {
        case cpus = "cpus"
        case diskGiB = "diskGiB"
        case memoryGiB = "memoryGiB"
        case name = "name"
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWireComputerCreateResult
struct SiloWireComputerCreateResult: Codable, Equatable, Sendable {
    var computer: SiloWireMacosComputer? = nil
    var jobId: String

    enum CodingKeys: String, CodingKey {
        case computer = "computer"
        case jobId = "jobId"
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

/// Mirrors `app/SiloUI/src-tauri/engine/src/macos_computers.rs::MacosComputer`
/// (lines 68-92). `kind` is added by the unified `computers.list` contract;
/// source `Option` fields remain explicit JSON nulls.
// MARK: - SiloWireMacosComputer
struct SiloWireMacosComputer: Codable, Equatable, Sendable {
    var checkpointOperation: SiloWireOperation? = nil
    var checkpoints: [SiloWireCheckpoint]
    var cpus: UInt64
    var detail: String? = nil
    var diskGiB: UInt64
    var displayOpen: Bool
    var id: String
    var installed: Bool
    var kind: SiloWireComputerKind
    var memoryGiB: UInt64
    var name: String
    var needsPersonalizing: Bool
    var osVersion: String? = nil
    var pendingRestore: SiloWirePendingRestore? = nil
    var progress: Double? = nil
    var setupComplete: Bool
    var state: SiloWireMacosComputerState

    enum CodingKeys: String, CodingKey {
        case checkpointOperation = "checkpointOperation"
        case checkpoints = "checkpoints"
        case cpus = "cpus"
        case detail = "detail"
        case diskGiB = "diskGiB"
        case displayOpen = "displayOpen"
        case id = "id"
        case installed = "installed"
        case kind = "kind"
        case memoryGiB = "memoryGiB"
        case name = "name"
        case needsPersonalizing = "needsPersonalizing"
        case osVersion = "osVersion"
        case pendingRestore = "pendingRestore"
        case progress = "progress"
        case setupComplete = "setupComplete"
        case state = "state"
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

/// Unified API view of Linux and macOS checkpoint operations.
// MARK: - SiloWireOperation
struct SiloWireOperation: Codable, Equatable, Sendable {
    var error: String? = nil
    var kind: SiloWireOperationKind
    var stage: String
    var status: SiloWireOperationStatus

    enum CodingKeys: String, CodingKey {
        case error = "error"
        case kind = "kind"
        case stage = "stage"
        case status = "status"
    }
}

enum SiloWireOperationKind: String, Codable, Equatable, Sendable {
    case capture = "capture"
    case delete = "delete"
    case fork = "fork"
    case restore = "restore"
}

enum SiloWireOperationStatus: String, Codable, Equatable, Sendable {
    case failed = "failed"
    case running = "running"
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

/// The common checkpoint view returned by Linux and macOS computers.
// MARK: - SiloWireCheckpoint
struct SiloWireCheckpoint: Codable, Equatable, Sendable {
    var createdAt: String
    var id: String
    var kind: SiloWireCheckpointKind
    var name: String
    var reason: SiloWireCheckpointReason
    var scope: SiloWireCheckpointScope
    var sizeBytes: UInt64? = nil

    enum CodingKeys: String, CodingKey {
        case createdAt = "createdAt"
        case id = "id"
        case kind = "kind"
        case name = "name"
        case reason = "reason"
        case scope = "scope"
        case sizeBytes = "sizeBytes"
    }
}

enum SiloWireCheckpointReason: String, Codable, Equatable, Sendable {
    case beforeRestore = "before-restore"
    case manual = "manual"
}

enum SiloWireCheckpointScope: String, Codable, Equatable, Sendable {
    case disk = "disk"
    case full = "full"
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

/// Mirrors `app/SiloUI/src-tauri/engine/src/macos_computers/store.rs::State`.
enum SiloWireMacosComputerState: String, Codable, Equatable, Sendable {
    case copying = "copying"
    case downloading = "downloading"
    case failed = "failed"
    case installing = "installing"
    case preparing = "preparing"
    case running = "running"
    case settingUp = "setting-up"
    case starting = "starting"
    case stopped = "stopped"
    case stopping = "stopping"
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWireComputerCreationSkipWaitParams
struct SiloWireComputerCreationSkipWaitParams: Codable, Equatable, Sendable {
    var requestId: String

    enum CodingKeys: String, CodingKey {
        case requestId = "requestId"
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWireComputerDeleteParams
struct SiloWireComputerDeleteParams: Codable, Equatable, Sendable {
    var computerId: String
    var deviceId: String? = nil
    var expected: SiloWireComputerConfiguration? = nil
    var requestId: String? = nil

    enum CodingKeys: String, CodingKey {
        case computerId = "computerId"
        case deviceId = "deviceId"
        case expected = "expected"
        case requestId = "requestId"
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWireComputerIdentitiesParams
struct SiloWireComputerIdentitiesParams: Codable, Equatable, Sendable {
    var deviceId: String? = nil
    var identities: [SiloWireComputerIdentity]

    enum CodingKeys: String, CodingKey {
        case deviceId = "deviceId"
        case identities = "identities"
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWireComputerIdentity
struct SiloWireComputerIdentity: Codable, Equatable, Sendable {
    var apply: Bool
    var computerId: String
    var email: String
    var name: String

    enum CodingKeys: String, CodingKey {
        case apply = "apply"
        case computerId = "computerId"
        case email = "email"
        case name = "name"
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWireComputerListParams
struct SiloWireComputerListParams: Codable, Equatable, Sendable {
    var deviceId: String? = nil
    var refreshRepositories: Bool? = nil

    enum CodingKeys: String, CodingKey {
        case deviceId = "deviceId"
        case refreshRepositories = "refreshRepositories"
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWireComputerShellParams
struct SiloWireComputerShellParams: Codable, Equatable, Sendable {
    var error: String

    enum CodingKeys: String, CodingKey {
        case error = "error"
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWireComputerTargetParams
struct SiloWireComputerTargetParams: Codable, Equatable, Sendable {
    var computerId: String
    var deviceId: String? = nil

    enum CodingKeys: String, CodingKey {
        case computerId = "computerId"
        case deviceId = "deviceId"
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWireComputerUseApprovalParams
struct SiloWireComputerUseApprovalParams: Codable, Equatable, Sendable {
    var computerId: String
    var deviceId: String? = nil
    var mode: SiloWireApprovalMode

    enum CodingKeys: String, CodingKey {
        case computerId = "computerId"
        case deviceId = "deviceId"
        case mode = "mode"
    }
}

enum SiloWireApprovalMode: String, Codable, Equatable, Sendable {
    case ask = "ask"
    case auto = "auto"
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWireComputerUseStateParams
struct SiloWireComputerUseStateParams: Codable, Equatable, Sendable {
    var computerId: String
    var deviceId: String? = nil

    enum CodingKeys: String, CodingKey {
        case computerId = "computerId"
        case deviceId = "deviceId"
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWireComputersChangedPayload
struct SiloWireComputersChangedPayload: Codable, Equatable, Sendable {
    var linux: SiloWireApplicationSource? = nil
    var macos: SiloWireMacosComputersState? = nil

    enum CodingKeys: String, CodingKey {
        case linux = "linux"
        case macos = "macos"
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

/// Mirrors `app/SiloUI/src-tauri/engine/src/runtime.rs::ApplicationSource` (lines
/// 548-565), retaining its field types and camelCase serialization.
// MARK: - SiloWireApplicationSource
struct SiloWireApplicationSource: Codable, Equatable, Sendable {
    var activities: [SiloJSONValue]
    var computerConfigurationOperation: SiloJSONValue? = nil
    var computers: [SiloWireApplicationComputer]
    var deviceCapacity: SiloWireDeviceCapacity? = nil
    var github: SiloJSONValue
    var repositoryPushOperations: [SiloJSONValue]
    var runtimeRepair: SiloJSONValue? = nil
    var secrets: [SiloJSONValue]

    enum CodingKeys: String, CodingKey {
        case activities = "activities"
        case computerConfigurationOperation = "computerConfigurationOperation"
        case computers = "computers"
        case deviceCapacity = "deviceCapacity"
        case github = "github"
        case repositoryPushOperations = "repositoryPushOperations"
        case runtimeRepair = "runtimeRepair"
        case secrets = "secrets"
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

/// Mirrors `app/SiloUI/src-tauri/engine/src/runtime.rs::ApplicationComputer` (lines
/// 591-628). `kind` is the discriminator required by 10 §1.3 and is added by
/// the canonical API; source fields retain their names and omission behavior.
// MARK: - SiloWireApplicationComputer
struct SiloWireApplicationComputer: Codable, Equatable, Sendable {
    var attention: SiloWireComputerAttention? = nil
    var canDismissError: Bool
    var checkpointOperation: SiloWireOperation? = nil
    var checkpoints: [SiloWireCheckpoint]? = nil
    var configuration: SiloWireComputerConfiguration
    var files: [SiloJSONValue]
    var freshness: SiloWireFreshness
    var githubRepositories: [String]
    var kind: SiloWireComputerKind
    var lifecycleFailure: String? = nil
    var lifecycleFailureDiagnostic: String? = nil
    var logs: [SiloJSONValue]
    var pendingCheckpointRestore: SiloWirePendingRestore? = nil
    var pendingSecretRevocations: [String]? = nil
    var ports: [SiloJSONValue]
    var purpose: String
    var repositories: [SiloJSONValue]
    var secretNames: [String]
    var settling: Bool? = nil
    var state: SiloWireLinuxComputerState
    var stateDetail: String
    var unfinishedRestore: SiloWireUnfinishedRestore? = nil

    enum CodingKeys: String, CodingKey {
        case attention = "attention"
        case canDismissError = "canDismissError"
        case checkpointOperation = "checkpointOperation"
        case checkpoints = "checkpoints"
        case configuration = "configuration"
        case files = "files"
        case freshness = "freshness"
        case githubRepositories = "githubRepositories"
        case kind = "kind"
        case lifecycleFailure = "lifecycleFailure"
        case lifecycleFailureDiagnostic = "lifecycleFailureDiagnostic"
        case logs = "logs"
        case pendingCheckpointRestore = "pendingCheckpointRestore"
        case pendingSecretRevocations = "pendingSecretRevocations"
        case ports = "ports"
        case purpose = "purpose"
        case repositories = "repositories"
        case secretNames = "secretNames"
        case settling = "settling"
        case state = "state"
        case stateDetail = "stateDetail"
        case unfinishedRestore = "unfinishedRestore"
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

/// Mirrors `app/SiloUI/src-tauri/engine/src/runtime.rs::ComputerAttention`
/// (lines 638-650).
// MARK: - SiloWireComputerAttention
struct SiloWireComputerAttention: Codable, Equatable, Sendable {
    var level: SiloWireAttentionLevel
    var message: String

    enum CodingKeys: String, CodingKey {
        case level = "level"
        case message = "message"
    }
}

enum SiloWireAttentionLevel: String, Codable, Equatable, Sendable {
    case error = "error"
    case warning = "warning"
}

enum SiloWireFreshness: String, Codable, Equatable, Sendable {
    case fresh = "fresh"
    case stale = "stale"
}

enum SiloWireLinuxComputerState: String, Codable, Equatable, Sendable {
    case failed = "failed"
    case running = "running"
    case starting = "starting"
    case stopped = "stopped"
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

/// Mirrors the Linux restore journal view in
/// `app/SiloUI/src-tauri/engine/src/runtime/checkpoints.rs` (lines 2381-2403).
// MARK: - SiloWireUnfinishedRestore
struct SiloWireUnfinishedRestore: Codable, Equatable, Sendable {
    var checkpointId: String
    var checkpointName: String? = nil
    var phase: SiloWireRestorePhase

    enum CodingKeys: String, CodingKey {
        case checkpointId = "checkpointId"
        case checkpointName = "checkpointName"
        case phase = "phase"
    }
}

enum SiloWireRestorePhase: String, Codable, Equatable, Sendable {
    case capturing = "capturing"
    case secured = "secured"
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

/// Mirrors `app/SiloUI/src-tauri/engine/src/runtime.rs::DeviceCapacity`.
// MARK: - SiloWireDeviceCapacity
struct SiloWireDeviceCapacity: Codable, Equatable, Sendable {
    var logicalCpus: Int
    var maxMemoryGib: UInt64
    var physicalMemoryBytes: UInt64

    enum CodingKeys: String, CodingKey {
        case logicalCpus = "logicalCpus"
        case maxMemoryGib = "maxMemoryGib"
        case physicalMemoryBytes = "physicalMemoryBytes"
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

/// Mirrors `app/SiloUI/src-tauri/engine/src/macos_computers.rs::MacosComputersState`.
// MARK: - SiloWireMacosComputersState
struct SiloWireMacosComputersState: Codable, Equatable, Sendable {
    var computers: [SiloWireMacosComputer]
    var minDiskGiB: UInt64
    var supported: Bool
    var template: SiloWireTemplateSummary? = nil
    var unsupportedReason: String? = nil

    enum CodingKeys: String, CodingKey {
        case computers = "computers"
        case minDiskGiB = "minDiskGiB"
        case supported = "supported"
        case template = "template"
        case unsupportedReason = "unsupportedReason"
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

/// Mirrors `app/SiloUI/src-tauri/engine/src/macos_computers.rs::TemplateSummary`.
// MARK: - SiloWireTemplateSummary
struct SiloWireTemplateSummary: Codable, Equatable, Sendable {
    var build: String
    var current: Bool
    var macosVersion: String

    enum CodingKeys: String, CodingKey {
        case build = "build"
        case current = "current"
        case macosVersion = "macosVersion"
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWireComputersListResult
struct SiloWireComputersListResult: Codable, Equatable, Sendable {
    var linux: SiloWireApplicationSource
    var macos: SiloWireMacosComputersState

    enum CodingKeys: String, CodingKey {
        case linux = "linux"
        case macos = "macos"
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWireConnectDeviceParams
struct SiloWireConnectDeviceParams: Codable, Equatable, Sendable {
    var address: String
    var replace: Bool? = nil

    enum CodingKeys: String, CodingKey {
        case address = "address"
        case replace = "replace"
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWireConnectionsSetEnabledParams
struct SiloWireConnectionsSetEnabledParams: Codable, Equatable, Sendable {
    var enabled: Bool

    enum CodingKeys: String, CodingKey {
        case enabled = "enabled"
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

/// Mirrors `app/SiloUI/src-tauri/engine/src/remote.rs::ConnectionsStatus`.
// MARK: - SiloWireConnectionsStatus
struct SiloWireConnectionsStatus: Codable, Equatable, Sendable {
    var address: String
    var addresses: [SiloWireDeviceAddress]
    var deviceId: String
    var enabled: Bool
    var error: String? = nil
    var name: String

    enum CodingKeys: String, CodingKey {
        case address = "address"
        case addresses = "addresses"
        case deviceId = "deviceId"
        case enabled = "enabled"
        case error = "error"
        case name = "name"
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWireDeviceAddress
struct SiloWireDeviceAddress: Codable, Equatable, Sendable {
    var address: String
    var kind: SiloWireDeviceAddressKind

    enum CodingKeys: String, CodingKey {
        case address = "address"
        case kind = "kind"
    }
}

enum SiloWireDeviceAddressKind: String, Codable, Equatable, Sendable {
    case name = "name"
    case network = "network"
    case tailscale = "tailscale"
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWireDependencyReport
struct SiloWireDependencyReport: Codable, Equatable, Sendable {
    var checkedAtMs: UInt64
    var checks: [SiloWireDependencyCheck]
    var requestId: String
    var schemaVersion: Int

    enum CodingKeys: String, CodingKey {
        case checkedAtMs = "checkedAtMs"
        case checks = "checks"
        case requestId = "requestId"
        case schemaVersion = "schemaVersion"
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWireDependencyCheck
struct SiloWireDependencyCheck: Codable, Equatable, Sendable {
    var detail: String
    var id: String
    var remediation: String? = nil
    var status: SiloWireDependencyStatus
    var title: String

    enum CodingKeys: String, CodingKey {
        case detail = "detail"
        case id = "id"
        case remediation = "remediation"
        case status = "status"
        case title = "title"
    }
}

enum SiloWireDependencyStatus: String, Codable, Equatable, Sendable {
    case failed = "failed"
    case pass = "pass"
    case timeout = "timeout"
    case unavailable = "unavailable"
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWireDependencyReportParams
struct SiloWireDependencyReportParams: Codable, Equatable, Sendable {
    var requestId: String

    enum CodingKeys: String, CodingKey {
        case requestId = "requestId"
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWireDesktopActionParams
struct SiloWireDesktopActionParams: Codable, Equatable, Sendable {
    var action: SiloWireDesktopAction
    var computerId: String
    var deviceId: String? = nil

    enum CodingKeys: String, CodingKey {
        case action = "action"
        case computerId = "computerId"
        case deviceId = "deviceId"
    }
}

enum SiloWireDesktopAction: String, Codable, Equatable, Sendable {
    case restart = "restart"
    case restartStreamer = "restart-streamer"
    case start = "start"
    case stop = "stop"
    case updateStreamer = "update-streamer"
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWireDesktopConnectParams
struct SiloWireDesktopConnectParams: Codable, Equatable, Sendable {
    var computerId: String

    enum CodingKeys: String, CodingKey {
        case computerId = "computerId"
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWireDesktopConnectResult
struct SiloWireDesktopConnectResult: Codable, Equatable, Sendable {
    var password: String
    var port: Int
    var username: String

    enum CodingKeys: String, CodingKey {
        case password = "password"
        case port = "port"
        case username = "username"
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

/// Mirrors `app/SiloUI/src-tauri/engine/src/remote.rs::Device`.
// MARK: - SiloWireDevice
struct SiloWireDevice: Codable, Equatable, Sendable {
    var address: String
    var id: String
    var name: String

    enum CodingKeys: String, CodingKey {
        case address = "address"
        case id = "id"
        case name = "name"
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWireDeviceFacts
struct SiloWireDeviceFacts: Codable, Equatable, Sendable {
    var deviceCapacity: SiloWireDeviceCapacity? = nil
    var macosHostLimits: SiloWireMacosHostLimits? = nil
    var remoteLogin: SiloWireRemoteLoginStatus

    enum CodingKeys: String, CodingKey {
        case deviceCapacity = "deviceCapacity"
        case macosHostLimits = "macosHostLimits"
        case remoteLogin = "remoteLogin"
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWireMacosHostLimits
struct SiloWireMacosHostLimits: Codable, Equatable, Sendable {
    var cpus: UInt64
    var memoryGib: UInt64

    enum CodingKeys: String, CodingKey {
        case cpus = "cpus"
        case memoryGib = "memory_gib"
    }
}

enum SiloWireRemoteLoginStatus: String, Codable, Equatable, Sendable {
    case disabled = "disabled"
    case enabled = "enabled"
    case unknown = "unknown"
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWireDeviceHealthResult
struct SiloWireDeviceHealthResult: Codable, Equatable, Sendable {
    var devices: [SiloWireDeviceHealth]

    enum CodingKeys: String, CodingKey {
        case devices = "devices"
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWireDeviceHealth
struct SiloWireDeviceHealth: Codable, Equatable, Sendable {
    var busy: Bool
    var connected: Bool
    var deviceId: String
    var error: String? = nil
    var lastSeen: String? = nil

    enum CodingKeys: String, CodingKey {
        case busy = "busy"
        case connected = "connected"
        case deviceId = "deviceId"
        case error = "error"
        case lastSeen = "lastSeen"
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWireDeviceIdParams
struct SiloWireDeviceIdParams: Codable, Equatable, Sendable {
    var deviceId: String

    enum CodingKeys: String, CodingKey {
        case deviceId = "deviceId"
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWireDeviceParams
struct SiloWireDeviceParams: Codable, Equatable, Sendable {
    var deviceId: String? = nil

    enum CodingKeys: String, CodingKey {
        case deviceId = "deviceId"
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWireEditorCommandParams
struct SiloWireEditorCommandParams: Codable, Equatable, Sendable {
    var computerId: String
    var deviceId: String? = nil
    var path: String? = nil

    enum CodingKeys: String, CodingKey {
        case computerId = "computerId"
        case deviceId = "deviceId"
        case path = "path"
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWireEngineShutdownParams
struct SiloWireEngineShutdownParams: Codable, Equatable, Sendable {
    var deadlineMs: UInt64? = nil
    var reason: SiloWireShutdownReason
    var stopComputers: Bool

    enum CodingKeys: String, CodingKey {
        case deadlineMs = "deadlineMs"
        case reason = "reason"
        case stopComputers = "stopComputers"
    }
}

enum SiloWireShutdownReason: String, Codable, Equatable, Sendable {
    case sessionEnd = "sessionEnd"
    case update = "update"
    case user = "user"
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWireEngineState
struct SiloWireEngineState: Codable, Equatable, Sendable {
    var generation: UInt64
    var phase: SiloWireShutdownPhase
    var sessionEnding: Bool
    var shuttingDown: Bool
    var updatePending: Bool

    enum CodingKeys: String, CodingKey {
        case generation = "generation"
        case phase = "phase"
        case sessionEnding = "sessionEnding"
        case shuttingDown = "shuttingDown"
        case updatePending = "updatePending"
    }
}

enum SiloWireShutdownPhase: String, Codable, Equatable, Sendable {
    case approved = "approved"
    case finishing = "finishing"
    case flushing = "flushing"
    case idle = "idle"
    case requested = "requested"
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWireEventsSubscribeParams
struct SiloWireEventsSubscribeParams: Codable, Equatable, Sendable {
    var deviceIds: [String]? = nil
    var events: [String]

    enum CodingKeys: String, CodingKey {
        case deviceIds = "deviceIds"
        case events = "events"
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWireEventsSubscribeResult
struct SiloWireEventsSubscribeResult: Codable, Equatable, Sendable {
    var subscription: String

    enum CodingKeys: String, CodingKey {
        case subscription = "subscription"
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWireEventsUnsubscribeParams
struct SiloWireEventsUnsubscribeParams: Codable, Equatable, Sendable {
    var subscription: String

    enum CodingKeys: String, CodingKey {
        case subscription = "subscription"
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWireExportAcknowledgeParams
struct SiloWireExportAcknowledgeParams: Codable, Equatable, Sendable {
    var deviceId: String? = nil
    var expectedOperationId: String

    enum CodingKeys: String, CodingKey {
        case deviceId = "deviceId"
        case expectedOperationId = "expectedOperationId"
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWireExportCreateParams
struct SiloWireExportCreateParams: Codable, Equatable, Sendable {
    var checkpointId: String? = nil
    var computerIds: [String]
    var destination: String
    var deviceId: String? = nil

    enum CodingKeys: String, CodingKey {
        case checkpointId = "checkpointId"
        case computerIds = "computerIds"
        case destination = "destination"
        case deviceId = "deviceId"
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWireExportDestinationResult
struct SiloWireExportDestinationResult: Codable, Equatable, Sendable {
    var destination: String

    enum CodingKeys: String, CodingKey {
        case destination = "destination"
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWireExportDestinationSetParams
struct SiloWireExportDestinationSetParams: Codable, Equatable, Sendable {
    var deviceId: String? = nil
    var path: String

    enum CodingKeys: String, CodingKey {
        case deviceId = "deviceId"
        case path = "path"
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWireExportDismissParams
struct SiloWireExportDismissParams: Codable, Equatable, Sendable {
    var deviceId: String? = nil
    var expectedOperation: SiloWireBackupOperation
    var expectedOperationId: String? = nil

    enum CodingKeys: String, CodingKey {
        case deviceId = "deviceId"
        case expectedOperation = "expectedOperation"
        case expectedOperationId = "expectedOperationId"
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWireBackupOperation
struct SiloWireBackupOperation: Codable, Equatable, Sendable {
    var archive: SiloWireArchive
    var canCancel: Bool? = nil
    var indeterminate: Bool? = nil
    var kind: SiloWireBackupOperationKindEnum
    var operation: SiloWireBackupOperationKind
    var phases: [SiloWireBackupPhase]? = nil
    var progress: Int? = nil
    var runningNames: [String]
    var targetName: String? = nil
    var detail: String? = nil
    var message: String? = nil
    var outcome: SiloWireBackupOutcome? = nil
    var title: String? = nil

    enum CodingKeys: String, CodingKey {
        case archive = "archive"
        case canCancel = "canCancel"
        case indeterminate = "indeterminate"
        case kind = "kind"
        case operation = "operation"
        case phases = "phases"
        case progress = "progress"
        case runningNames = "runningNames"
        case targetName = "targetName"
        case detail = "detail"
        case message = "message"
        case outcome = "outcome"
        case title = "title"
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWireExportImportParams
struct SiloWireExportImportParams: Codable, Equatable, Sendable {
    var archivePath: String
    var deviceId: String? = nil
    var newName: String
    var sourceName: String? = nil

    enum CodingKeys: String, CodingKey {
        case archivePath = "archivePath"
        case deviceId = "deviceId"
        case newName = "newName"
        case sourceName = "sourceName"
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWireExportInspectParams
struct SiloWireExportInspectParams: Codable, Equatable, Sendable {
    var archivePath: String
    var deviceId: String? = nil
    var requestId: String? = nil

    enum CodingKeys: String, CodingKey {
        case archivePath = "archivePath"
        case deviceId = "deviceId"
        case requestId = "requestId"
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWireExportStateParams
struct SiloWireExportStateParams: Codable, Equatable, Sendable {
    var deviceId: String? = nil

    enum CodingKeys: String, CodingKey {
        case deviceId = "deviceId"
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWireFileDownloadParams
struct SiloWireFileDownloadParams: Codable, Equatable, Sendable {
    var computerId: String
    var destination: String? = nil
    var deviceId: String? = nil
    var path: String
    var transferId: String

    enum CodingKeys: String, CodingKey {
        case computerId = "computerId"
        case destination = "destination"
        case deviceId = "deviceId"
        case path = "path"
        case transferId = "transferId"
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWireFileListParams
struct SiloWireFileListParams: Codable, Equatable, Sendable {
    var computerId: String
    var deviceId: String? = nil
    var offset: UInt64
    var path: String
    var snapshotId: String? = nil

    enum CodingKeys: String, CodingKey {
        case computerId = "computerId"
        case deviceId = "deviceId"
        case offset = "offset"
        case path = "path"
        case snapshotId = "snapshotId"
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWireFileListResult
struct SiloWireFileListResult: Codable, Equatable, Sendable {
    var entries: [SiloWireFileEntry]
    var nextOffset: UInt64? = nil
    var snapshotId: String

    enum CodingKeys: String, CodingKey {
        case entries = "entries"
        case nextOffset = "nextOffset"
        case snapshotId = "snapshotId"
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWireFileEntry
struct SiloWireFileEntry: Codable, Equatable, Sendable {
    var kind: SiloWireFileEntryKind
    var name: String
    var path: String

    enum CodingKeys: String, CodingKey {
        case kind = "kind"
        case name = "name"
        case path = "path"
    }
}

enum SiloWireFileEntryKind: String, Codable, Equatable, Sendable {
    case file = "file"
    case folder = "folder"
    case symlink = "symlink"
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWireFileUploadParams
struct SiloWireFileUploadParams: Codable, Equatable, Sendable {
    var computerId: String
    var conflict: SiloWireConflictPolicy
    var connectionId: String? = nil
    var deviceId: String? = nil
    var directory: String
    var origin: SiloWireUploadOrigin? = nil
    var paths: [String]? = nil
    var selection: String? = nil
    var transferId: String

    enum CodingKeys: String, CodingKey {
        case computerId = "computerId"
        case conflict = "conflict"
        case connectionId = "connectionId"
        case deviceId = "deviceId"
        case directory = "directory"
        case origin = "origin"
        case paths = "paths"
        case selection = "selection"
        case transferId = "transferId"
    }
}

enum SiloWireConflictPolicy: String, Codable, Equatable, Sendable {
    case ask = "ask"
    case keepBoth = "keepBoth"
    case replace = "replace"
}

enum SiloWireUploadOrigin: String, Codable, Equatable, Sendable {
    case client = "client"
    case viewer = "viewer"
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWireGetJobParams
struct SiloWireGetJobParams: Codable, Equatable, Sendable {
    var deviceId: String? = nil
    var jobId: String
    var offsetBytes: UInt64? = nil

    enum CodingKeys: String, CodingKey {
        case deviceId = "deviceId"
        case jobId = "jobId"
        case offsetBytes = "offsetBytes"
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWireGitHubAccessSetParams
struct SiloWireGitHubAccessSetParams: Codable, Equatable, Sendable {
    var deviceId: String? = nil
    var enabled: Bool

    enum CodingKeys: String, CodingKey {
        case deviceId = "deviceId"
        case enabled = "enabled"
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWireGitHubConfigurationRetryParams
struct SiloWireGitHubConfigurationRetryParams: Codable, Equatable, Sendable {
    var computerId: String? = nil
    var deviceId: String? = nil

    enum CodingKeys: String, CodingKey {
        case computerId = "computerId"
        case deviceId = "deviceId"
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWireGitHubConfigurationSaveParams
struct SiloWireGitHubConfigurationSaveParams: Codable, Equatable, Sendable {
    var configuration: SiloWireGitHubConfiguration
    var deviceId: String? = nil

    enum CodingKeys: String, CodingKey {
        case configuration = "configuration"
        case deviceId = "deviceId"
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWireGitHubConfiguration
struct SiloWireGitHubConfiguration: Codable, Equatable, Sendable {
    var baseRevision: UInt64? = nil
    var computers: [SiloWireGitHubPolicy]

    enum CodingKeys: String, CodingKey {
        case baseRevision = "baseRevision"
        case computers = "computers"
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

/// Public projection of `app/SiloUI/src-tauri/engine/src/github.rs::public_snapshot`;
/// `computer` references are replaced with canonical `computerId` identifiers.
// MARK: - SiloWireGitHubPolicy
struct SiloWireGitHubPolicy: Codable, Equatable, Sendable {
    var allRepositoriesAllowChanges: Bool
    var authenticationMethod: SiloWireGitHubAuthenticationMethod
    var computerId: String
    var identity: SiloWireGitHubIdentity
    var repositories: [SiloWireGitHubRepositoryPolicy]
    var repositoryMode: SiloWireGitHubRepositoryMode

    enum CodingKeys: String, CodingKey {
        case allRepositoriesAllowChanges = "allRepositoriesAllowChanges"
        case authenticationMethod = "authenticationMethod"
        case computerId = "computerId"
        case identity = "identity"
        case repositories = "repositories"
        case repositoryMode = "repositoryMode"
    }
}

enum SiloWireGitHubAuthenticationMethod: String, Codable, Equatable, Sendable {
    case oauth = "oauth"
    case token = "token"
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWireGitHubIdentity
struct SiloWireGitHubIdentity: Codable, Equatable, Sendable {
    var apply: Bool
    var email: String
    var name: String

    enum CodingKeys: String, CodingKey {
        case apply = "apply"
        case email = "email"
        case name = "name"
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWireGitHubRepositoryPolicy
struct SiloWireGitHubRepositoryPolicy: Codable, Equatable, Sendable {
    var allowPushes: Bool
    var repository: String

    enum CodingKeys: String, CodingKey {
        case allowPushes = "allowPushes"
        case repository = "repository"
    }
}

enum SiloWireGitHubRepositoryMode: String, Codable, Equatable, Sendable {
    case all = "all"
    case selected = "selected"
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWireGitHubConnectCallbackParams
struct SiloWireGitHubConnectCallbackParams: Codable, Equatable, Sendable {
    var deviceId: String? = nil
    var jobId: String

    enum CodingKeys: String, CodingKey {
        case deviceId = "deviceId"
        case jobId = "jobId"
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWireGitHubPersonalTokenSaveParams
struct SiloWireGitHubPersonalTokenSaveParams: Codable, Equatable, Sendable {
    var deviceId: String? = nil
    var token: String

    enum CodingKeys: String, CodingKey {
        case deviceId = "deviceId"
        case token = "token"
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWireGitHubRepositoriesManageResult
struct SiloWireGitHubRepositoriesManageResult: Codable, Equatable, Sendable {
    var url: String

    enum CodingKeys: String, CodingKey {
        case url = "url"
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWireGuestAccount
struct SiloWireGuestAccount: Codable, Equatable, Sendable {
    var home: String
    var uid: Int
    var user: String

    enum CodingKeys: String, CodingKey {
        case home = "home"
        case uid = "uid"
        case user = "user"
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWireGuestAccountParams
struct SiloWireGuestAccountParams: Codable, Equatable, Sendable {
    var computerId: String
    var deviceId: String? = nil

    enum CodingKeys: String, CodingKey {
        case computerId = "computerId"
        case deviceId = "deviceId"
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWireGuestExecExitedEvent
struct SiloWireGuestExecExitedEvent: Codable, Equatable, Sendable {
    var exitCode: Int32? = nil
    var jobId: String
    var signal: String? = nil

    enum CodingKeys: String, CodingKey {
        case exitCode = "exitCode"
        case jobId = "jobId"
        case signal = "signal"
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWireGuestExecGetParams
struct SiloWireGuestExecGetParams: Codable, Equatable, Sendable {
    var deviceId: String? = nil
    var jobId: String
    var sinceSeq: UInt64? = nil

    enum CodingKeys: String, CodingKey {
        case deviceId = "deviceId"
        case jobId = "jobId"
        case sinceSeq = "sinceSeq"
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWireGuestExecGetResult
struct SiloWireGuestExecGetResult: Codable, Equatable, Sendable {
    var exitCode: Int32? = nil
    var firstRetainedSeq: UInt64
    var output: [SiloWireGuestExecOutput]
    var state: SiloWireGuestExecState

    enum CodingKeys: String, CodingKey {
        case exitCode = "exitCode"
        case firstRetainedSeq = "firstRetainedSeq"
        case output = "output"
        case state = "state"
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWireGuestExecOutput
struct SiloWireGuestExecOutput: Codable, Equatable, Sendable {
    var data: [Int]
    var seq: UInt64
    var stream: SiloWireGuestExecStream

    enum CodingKeys: String, CodingKey {
        case data = "data"
        case seq = "seq"
        case stream = "stream"
    }
}

enum SiloWireGuestExecStream: String, Codable, Equatable, Sendable {
    case stderr = "stderr"
    case stdout = "stdout"
}

enum SiloWireGuestExecState: String, Codable, Equatable, Sendable {
    case cancelled = "cancelled"
    case exited = "exited"
    case lost = "lost"
    case running = "running"
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWireGuestExecInputParams
struct SiloWireGuestExecInputParams: Codable, Equatable, Sendable {
    var close: Bool? = nil
    var data: [Int]? = nil
    var jobId: String

    enum CodingKeys: String, CodingKey {
        case close = "close"
        case data = "data"
        case jobId = "jobId"
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWireGuestExecOutputEvent
struct SiloWireGuestExecOutputEvent: Codable, Equatable, Sendable {
    var data: [Int]
    var jobId: String
    var seq: UInt64
    var stream: SiloWireGuestExecStream

    enum CodingKeys: String, CodingKey {
        case data = "data"
        case jobId = "jobId"
        case seq = "seq"
        case stream = "stream"
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWireGuestExecParams
struct SiloWireGuestExecParams: Codable, Equatable, Sendable {
    var argv: [String]
    var guestExecParamsAs: SiloWireGuestExecUser? = nil
    var computerId: String
    var cwd: String? = nil
    var deviceId: String? = nil
    var env: [SiloWireGuestEnvVar]? = nil
    var maxOutputBytes: UInt64? = nil
    var stdin: [Int]? = nil
    var timeoutMs: UInt64

    enum CodingKeys: String, CodingKey {
        case argv = "argv"
        case guestExecParamsAs = "as"
        case computerId = "computerId"
        case cwd = "cwd"
        case deviceId = "deviceId"
        case env = "env"
        case maxOutputBytes = "maxOutputBytes"
        case stdin = "stdin"
        case timeoutMs = "timeoutMs"
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWireGuestEnvVar
struct SiloWireGuestEnvVar: Codable, Equatable, Sendable {
    var name: String
    var value: String

    enum CodingKeys: String, CodingKey {
        case name = "name"
        case value = "value"
    }
}

enum SiloWireGuestExecUser: String, Codable, Equatable, Sendable {
    case account = "account"
    case root = "root"
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWireGuestExecResult
struct SiloWireGuestExecResult: Codable, Equatable, Sendable {
    var exitCode: Int32? = nil
    var signal: String? = nil
    var stderr: [Int]
    var stdout: [Int]

    enum CodingKeys: String, CodingKey {
        case exitCode = "exitCode"
        case signal = "signal"
        case stderr = "stderr"
        case stdout = "stdout"
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWireGuestExecStartParams
struct SiloWireGuestExecStartParams: Codable, Equatable, Sendable {
    var argv: [String]
    var guestExecStartParamsAs: SiloWireGuestExecUser? = nil
    var computerId: String
    var cwd: String? = nil
    var deviceId: String? = nil
    var env: [SiloWireGuestEnvVar]? = nil
    var retainOutputBytes: UInt64
    var stdin: [Int]? = nil
    var stdinOpen: Bool

    enum CodingKeys: String, CodingKey {
        case argv = "argv"
        case guestExecStartParamsAs = "as"
        case computerId = "computerId"
        case cwd = "cwd"
        case deviceId = "deviceId"
        case env = "env"
        case retainOutputBytes = "retainOutputBytes"
        case stdin = "stdin"
        case stdinOpen = "stdinOpen"
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWireGuestFilesChangedPayload
struct SiloWireGuestFilesChangedPayload: Codable, Equatable, Sendable {
    var path: String
    var subscriptionId: String

    enum CodingKeys: String, CodingKey {
        case path = "path"
        case subscriptionId = "subscriptionId"
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWireGuestFilesListParams
struct SiloWireGuestFilesListParams: Codable, Equatable, Sendable {
    var computerId: String
    var deviceId: String? = nil
    var path: String

    enum CodingKeys: String, CodingKey {
        case computerId = "computerId"
        case deviceId = "deviceId"
        case path = "path"
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWireGuestFilesListResult
struct SiloWireGuestFilesListResult: Codable, Equatable, Sendable {
    var entries: [SiloWireGuestFileEntry]

    enum CodingKeys: String, CodingKey {
        case entries = "entries"
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWireGuestFileEntry
struct SiloWireGuestFileEntry: Codable, Equatable, Sendable {
    var mtimeMs: UInt64
    var name: String
    var size: UInt64
    var type: SiloWireGuestFileKind

    enum CodingKeys: String, CodingKey {
        case mtimeMs = "mtimeMs"
        case name = "name"
        case size = "size"
        case type = "type"
    }
}

enum SiloWireGuestFileKind: String, Codable, Equatable, Sendable {
    case dir = "dir"
    case file = "file"
    case link = "link"
    case other = "other"
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWireGuestFilesReadParams
struct SiloWireGuestFilesReadParams: Codable, Equatable, Sendable {
    var computerId: String
    var deviceId: String? = nil
    var length: UInt64? = nil
    var offset: UInt64? = nil
    var path: String

    enum CodingKeys: String, CodingKey {
        case computerId = "computerId"
        case deviceId = "deviceId"
        case length = "length"
        case offset = "offset"
        case path = "path"
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWireGuestFilesReadResult
struct SiloWireGuestFilesReadResult: Codable, Equatable, Sendable {
    var data: [Int]
    var inode: UInt64
    var mode: Int
    var mtimeMs: UInt64
    var size: UInt64

    enum CodingKeys: String, CodingKey {
        case data = "data"
        case inode = "inode"
        case mode = "mode"
        case mtimeMs = "mtimeMs"
        case size = "size"
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWireGuestFilesRemoveParams
struct SiloWireGuestFilesRemoveParams: Codable, Equatable, Sendable {
    var computerId: String
    var deviceId: String? = nil
    var paths: [String]

    enum CodingKeys: String, CodingKey {
        case computerId = "computerId"
        case deviceId = "deviceId"
        case paths = "paths"
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWireGuestFilesRemoveResult
struct SiloWireGuestFilesRemoveResult: Codable, Equatable, Sendable {
    var removed: [String]

    enum CodingKeys: String, CodingKey {
        case removed = "removed"
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWireGuestFilesWatchParams
struct SiloWireGuestFilesWatchParams: Codable, Equatable, Sendable {
    var computerId: String
    var deviceId: String? = nil
    var paths: [String]

    enum CodingKeys: String, CodingKey {
        case computerId = "computerId"
        case deviceId = "deviceId"
        case paths = "paths"
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWireGuestFilesWatchResult
struct SiloWireGuestFilesWatchResult: Codable, Equatable, Sendable {
    var subscriptionId: String

    enum CodingKeys: String, CodingKey {
        case subscriptionId = "subscriptionId"
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWireGuestFilesWriteParams
struct SiloWireGuestFilesWriteParams: Codable, Equatable, Sendable {
    var computerId: String
    var createParents: Bool? = nil
    var data: [Int]
    var deviceId: String? = nil
    var expectedSha256: String? = nil
    var mode: Int
    var path: String
    var replace: SiloWireGuestFileReplace

    enum CodingKeys: String, CodingKey {
        case computerId = "computerId"
        case createParents = "createParents"
        case data = "data"
        case deviceId = "deviceId"
        case expectedSha256 = "expectedSha256"
        case mode = "mode"
        case path = "path"
        case replace = "replace"
    }
}

enum SiloWireGuestFileReplace: String, Codable, Equatable, Sendable {
    case always = "always"
    case ifSha256 = "ifSha256"
    case never = "never"
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWireGuestFilesWriteResult
struct SiloWireGuestFilesWriteResult: Codable, Equatable, Sendable {
    var inode: UInt64
    var mtimeMs: UInt64
    var size: UInt64

    enum CodingKeys: String, CodingKey {
        case inode = "inode"
        case mtimeMs = "mtimeMs"
        case size = "size"
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWireGuestPrepareParams
struct SiloWireGuestPrepareParams: Codable, Equatable, Sendable {
    var accountProtocol: Int
    var computerId: String
    var deviceId: String? = nil
    var forwarding: Bool? = nil
    var path: String
    var publicKey: String

    enum CodingKeys: String, CodingKey {
        case accountProtocol = "accountProtocol"
        case computerId = "computerId"
        case deviceId = "deviceId"
        case forwarding = "forwarding"
        case path = "path"
        case publicKey = "publicKey"
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWireGuestPrepareResult
struct SiloWireGuestPrepareResult: Codable, Equatable, Sendable {
    var guestAddress: String? = nil
    var hostPublicKey: String
    var user: String

    enum CodingKeys: String, CodingKey {
        case guestAddress = "guestAddress"
        case hostPublicKey = "hostPublicKey"
        case user = "user"
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWireGuestSshAliasEnsureParams
struct SiloWireGuestSshAliasEnsureParams: Codable, Equatable, Sendable {
    var computerId: String
    var deviceId: String? = nil
    var installInclude: Bool? = nil
    var path: String? = nil

    enum CodingKeys: String, CodingKey {
        case computerId = "computerId"
        case deviceId = "deviceId"
        case installInclude = "installInclude"
        case path = "path"
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWireGuestSshAliasEnsureResult
struct SiloWireGuestSshAliasEnsureResult: Codable, Equatable, Sendable {
    var alias: String
    var configPath: String
    var home: String
    var includeInstalled: Bool
    var includeLine: String
    var user: String

    enum CodingKeys: String, CodingKey {
        case alias = "alias"
        case configPath = "configPath"
        case home = "home"
        case includeInstalled = "includeInstalled"
        case includeLine = "includeLine"
        case user = "user"
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWireGuestSshParams
struct SiloWireGuestSshParams: Codable, Equatable, Sendable {
    var computerId: String
    var port: Int? = nil
    var purpose: SiloWireGuestSshPurpose? = nil

    enum CodingKeys: String, CodingKey {
        case computerId = "computerId"
        case port = "port"
        case purpose = "purpose"
    }
}

enum SiloWireGuestSshPurpose: String, Codable, Equatable, Sendable {
    case port = "port"
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWireJobStartResult
struct SiloWireJobStartResult: Codable, Equatable, Sendable {
    var jobId: String

    enum CodingKeys: String, CodingKey {
        case jobId = "jobId"
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWireLaunchStatus
struct SiloWireLaunchStatus: Codable, Equatable, Sendable {
    var computerIds: [String]
    var enabled: Bool
    var lastPass: SiloWireLaunchPass? = nil

    enum CodingKeys: String, CodingKey {
        case computerIds = "computerIds"
        case enabled = "enabled"
        case lastPass = "lastPass"
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWireLaunchPass
struct SiloWireLaunchPass: Codable, Equatable, Sendable {
    var failures: [String]
    var finishedAt: UInt64

    enum CodingKeys: String, CodingKey {
        case failures = "failures"
        case finishedAt = "finishedAt"
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

/// Canonical lifecycle payload at `runtime.rs:3343`; the step values mirror
/// `app/SiloUI/src-tauri/engine/src/runtime.rs::LifecycleStep` (line 1275).
// MARK: - SiloWireLifecycleProgress
struct SiloWireLifecycleProgress: Codable, Equatable, Sendable {
    var action: String
    var computerId: String
    var step: SiloWireLifecycleStep

    enum CodingKeys: String, CodingKey {
        case action = "action"
        case computerId = "computerId"
        case step = "step"
    }
}

enum SiloWireLifecycleStep: String, Codable, Equatable, Sendable {
    case account = "account"
    case boot = "boot"
    case network = "network"
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWireLogPage
struct SiloWireLogPage: Codable, Equatable, Sendable {
    var entries: [SiloWireLogEntry]
    var newestAvailableTimestamp: String? = nil
    var nextCursor: String? = nil
    var oldestAvailableTimestamp: String? = nil
    var snapshot: String? = nil
    var timestampEstimated: Bool
    var totalMatches: UInt64
    var unreadableRecords: Bool? = nil
    var unsupported: Bool? = nil

    enum CodingKeys: String, CodingKey {
        case entries = "entries"
        case newestAvailableTimestamp = "newestAvailableTimestamp"
        case nextCursor = "nextCursor"
        case oldestAvailableTimestamp = "oldestAvailableTimestamp"
        case snapshot = "snapshot"
        case timestampEstimated = "timestampEstimated"
        case totalMatches = "totalMatches"
        case unreadableRecords = "unreadableRecords"
        case unsupported = "unsupported"
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWireLogEntry
struct SiloWireLogEntry: Codable, Equatable, Sendable {
    var computerId: String
    var computerName: String
    var deviceId: String
    var deviceName: String
    var guestTimestamp: Bool? = nil
    var id: String
    var line: String
    var occurredAt: String
    var session: String? = nil
    var source: String

    enum CodingKeys: String, CodingKey {
        case computerId = "computerId"
        case computerName = "computerName"
        case deviceId = "deviceId"
        case deviceName = "deviceName"
        case guestTimestamp = "guestTimestamp"
        case id = "id"
        case line = "line"
        case occurredAt = "occurredAt"
        case session = "session"
        case source = "source"
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWireLogsExportParams
struct SiloWireLogsExportParams: Codable, Equatable, Sendable {
    var destination: String
    var requests: [SiloWireLogsQueryParams]

    enum CodingKeys: String, CodingKey {
        case destination = "destination"
        case requests = "requests"
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWireLogsQueryParams
struct SiloWireLogsQueryParams: Codable, Equatable, Sendable {
    var aroundId: String? = nil
    var computerId: String
    var cursor: String? = nil
    var deviceId: String? = nil
    var follow: String? = nil
    var limit: Int? = nil
    var query: String? = nil
    var since: String? = nil
    var source: SiloWireLogSource? = nil
    var until: String? = nil

    enum CodingKeys: String, CodingKey {
        case aroundId = "aroundId"
        case computerId = "computerId"
        case cursor = "cursor"
        case deviceId = "deviceId"
        case follow = "follow"
        case limit = "limit"
        case query = "query"
        case since = "since"
        case source = "source"
        case until = "until"
    }
}

enum SiloWireLogSource: String, Codable, Equatable, Sendable {
    case all = "all"
    case kernel = "kernel"
    case output = "output"
    case runtime = "runtime"
    case stderr = "stderr"
    case stdout = "stdout"
    case system = "system"
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWireMacosDisplayConnectParams
struct SiloWireMacosDisplayConnectParams: Codable, Equatable, Sendable {
    var computerId: String

    enum CodingKeys: String, CodingKey {
        case computerId = "computerId"
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWireMacosDisplayConnectResult
struct SiloWireMacosDisplayConnectResult: Codable, Equatable, Sendable {
    var height: Int
    var password: String
    var username: String
    var width: Int

    enum CodingKeys: String, CodingKey {
        case height = "height"
        case password = "password"
        case username = "username"
        case width = "width"
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWireMacosDisplayResizeParams
struct SiloWireMacosDisplayResizeParams: Codable, Equatable, Sendable {
    var computerId: String
    var heightPx: UInt64
    var widthPx: UInt64

    enum CodingKeys: String, CodingKey {
        case computerId = "computerId"
        case heightPx = "heightPx"
        case widthPx = "widthPx"
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWireMacosDisplayResizeResult
struct SiloWireMacosDisplayResizeResult: Codable, Equatable, Sendable {
    var heightPx: Int
    var widthPx: Int

    enum CodingKeys: String, CodingKey {
        case heightPx = "heightPx"
        case widthPx = "widthPx"
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWireMacosDisplaySessionParams
struct SiloWireMacosDisplaySessionParams: Codable, Equatable, Sendable {
    var computerId: String
    var deviceId: String

    enum CodingKeys: String, CodingKey {
        case computerId = "computerId"
        case deviceId = "deviceId"
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWireMacosDisplaySessionResult
struct SiloWireMacosDisplaySessionResult: Codable, Equatable, Sendable {
    var height: Int
    var password: String
    var url: String
    var username: String
    var width: Int

    enum CodingKeys: String, CodingKey {
        case height = "height"
        case password = "password"
        case url = "url"
        case username = "username"
        case width = "width"
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

/// The macOS progress projection from 05 §4.2 E (`MacosComputer` row fields).
// MARK: - SiloWireMacosJobProgress
struct SiloWireMacosJobProgress: Codable, Equatable, Sendable {
    var checkpointOperation: SiloWireOperation? = nil
    var computerId: String
    var detail: String? = nil
    var progress: Double? = nil
    var state: SiloWireMacosComputerState

    enum CodingKeys: String, CodingKey {
        case checkpointOperation = "checkpointOperation"
        case computerId = "computerId"
        case detail = "detail"
        case progress = "progress"
        case state = "state"
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

/// Optimistic state check for a stopped macOS computer's resource edit.
// MARK: - SiloWireMacosResourceConfiguration
struct SiloWireMacosResourceConfiguration: Codable, Equatable, Sendable {
    var cpus: UInt64
    var diskGiB: UInt64
    var memoryGiB: UInt64

    enum CodingKeys: String, CodingKey {
        case cpus = "cpus"
        case diskGiB = "diskGiB"
        case memoryGiB = "memoryGiB"
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWireMigrationState
struct SiloWireMigrationState: Codable, Equatable, Sendable {
    var canContinue: Bool
    var error: String? = nil
    var failedCount: UInt64
    var logPath: String? = nil
    var logs: [String]
    var migratedCount: UInt64
    var stage: String
    var status: String
    var totalCount: UInt64
    var version: Int

    enum CodingKeys: String, CodingKey {
        case canContinue = "canContinue"
        case error = "error"
        case failedCount = "failedCount"
        case logPath = "logPath"
        case logs = "logs"
        case migratedCount = "migratedCount"
        case stage = "stage"
        case status = "status"
        case totalCount = "totalCount"
        case version = "version"
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWireNativeDisplayAttachParams
struct SiloWireNativeDisplayAttachParams: Codable, Equatable, Sendable {
    var computerId: String

    enum CodingKeys: String, CodingKey {
        case computerId = "computerId"
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

/// JSON messages used by the native display stream. Pixel data itself is
/// transferred out of band through the shared-memory path.
// MARK: - SiloWireNativeDisplayMessage
struct SiloWireNativeDisplayMessage: Codable, Equatable, Sendable {
    var sandbox: String? = nil
    var t: SiloWireT
    var format: String? = nil
    var height: Int? = nil
    var path: String? = nil
    var scanout: Int? = nil
    var slots: Int? = nil
    var width: Int? = nil
    var rect: [Int]? = nil
    var seq: UInt64? = nil
    var slot: Int? = nil
    var code: Int? = nil
    var down: Bool? = nil
    var x: SiloDisplayAxis? = nil
    var y: SiloDisplayAxis? = nil
    var value: Int32? = nil

    enum CodingKeys: String, CodingKey {
        case sandbox = "sandbox"
        case t = "t"
        case format = "format"
        case height = "height"
        case path = "path"
        case scanout = "scanout"
        case slots = "slots"
        case width = "width"
        case rect = "rect"
        case seq = "seq"
        case slot = "slot"
        case code = "code"
        case down = "down"
        case x = "x"
        case y = "y"
        case value = "value"
    }
}

enum SiloWireT: String, Codable, Equatable, Sendable {
    case abs = "abs"
    case btn = "btn"
    case configure = "configure"
    case disable = "disable"
    case frame = "frame"
    case hello = "hello"
    case key = "key"
    case rel = "rel"
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWireNetworkOpenParams
struct SiloWireNetworkOpenParams: Codable, Equatable, Sendable {
    var computerId: String
    var deviceId: String? = nil
    var port: Int

    enum CodingKeys: String, CodingKey {
        case computerId = "computerId"
        case deviceId = "deviceId"
        case port = "port"
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWireNetworkOpenResult
struct SiloWireNetworkOpenResult: Codable, Equatable, Sendable {
    var url: String

    enum CodingKeys: String, CodingKey {
        case url = "url"
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWireNetworkPublishParams
struct SiloWireNetworkPublishParams: Codable, Equatable, Sendable {
    var computerId: String
    var deviceId: String? = nil
    var hostPort: Int? = nil
    var port: Int
    var scheme: SiloWireNetworkScheme? = nil

    enum CodingKeys: String, CodingKey {
        case computerId = "computerId"
        case deviceId = "deviceId"
        case hostPort = "hostPort"
        case port = "port"
        case scheme = "scheme"
    }
}

enum SiloWireNetworkScheme: String, Codable, Equatable, Sendable {
    case http = "http"
    case https = "https"
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWireNetworkState
struct SiloWireNetworkState: Codable, Equatable, Sendable {
    var computers: [SiloWireNetworkComputer]

    enum CodingKeys: String, CodingKey {
        case computers = "computers"
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWireNetworkComputer
struct SiloWireNetworkComputer: Codable, Equatable, Sendable {
    var computer: String
    var computerId: String? = nil
    var error: String? = nil
    var host: String? = nil
    var ports: [SiloWirePublishedPort]

    enum CodingKeys: String, CodingKey {
        case computer = "computer"
        case computerId = "computerId"
        case error = "error"
        case host = "host"
        case ports = "ports"
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWirePublishedPort
struct SiloWirePublishedPort: Codable, Equatable, Sendable {
    var configured: Bool
    var configuredHostPort: Int? = nil
    var hostPort: Int? = nil
    var message: String? = nil
    var port: Int
    var scheme: SiloWireNetworkScheme? = nil
    var state: SiloWirePublishedPortState

    enum CodingKeys: String, CodingKey {
        case configured = "configured"
        case configuredHostPort = "configuredHostPort"
        case hostPort = "hostPort"
        case message = "message"
        case port = "port"
        case scheme = "scheme"
        case state = "state"
    }
}

enum SiloWirePublishedPortState: String, Codable, Equatable, Sendable {
    case reachable = "reachable"
    case unknown = "unknown"
    case unpublished = "unpublished"
    case waiting = "waiting"
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWireNetworkUnpublishParams
struct SiloWireNetworkUnpublishParams: Codable, Equatable, Sendable {
    var computerId: String
    var deviceId: String? = nil
    var port: Int

    enum CodingKeys: String, CodingKey {
        case computerId = "computerId"
        case deviceId = "deviceId"
        case port = "port"
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWireNotice
struct SiloWireNotice: Codable, Equatable, Sendable {
    var body: String
    var category: SiloWireNoticeCategory
    var computer: SiloWireNoticeComputer? = nil
    var key: String
    var title: String

    enum CodingKeys: String, CodingKey {
        case body = "body"
        case category = "category"
        case computer = "computer"
        case key = "key"
        case title = "title"
    }
}

enum SiloWireNoticeCategory: String, Codable, Equatable, Sendable {
    case changes = "changes"
    case completions = "completions"
    case failures = "failures"
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWireNoticeComputer
struct SiloWireNoticeComputer: Codable, Equatable, Sendable {
    var id: String
    var name: String

    enum CodingKeys: String, CodingKey {
        case id = "id"
        case name = "name"
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWireNotificationsClearedPayload
struct SiloWireNotificationsClearedPayload: Codable, Equatable, Sendable {
    var computerId: String

    enum CodingKeys: String, CodingKey {
        case computerId = "computerId"
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

/// Mirrors `app/SiloUI/src-tauri/engine/src/runtime/operation_gate.rs::OperationQueue`
/// and adds the retained completed-job discovery list required by 95 §3.
// MARK: - SiloWireOperationQueue
struct SiloWireOperationQueue: Codable, Equatable, Sendable {
    var running: [SiloWireOperationEntry]
    var unacknowledgedJobIds: [String]
    var waiting: [SiloWireOperationEntry]

    enum CodingKeys: String, CodingKey {
        case running = "running"
        case unacknowledgedJobIds = "unacknowledgedJobIds"
        case waiting = "waiting"
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

/// Mirrors `app/SiloUI/src-tauri/engine/src/runtime/operation_gate.rs::OperationEntry`.
// MARK: - SiloWireOperationEntry
struct SiloWireOperationEntry: Codable, Equatable, Sendable {
    var blockedByHidden: Bool? = nil
    var cancellable: Bool
    var computerId: String? = nil
    var computerName: String? = nil
    var expectedMs: UInt64? = nil
    var id: UInt64
    /// Added by the canonical job contract; absent for non-job queue entries.
    var jobId: String? = nil
    var kind: SiloWireOperationKind2
    var label: String
    var sinceMs: UInt64

    enum CodingKeys: String, CodingKey {
        case blockedByHidden = "blockedByHidden"
        case cancellable = "cancellable"
        case computerId = "computerId"
        case computerName = "computerName"
        case expectedMs = "expectedMs"
        case id = "id"
        case jobId = "jobId"
        case kind = "kind"
        case label = "label"
        case sinceMs = "sinceMs"
    }
}

/// Mirrors `app/SiloUI/src-tauri/engine/src/runtime/operation_gate.rs::OperationKind`
/// and its camelCase serde names.
enum SiloWireOperationKind2: String, Codable, Equatable, Sendable {
    case checkpointCapture = "checkpointCapture"
    case checkpointDelete = "checkpointDelete"
    case checkpointFork = "checkpointFork"
    case checkpointRestore = "checkpointRestore"
    case computerConfiguration = "computerConfiguration"
    case export = "export"
    case githubApply = "githubApply"
    case kindImport = "import"
    case lifecycle = "lifecycle"
    case other = "other"
    case portPublish = "portPublish"
    case portRemove = "portRemove"
    case push = "push"
    case shutdown = "shutdown"
    case storageReclaim = "storageReclaim"
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWireOperationsListParams
struct SiloWireOperationsListParams: Codable, Equatable, Sendable {
    var deviceId: String? = nil

    enum CodingKeys: String, CodingKey {
        case deviceId = "deviceId"
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

/// The Linux and macOS forms described in 20 §1.4. Their field names and
/// optionality match `runtime/checkpoints.rs` and `macos_computers/checkpoints.rs`.
// MARK: - SiloWirePendingRestore
struct SiloWirePendingRestore: Codable, Equatable, Sendable {
    var checkpointId: String
    var sourceComputer: String? = nil
    var state: SiloWireCheckpointScope? = nil
    var memory: Bool? = nil

    enum CodingKeys: String, CodingKey {
        case checkpointId = "checkpointId"
        case sourceComputer = "sourceComputer"
        case state = "state"
        case memory = "memory"
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWirePreUpgradeBackup
struct SiloWirePreUpgradeBackup: Codable, Equatable, Sendable {
    var deleteAt: String? = nil
    var noticePending: Bool
    var path: String

    enum CodingKeys: String, CodingKey {
        case deleteAt = "deleteAt"
        case noticePending = "noticePending"
        case path = "path"
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

/// Mirrors `app/SiloUI/src-tauri/engine/src/preparation.rs::PreparationStatus`.
// MARK: - SiloWirePreparationStatus
struct SiloWirePreparationStatus: Codable, Equatable, Sendable {
    var image: SiloWirePreparationTask
    var lcu: SiloWirePreparationTask

    enum CodingKeys: String, CodingKey {
        case image = "image"
        case lcu = "lcu"
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWirePreparationTask
struct SiloWirePreparationTask: Codable, Equatable, Sendable {
    var fraction: Int? = nil
    var message: String? = nil
    var retryable: Bool
    var state: SiloWirePreparationTaskState

    enum CodingKeys: String, CodingKey {
        case fraction = "fraction"
        case message = "message"
        case retryable = "retryable"
        case state = "state"
    }
}

enum SiloWirePreparationTaskState: String, Codable, Equatable, Sendable {
    case failed = "failed"
    case pending = "pending"
    case ready = "ready"
    case running = "running"
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWirePushDismissParams
struct SiloWirePushDismissParams: Codable, Equatable, Sendable {
    var computerId: String
    var deviceId: String? = nil
    var repositoryPath: String

    enum CodingKeys: String, CodingKey {
        case computerId = "computerId"
        case deviceId = "deviceId"
        case repositoryPath = "repositoryPath"
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWirePushRepositoriesParams
struct SiloWirePushRepositoriesParams: Codable, Equatable, Sendable {
    var computerId: String
    var deviceId: String? = nil
    var refresh: Bool? = nil

    enum CodingKeys: String, CodingKey {
        case computerId = "computerId"
        case deviceId = "deviceId"
        case refresh = "refresh"
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWirePushRepository
struct SiloWirePushRepository: Codable, Equatable, Sendable {
    var ahead: UInt64
    var behind: UInt64
    var branch: String
    var dirty: Bool
    var head: String? = nil
    var path: String
    var repository: String? = nil

    enum CodingKeys: String, CodingKey {
        case ahead = "ahead"
        case behind = "behind"
        case branch = "branch"
        case dirty = "dirty"
        case head = "head"
        case path = "path"
        case repository = "repository"
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWirePushStartParams
struct SiloWirePushStartParams: Codable, Equatable, Sendable {
    var computerId: String
    var deviceId: String? = nil
    var operationId: String
    var repositoryPath: String
    var target: SiloWirePushTarget

    enum CodingKeys: String, CodingKey {
        case computerId = "computerId"
        case deviceId = "deviceId"
        case operationId = "operationId"
        case repositoryPath = "repositoryPath"
        case target = "target"
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWirePushTarget
struct SiloWirePushTarget: Codable, Equatable, Sendable {
    var branch: String
    var commit: String
    var repository: String

    enum CodingKeys: String, CodingKey {
        case branch = "branch"
        case commit = "commit"
        case repository = "repository"
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWirePushStatusParams
struct SiloWirePushStatusParams: Codable, Equatable, Sendable {
    var computerId: String
    var deviceId: String? = nil
    var operationId: String
    var repositoryPath: String

    enum CodingKeys: String, CodingKey {
        case computerId = "computerId"
        case deviceId = "deviceId"
        case operationId = "operationId"
        case repositoryPath = "repositoryPath"
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWireRevokeKeyParams
struct SiloWireRevokeKeyParams: Codable, Equatable, Sendable {
    var deviceId: String? = nil
    var publicKey: String

    enum CodingKeys: String, CodingKey {
        case deviceId = "deviceId"
        case publicKey = "publicKey"
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWireSecret
struct SiloWireSecret: Codable, Equatable, Sendable {
    var allowedDomains: [String]
    var computerIds: [String]
    var error: String? = nil
    var id: String
    var name: String
    var pendingComputerIds: [String]
    var removing: Bool
    var state: SiloWireSecretState

    enum CodingKeys: String, CodingKey {
        case allowedDomains = "allowedDomains"
        case computerIds = "computerIds"
        case error = "error"
        case id = "id"
        case name = "name"
        case pendingComputerIds = "pendingComputerIds"
        case removing = "removing"
        case state = "state"
    }
}

enum SiloWireSecretState: String, Codable, Equatable, Sendable {
    case active = "active"
    case applying = "applying"
    case restartRequired = "restart-required"
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWireSecretIdParams
struct SiloWireSecretIdParams: Codable, Equatable, Sendable {
    var deviceId: String? = nil
    var id: String

    enum CodingKeys: String, CodingKey {
        case deviceId = "deviceId"
        case id = "id"
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWireSecretsSaveParams
struct SiloWireSecretsSaveParams: Codable, Equatable, Sendable {
    var deviceId: String? = nil
    var request: SiloWireSecretSaveRequest

    enum CodingKeys: String, CodingKey {
        case deviceId = "deviceId"
        case request = "request"
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWireSecretSaveRequest
struct SiloWireSecretSaveRequest: Codable, Equatable, Sendable {
    var allowAnyDestination: Bool? = nil
    var allowedDomains: [String]
    var computerIds: [String]
    var id: String? = nil
    var name: String
    var operation: SiloWireSecretSaveAction
    var value: String? = nil

    enum CodingKeys: String, CodingKey {
        case allowAnyDestination = "allowAnyDestination"
        case allowedDomains = "allowedDomains"
        case computerIds = "computerIds"
        case id = "id"
        case name = "name"
        case operation = "operation"
        case value = "value"
    }
}

enum SiloWireSecretSaveAction: String, Codable, Equatable, Sendable {
    case add = "add"
    case edit = "edit"
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

/// Mirrors `app/SiloUI/src-tauri/engine/src/settings.rs::Snapshot`, with the
/// engine-owned API draft fixed to JSON null as 60 §2.1 and 95 A-5 require.
// MARK: - SiloWireSettingsSnapshot
struct SiloWireSettingsSnapshot: Codable, Equatable, Sendable {
    var onboardingDraft: SiloJSONValue
    var revision: UInt64
    var saveError: String? = nil
    var settings: SiloWireSettingsValues
    var writeProtected: Bool

    enum CodingKeys: String, CodingKey {
        case onboardingDraft = "onboardingDraft"
        case revision = "revision"
        case saveError = "saveError"
        case settings = "settings"
        case writeProtected = "writeProtected"
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

/// Known settings exposed by 60 §2.3. Unknown keys are rejected by the API;
/// disk migration and legacy preservation remain engine concerns.
// MARK: - SiloWireSettingsValues
struct SiloWireSettingsValues: Codable, Equatable, Sendable {
    var alphaNoticeDismissed: Bool? = nil
    var automaticCheckpointRetentionCount: UInt64? = nil
    var browser: String? = nil
    var browserPath: String? = nil
    var browserUseSystemDefault: Bool? = nil
    var computerOrder: [String]? = nil
    var computerUseAutoApproval: Bool? = nil
    var editor: String? = nil
    var editorIncludeNoticeDismissed: String? = nil
    var editorPath: String? = nil
    var editorUseSystemDefault: Bool? = nil
    var launchAtLogin: Bool? = nil
    var notificationsEnabled: Bool? = nil
    var notifyChanges: Bool? = nil
    var notifyCompletions: Bool? = nil
    var notifyFailures: Bool? = nil
    var onboardingComplete: Bool? = nil
    var reduceMotion: Bool? = nil
    var startComputersAtLaunch: Bool? = nil
    var startupComputerIds: [String]? = nil
    var terminal: String? = nil
    var terminalPath: String? = nil
    var terminalUseSystemDefault: Bool? = nil
    var theme: SiloWireTheme? = nil

    enum CodingKeys: String, CodingKey {
        case alphaNoticeDismissed = "alphaNoticeDismissed"
        case automaticCheckpointRetentionCount = "automaticCheckpointRetentionCount"
        case browser = "browser"
        case browserPath = "browserPath"
        case browserUseSystemDefault = "browserUseSystemDefault"
        case computerOrder = "computerOrder"
        case computerUseAutoApproval = "computerUseAutoApproval"
        case editor = "editor"
        case editorIncludeNoticeDismissed = "editorIncludeNoticeDismissed"
        case editorPath = "editorPath"
        case editorUseSystemDefault = "editorUseSystemDefault"
        case launchAtLogin = "launchAtLogin"
        case notificationsEnabled = "notificationsEnabled"
        case notifyChanges = "notifyChanges"
        case notifyCompletions = "notifyCompletions"
        case notifyFailures = "notifyFailures"
        case onboardingComplete = "onboardingComplete"
        case reduceMotion = "reduceMotion"
        case startComputersAtLaunch = "startComputersAtLaunch"
        case startupComputerIds = "startupComputerIds"
        case terminal = "terminal"
        case terminalPath = "terminalPath"
        case terminalUseSystemDefault = "terminalUseSystemDefault"
        case theme = "theme"
    }
}

enum SiloWireTheme: String, Codable, Equatable, Sendable {
    case dark = "dark"
    case light = "light"
    case system = "system"
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWireSettingsUpdateParams
struct SiloWireSettingsUpdateParams: Codable, Equatable, Sendable {
    var patch: SiloWireSettingsValues

    enum CodingKeys: String, CodingKey {
        case patch = "patch"
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWireShutdownChangedPayload
struct SiloWireShutdownChangedPayload: Codable, Equatable, Sendable {
    var shuttingDown: Bool

    enum CodingKeys: String, CodingKey {
        case shuttingDown = "shuttingDown"
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWireSSHAccessConnectionParams
struct SiloWireSSHAccessConnectionParams: Codable, Equatable, Sendable {
    var computerId: String
    var destination: String? = nil
    var deviceId: String? = nil
    var download: Bool
    var network: Bool? = nil

    enum CodingKeys: String, CodingKey {
        case computerId = "computerId"
        case destination = "destination"
        case deviceId = "deviceId"
        case download = "download"
        case network = "network"
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWireSSHAccessSaveParams
struct SiloWireSSHAccessSaveParams: Codable, Equatable, Sendable {
    var bindAddress: String
    var computerId: String
    var deviceId: String? = nil
    var enabled: Bool
    var keys: [String]? = nil
    var port: Int

    enum CodingKeys: String, CodingKey {
        case bindAddress = "bindAddress"
        case computerId = "computerId"
        case deviceId = "deviceId"
        case enabled = "enabled"
        case keys = "keys"
        case port = "port"
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWireSSHAccessState
struct SiloWireSSHAccessState: Codable, Equatable, Sendable {
    var computers: [SiloWireSSHAccessComputer]

    enum CodingKeys: String, CodingKey {
        case computers = "computers"
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWireSSHAccessComputer
struct SiloWireSSHAccessComputer: Codable, Equatable, Sendable {
    var addresses: [String]
    var bindAddress: String
    var computer: String
    var computerId: String
    var deviceName: String
    var enabled: Bool
    var fingerprint: String? = nil
    var keys: [String]
    var message: String? = nil
    var port: Int
    var state: SiloWireSSHAccessComputerState
    var user: String

    enum CodingKeys: String, CodingKey {
        case addresses = "addresses"
        case bindAddress = "bindAddress"
        case computer = "computer"
        case computerId = "computerId"
        case deviceName = "deviceName"
        case enabled = "enabled"
        case fingerprint = "fingerprint"
        case keys = "keys"
        case message = "message"
        case port = "port"
        case state = "state"
        case user = "user"
    }
}

enum SiloWireSSHAccessComputerState: String, Codable, Equatable, Sendable {
    case disabled = "disabled"
    case error = "error"
    case listening = "listening"
    case waiting = "waiting"
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWireSSHAddressParams
struct SiloWireSSHAddressParams: Codable, Equatable, Sendable {
    var address: String

    enum CodingKeys: String, CodingKey {
        case address = "address"
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWireSSHCommandResult
struct SiloWireSSHCommandResult: Codable, Equatable, Sendable {
    var command: String

    enum CodingKeys: String, CodingKey {
        case command = "command"
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWireStorageParams
struct SiloWireStorageParams: Codable, Equatable, Sendable {
    var computerId: String
    var deviceId: String? = nil

    enum CodingKeys: String, CodingKey {
        case computerId = "computerId"
        case deviceId = "deviceId"
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWireTerminalCommandParams
struct SiloWireTerminalCommandParams: Codable, Equatable, Sendable {
    var computerId: String
    var deviceId: String? = nil

    enum CodingKeys: String, CodingKey {
        case computerId = "computerId"
        case deviceId = "deviceId"
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

/// Mirrors `app/SiloUI/src-tauri/engine/src/transfer.rs::Progress`; the serialized
/// names deliberately retain `id` and `computer`, not the surrounding job's
/// `jobId` and `computerId`.
// MARK: - SiloWireTransferProgress
struct SiloWireTransferProgress: Codable, Equatable, Sendable {
    var bytesDone: UInt64
    var bytesTotal: UInt64
    var computer: String
    var direction: SiloWireTransferDirection
    var fileCount: Int
    var fileIndex: Int
    var id: String
    var name: String
    var state: SiloWireTransferState

    enum CodingKeys: String, CodingKey {
        case bytesDone = "bytesDone"
        case bytesTotal = "bytesTotal"
        case computer = "computer"
        case direction = "direction"
        case fileCount = "fileCount"
        case fileIndex = "fileIndex"
        case id = "id"
        case name = "name"
        case state = "state"
    }
}

enum SiloWireTransferDirection: String, Codable, Equatable, Sendable {
    case download = "download"
    case upload = "upload"
}

enum SiloWireTransferState: String, Codable, Equatable, Sendable {
    case cancelled = "cancelled"
    case done = "done"
    case failed = "failed"
    case transferring = "transferring"
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWireUnexpectedComputerChange
struct SiloWireUnexpectedComputerChange: Codable, Equatable, Sendable {
    var computerId: String
    var name: String
    var state: String

    enum CodingKeys: String, CodingKey {
        case computerId = "computerId"
        case name = "name"
        case state = "state"
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

/// The `operations.job.progress` source projection mirrors the current Rust
/// `updates::Snapshot` at `app/SiloUI/src-tauri/engine/src/updates.rs:41-61` exactly.
/// Method and `updates.changed` results use `UpdateSnapshot`, which omits the
/// obsolete install helper field per 60 §5.1.
// MARK: - SiloWireUpdateProgressData
struct SiloWireUpdateProgressData: Codable, Equatable, Sendable {
    var automaticChecks: Bool
    var availableVersion: String? = nil
    var canInstall: Bool
    var currentVersion: String
    var downloadedBytes: UInt64
    var error: String? = nil
    var errorDetails: String? = nil
    var installBlockReason: String? = nil
    var installStatus: String? = nil
    var lastChecked: String? = nil
    var packageKind: String
    var phase: String
    var releaseNotes: String? = nil
    var releaseUrl: String
    var retryAction: String? = nil
    var runningComputers: [String]
    var totalBytes: UInt64? = nil

    enum CodingKeys: String, CodingKey {
        case automaticChecks = "automaticChecks"
        case availableVersion = "availableVersion"
        case canInstall = "canInstall"
        case currentVersion = "currentVersion"
        case downloadedBytes = "downloadedBytes"
        case error = "error"
        case errorDetails = "errorDetails"
        case installBlockReason = "installBlockReason"
        case installStatus = "installStatus"
        case lastChecked = "lastChecked"
        case packageKind = "packageKind"
        case phase = "phase"
        case releaseNotes = "releaseNotes"
        case releaseUrl = "releaseUrl"
        case retryAction = "retryAction"
        case runningComputers = "runningComputers"
        case totalBytes = "totalBytes"
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWireUpdatesSetAutomaticChecksParams
struct SiloWireUpdatesSetAutomaticChecksParams: Codable, Equatable, Sendable {
    var enabled: Bool

    enum CodingKeys: String, CodingKey {
        case enabled = "enabled"
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWireViewerAudioSetParams
struct SiloWireViewerAudioSetParams: Codable, Equatable, Sendable {
    var active: Bool
    var connectionId: String
    var muted: Bool
    var revision: UInt64

    enum CodingKeys: String, CodingKey {
        case active = "active"
        case connectionId = "connectionId"
        case muted = "muted"
        case revision = "revision"
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWireViewerConnectionParams
struct SiloWireViewerConnectionParams: Codable, Equatable, Sendable {
    var connectionId: String

    enum CodingKeys: String, CodingKey {
        case connectionId = "connectionId"
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWireViewerOpenResult
struct SiloWireViewerOpenResult: Codable, Equatable, Sendable {
    var connectionId: String
    var cookie: SiloWireViewerCookie
    var initScript: String
    var name: String
    var url: String

    enum CodingKeys: String, CodingKey {
        case connectionId = "connectionId"
        case cookie = "cookie"
        case initScript = "initScript"
        case name = "name"
        case url = "url"
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWireViewerCookie
struct SiloWireViewerCookie: Codable, Equatable, Sendable {
    var domain: String
    var httpOnly: Bool
    var name: String
    var path: String
    var value: String

    enum CodingKeys: String, CodingKey {
        case domain = "domain"
        case httpOnly = "httpOnly"
        case name = "name"
        case path = "path"
        case value = "value"
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWireViewerPageEvent
struct SiloWireViewerPageEvent: Codable, Equatable, Sendable {
    var connectionId: String
    var script: String

    enum CodingKeys: String, CodingKey {
        case connectionId = "connectionId"
        case script = "script"
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWireViewerSoundCheckResult
struct SiloWireViewerSoundCheckResult: Codable, Equatable, Sendable {
    var sound: Bool

    enum CodingKeys: String, CodingKey {
        case sound = "sound"
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

/// Root document that makes every public wire type reachable to schemars.
/// Its fields describe the contract catalogue, not one transport message.
// MARK: - SiloWireSiloAPI
struct SiloWireSiloAPI: Codable, Equatable, Sendable {
    var errors: SiloWireErrorContractSchema
    var events: SiloWireEventEnvelope
    var handshake: SiloWireHandshakeParams
    var handshakeResult: SiloWireHandshakeResult
    var jobTerminalResults: SiloWireJobTerminalResultsSchema
    var jobs: SiloWireJobContractSchema
    var methods: SiloWireMethodContractSchema
    var request: SiloWireRequestEnvelope
    var response: SiloWireResponseEnvelope

    enum CodingKeys: String, CodingKey {
        case errors = "errors"
        case events = "events"
        case handshake = "handshake"
        case handshakeResult = "handshake_result"
        case jobTerminalResults = "job_terminal_results"
        case jobs = "jobs"
        case methods = "methods"
        case request = "request"
        case response = "response"
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWireErrorContractSchema
struct SiloWireErrorContractSchema: Codable, Equatable, Sendable {
    var code: SiloWireErrorCode
    var error: SiloWireErrorObject

    enum CodingKeys: String, CodingKey {
        case code = "code"
        case error = "error"
    }
}

/// Stable snake_case wire error code. Existing values are sourced from
/// `app/SiloUI/src-tauri/engine/src/bridge_error.rs`; pending values are listed in 95 A-10.
enum SiloWireErrorCode: String, Codable, Equatable, Sendable {
    case accountNotMigrated = "account_not_migrated"
    case alreadyQueued = "already_queued"
    case busy = "busy"
    case cancelled = "cancelled"
    case changed = "changed"
    case desktopUpdateRequired = "desktop_update_required"
    case errorCodeInternal = "internal"
    case exists = "exists"
    case includeNotWritable = "include_not_writable"
    case incompatibleVersion = "incompatible_version"
    case needsPersonalizing = "needs_personalizing"
    case notAFile = "not_a_file"
    case notFound = "not_found"
    case notRunning = "not_running"
    case opensshMissing = "open_ssh_missing"
    case outputTooLarge = "output_too_large"
    case permissionDenied = "permission_denied"
    case runningLimit = "running_limit"
    case screenSharingUnavailable = "screen_sharing_unavailable"
    case setupIncomplete = "setup_incomplete"
    case stdinClosed = "stdin_closed"
    case timedOut = "timed_out"
    case unsupportedRemoteOperation = "unsupported_remote_operation"
    case updateInProgress = "update_in_progress"
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

/// A method error with optional structured version diagnostics for handshake refusal.
// MARK: - SiloWireErrorObject
struct SiloWireErrorObject: Codable, Equatable, Sendable {
    var code: SiloWireErrorCode
    var diagnostics: SiloWireIncompatibleVersionDiagnostics? = nil
    var message: String

    enum CodingKeys: String, CodingKey {
        case code = "code"
        case diagnostics = "diagnostics"
        case message = "message"
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

/// Engine and client versions reported when handshake protocol negotiation fails.
// MARK: - SiloWireIncompatibleVersionDiagnostics
struct SiloWireIncompatibleVersionDiagnostics: Codable, Equatable, Sendable {
    var clientAppVersion: String? = nil
    var clientProtocolRange: SiloWireProtocolRange
    var engineAppVersion: String
    var engineProtocolRange: SiloWireProtocolRange

    enum CodingKeys: String, CodingKey {
        case clientAppVersion = "clientAppVersion"
        case clientProtocolRange = "clientProtocolRange"
        case engineAppVersion = "engineAppVersion"
        case engineProtocolRange = "engineProtocolRange"
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

/// The inclusive protocol range a client supports.
// MARK: - SiloWireProtocolRange
struct SiloWireProtocolRange: Codable, Equatable, Sendable {
    var max: Int
    var min: Int

    enum CodingKeys: String, CodingKey {
        case max = "max"
        case min = "min"
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

/// Event payloads stay domain typed. The common envelope fields use the exact
/// `event`, `subscription`, `deviceId`, `seq`, and `payload` wire names.
// MARK: - SiloWireEventEnvelope
struct SiloWireEventEnvelope: Codable, Equatable, Sendable {
    var deviceId: String
    var event: SiloWireEvent
    var payload: SiloJSONValue? = nil
    var seq: UInt64
    var subscription: String

    enum CodingKeys: String, CodingKey {
        case deviceId = "deviceId"
        case event = "event"
        case payload = "payload"
        case seq = "seq"
        case subscription = "subscription"
    }
}

enum SiloWireEvent: String, Codable, Equatable, Sendable {
    case checkpointsChanged = "checkpoints.changed"
    case computersChanged = "computers.changed"
    case computersUnexpectedChange = "computers.unexpectedChange"
    case connectionsDevicesChanged = "connections.devices.changed"
    case displayViewerPage = "display.viewer.page"
    case editorIncludeNoticeChanged = "editor.includeNotice.changed"
    case engineShutdownChanged = "engine.shutdown.changed"
    case exportsChanged = "exports.changed"
    case githubChanged = "github.changed"
    case guestExecExited = "guest.exec.exited"
    case guestExecOutput = "guest.exec.output"
    case guestFilesChanged = "guest.files.changed"
    case migrationChanged = "migration.changed"
    case migrationPreUpgradeBackupChanged = "migration.preUpgradeBackup.changed"
    case networkChanged = "network.changed"
    case notificationsCleared = "notifications.cleared"
    case notificationsNotice = "notifications.notice"
    case operationsJobFinished = "operations.job.finished"
    case operationsJobProgress = "operations.job.progress"
    case operationsQueueChanged = "operations.queue.changed"
    case preparationChanged = "preparation.changed"
    case preparationChatgptChanged = "preparation.chatgpt.changed"
    case pushChanged = "push.changed"
    case secretsChanged = "secrets.changed"
    case settingsChanged = "settings.changed"
    case updatesChanged = "updates.changed"
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

/// `engine.handshake` parameters. `sshKey` is used by the Connections bridge
/// to install the restricted key; local engine clients omit it.
// MARK: - SiloWireHandshakeParams
struct SiloWireHandshakeParams: Codable, Equatable, Sendable {
    var client: SiloWireClientMetadata? = nil
    var handshakeParamsProtocol: SiloWireProtocolRange
    var sshKey: String? = nil

    enum CodingKeys: String, CodingKey {
        case client = "client"
        case handshakeParamsProtocol = "protocol"
        case sshKey = "sshKey"
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

/// Client information is diagnostic metadata, not an authorization identity.
// MARK: - SiloWireClientMetadata
struct SiloWireClientMetadata: Codable, Equatable, Sendable {
    var name: String
    var version: String

    enum CodingKeys: String, CodingKey {
        case name = "name"
        case version = "version"
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

/// Result of protocol negotiation. `clientId` is supplied on `engine.sock`
/// and omitted when the handshake runs through the remote control socket.
// MARK: - SiloWireHandshakeResult
struct SiloWireHandshakeResult: Codable, Equatable, Sendable {
    var capabilities: [String]
    var clientId: String? = nil
    var deviceId: String
    var name: String
    var handshakeResultProtocol: Int

    enum CodingKeys: String, CodingKey {
        case capabilities = "capabilities"
        case clientId = "clientId"
        case deviceId = "deviceId"
        case name = "name"
        case handshakeResultProtocol = "protocol"
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

/// Terminal job values remain untagged on the wire. This catalogue roots every
/// method-specific result schema and maps the defined job completion shapes.
// MARK: - SiloWireJobTerminalResultsSchema
struct SiloWireJobTerminalResultsSchema: Codable, Equatable, Sendable {
    var applicationSource: SiloWireApplicationSource
    var archiveInspection: SiloWireArchiveInspectionResult
    var backup: SiloWireBackupOperation
    var checkpointCreated: SiloWireCheckpointCreatedResult
    var desktop: SiloWireDesktopStatus
    var download: SiloWireDownloadOutcome
    var engineUpdatePrepare: SiloWireEngineUpdatePrepareFinishedResult
    var github: SiloWireGitHubState
    var guestExec: SiloWireGuestExecFinishedResult
    var macosComputers: SiloWireMacosComputersState
    var push: SiloWirePushOperation
    var storage: SiloWireStorageState
    var update: SiloWireUpdateSnapshot
    var upload: SiloWireUploadOutcome

    enum CodingKeys: String, CodingKey {
        case applicationSource = "application_source"
        case archiveInspection = "archive_inspection"
        case backup = "backup"
        case checkpointCreated = "checkpoint_created"
        case desktop = "desktop"
        case download = "download"
        case engineUpdatePrepare = "engine_update_prepare"
        case github = "github"
        case guestExec = "guest_exec"
        case macosComputers = "macos_computers"
        case push = "push"
        case storage = "storage"
        case update = "update"
        case upload = "upload"
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWireArchiveInspectionResult
struct SiloWireArchiveInspectionResult: Codable, Equatable, Sendable {
    var archive: SiloWireArchive
    var reason: String? = nil
    var valid: Bool

    enum CodingKeys: String, CodingKey {
        case archive = "archive"
        case reason = "reason"
        case valid = "valid"
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWireCheckpointCreatedResult
struct SiloWireCheckpointCreatedResult: Codable, Equatable, Sendable {
    var checkpoint: SiloWireCheckpoint

    enum CodingKeys: String, CodingKey {
        case checkpoint = "checkpoint"
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWireDesktopStatus
struct SiloWireDesktopStatus: Codable, Equatable, Sendable {
    var autoStart: Bool
    var backend: String? = nil
    var computerUse: SiloWireComputerUseState? = nil
    var display: String? = nil
    var installed: Bool
    var name: String? = nil
    var sessionState: String? = nil
    var state: String
    var streamerVersion: String? = nil
    var streamState: String? = nil
    var updateAvailable: Bool
    var updateRequired: Bool
    var user: String? = nil
    var version: String? = nil

    enum CodingKeys: String, CodingKey {
        case autoStart = "autoStart"
        case backend = "backend"
        case computerUse = "computerUse"
        case display = "display"
        case installed = "installed"
        case name = "name"
        case sessionState = "sessionState"
        case state = "state"
        case streamerVersion = "streamerVersion"
        case streamState = "streamState"
        case updateAvailable = "updateAvailable"
        case updateRequired = "updateRequired"
        case user = "user"
        case version = "version"
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

/// State projection described by 40 §4 and `computer_use::state_object` in
/// `app/SiloUI/src-tauri/engine/src/computer_use.rs`.
// MARK: - SiloWireComputerUseState
struct SiloWireComputerUseState: Codable, Equatable, Sendable {
    var agents: [String]? = nil
    var appliedApproval: SiloWireComputerUseApprovalState? = nil
    var approval: SiloWireComputerUseApprovalState? = nil
    var approvalApply: SiloWireComputerUseApprovalApplyState? = nil
    var approvalApplyReason: String? = nil
    var appVersion: String? = nil
    /// RFC 3339 receipt time on macOS; null until the receipt has been read.
    var at: String? = nil
    var cause: SiloWireComputerUseCause? = nil
    /// macOS receipt field; Linux projections use `appVersion` instead.
    var chatgptVersion: String? = nil
    var compatibility: SiloWireComputerUseCompatibility? = nil
    var lcuVersion: String? = nil
    var reason: String? = nil
    var runtimeVersion: String? = nil
    /// Nullable before the macOS guest receipt has been read.
    var schemaVersion: Int? = nil
    /// Nullable before the macOS guest receipt has been read.
    var state: SiloWireComputerUseInstallState? = nil
    var warning: String? = nil

    enum CodingKeys: String, CodingKey {
        case agents = "agents"
        case appliedApproval = "appliedApproval"
        case approval = "approval"
        case approvalApply = "approvalApply"
        case approvalApplyReason = "approvalApplyReason"
        case appVersion = "appVersion"
        case at = "at"
        case cause = "cause"
        case chatgptVersion = "chatgptVersion"
        case compatibility = "compatibility"
        case lcuVersion = "lcuVersion"
        case reason = "reason"
        case runtimeVersion = "runtimeVersion"
        case schemaVersion = "schemaVersion"
        case state = "state"
        case warning = "warning"
    }
}

enum SiloWireComputerUseApprovalState: String, Codable, Equatable, Sendable {
    case ask = "ask"
    case auto = "auto"
    case unknown = "unknown"
}

enum SiloWireComputerUseApprovalApplyState: String, Codable, Equatable, Sendable {
    case applied = "applied"
    case failed = "failed"
    case partial = "partial"
    case pending = "pending"
    case unknown = "unknown"
}

enum SiloWireComputerUseCause: String, Codable, Equatable, Sendable {
    case appDownload = "app-download"
}

enum SiloWireComputerUseCompatibility: String, Codable, Equatable, Sendable {
    case tested = "tested"
    case unknown = "unknown"
    case untested = "untested"
}

enum SiloWireComputerUseInstallState: String, Codable, Equatable, Sendable {
    case failed = "failed"
    case installing = "installing"
    case preparing = "preparing"
    case ready = "ready"
    case unavailable = "unavailable"
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWireDownloadOutcome
struct SiloWireDownloadOutcome: Codable, Equatable, Sendable {
    var path: String? = nil
    var status: SiloWireDownloadOutcomeStatus

    enum CodingKeys: String, CodingKey {
        case path = "path"
        case status = "status"
    }
}

enum SiloWireDownloadOutcomeStatus: String, Codable, Equatable, Sendable {
    case cancelled = "cancelled"
    case done = "done"
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWireEngineUpdatePrepareFinishedResult
struct SiloWireEngineUpdatePrepareFinishedResult: Codable, Equatable, Sendable {
    var resuming: [SiloWireResumingComputer]

    enum CodingKeys: String, CodingKey {
        case resuming = "resuming"
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWireResumingComputer
struct SiloWireResumingComputer: Codable, Equatable, Sendable {
    var id: String
    var name: String

    enum CodingKeys: String, CodingKey {
        case id = "id"
        case name = "name"
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

/// Public projection of `app/SiloUI/src-tauri/engine/src/github.rs::public_snapshot`
/// from 50 §2. Token values and other credential material are absent.
// MARK: - SiloWireGitHubState
struct SiloWireGitHubState: Codable, Equatable, Sendable {
    var accessEnabled: Bool
    var account: String? = nil
    var computerOperations: [SiloWireGitHubComputerOperation]
    var computers: [SiloWireGitHubPolicy]
    var deviceIdentity: SiloWireGitHubDeviceIdentity? = nil
    var pendingAuthorizationUrl: String? = nil
    var personalToken: SiloWireGitHubPersonalToken
    var policyRevision: UInt64
    var repositoryCatalog: [String]
    var repositoryCatalogStatus: SiloWireGitHubRepositoryCatalogStatus
    var state: SiloWireGitHubConnectionState

    enum CodingKeys: String, CodingKey {
        case accessEnabled = "accessEnabled"
        case account = "account"
        case computerOperations = "computerOperations"
        case computers = "computers"
        case deviceIdentity = "deviceIdentity"
        case pendingAuthorizationUrl = "pendingAuthorizationUrl"
        case personalToken = "personalToken"
        case policyRevision = "policyRevision"
        case repositoryCatalog = "repositoryCatalog"
        case repositoryCatalogStatus = "repositoryCatalogStatus"
        case state = "state"
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWireGitHubComputerOperation
struct SiloWireGitHubComputerOperation: Codable, Equatable, Sendable {
    var canRetry: Bool? = nil
    var computerId: String
    /// 50 §2 leaves the nested diagnostic details shape unspecified.
    var diagnosticDetails: SiloJSONValue? = nil
    var message: String
    var status: SiloWireGitHubComputerOperationStatus

    enum CodingKeys: String, CodingKey {
        case canRetry = "canRetry"
        case computerId = "computerId"
        case diagnosticDetails = "diagnosticDetails"
        case message = "message"
        case status = "status"
    }
}

enum SiloWireGitHubComputerOperationStatus: String, Codable, Equatable, Sendable {
    case applying = "applying"
    case failed = "failed"
    case succeeded = "succeeded"
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWireGitHubDeviceIdentity
struct SiloWireGitHubDeviceIdentity: Codable, Equatable, Sendable {
    var email: String
    var name: String

    enum CodingKeys: String, CodingKey {
        case email = "email"
        case name = "name"
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWireGitHubPersonalToken
struct SiloWireGitHubPersonalToken: Codable, Equatable, Sendable {
    var account: String? = nil
    var message: String? = nil
    var saved: Bool
    var state: SiloWireGitHubPersonalTokenState

    enum CodingKeys: String, CodingKey {
        case account = "account"
        case message = "message"
        case saved = "saved"
        case state = "state"
    }
}

enum SiloWireGitHubPersonalTokenState: String, Codable, Equatable, Sendable {
    case connected = "connected"
    case disconnected = "disconnected"
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWireGitHubRepositoryCatalogStatus
struct SiloWireGitHubRepositoryCatalogStatus: Codable, Equatable, Sendable {
    var status: SiloWireBackupAvailability
    var canRetry: Bool? = nil
    var message: String? = nil

    enum CodingKeys: String, CodingKey {
        case status = "status"
        case canRetry = "canRetry"
        case message = "message"
    }
}

enum SiloWireGitHubConnectionState: String, Codable, Equatable, Sendable {
    case connected = "connected"
    case connecting = "connecting"
    case disconnected = "disconnected"
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWireGuestExecFinishedResult
struct SiloWireGuestExecFinishedResult: Codable, Equatable, Sendable {
    var exitCode: Int32? = nil
    var signal: String? = nil

    enum CodingKeys: String, CodingKey {
        case exitCode = "exitCode"
        case signal = "signal"
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

/// Mirrors the push-operation value recorded by
/// `app/SiloUI/src-tauri/engine/src/host_push_operations.rs`.
// MARK: - SiloWirePushOperation
struct SiloWirePushOperation: Codable, Equatable, Sendable {
    var commitCount: UInt64
    var computer: String
    var message: String? = nil
    var operationId: String
    var repositoryPath: String
    var status: SiloWirePushOperationStatus
    var target: SiloWirePushTarget

    enum CodingKeys: String, CodingKey {
        case commitCount = "commitCount"
        case computer = "computer"
        case message = "message"
        case operationId = "operationId"
        case repositoryPath = "repositoryPath"
        case status = "status"
        case target = "target"
    }
}

enum SiloWirePushOperationStatus: String, Codable, Equatable, Sendable {
    case failed = "failed"
    case pushing = "pushing"
    case succeeded = "succeeded"
    case unknown = "unknown"
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWireStorageState
struct SiloWireStorageState: Codable, Equatable, Sendable {
    var checkpointCount: UInt64
    var checkpointHostBytes: UInt64? = nil
    var history: [SiloWireReclaimEntry]
    var lastError: String? = nil
    var lastReclaimedBytes: UInt64? = nil
    var lastTrimAt: UInt64? = nil
    var runtimeHostBytes: UInt64? = nil
    var workspaceCapacityBytes: UInt64? = nil
    var workspaceHostBytes: UInt64? = nil
    var workspaceUsedBytes: UInt64? = nil

    enum CodingKeys: String, CodingKey {
        case checkpointCount = "checkpointCount"
        case checkpointHostBytes = "checkpointHostBytes"
        case history = "history"
        case lastError = "lastError"
        case lastReclaimedBytes = "lastReclaimedBytes"
        case lastTrimAt = "lastTrimAt"
        case runtimeHostBytes = "runtimeHostBytes"
        case workspaceCapacityBytes = "workspaceCapacityBytes"
        case workspaceHostBytes = "workspaceHostBytes"
        case workspaceUsedBytes = "workspaceUsedBytes"
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWireReclaimEntry
struct SiloWireReclaimEntry: Codable, Equatable, Sendable {
    var at: UInt64
    var error: String? = nil
    var reclaimedBytes: UInt64? = nil
    var trigger: SiloWireReclaimTrigger

    enum CodingKeys: String, CodingKey {
        case at = "at"
        case error = "error"
        case reclaimedBytes = "reclaimedBytes"
        case trigger = "trigger"
    }
}

enum SiloWireReclaimTrigger: String, Codable, Equatable, Sendable {
    case afterStart = "afterStart"
    case beforeStop = "beforeStop"
    case manual = "manual"
    case scheduled = "scheduled"
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

/// Mirrors `app/SiloUI/src-tauri/engine/src/updates.rs::Snapshot` with camelCase
/// fields. `installStatus` is excluded by 60 §5.1 even though the current Rust
/// source still serializes its obsolete Debian helper value.
// MARK: - SiloWireUpdateSnapshot
struct SiloWireUpdateSnapshot: Codable, Equatable, Sendable {
    var automaticChecks: Bool
    var availableVersion: String? = nil
    var canInstall: Bool
    var currentVersion: String
    var downloadedBytes: UInt64
    var error: String? = nil
    var errorDetails: String? = nil
    var installBlockReason: String? = nil
    var lastChecked: String? = nil
    var packageKind: String
    var phase: String
    var releaseNotes: String? = nil
    var releaseUrl: String
    var retryAction: String? = nil
    var runningComputers: [String]
    var totalBytes: UInt64? = nil

    enum CodingKeys: String, CodingKey {
        case automaticChecks = "automaticChecks"
        case availableVersion = "availableVersion"
        case canInstall = "canInstall"
        case currentVersion = "currentVersion"
        case downloadedBytes = "downloadedBytes"
        case error = "error"
        case errorDetails = "errorDetails"
        case installBlockReason = "installBlockReason"
        case lastChecked = "lastChecked"
        case packageKind = "packageKind"
        case phase = "phase"
        case releaseNotes = "releaseNotes"
        case releaseUrl = "releaseUrl"
        case retryAction = "retryAction"
        case runningComputers = "runningComputers"
        case totalBytes = "totalBytes"
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWireUploadOutcome
struct SiloWireUploadOutcome: Codable, Equatable, Sendable {
    var names: [String]? = nil
    var status: SiloWireUploadOutcomeStatus

    enum CodingKeys: String, CodingKey {
        case names = "names"
        case status = "status"
    }
}

enum SiloWireUploadOutcomeStatus: String, Codable, Equatable, Sendable {
    case cancelled = "cancelled"
    case conflict = "conflict"
    case done = "done"
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWireJobContractSchema
struct SiloWireJobContractSchema: Codable, Equatable, Sendable {
    var acknowledge: SiloWireAcknowledgeJobParams
    var finished: SiloWireJobFinished
    var id: String
    var lookup: SiloWireJobLookupResult
    var progress: SiloWireJobProgress

    enum CodingKeys: String, CodingKey {
        case acknowledge = "acknowledge"
        case finished = "finished"
        case id = "id"
        case lookup = "lookup"
        case progress = "progress"
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWireAcknowledgeJobParams
struct SiloWireAcknowledgeJobParams: Codable, Equatable, Sendable {
    var deviceId: String? = nil
    var jobId: String

    enum CodingKeys: String, CodingKey {
        case deviceId = "deviceId"
        case jobId = "jobId"
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

/// One terminal job event. `result` remains the untagged final JSON value
/// returned by the method that started the job. The schema's
/// `x-silo-job-results` catalogue maps methods to their terminal result schemas.
// MARK: - SiloWireJobFinished
struct SiloWireJobFinished: Codable, Equatable, Sendable {
    var error: SiloWireErrorObject? = nil
    var jobId: String
    /// The complete outcome is retained and available through `operations.job.get` chunks.
    var outcomeChunked: Bool? = nil
    var result: SiloJSONValue? = nil

    enum CodingKeys: String, CodingKey {
        case error = "error"
        case jobId = "jobId"
        case outcomeChunked = "outcomeChunked"
        case result = "result"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        error = try container.decodeIfPresent(SiloWireErrorObject.self, forKey: .error)
        jobId = try container.decode(String.self, forKey: .jobId)
        outcomeChunked = try container.decodeIfPresent(Bool.self, forKey: .outcomeChunked)
        result = container.contains(.result) ? try container.decode(SiloJSONValue.self, forKey: .result) : nil
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWireJobLookupResult
struct SiloWireJobLookupResult: Codable, Equatable, Sendable {
    var jobId: String
    var outcome: SiloWireJobOutcome? = nil
    /// Present when the retained outcome is too large for one response. `data`
    /// is an exact UTF-8 slice of the persisted JobOutcome JSON.
    var outcomeChunk: SiloWireJobOutcomeChunk? = nil
    var state: SiloWireJobState

    enum CodingKeys: String, CodingKey {
        case jobId = "jobId"
        case outcome = "outcome"
        case outcomeChunk = "outcomeChunk"
        case state = "state"
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWireJobOutcome
struct SiloWireJobOutcome: Codable, Equatable, Sendable {
    var error: SiloWireErrorObject? = nil
    var result: SiloJSONValue? = nil

    enum CodingKeys: String, CodingKey {
        case error = "error"
        case result = "result"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        error = try container.decodeIfPresent(SiloWireErrorObject.self, forKey: .error)
        result = container.contains(.result) ? try container.decode(SiloJSONValue.self, forKey: .result) : nil
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWireJobOutcomeChunk
struct SiloWireJobOutcomeChunk: Codable, Equatable, Sendable {
    var data: String
    var nextOffsetBytes: UInt64? = nil
    var offsetBytes: UInt64
    var totalBytes: UInt64

    enum CodingKeys: String, CodingKey {
        case data = "data"
        case nextOffsetBytes = "nextOffsetBytes"
        case offsetBytes = "offsetBytes"
        case totalBytes = "totalBytes"
    }
}

enum SiloWireJobState: String, Codable, Equatable, Sendable {
    case finished = "finished"
    case running = "running"
    case waiting = "waiting"
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

/// The values emitted as the `data` field of `operations.job.progress`.
///
/// Payload member names mirror their source serde structs. The macOS contract
/// uses `computerId` as stated in 05 §4.2 E; the current MacosComputer row uses
/// `id`, a source/spec discrepancy recorded in the implementation report.
// MARK: - SiloWireJobProgress
struct SiloWireJobProgress: Codable, Equatable, Sendable {
    var computerId: String? = nil
    var data: SiloWireDataClass
    var jobId: String
    var kind: SiloWireOperationKind2? = nil
    var source: SiloWireSource

    enum CodingKeys: String, CodingKey {
        case computerId = "computerId"
        case data = "data"
        case jobId = "jobId"
        case kind = "kind"
        case source = "source"
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

/// Mirrors `app/SiloUI/src-tauri/engine/src/runtime.rs::ComputerConfigurationProgress`
/// (lines 3343 and 3462-3494), including its explicit `type` field.
///
/// Canonical lifecycle payload at `runtime.rs:3343`; the step values mirror
/// `app/SiloUI/src-tauri/engine/src/runtime.rs::LifecycleStep` (line 1275).
///
/// Mirrors `app/SiloUI/src-tauri/engine/src/transfer.rs::Progress`; the serialized
/// names deliberately retain `id` and `computer`, not the surrounding job's
/// `jobId` and `computerId`.
///
/// Mirrors the push-operation value recorded by
/// `app/SiloUI/src-tauri/engine/src/host_push_operations.rs`.
///
/// The macOS progress projection from 05 §4.2 E (`MacosComputer` row fields).
///
/// The `operations.job.progress` source projection mirrors the current Rust
/// `updates::Snapshot` at `app/SiloUI/src-tauri/engine/src/updates.rs:41-61` exactly.
/// Method and `updates.changed` results use `UpdateSnapshot`, which omits the
/// obsolete install helper field per 60 §5.1.
// MARK: - SiloWireDataClass
struct SiloWireDataClass: Codable, Equatable, Sendable {
    var computer: String? = nil
    var diagnostic: String? = nil
    var downloadedBytes: UInt64? = nil
    var elapsedSeconds: UInt64? = nil
    var exitCode: Int32? = nil
    var failureCode: String? = nil
    var fraction: Int? = nil
    var level: String? = nil
    var message: String? = nil
    var partial: Bool? = nil
    var phase: String? = nil
    var requestId: String? = nil
    var safeForDisplay: Bool? = nil
    var schemaVersion: Int? = nil
    var step: String? = nil
    var timestamp: UInt64? = nil
    var totalBytes: UInt64? = nil
    var type: String? = nil
    var action: String? = nil
    var computerId: String? = nil
    var bytesDone: UInt64? = nil
    var bytesTotal: UInt64? = nil
    var direction: SiloWireTransferDirection? = nil
    var fileCount: Int? = nil
    var fileIndex: Int? = nil
    var id: String? = nil
    var name: String? = nil
    var state: SiloWireDataState? = nil
    var archive: SiloWireArchive? = nil
    var canCancel: Bool? = nil
    var indeterminate: Bool? = nil
    var kind: SiloWireBackupOperationKindEnum? = nil
    var operation: SiloWireBackupOperationKind? = nil
    var phases: [SiloWireBackupPhase]? = nil
    var progress: SiloWireProgress? = nil
    var runningNames: [String]? = nil
    var targetName: String? = nil
    var detail: String? = nil
    var outcome: SiloWireBackupOutcome? = nil
    var title: String? = nil
    var commitCount: UInt64? = nil
    var operationId: String? = nil
    var repositoryPath: String? = nil
    var status: SiloWirePushOperationStatus? = nil
    var target: SiloWirePushTarget? = nil
    var checkpointOperation: SiloWireOperation? = nil
    var automaticChecks: Bool? = nil
    var availableVersion: String? = nil
    var canInstall: Bool? = nil
    var currentVersion: String? = nil
    var error: String? = nil
    var errorDetails: String? = nil
    var installBlockReason: String? = nil
    var installStatus: String? = nil
    var lastChecked: String? = nil
    var packageKind: String? = nil
    var releaseNotes: String? = nil
    var releaseUrl: String? = nil
    var retryAction: String? = nil
    var runningComputers: [String]? = nil

    enum CodingKeys: String, CodingKey {
        case computer = "computer"
        case diagnostic = "diagnostic"
        case downloadedBytes = "downloadedBytes"
        case elapsedSeconds = "elapsedSeconds"
        case exitCode = "exitCode"
        case failureCode = "failureCode"
        case fraction = "fraction"
        case level = "level"
        case message = "message"
        case partial = "partial"
        case phase = "phase"
        case requestId = "requestId"
        case safeForDisplay = "safeForDisplay"
        case schemaVersion = "schemaVersion"
        case step = "step"
        case timestamp = "timestamp"
        case totalBytes = "totalBytes"
        case type = "type"
        case action = "action"
        case computerId = "computerId"
        case bytesDone = "bytesDone"
        case bytesTotal = "bytesTotal"
        case direction = "direction"
        case fileCount = "fileCount"
        case fileIndex = "fileIndex"
        case id = "id"
        case name = "name"
        case state = "state"
        case archive = "archive"
        case canCancel = "canCancel"
        case indeterminate = "indeterminate"
        case kind = "kind"
        case operation = "operation"
        case phases = "phases"
        case progress = "progress"
        case runningNames = "runningNames"
        case targetName = "targetName"
        case detail = "detail"
        case outcome = "outcome"
        case title = "title"
        case commitCount = "commitCount"
        case operationId = "operationId"
        case repositoryPath = "repositoryPath"
        case status = "status"
        case target = "target"
        case checkpointOperation = "checkpointOperation"
        case automaticChecks = "automaticChecks"
        case availableVersion = "availableVersion"
        case canInstall = "canInstall"
        case currentVersion = "currentVersion"
        case error = "error"
        case errorDetails = "errorDetails"
        case installBlockReason = "installBlockReason"
        case installStatus = "installStatus"
        case lastChecked = "lastChecked"
        case packageKind = "packageKind"
        case releaseNotes = "releaseNotes"
        case releaseUrl = "releaseUrl"
        case retryAction = "retryAction"
        case runningComputers = "runningComputers"
    }
}

enum SiloWireProgress: Codable, Equatable, Sendable {
    case double(Double)
    case integer(Int)
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let x = try? container.decode(Int.self) {
            self = .integer(x)
            return
        }
        if let x = try? container.decode(Double.self) {
            self = .double(x)
            return
        }
        if container.decodeNil() {
            self = .null
            return
        }
        throw DecodingError.typeMismatch(SiloWireProgress.self, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Wrong type for SiloWireProgress"))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .double(let x):
            try container.encode(x)
        case .integer(let x):
            try container.encode(x)
        case .null:
            try container.encodeNil()
        }
    }
}

/// Mirrors `app/SiloUI/src-tauri/engine/src/macos_computers/store.rs::State`.
enum SiloWireDataState: String, Codable, Equatable, Sendable {
    case cancelled = "cancelled"
    case copying = "copying"
    case done = "done"
    case downloading = "downloading"
    case failed = "failed"
    case installing = "installing"
    case preparing = "preparing"
    case running = "running"
    case settingUp = "setting-up"
    case starting = "starting"
    case stopped = "stopped"
    case stopping = "stopping"
    case transferring = "transferring"
}

enum SiloWireSource: String, Codable, Equatable, Sendable {
    case backup = "backup"
    case lifecycle = "lifecycle"
    case macos = "macos"
    case push = "push"
    case setup = "setup"
    case transfer = "transfer"
    case update = "update"
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWireMethodContractSchema
struct SiloWireMethodContractSchema: Codable, Equatable, Sendable {
    var params: SiloWireMethodParams
    var results: SiloWireMethodResults

    enum CodingKeys: String, CodingKey {
        case params = "params"
        case results = "results"
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWireMethodParams
struct SiloWireMethodParams: Codable, Equatable, Sendable {
    var method: SiloWireMethodName
    var params: SiloWireParams

    enum CodingKeys: String, CodingKey {
        case method = "method"
        case params = "params"
    }
}

enum SiloWireMethodName: String, Codable, Equatable, Sendable {
    case activitySetupRead = "activity.setup.read"
    case checkpointsAbandonRestore = "checkpoints.abandonRestore"
    case checkpointsCreate = "checkpoints.create"
    case checkpointsDelete = "checkpoints.delete"
    case checkpointsFork = "checkpoints.fork"
    case checkpointsRestore = "checkpoints.restore"
    case checkpointsUsage = "checkpoints.usage"
    case clipboardRead = "clipboard.read"
    case clipboardTransfer = "clipboard.transfer"
    case clipboardWrite = "clipboard.write"
    case computerUseApproval = "computerUse.approval"
    case computerUseSetup = "computerUse.setup"
    case computerUseState = "computerUse.state"
    case computersConfigurationChange = "computers.configuration.change"
    case computersConfigurationRead = "computers.configuration.read"
    case computersConfigurationRetry = "computers.configuration.retry"
    case computersCreate = "computers.create"
    case computersCreationSkipComputerUseWait = "computers.creation.skipComputerUseWait"
    case computersDelete = "computers.delete"
    case computersDismissError = "computers.dismissError"
    case computersForceStop = "computers.forceStop"
    case computersIdentitiesConfigure = "computers.identities.configure"
    case computersIdentitiesVerify = "computers.identities.verify"
    case computersLaunch = "computers.launch"
    case computersList = "computers.list"
    case computersRestart = "computers.restart"
    case computersShell = "computers.shell"
    case computersStart = "computers.start"
    case computersStop = "computers.stop"
    case connectionsDevicesConnect = "connections.devices.connect"
    case connectionsDevicesHealth = "connections.devices.health"
    case connectionsDevicesList = "connections.devices.list"
    case connectionsDevicesRemove = "connections.devices.remove"
    case connectionsKeysRevoke = "connections.keys.revoke"
    case connectionsSetEnabled = "connections.setEnabled"
    case connectionsStatus = "connections.status"
    case connectionssshAuthorizationCommand = "connections.ssh.authorizationCommand"
    case connectionssshKeySetupCommand = "connections.ssh.keySetupCommand"
    case desktopAction = "desktop.action"
    case desktopConnect = "desktop.connect"
    case desktopStatus = "desktop.status"
    case deviceDependencies = "device.dependencies"
    case deviceFacts = "device.facts"
    case displayClose = "display.close"
    case displayNativeAttach = "display.native.attach"
    case displayShow = "display.show"
    case displayViewerAudioSet = "display.viewer.audio.set"
    case displayViewerClose = "display.viewer.close"
    case displayViewerOpen = "display.viewer.open"
    case displayViewerScreenReset = "display.viewer.screen.reset"
    case displayViewerSoundCancel = "display.viewer.sound.cancel"
    case displayViewerSoundCheck = "display.viewer.sound.check"
    case editorCommand = "editor.command"
    case editorIncludeNotice = "editor.includeNotice"
    case engineDisconnect = "engine.disconnect"
    case engineHandshake = "engine.handshake"
    case engineShutdown = "engine.shutdown"
    case engineState = "engine.state"
    case engineUpdateAbort = "engine.update.abort"
    case engineUpdatePrepare = "engine.update.prepare"
    case eventsSubscribe = "events.subscribe"
    case eventsUnsubscribe = "events.unsubscribe"
    case exportsAcknowledge = "exports.acknowledge"
    case exportsCreate = "exports.create"
    case exportsDestinationSet = "exports.destination.set"
    case exportsDismiss = "exports.dismiss"
    case exportsImport = "exports.import"
    case exportsInspect = "exports.inspect"
    case exportsState = "exports.state"
    case filesDownload = "files.download"
    case filesList = "files.list"
    case filesUpload = "files.upload"
    case githubAccessSet = "github.access.set"
    case githubConfigurationRetry = "github.configuration.retry"
    case githubConfigurationSave = "github.configuration.save"
    case githubConnect = "github.connect"
    case githubConnectCallback = "github.connect.callback"
    case githubConnectReopen = "github.connect.reopen"
    case githubDisconnect = "github.disconnect"
    case githubPersonalTokenRemove = "github.personalToken.remove"
    case githubPersonalTokenSave = "github.personalToken.save"
    case githubRepositoriesManage = "github.repositories.manage"
    case githubRepositoriesRefresh = "github.repositories.refresh"
    case githubState = "github.state"
    case guestAccount = "guest.account"
    case guestExec = "guest.exec"
    case guestExecGet = "guest.exec.get"
    case guestExecInput = "guest.exec.input"
    case guestExecStart = "guest.exec.start"
    case guestFilesList = "guest.files.list"
    case guestFilesRead = "guest.files.read"
    case guestFilesRemove = "guest.files.remove"
    case guestFilesWatch = "guest.files.watch"
    case guestFilesWrite = "guest.files.write"
    case guestPrepare = "guest.prepare"
    case guestssh = "guest.ssh"
    case guestsshAliasEnsure = "guest.sshAlias.ensure"
    case guestsshAliasRemove = "guest.sshAlias.remove"
    case logsExport = "logs.export"
    case logsQuery = "logs.query"
    case macosDisplayConnect = "macos.display.connect"
    case macosDisplayResize = "macos.display.resize"
    case macosDisplaySession = "macos.display.session"
    case macosDisplayStream = "macos.display.stream"
    case macosSetupRetry = "macos.setup.retry"
    case macosTemplateDelete = "macos.template.delete"
    case migrationPreUpgradeBackupAcknowledgeNotice = "migration.preUpgradeBackup.acknowledgeNotice"
    case migrationPreUpgradeBackupDelete = "migration.preUpgradeBackup.delete"
    case migrationPreUpgradeBackupGet = "migration.preUpgradeBackup.get"
    case migrationPreUpgradeBackupMeasure = "migration.preUpgradeBackup.measure"
    case migrationState = "migration.state"
    case networkOpen = "network.open"
    case networkPublish = "network.publish"
    case networkState = "network.state"
    case networkUnpublish = "network.unpublish"
    case notificationsList = "notifications.list"
    case operationsCancel = "operations.cancel"
    case operationsJobAcknowledge = "operations.job.acknowledge"
    case operationsJobGet = "operations.job.get"
    case operationsList = "operations.list"
    case preparationChatgptRetry = "preparation.chatgpt.retry"
    case preparationChatgptStatus = "preparation.chatgpt.status"
    case preparationRetry = "preparation.retry"
    case preparationStatus = "preparation.status"
    case pushDismiss = "push.dismiss"
    case pushRepositories = "push.repositories"
    case pushStart = "push.start"
    case pushStatus = "push.status"
    case secretsList = "secrets.list"
    case secretsRemove = "secrets.remove"
    case secretsRetry = "secrets.retry"
    case secretsSave = "secrets.save"
    case settingsFlush = "settings.flush"
    case settingsRead = "settings.read"
    case settingsUpdate = "settings.update"
    case sshAccessConnection = "sshAccess.connection"
    case sshAccessSave = "sshAccess.save"
    case sshAccessState = "sshAccess.state"
    case storageRead = "storage.read"
    case storageReclaim = "storage.reclaim"
    case terminalCommand = "terminal.command"
    case updatesCheck = "updates.check"
    case updatesDownload = "updates.download"
    case updatesFocused = "updates.focused"
    case updatesSetAutomaticChecks = "updates.setAutomaticChecks"
    case updatesState = "updates.state"
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

/// `engine.handshake` parameters. `sshKey` is used by the Connections bridge
/// to install the restricted key; local engine clients omit it.
// MARK: - SiloWireParams
struct SiloWireParams: Codable, Equatable, Sendable {
    var computerId: String? = nil
    var deviceId: String? = nil
    var kind: SiloWireParamsKind? = nil
    var name: String? = nil
    var checkpointId: String? = nil
    var newName: String? = nil
    var action: SiloWireAction? = nil
    var connectionId: String? = nil
    var content: SiloWireClipboardWritableContent? = nil
    var mode: SiloWireMode? = nil
    var change: SiloWireComputerConfigurationChange? = nil
    var requestId: String? = nil
    var retryComputerId: String? = nil
    var configuration: SiloWireConfigurationClass? = nil
    var request: SiloWireRequest? = nil
    var expected: SiloWireComputerConfiguration? = nil
    var identities: [SiloWireComputerIdentity]? = nil
    var refreshRepositories: Bool? = nil
    var error: String? = nil
    var address: String? = nil
    var replace: SiloWireCanCancel? = nil
    var publicKey: String? = nil
    var enabled: Bool? = nil
    var active: Bool? = nil
    var muted: Bool? = nil
    var revision: UInt64? = nil
    var path: String? = nil
    var client: SiloWireClientMetadata? = nil
    var paramsProtocol: SiloWireProtocolRange? = nil
    var sshKey: String? = nil
    var deadlineMs: UInt64? = nil
    var reason: SiloWireShutdownReason? = nil
    var stopComputers: Bool? = nil
    var deviceIds: [String]? = nil
    var events: [String]? = nil
    var subscription: String? = nil
    var expectedOperationId: String? = nil
    var computerIds: [String]? = nil
    var destination: String? = nil
    var expectedOperation: SiloWireBackupOperation? = nil
    var archivePath: String? = nil
    var sourceName: String? = nil
    var transferId: String? = nil
    var offset: UInt64? = nil
    var snapshotId: String? = nil
    var conflict: SiloWireConflictPolicy? = nil
    var directory: String? = nil
    var origin: SiloWireUploadOrigin? = nil
    var paths: [String]? = nil
    var selection: String? = nil
    var jobId: String? = nil
    var token: String? = nil
    var argv: [String]? = nil
    var paramsAs: SiloWireGuestExecUser? = nil
    var cwd: String? = nil
    var env: [SiloWireGuestEnvVar]? = nil
    var maxOutputBytes: UInt64? = nil
    var stdin: [Int]? = nil
    var timeoutMs: UInt64? = nil
    var sinceSeq: UInt64? = nil
    var close: Bool? = nil
    var data: [Int]? = nil
    var retainOutputBytes: UInt64? = nil
    var stdinOpen: Bool? = nil
    var length: UInt64? = nil
    var createParents: Bool? = nil
    var expectedSha256: String? = nil
    var accountProtocol: Int? = nil
    var forwarding: Bool? = nil
    var port: Int? = nil
    var purpose: SiloWireGuestSshPurpose? = nil
    var installInclude: Bool? = nil
    var requests: [SiloWireLogsQueryParams]? = nil
    var aroundId: String? = nil
    var cursor: String? = nil
    var follow: String? = nil
    var limit: Int? = nil
    var query: String? = nil
    var since: String? = nil
    var source: SiloWireLogSource? = nil
    var until: String? = nil
    var heightPx: UInt64? = nil
    var widthPx: UInt64? = nil
    var hostPort: Int? = nil
    var scheme: SiloWireNetworkScheme? = nil
    var offsetBytes: UInt64? = nil
    var repositoryPath: String? = nil
    var refresh: Bool? = nil
    var operationId: String? = nil
    var target: SiloWirePushTarget? = nil
    var id: String? = nil
    var patch: SiloWireSettingsValues? = nil
    var download: Bool? = nil
    var network: Bool? = nil
    var bindAddress: String? = nil
    var keys: [String]? = nil

    enum CodingKeys: String, CodingKey {
        case computerId = "computerId"
        case deviceId = "deviceId"
        case kind = "kind"
        case name = "name"
        case checkpointId = "checkpointId"
        case newName = "newName"
        case action = "action"
        case connectionId = "connectionId"
        case content = "content"
        case mode = "mode"
        case change = "change"
        case requestId = "requestId"
        case retryComputerId = "retryComputerId"
        case configuration = "configuration"
        case request = "request"
        case expected = "expected"
        case identities = "identities"
        case refreshRepositories = "refreshRepositories"
        case error = "error"
        case address = "address"
        case replace = "replace"
        case publicKey = "publicKey"
        case enabled = "enabled"
        case active = "active"
        case muted = "muted"
        case revision = "revision"
        case path = "path"
        case client = "client"
        case paramsProtocol = "protocol"
        case sshKey = "sshKey"
        case deadlineMs = "deadlineMs"
        case reason = "reason"
        case stopComputers = "stopComputers"
        case deviceIds = "deviceIds"
        case events = "events"
        case subscription = "subscription"
        case expectedOperationId = "expectedOperationId"
        case computerIds = "computerIds"
        case destination = "destination"
        case expectedOperation = "expectedOperation"
        case archivePath = "archivePath"
        case sourceName = "sourceName"
        case transferId = "transferId"
        case offset = "offset"
        case snapshotId = "snapshotId"
        case conflict = "conflict"
        case directory = "directory"
        case origin = "origin"
        case paths = "paths"
        case selection = "selection"
        case jobId = "jobId"
        case token = "token"
        case argv = "argv"
        case paramsAs = "as"
        case cwd = "cwd"
        case env = "env"
        case maxOutputBytes = "maxOutputBytes"
        case stdin = "stdin"
        case timeoutMs = "timeoutMs"
        case sinceSeq = "sinceSeq"
        case close = "close"
        case data = "data"
        case retainOutputBytes = "retainOutputBytes"
        case stdinOpen = "stdinOpen"
        case length = "length"
        case createParents = "createParents"
        case expectedSha256 = "expectedSha256"
        case accountProtocol = "accountProtocol"
        case forwarding = "forwarding"
        case port = "port"
        case purpose = "purpose"
        case installInclude = "installInclude"
        case requests = "requests"
        case aroundId = "aroundId"
        case cursor = "cursor"
        case follow = "follow"
        case limit = "limit"
        case query = "query"
        case since = "since"
        case source = "source"
        case until = "until"
        case heightPx = "heightPx"
        case widthPx = "widthPx"
        case hostPort = "hostPort"
        case scheme = "scheme"
        case offsetBytes = "offsetBytes"
        case repositoryPath = "repositoryPath"
        case refresh = "refresh"
        case operationId = "operationId"
        case target = "target"
        case id = "id"
        case patch = "patch"
        case download = "download"
        case network = "network"
        case bindAddress = "bindAddress"
        case keys = "keys"
    }
}

enum SiloWireAction: String, Codable, Equatable, Sendable {
    case copy = "copy"
    case paste = "paste"
    case restart = "restart"
    case restartStreamer = "restart-streamer"
    case start = "start"
    case stop = "stop"
    case updateStreamer = "update-streamer"
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

/// Mirrors `app/SiloUI/src-tauri/engine/src/runtime.rs::ComputerConfiguration`
/// (lines 304-319), including rejection of unknown fields.
// MARK: - SiloWireConfigurationClass
struct SiloWireConfigurationClass: Codable, Equatable, Sendable {
    var cpus: Int? = nil
    var desktop: SiloWireDesktopConfiguration? = nil
    var id: String? = nil
    var maxCPUs: Int? = nil
    var maxMemoryGiB: Int? = nil
    var memoryGiB: Int? = nil
    var name: String? = nil
    var runtimeStorageGiB: Int? = nil
    var workspaceStorageGiB: Int? = nil
    var baseRevision: UInt64? = nil
    var computers: [SiloWireGitHubPolicy]? = nil

    enum CodingKeys: String, CodingKey {
        case cpus = "cpus"
        case desktop = "desktop"
        case id = "id"
        case maxCPUs = "maxCPUs"
        case maxMemoryGiB = "maxMemoryGiB"
        case memoryGiB = "memoryGiB"
        case name = "name"
        case runtimeStorageGiB = "runtimeStorageGiB"
        case workspaceStorageGiB = "workspaceStorageGiB"
        case baseRevision = "baseRevision"
        case computers = "computers"
    }
}

enum SiloWireParamsKind: String, Codable, Equatable, Sendable {
    case automatic = "automatic"
    case linux = "linux"
    case macos = "macos"
    case manual = "manual"
}

enum SiloWireMode: Codable, Equatable, Sendable {
    case enumeration(SiloWireApprovalMode)
    case integer(Int)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let x = try? container.decode(Int.self) {
            self = .integer(x)
            return
        }
        if let x = try? container.decode(SiloWireApprovalMode.self) {
            self = .enumeration(x)
            return
        }
        throw DecodingError.typeMismatch(SiloWireMode.self, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Wrong type for SiloWireMode"))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .enumeration(let x):
            try container.encode(x)
        case .integer(let x):
            try container.encode(x)
        }
    }
}

enum SiloWireCanCancel: Codable, Equatable, Sendable {
    case bool(Bool)
    case enumeration(SiloWireGuestFileReplace)
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let x = try? container.decode(Bool.self) {
            self = .bool(x)
            return
        }
        if let x = try? container.decode(SiloWireGuestFileReplace.self) {
            self = .enumeration(x)
            return
        }
        if container.decodeNil() {
            self = .null
            return
        }
        throw DecodingError.typeMismatch(SiloWireCanCancel.self, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Wrong type for SiloWireCanCancel"))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .bool(let x):
            try container.encode(x)
        case .enumeration(let x):
            try container.encode(x)
        case .null:
            try container.encodeNil()
        }
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWireRequest
struct SiloWireRequest: Codable, Equatable, Sendable {
    var cpus: UInt64? = nil
    var diskGiB: UInt64? = nil
    var memoryGiB: UInt64? = nil
    var name: String
    var allowAnyDestination: Bool? = nil
    var allowedDomains: [String]? = nil
    var computerIds: [String]? = nil
    var id: String? = nil
    var operation: SiloWireSecretSaveAction? = nil
    var value: String? = nil

    enum CodingKeys: String, CodingKey {
        case cpus = "cpus"
        case diskGiB = "diskGiB"
        case memoryGiB = "memoryGiB"
        case name = "name"
        case allowAnyDestination = "allowAnyDestination"
        case allowedDomains = "allowedDomains"
        case computerIds = "computerIds"
        case id = "id"
        case operation = "operation"
        case value = "value"
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWireMethodResults
struct SiloWireMethodResults: Codable, Equatable, Sendable {
    var method: SiloWireMethodName
    var result: SiloWireResultUnion

    enum CodingKeys: String, CodingKey {
        case method = "method"
        case result = "result"
    }
}

enum SiloWireResultUnion: Codable, Equatable, Sendable {
    case bool(Bool)
    case integer(UInt64)
    case siloWireJobStartResultClass(SiloWireJobStartResultClass)
    case siloWireResultElementArray([SiloWireResultElement])
    case string(String)
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let x = try? container.decode(Bool.self) {
            self = .bool(x)
            return
        }
        if let x = try? container.decode(UInt64.self) {
            self = .integer(x)
            return
        }
        if let x = try? container.decode([SiloWireResultElement].self) {
            self = .siloWireResultElementArray(x)
            return
        }
        if let x = try? container.decode(String.self) {
            self = .string(x)
            return
        }
        if let x = try? container.decode(SiloWireJobStartResultClass.self) {
            self = .siloWireJobStartResultClass(x)
            return
        }
        if container.decodeNil() {
            self = .null
            return
        }
        throw DecodingError.typeMismatch(SiloWireResultUnion.self, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Wrong type for SiloWireResultUnion"))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .bool(let x):
            try container.encode(x)
        case .integer(let x):
            try container.encode(x)
        case .siloWireJobStartResultClass(let x):
            try container.encode(x)
        case .siloWireResultElementArray(let x):
            try container.encode(x)
        case .string(let x):
            try container.encode(x)
        case .null:
            try container.encodeNil()
        }
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

/// Mirrors `app/SiloUI/src-tauri/engine/src/runtime.rs::ComputerConfigurationProgress`
/// (lines 3343 and 3462-3494), including its explicit `type` field.
///
/// Mirrors `app/SiloUI/src-tauri/engine/src/remote.rs::Device`.
// MARK: - SiloWireResultElement
struct SiloWireResultElement: Codable, Equatable, Sendable {
    var computer: SiloWireResultComputer? = nil
    var diagnostic: String? = nil
    var downloadedBytes: UInt64? = nil
    var elapsedSeconds: UInt64? = nil
    var exitCode: Int32? = nil
    var failureCode: String? = nil
    var fraction: Int? = nil
    var level: String? = nil
    var message: String? = nil
    var partial: Bool? = nil
    var phase: String? = nil
    var requestId: String? = nil
    var safeForDisplay: Bool? = nil
    var schemaVersion: Int? = nil
    var step: String? = nil
    var timestamp: UInt64? = nil
    var totalBytes: UInt64? = nil
    var type: String? = nil
    var address: String? = nil
    var id: String? = nil
    var name: String? = nil
    var body: String? = nil
    var category: SiloWireNoticeCategory? = nil
    var key: String? = nil
    var title: String? = nil
    var ahead: UInt64? = nil
    var behind: UInt64? = nil
    var branch: String? = nil
    var dirty: Bool? = nil
    var head: String? = nil
    var path: String? = nil
    var repository: String? = nil
    var allowedDomains: [String]? = nil
    var computerIds: [String]? = nil
    var error: String? = nil
    var pendingComputerIds: [String]? = nil
    var removing: Bool? = nil
    var state: SiloWireSecretState? = nil

    enum CodingKeys: String, CodingKey {
        case computer = "computer"
        case diagnostic = "diagnostic"
        case downloadedBytes = "downloadedBytes"
        case elapsedSeconds = "elapsedSeconds"
        case exitCode = "exitCode"
        case failureCode = "failureCode"
        case fraction = "fraction"
        case level = "level"
        case message = "message"
        case partial = "partial"
        case phase = "phase"
        case requestId = "requestId"
        case safeForDisplay = "safeForDisplay"
        case schemaVersion = "schemaVersion"
        case step = "step"
        case timestamp = "timestamp"
        case totalBytes = "totalBytes"
        case type = "type"
        case address = "address"
        case id = "id"
        case name = "name"
        case body = "body"
        case category = "category"
        case key = "key"
        case title = "title"
        case ahead = "ahead"
        case behind = "behind"
        case branch = "branch"
        case dirty = "dirty"
        case head = "head"
        case path = "path"
        case repository = "repository"
        case allowedDomains = "allowedDomains"
        case computerIds = "computerIds"
        case error = "error"
        case pendingComputerIds = "pendingComputerIds"
        case removing = "removing"
        case state = "state"
    }
}

enum SiloWireResultComputer: Codable, Equatable, Sendable {
    case siloWireNoticeComputer(SiloWireNoticeComputer)
    case string(String)
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let x = try? container.decode(String.self) {
            self = .string(x)
            return
        }
        if let x = try? container.decode(SiloWireNoticeComputer.self) {
            self = .siloWireNoticeComputer(x)
            return
        }
        if container.decodeNil() {
            self = .null
            return
        }
        throw DecodingError.typeMismatch(SiloWireResultComputer.self, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Wrong type for SiloWireResultComputer"))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .siloWireNoticeComputer(let x):
            try container.encode(x)
        case .string(let x):
            try container.encode(x)
        case .null:
            try container.encodeNil()
        }
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

/// State projection described by 40 §4 and `computer_use::state_object` in
/// `app/SiloUI/src-tauri/engine/src/computer_use.rs`.
///
/// Mirrors `app/SiloUI/src-tauri/engine/src/runtime.rs::ComputerConfigurationRequest`
/// (lines 297-302).
///
/// Mirrors `app/SiloUI/src-tauri/engine/src/runtime.rs::ApplicationSource` (lines
/// 548-565), retaining its field types and camelCase serialization.
///
/// Mirrors `app/SiloUI/src-tauri/engine/src/remote.rs::Device`.
///
/// Mirrors `app/SiloUI/src-tauri/engine/src/remote.rs::ConnectionsStatus`.
///
/// Result of protocol negotiation. `clientId` is supplied on `engine.sock`
/// and omitted when the handshake runs through the remote control socket.
///
/// Mirrors `app/SiloUI/src-tauri/engine/src/backup_controller.rs::BackupState`, with
/// the API's remembered destination field added for a client-owned folder picker.
///
/// Public projection of `app/SiloUI/src-tauri/engine/src/github.rs::public_snapshot`
/// from 50 §2. Token values and other credential material are absent.
///
/// Mirrors `app/SiloUI/src-tauri/engine/src/runtime/operation_gate.rs::OperationQueue`
/// and adds the retained completed-job discovery list required by 95 §3.
///
/// Mirrors `app/SiloUI/src-tauri/engine/src/preparation.rs::PreparationStatus`.
///
/// Mirrors the push-operation value recorded by
/// `app/SiloUI/src-tauri/engine/src/host_push_operations.rs`.
///
/// Mirrors `app/SiloUI/src-tauri/engine/src/settings.rs::Snapshot`, with the
/// engine-owned API draft fixed to JSON null as 60 §2.1 and 95 A-5 require.
///
/// Mirrors `app/SiloUI/src-tauri/engine/src/updates.rs::Snapshot` with camelCase
/// fields. `installStatus` is excluded by 60 §5.1 even though the current Rust
/// source still serializes its obsolete Debian helper value.
// MARK: - SiloWireJobStartResultClass
struct SiloWireJobStartResultClass: Codable, Equatable, Sendable {
    var jobId: String? = nil
    var checkpoints: [SiloWireCheckpointUsageEntry]? = nil
    var totalBytes: UInt64? = nil
    var kind: SiloWireClipboardContentKind? = nil
    var text: String? = nil
    var bytes: [Int]? = nil
    var mime: String? = nil
    var action: SiloWireClipboardAction? = nil
    var content: SiloWireClipboardTransferContent? = nil
    var message: String? = nil
    var status: String? = nil
    var agents: [String]? = nil
    var appliedApproval: SiloWireComputerUseApprovalState? = nil
    var approval: SiloWireComputerUseApprovalState? = nil
    var approvalApply: SiloWireComputerUseApprovalApplyState? = nil
    var approvalApplyReason: String? = nil
    var appVersion: String? = nil
    /// RFC 3339 receipt time on macOS; null until the receipt has been read.
    var at: String? = nil
    var cause: SiloWireComputerUseCause? = nil
    /// macOS receipt field; Linux projections use `appVersion` instead.
    var chatgptVersion: String? = nil
    var compatibility: SiloWireComputerUseCompatibility? = nil
    var lcuVersion: String? = nil
    var reason: String? = nil
    var runtimeVersion: String? = nil
    /// Nullable before the macOS guest receipt has been read.
    var schemaVersion: Int? = nil
    /// Nullable before the macOS guest receipt has been read.
    var state: String? = nil
    var warning: String? = nil
    var computers: [SiloWireComputerElement]? = nil
    var computer: SiloWireJobStartResultComputer? = nil
    var activities: [SiloJSONValue]? = nil
    var computerConfigurationOperation: SiloJSONValue? = nil
    var deviceCapacity: SiloWireDeviceCapacity? = nil
    var github: SiloJSONValue? = nil
    var repositoryPushOperations: [SiloJSONValue]? = nil
    var runtimeRepair: SiloJSONValue? = nil
    var secrets: [SiloJSONValue]? = nil
    var computerIds: [String]? = nil
    var enabled: Bool? = nil
    var lastPass: SiloWireLaunchPass? = nil
    var linux: SiloWireApplicationSource? = nil
    var macos: SiloWireMacosComputersState? = nil
    var address: String? = nil
    var id: String? = nil
    var name: String? = nil
    var devices: [SiloWireDeviceHealth]? = nil
    var addresses: [SiloWireDeviceAddress]? = nil
    var deviceId: String? = nil
    var error: String? = nil
    var command: String? = nil
    var password: String? = nil
    var port: Int? = nil
    var username: String? = nil
    var autoStart: Bool? = nil
    var backend: String? = nil
    var computerUse: SiloWireComputerUseState? = nil
    var display: String? = nil
    var installed: Bool? = nil
    var sessionState: String? = nil
    var streamerVersion: String? = nil
    var streamState: String? = nil
    var updateAvailable: Bool? = nil
    var updateRequired: Bool? = nil
    var user: String? = nil
    var version: SiloWireDeviceid? = nil
    var checkedAtMs: UInt64? = nil
    var checks: [SiloWireDependencyCheck]? = nil
    var requestId: String? = nil
    var macosHostLimits: SiloWireMacosHostLimits? = nil
    var remoteLogin: SiloWireRemoteLoginStatus? = nil
    var sandbox: String? = nil
    var t: SiloWireT? = nil
    var format: String? = nil
    var height: Int? = nil
    var path: String? = nil
    var scanout: Int? = nil
    var slots: Int? = nil
    var width: Int? = nil
    var rect: [Int]? = nil
    var seq: UInt64? = nil
    var slot: Int? = nil
    var code: Int? = nil
    var down: Bool? = nil
    var x: SiloDisplayAxis? = nil
    var y: SiloDisplayAxis? = nil
    var value: Int32? = nil
    var connectionId: String? = nil
    var cookie: SiloWireViewerCookie? = nil
    var initScript: String? = nil
    var url: String? = nil
    var sound: Bool? = nil
    var argv: [String]? = nil
    var capabilities: [String]? = nil
    var clientId: String? = nil
    var jobStartResultProtocol: Int? = nil
    var generation: UInt64? = nil
    var phase: String? = nil
    var sessionEnding: Bool? = nil
    var shuttingDown: Bool? = nil
    var updatePending: Bool? = nil
    var subscription: String? = nil
    var destination: String? = nil
    var archives: [SiloWireArchive]? = nil
    var availability: SiloWireBackupAvailability? = nil
    var availabilityMessage: String? = nil
    var operation: SiloWireOperationClass? = nil
    var operationId: String? = nil
    var resultUnseen: Bool? = nil
    var snapshotId: String? = nil
    var entries: [SiloWireEntry]? = nil
    var nextOffset: UInt64? = nil
    var accessEnabled: Bool? = nil
    var account: String? = nil
    var computerOperations: [SiloWireGitHubComputerOperation]? = nil
    var deviceIdentity: SiloWireGitHubDeviceIdentity? = nil
    var pendingAuthorizationUrl: String? = nil
    var personalToken: SiloWireGitHubPersonalToken? = nil
    var policyRevision: UInt64? = nil
    var repositoryCatalog: [String]? = nil
    var repositoryCatalogStatus: SiloWireGitHubRepositoryCatalogStatus? = nil
    var home: String? = nil
    var uid: Int? = nil
    var exitCode: Int32? = nil
    var signal: String? = nil
    var stderr: [Int]? = nil
    var stdout: [Int]? = nil
    var firstRetainedSeq: UInt64? = nil
    var output: [SiloWireGuestExecOutput]? = nil
    var data: [Int]? = nil
    var inode: UInt64? = nil
    var mode: Int? = nil
    var mtimeMs: UInt64? = nil
    var size: UInt64? = nil
    var removed: [String]? = nil
    var subscriptionId: String? = nil
    var guestAddress: String? = nil
    var hostPublicKey: String? = nil
    var alias: String? = nil
    var configPath: String? = nil
    var includeInstalled: Bool? = nil
    var includeLine: String? = nil
    var newestAvailableTimestamp: String? = nil
    var nextCursor: String? = nil
    var oldestAvailableTimestamp: String? = nil
    var snapshot: String? = nil
    var timestampEstimated: Bool? = nil
    var totalMatches: UInt64? = nil
    var unreadableRecords: Bool? = nil
    var unsupported: Bool? = nil
    var heightPx: Int? = nil
    var widthPx: Int? = nil
    var deleteAt: String? = nil
    var noticePending: Bool? = nil
    var canContinue: Bool? = nil
    var failedCount: UInt64? = nil
    var logPath: String? = nil
    var logs: [String]? = nil
    var migratedCount: UInt64? = nil
    var stage: String? = nil
    var totalCount: UInt64? = nil
    var outcome: SiloWireJobOutcome? = nil
    /// Present when the retained outcome is too large for one response. `data`
    /// is an exact UTF-8 slice of the persisted JobOutcome JSON.
    var outcomeChunk: SiloWireJobOutcomeChunk? = nil
    var running: [SiloWireOperationEntry]? = nil
    var unacknowledgedJobIds: [String]? = nil
    var waiting: [SiloWireOperationEntry]? = nil
    var receivedBytes: UInt64? = nil
    var retryable: Bool? = nil
    var image: SiloWirePreparationTask? = nil
    var lcu: SiloWirePreparationTask? = nil
    var commitCount: UInt64? = nil
    var repositoryPath: String? = nil
    var target: SiloWirePushTarget? = nil
    var onboardingDraft: SiloJSONValue? = nil
    var revision: UInt64? = nil
    var saveError: String? = nil
    var settings: SiloWireSettingsValues? = nil
    var writeProtected: Bool? = nil
    var checkpointCount: UInt64? = nil
    var checkpointHostBytes: UInt64? = nil
    var history: [SiloWireReclaimEntry]? = nil
    var lastError: String? = nil
    var lastReclaimedBytes: UInt64? = nil
    var lastTrimAt: UInt64? = nil
    var runtimeHostBytes: UInt64? = nil
    var workspaceCapacityBytes: UInt64? = nil
    var workspaceHostBytes: UInt64? = nil
    var workspaceUsedBytes: UInt64? = nil
    var automaticChecks: Bool? = nil
    var availableVersion: String? = nil
    var canInstall: Bool? = nil
    var currentVersion: String? = nil
    var downloadedBytes: UInt64? = nil
    var errorDetails: String? = nil
    var installBlockReason: String? = nil
    var lastChecked: String? = nil
    var packageKind: String? = nil
    var releaseNotes: String? = nil
    var releaseUrl: String? = nil
    var retryAction: String? = nil
    var runningComputers: [String]? = nil

    enum CodingKeys: String, CodingKey {
        case jobId = "jobId"
        case checkpoints = "checkpoints"
        case totalBytes = "totalBytes"
        case kind = "kind"
        case text = "text"
        case bytes = "bytes"
        case mime = "mime"
        case action = "action"
        case content = "content"
        case message = "message"
        case status = "status"
        case agents = "agents"
        case appliedApproval = "appliedApproval"
        case approval = "approval"
        case approvalApply = "approvalApply"
        case approvalApplyReason = "approvalApplyReason"
        case appVersion = "appVersion"
        case at = "at"
        case cause = "cause"
        case chatgptVersion = "chatgptVersion"
        case compatibility = "compatibility"
        case lcuVersion = "lcuVersion"
        case reason = "reason"
        case runtimeVersion = "runtimeVersion"
        case schemaVersion = "schemaVersion"
        case state = "state"
        case warning = "warning"
        case computers = "computers"
        case computer = "computer"
        case activities = "activities"
        case computerConfigurationOperation = "computerConfigurationOperation"
        case deviceCapacity = "deviceCapacity"
        case github = "github"
        case repositoryPushOperations = "repositoryPushOperations"
        case runtimeRepair = "runtimeRepair"
        case secrets = "secrets"
        case computerIds = "computerIds"
        case enabled = "enabled"
        case lastPass = "lastPass"
        case linux = "linux"
        case macos = "macos"
        case address = "address"
        case id = "id"
        case name = "name"
        case devices = "devices"
        case addresses = "addresses"
        case deviceId = "deviceId"
        case error = "error"
        case command = "command"
        case password = "password"
        case port = "port"
        case username = "username"
        case autoStart = "autoStart"
        case backend = "backend"
        case computerUse = "computerUse"
        case display = "display"
        case installed = "installed"
        case sessionState = "sessionState"
        case streamerVersion = "streamerVersion"
        case streamState = "streamState"
        case updateAvailable = "updateAvailable"
        case updateRequired = "updateRequired"
        case user = "user"
        case version = "version"
        case checkedAtMs = "checkedAtMs"
        case checks = "checks"
        case requestId = "requestId"
        case macosHostLimits = "macosHostLimits"
        case remoteLogin = "remoteLogin"
        case sandbox = "sandbox"
        case t = "t"
        case format = "format"
        case height = "height"
        case path = "path"
        case scanout = "scanout"
        case slots = "slots"
        case width = "width"
        case rect = "rect"
        case seq = "seq"
        case slot = "slot"
        case code = "code"
        case down = "down"
        case x = "x"
        case y = "y"
        case value = "value"
        case connectionId = "connectionId"
        case cookie = "cookie"
        case initScript = "initScript"
        case url = "url"
        case sound = "sound"
        case argv = "argv"
        case capabilities = "capabilities"
        case clientId = "clientId"
        case jobStartResultProtocol = "protocol"
        case generation = "generation"
        case phase = "phase"
        case sessionEnding = "sessionEnding"
        case shuttingDown = "shuttingDown"
        case updatePending = "updatePending"
        case subscription = "subscription"
        case destination = "destination"
        case archives = "archives"
        case availability = "availability"
        case availabilityMessage = "availabilityMessage"
        case operation = "operation"
        case operationId = "operationId"
        case resultUnseen = "resultUnseen"
        case snapshotId = "snapshotId"
        case entries = "entries"
        case nextOffset = "nextOffset"
        case accessEnabled = "accessEnabled"
        case account = "account"
        case computerOperations = "computerOperations"
        case deviceIdentity = "deviceIdentity"
        case pendingAuthorizationUrl = "pendingAuthorizationUrl"
        case personalToken = "personalToken"
        case policyRevision = "policyRevision"
        case repositoryCatalog = "repositoryCatalog"
        case repositoryCatalogStatus = "repositoryCatalogStatus"
        case home = "home"
        case uid = "uid"
        case exitCode = "exitCode"
        case signal = "signal"
        case stderr = "stderr"
        case stdout = "stdout"
        case firstRetainedSeq = "firstRetainedSeq"
        case output = "output"
        case data = "data"
        case inode = "inode"
        case mode = "mode"
        case mtimeMs = "mtimeMs"
        case size = "size"
        case removed = "removed"
        case subscriptionId = "subscriptionId"
        case guestAddress = "guestAddress"
        case hostPublicKey = "hostPublicKey"
        case alias = "alias"
        case configPath = "configPath"
        case includeInstalled = "includeInstalled"
        case includeLine = "includeLine"
        case newestAvailableTimestamp = "newestAvailableTimestamp"
        case nextCursor = "nextCursor"
        case oldestAvailableTimestamp = "oldestAvailableTimestamp"
        case snapshot = "snapshot"
        case timestampEstimated = "timestampEstimated"
        case totalMatches = "totalMatches"
        case unreadableRecords = "unreadableRecords"
        case unsupported = "unsupported"
        case heightPx = "heightPx"
        case widthPx = "widthPx"
        case deleteAt = "deleteAt"
        case noticePending = "noticePending"
        case canContinue = "canContinue"
        case failedCount = "failedCount"
        case logPath = "logPath"
        case logs = "logs"
        case migratedCount = "migratedCount"
        case stage = "stage"
        case totalCount = "totalCount"
        case outcome = "outcome"
        case outcomeChunk = "outcomeChunk"
        case running = "running"
        case unacknowledgedJobIds = "unacknowledgedJobIds"
        case waiting = "waiting"
        case receivedBytes = "receivedBytes"
        case retryable = "retryable"
        case image = "image"
        case lcu = "lcu"
        case commitCount = "commitCount"
        case repositoryPath = "repositoryPath"
        case target = "target"
        case onboardingDraft = "onboardingDraft"
        case revision = "revision"
        case saveError = "saveError"
        case settings = "settings"
        case writeProtected = "writeProtected"
        case checkpointCount = "checkpointCount"
        case checkpointHostBytes = "checkpointHostBytes"
        case history = "history"
        case lastError = "lastError"
        case lastReclaimedBytes = "lastReclaimedBytes"
        case lastTrimAt = "lastTrimAt"
        case runtimeHostBytes = "runtimeHostBytes"
        case workspaceCapacityBytes = "workspaceCapacityBytes"
        case workspaceHostBytes = "workspaceHostBytes"
        case workspaceUsedBytes = "workspaceUsedBytes"
        case automaticChecks = "automaticChecks"
        case availableVersion = "availableVersion"
        case canInstall = "canInstall"
        case currentVersion = "currentVersion"
        case downloadedBytes = "downloadedBytes"
        case errorDetails = "errorDetails"
        case installBlockReason = "installBlockReason"
        case lastChecked = "lastChecked"
        case packageKind = "packageKind"
        case releaseNotes = "releaseNotes"
        case releaseUrl = "releaseUrl"
        case retryAction = "retryAction"
        case runningComputers = "runningComputers"
    }
}

enum SiloWireJobStartResultComputer: Codable, Equatable, Sendable {
    case siloWireMacosComputer(SiloWireMacosComputer)
    case string(String)
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let x = try? container.decode(String.self) {
            self = .string(x)
            return
        }
        if let x = try? container.decode(SiloWireMacosComputer.self) {
            self = .siloWireMacosComputer(x)
            return
        }
        if container.decodeNil() {
            self = .null
            return
        }
        throw DecodingError.typeMismatch(SiloWireJobStartResultComputer.self, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Wrong type for SiloWireJobStartResultComputer"))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .siloWireMacosComputer(let x):
            try container.encode(x)
        case .string(let x):
            try container.encode(x)
        case .null:
            try container.encodeNil()
        }
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

/// Mirrors `app/SiloUI/src-tauri/engine/src/runtime.rs::ComputerConfiguration`
/// (lines 304-319), including rejection of unknown fields.
///
/// Mirrors `app/SiloUI/src-tauri/engine/src/runtime.rs::ApplicationComputer` (lines
/// 591-628). `kind` is the discriminator required by 10 §1.3 and is added by
/// the canonical API; source fields retain their names and omission behavior.
///
/// Public projection of `app/SiloUI/src-tauri/engine/src/github.rs::public_snapshot`;
/// `computer` references are replaced with canonical `computerId` identifiers.
// MARK: - SiloWireComputerElement
struct SiloWireComputerElement: Codable, Equatable, Sendable {
    var cpus: Int? = nil
    var desktop: SiloWireDesktopConfiguration? = nil
    var id: String? = nil
    var maxCPUs: Int? = nil
    var maxMemoryGiB: Int? = nil
    var memoryGiB: Int? = nil
    var name: String? = nil
    var runtimeStorageGiB: Int? = nil
    var workspaceStorageGiB: Int? = nil
    var attention: SiloWireComputerAttention? = nil
    var canDismissError: Bool? = nil
    var checkpointOperation: SiloWireOperation? = nil
    var checkpoints: [SiloWireCheckpoint]? = nil
    var configuration: SiloWireComputerConfiguration? = nil
    var files: [SiloJSONValue]? = nil
    var freshness: SiloWireFreshness? = nil
    var githubRepositories: [String]? = nil
    var kind: SiloWireComputerKind? = nil
    var lifecycleFailure: String? = nil
    var lifecycleFailureDiagnostic: String? = nil
    var logs: [SiloJSONValue]? = nil
    var pendingCheckpointRestore: SiloWirePendingRestore? = nil
    var pendingSecretRevocations: [String]? = nil
    var ports: [SiloJSONValue]? = nil
    var purpose: String? = nil
    var repositories: [SiloJSONValue]? = nil
    var secretNames: [String]? = nil
    var settling: Bool? = nil
    var state: SiloWireComputerState? = nil
    var stateDetail: String? = nil
    var unfinishedRestore: SiloWireUnfinishedRestore? = nil
    var allRepositoriesAllowChanges: Bool? = nil
    var authenticationMethod: SiloWireGitHubAuthenticationMethod? = nil
    var computerId: String? = nil
    var identity: SiloWireGitHubIdentity? = nil
    var repositoryMode: SiloWireGitHubRepositoryMode? = nil
    var computer: String? = nil
    var error: String? = nil
    var host: String? = nil
    var addresses: [String]? = nil
    var bindAddress: String? = nil
    var deviceName: String? = nil
    var enabled: Bool? = nil
    var fingerprint: String? = nil
    var keys: [String]? = nil
    var message: String? = nil
    var port: Int? = nil
    var user: String? = nil

    enum CodingKeys: String, CodingKey {
        case cpus = "cpus"
        case desktop = "desktop"
        case id = "id"
        case maxCPUs = "maxCPUs"
        case maxMemoryGiB = "maxMemoryGiB"
        case memoryGiB = "memoryGiB"
        case name = "name"
        case runtimeStorageGiB = "runtimeStorageGiB"
        case workspaceStorageGiB = "workspaceStorageGiB"
        case attention = "attention"
        case canDismissError = "canDismissError"
        case checkpointOperation = "checkpointOperation"
        case checkpoints = "checkpoints"
        case configuration = "configuration"
        case files = "files"
        case freshness = "freshness"
        case githubRepositories = "githubRepositories"
        case kind = "kind"
        case lifecycleFailure = "lifecycleFailure"
        case lifecycleFailureDiagnostic = "lifecycleFailureDiagnostic"
        case logs = "logs"
        case pendingCheckpointRestore = "pendingCheckpointRestore"
        case pendingSecretRevocations = "pendingSecretRevocations"
        case ports = "ports"
        case purpose = "purpose"
        case repositories = "repositories"
        case secretNames = "secretNames"
        case settling = "settling"
        case state = "state"
        case stateDetail = "stateDetail"
        case unfinishedRestore = "unfinishedRestore"
        case allRepositoriesAllowChanges = "allRepositoriesAllowChanges"
        case authenticationMethod = "authenticationMethod"
        case computerId = "computerId"
        case identity = "identity"
        case repositoryMode = "repositoryMode"
        case computer = "computer"
        case error = "error"
        case host = "host"
        case addresses = "addresses"
        case bindAddress = "bindAddress"
        case deviceName = "deviceName"
        case enabled = "enabled"
        case fingerprint = "fingerprint"
        case keys = "keys"
        case message = "message"
        case port = "port"
        case user = "user"
    }
}

enum SiloWireComputerState: String, Codable, Equatable, Sendable {
    case disabled = "disabled"
    case error = "error"
    case failed = "failed"
    case listening = "listening"
    case running = "running"
    case starting = "starting"
    case stopped = "stopped"
    case waiting = "waiting"
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

// MARK: - SiloWireEntry
struct SiloWireEntry: Codable, Equatable, Sendable {
    var kind: SiloWireFileEntryKind? = nil
    var name: String? = nil
    var path: String? = nil
    var mtimeMs: UInt64? = nil
    var size: UInt64? = nil
    var type: SiloWireGuestFileKind? = nil
    var computerId: String? = nil
    var computerName: String? = nil
    var deviceId: String? = nil
    var deviceName: String? = nil
    var guestTimestamp: Bool? = nil
    var id: String? = nil
    var line: String? = nil
    var occurredAt: String? = nil
    var session: String? = nil
    var source: String? = nil

    enum CodingKeys: String, CodingKey {
        case kind = "kind"
        case name = "name"
        case path = "path"
        case mtimeMs = "mtimeMs"
        case size = "size"
        case type = "type"
        case computerId = "computerId"
        case computerName = "computerName"
        case deviceId = "deviceId"
        case deviceName = "deviceName"
        case guestTimestamp = "guestTimestamp"
        case id = "id"
        case line = "line"
        case occurredAt = "occurredAt"
        case session = "session"
        case source = "source"
    }
}

enum SiloWireDeviceid: Codable, Equatable, Sendable {
    case integer(Int)
    case string(String)
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let x = try? container.decode(Int.self) {
            self = .integer(x)
            return
        }
        if let x = try? container.decode(String.self) {
            self = .string(x)
            return
        }
        if container.decodeNil() {
            self = .null
            return
        }
        throw DecodingError.typeMismatch(SiloWireDeviceid.self, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Wrong type for SiloWireDeviceid"))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .integer(let x):
            try container.encode(x)
        case .string(let x):
            try container.encode(x)
        case .null:
            try container.encodeNil()
        }
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

/// A canonical multiplexed request. `operationId` and `startWithinMs` are
/// present only for methods that use change admission semantics.
// MARK: - SiloWireRequestEnvelope
struct SiloWireRequestEnvelope: Codable, Equatable, Sendable {
    var id: String
    var method: SiloWireMethodName
    var operationId: String? = nil
    var params: SiloJSONValue
    var startWithinMs: UInt64? = nil

    enum CodingKeys: String, CodingKey {
        case id = "id"
        case method = "method"
        case operationId = "operationId"
        case params = "params"
        case startWithinMs = "startWithinMs"
    }
}

//
// Hashable or Equatable:
// The compiler will not be able to synthesize the implementation of Hashable or Equatable
// for types that require the use of JSONAny, nor will the implementation of Hashable be
// synthesized for types that have collections (such as arrays or dictionaries).

/// A response echoes its request id and contains exactly one success or error.
// MARK: - SiloWireResponseEnvelope
struct SiloWireResponseEnvelope: Codable, Equatable, Sendable {
    var id: String
    var result: SiloJSONValue? = nil
    var error: SiloWireErrorObject? = nil

    enum CodingKeys: String, CodingKey {
        case id = "id"
        case result = "result"
        case error = "error"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        result = container.contains(.result) ? try container.decode(SiloJSONValue.self, forKey: .result) : nil
        error = try container.decodeIfPresent(SiloWireErrorObject.self, forKey: .error)
    }
}

typealias SiloWireDisplayAxis = SiloDisplayAxis
typealias SiloWireEmptyParams = [String: SiloJSONValue]
typealias SiloWireJobId = String

