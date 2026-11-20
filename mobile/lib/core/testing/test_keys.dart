import 'package:flutter/widgets.dart';

/// Centralized stable test IDs used across Widget tests, Flutter integration_test,
/// and Android UIAutomator (via Semantics identifier).
abstract final class AppTestKeys {
  // Home screen controls
  static const String modeCopyId = 'mode_copy_btn';
  static const String modeCropId = 'mode_crop_btn';
  static const String limitAllId = 'limit_all_btn';
  static const String limitFilesId = 'limit_files_btn';
  static const String limitMbId = 'limit_mb_btn';
  static const String limitValueInputId = 'limit_value_input';
  static const String startBackupId = 'start_backup_btn';
  static const String continueBackupId = 'continue_backup_btn';
  static const String pauseBackupId = 'pause_backup_btn';
  static const String resumeBackupId = 'resume_backup_btn';
  static const String stopBackupId = 'stop_backup_btn';
  static const String openSettingsId = 'open_settings_btn';
  static const String testConnectionId = 'test_connection_btn';
  static const String connectionStatusBannerId = 'connection_status_banner';
  static const String appLogoId = 'app_logo';
  static const String appVersionId = 'app_version_label';
  static const String grantMediaPermId = 'grant_media_perm_btn';
  static const String grantAllFilesPermId = 'grant_all_files_perm_btn';

  // Progress counters (text-only, zero previews)
  static const String statTotalId = 'stat_total';
  static const String statTransferredId = 'stat_transferred';
  static const String statRemainingId = 'stat_remaining';
  static const String statSkippedId = 'stat_skipped';
  static const String statFailedId = 'stat_failed';
  static const String statBytesId = 'stat_bytes';
  static const String statElapsedId = 'stat_elapsed';
  static const String statEtaId = 'stat_eta';
  static const String statusStateId = 'status_state';
  static const String statusStageId = 'status_stage';
  static const String statusCurrentFileId = 'status_current_file';
  static const String statusCurrentFileProgressId = 'status_current_file_progress';
  static const String errorLogBtnId = 'error_log_btn';
  static const String errorLogListId = 'error_log_list';

  // Collapsible Media Sources controls on Home screen
  static const String mediaSourcesCollapseId = 'media_sources_collapse_btn';
  static const String mediaSourcesSummaryId = 'media_sources_summary';
  static const String mediaSourcesEstimatingId = 'media_sources_estimating';
  static String sourceToggleId(String sourceId) => 'source_${sourceId}_toggle';
  static ValueKey<String> sourceToggle(String sourceId) => ValueKey(sourceToggleId(sourceId));
  static String sourceExpandId(String sourceId) => 'source_${sourceId}_expand';
  static ValueKey<String> sourceExpand(String sourceId) => ValueKey(sourceExpandId(sourceId));
  static String sourceStatsId(String sourceId) => 'source_${sourceId}_stats';
  static ValueKey<String> sourceStats(String sourceId) => ValueKey(sourceStatsId(sourceId));

  // Settings screen controls
  static const String settingsDestinationTypeId = 'settings_destination_type';
  static const String settingsHostId = 'settings_host_input';
  static const String settingsPortId = 'settings_port_input';
  static const String settingsShareId = 'settings_share_input';
  static const String settingsBasePathId = 'settings_base_path_input';
  static const String settingsUsernameId = 'settings_username_input';
  static const String settingsPasswordId = 'settings_password_input';
  static const String settingsDomainId = 'settings_domain_input';
  static const String settingsWhatsappKeyId = 'settings_whatsapp_key_input';
  static const String settingsDeviceOverrideId = 'settings_device_override_input';
  static const String settingsSaveId = 'settings_save_btn';
  static const String settingsResetDefaultsId = 'settings_reset_defaults_btn';
  static const String settingsTestConnectionId = 'settings_test_connection_btn';
  static const String settingsAllFilesPermId = 'settings_all_files_permission_btn';
  static const String settingsCustomFolderPathId = 'settings_custom_folder_path_input';
  static const String settingsCustomFolderNameId = 'settings_custom_folder_name_input';
  static const String settingsBrowseCustomFolderId = 'settings_browse_custom_folder_btn';
  static const String settingsAddCustomFolderId = 'settings_add_custom_folder_btn';
  static String settingsRemoveCustomFolderId(String id) => 'settings_remove_custom_folder_$id';
  static ValueKey<String> settingsRemoveCustomFolder(String id) =>
      ValueKey(settingsRemoveCustomFolderId(id));

