import 'package:material_ui/material_ui.dart';

import '../core/backup/backup_controller.dart';
import '../core/backup/media_exporter.dart';
import '../core/testing/test_keys.dart';
import 'settings_screen.dart';
import 'widgets/adaptive_layout.dart';
import 'widgets/batch_limit_selector.dart';
import 'widgets/connection_banner.dart';
import 'widgets/error_log_sheet.dart';
import 'widgets/media_sources_card.dart';
import 'widgets/mode_selector.dart';
import 'widgets/permissions_card.dart';
import 'widgets/progress_dashboard.dart';

class HomeScreen extends StatefulWidget {
  final BackupController controller;

  const HomeScreen({super.key, required this.controller});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  late final TextEditingController _limitCtrl;
  final FocusNode _limitFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _limitCtrl = TextEditingController(text: widget.controller.limitValue.toString());
    widget.controller.addListener(_syncLimitText);
  }

  void _syncLimitText() {
    final target = widget.controller.limitValue.toString();
    if (_limitCtrl.text != target && !_limitFocusNode.hasFocus) {
      _limitCtrl.text = target;
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_syncLimitText);
    WidgetsBinding.instance.removeObserver(this);
    _limitCtrl.dispose();
    _limitFocusNode.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      widget.controller.refreshPermissions();
    }
  }

  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SettingsScreen(controller: widget.controller),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final ctrl = widget.controller;
        final isRunning = ctrl.progress.isActive;
        final cs = Theme.of(context).colorScheme;

        return Scaffold(
          appBar: AppBar(
            title: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                withTestId(
                  AppTestKeys.appLogoId,
                  child: Image.asset(
                    'assets/icon/uback_logo.png',
                    key: AppTestKeys.appLogo,
                    width: 28,
                    height: 28,
                  ),
                ),
                const SizedBox(width: 10),
                const Flexible(
                  child: Text('UBack', overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
            actions: [
              withTestId(
                AppTestKeys.testConnectionId,
                child: IconButton(
                  key: AppTestKeys.testConnection,
                  tooltip: 'Test Connection',
                  onPressed: ctrl.testingConnection || isRunning ? null : () => ctrl.testConnection(),
                  icon: ctrl.testingConnection
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.wifi_tethering),
                ),
              ),
              withTestId(
                AppTestKeys.openSettingsId,
                child: IconButton(
                  key: AppTestKeys.openSettings,
                  tooltip: 'Settings',
                  onPressed: isRunning ? null : _openSettings,
                  icon: const Icon(Icons.settings),
                ),
              ),
            ],
          ),
          body: AdaptiveTwoPaneLayout(
            portraitBuilder: (_) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ..._buildBanners(ctrl),
                ModeSelector(
                  selectedMode: ctrl.mode,
                  enabled: !isRunning,
                  onSelect: ctrl.setMode,
                ),
                const SizedBox(height: 16),
                _buildSourcesCard(ctrl, isRunning),
                const SizedBox(height: 16),
                ..._buildControlsAndProgress(context, ctrl, isRunning, cs),
              ],
            ),
            leftPaneBuilder: (_) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ..._buildBanners(ctrl),
                ModeSelector(
                  selectedMode: ctrl.mode,
                  enabled: !isRunning,
                  onSelect: ctrl.setMode,
                ),
                const SizedBox(height: 16),
                ..._buildControlsAndProgress(context, ctrl, isRunning, cs),
              ],
            ),
            rightPaneBuilder: (_) => _buildSourcesCard(ctrl, isRunning),
          ),
        );
      },
    );
  }

  List<Widget> _buildBanners(BackupController ctrl) => [
        if (ctrl.connectionResult != null) ...[
          ConnectionBanner(result: ctrl.connectionResult!),
          const SizedBox(height: 12),
        ],
        if (ctrl.initialized)
          PermissionsAlertCard(
            permissions: ctrl.permissions,
            mode: ctrl.mode,
            onGrantMedia: ctrl.requestMediaPermissions,
            onGrantAllFiles: ctrl.openAllFilesAccessSettings,
          ),
      ];

  Widget _buildSourcesCard(BackupController ctrl, bool isRunning) => MediaSourcesCard(
        sources: ctrl.mediaSources,
        enabledSourceIds: ctrl.settings.enabledSourceIds,
        sectionExpanded: ctrl.mediaSourcesExpanded,
        expandedNodeIds: ctrl.expandedSourceGroupIds,
        stats: ctrl.sourceStats,
        estimating: ctrl.estimatingStats,
        hasEstimated: ctrl.hasEstimatedStats,
        selectedFiles: ctrl.selectedFileCount,
        selectedBytes: ctrl.selectedTotalBytes,
        enabled: !isRunning,
        onSectionExpandedChanged: ctrl.setMediaSourcesExpanded,
        onToggleNodeExpanded: ctrl.toggleSourceGroupExpanded,
        onToggle: ctrl.toggleSourceNode,
        onRefreshEstimate: ctrl.refreshSourceStats,
      );

  List<Widget> _buildControlsAndProgress(
    BuildContext context,
    BackupController ctrl,
    bool isRunning,
    ColorScheme cs,
  ) =>
      [
        BatchLimitSelector(
          limitType: ctrl.limitType,
          valueController: _limitCtrl,
          focusNode: _limitFocusNode,
          enabled: !isRunning,
          onSelectType: (type) {
            ctrl.setLimitType(type);
            _limitCtrl.text = ctrl.limitValue.toString();
          },
          onChangeValue: ctrl.setLimitValue,
        ),
        const SizedBox(height: 18),
        _PrimaryActionButton(
          isRunning: isRunning,
          mode: ctrl.mode,
          onStart: ctrl.startBackup,
          onStop: ctrl.stopBackup,
        ),
        if (ctrl.statusMessage != null) ...[
          const SizedBox(height: 10),
          Text(
            ctrl.statusMessage!,
            style: TextStyle(color: cs.error, fontSize: 13),
          ),
        ],
        const SizedBox(height: 18),
        ProgressDashboard(
          progress: ctrl.progress,
          onViewErrors: () => showErrorLogSheet(context, ctrl.progress.errors),
        ),
        const SizedBox(height: 16),
        Center(
          child: withTestId(
            AppTestKeys.appVersionId,
            child: Text(
              ctrl.appVersionLabel,
              key: AppTestKeys.appVersion,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
            ),
          ),
        ),
      ];
}

class _PrimaryActionButton extends StatelessWidget {
  final bool isRunning;
  final BackupMode mode;
  final VoidCallback onStart;
  final VoidCallback onStop;

  const _PrimaryActionButton({
    required this.isRunning,
    required this.mode,
    required this.onStart,
    required this.onStop,
  });

  @override
  Widget build(BuildContext context) {
    if (isRunning) {
      return withTestId(
        AppTestKeys.stopBackupId,
        child: FilledButton.icon(
          key: AppTestKeys.stopBackup,
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(54),
            backgroundColor: Colors.redAccent,
            foregroundColor: Colors.white,
          ),
          onPressed: onStop,
          icon: const Icon(Icons.stop_circle_outlined),
          label: const Text(
            'Stop Backup Safely',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
        ),
      );
    }

    return withTestId(
      AppTestKeys.startBackupId,
      child: FilledButton.icon(
        key: AppTestKeys.startBackup,
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
        onPressed: onStart,
        icon: const Icon(Icons.backup_rounded),
        label: Text(
          mode == BackupMode.crop ? 'Start Crop Backup' : 'Start Copy Backup',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}