  // ValueKeys for Flutter finder convenience
  static const ValueKey<String> modeCopy = ValueKey(modeCopyId);
  static const ValueKey<String> modeCrop = ValueKey(modeCropId);
  static const ValueKey<String> limitAll = ValueKey(limitAllId);
  static const ValueKey<String> limitFiles = ValueKey(limitFilesId);
  static const ValueKey<String> limitMb = ValueKey(limitMbId);
  static const ValueKey<String> limitValueInput = ValueKey(limitValueInputId);
  static const ValueKey<String> startBackup = ValueKey(startBackupId);
  static const ValueKey<String> continueBackup = ValueKey(continueBackupId);
  static const ValueKey<String> pauseBackup = ValueKey(pauseBackupId);
  static const ValueKey<String> resumeBackup = ValueKey(resumeBackupId);
  static const ValueKey<String> stopBackup = ValueKey(stopBackupId);
  static const ValueKey<String> openSettings = ValueKey(openSettingsId);
  static const ValueKey<String> testConnection = ValueKey(testConnectionId);
  static const ValueKey<String> connectionStatusBanner = ValueKey(connectionStatusBannerId);
  static const ValueKey<String> appLogo = ValueKey(appLogoId);
  static const ValueKey<String> appVersion = ValueKey(appVersionId);
  static const ValueKey<String> grantMediaPerm = ValueKey(grantMediaPermId);
  static const ValueKey<String> grantAllFilesPerm = ValueKey(grantAllFilesPermId);

  static const ValueKey<String> statTotal = ValueKey(statTotalId);
  static const ValueKey<String> statTransferred = ValueKey(statTransferredId);
  static const ValueKey<String> statRemaining = ValueKey(statRemainingId);
  static const ValueKey<String> statSkipped = ValueKey(statSkippedId);
  static const ValueKey<String> statFailed = ValueKey(statFailedId);
  static const ValueKey<String> statBytes = ValueKey(statBytesId);
  static const ValueKey<String> statElapsed = ValueKey(statElapsedId);
  static const ValueKey<String> statEta = ValueKey(statEtaId);
  static const ValueKey<String> statusState = ValueKey(statusStateId);
  static const ValueKey<String> statusStage = ValueKey(statusStageId);
  static const ValueKey<String> statusCurrentFile = ValueKey(statusCurrentFileId);
  static const ValueKey<String> statusCurrentFileProgress =
      ValueKey(statusCurrentFileProgressId);
  static const ValueKey<String> errorLogBtn = ValueKey(errorLogBtnId);
  static const ValueKey<String> errorLogList = ValueKey(errorLogListId);

  static const ValueKey<String> mediaSourcesCollapse = ValueKey(mediaSourcesCollapseId);
  static const ValueKey<String> mediaSourcesSummary = ValueKey(mediaSourcesSummaryId);
  static const ValueKey<String> mediaSourcesEstimating = ValueKey(mediaSourcesEstimatingId);

  static const ValueKey<String> settingsDestinationType = ValueKey(settingsDestinationTypeId);
  static const ValueKey<String> settingsHost = ValueKey(settingsHostId);
  static const ValueKey<String> settingsPort = ValueKey(settingsPortId);
  static const ValueKey<String> settingsShare = ValueKey(settingsShareId);
  static const ValueKey<String> settingsBasePath = ValueKey(settingsBasePathId);
  static const ValueKey<String> settingsUsername = ValueKey(settingsUsernameId);
  static const ValueKey<String> settingsPassword = ValueKey(settingsPasswordId);
  static const ValueKey<String> settingsDomain = ValueKey(settingsDomainId);
  static const ValueKey<String> settingsWhatsappKey = ValueKey(settingsWhatsappKeyId);
  static const ValueKey<String> settingsDeviceOverride = ValueKey(settingsDeviceOverrideId);
  static const ValueKey<String> settingsSave = ValueKey(settingsSaveId);
  static const ValueKey<String> settingsResetDefaults = ValueKey(settingsResetDefaultsId);
  static const ValueKey<String> settingsTestConnection = ValueKey(settingsTestConnectionId);
  static const ValueKey<String> settingsAllFilesPerm = ValueKey(settingsAllFilesPermId);
  static const ValueKey<String> settingsCustomFolderPath = ValueKey(settingsCustomFolderPathId);
  static const ValueKey<String> settingsCustomFolderName = ValueKey(settingsCustomFolderNameId);
  static const ValueKey<String> settingsBrowseCustomFolder = ValueKey(settingsBrowseCustomFolderId);
  static const ValueKey<String> settingsAddCustomFolder = ValueKey(settingsAddCustomFolderId);
}

/// Wraps a widget with a Semantics identifier so both Flutter tests and native UIAutomator
/// can locate elements reliably by test ID.
Widget withTestId(String id, {required Widget child}) {
  return Semantics(
    identifier: id,
    child: child,
  );
}
