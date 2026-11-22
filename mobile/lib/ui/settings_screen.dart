import 'package:material_ui/material_ui.dart';

import '../core/backup/backup_controller.dart';
import '../core/backup/native_bridge.dart';
import '../core/config/app_config.dart';
import '../core/config/smb_destination_config.dart';
import '../core/testing/test_keys.dart';
import '../core/utils/path_sanitizer.dart';
import 'widgets/adaptive_layout.dart';
import 'widgets/connection_banner.dart';
import 'widgets/connectors_section.dart';
import 'widgets/custom_folders_section.dart';
import 'widgets/destinations_section.dart';
import 'widgets/settings_components.dart';
import 'widgets/settings_sources_section.dart';

class SettingsScreen extends StatefulWidget {
  final BackupController controller;

  const SettingsScreen({super.key, required this.controller});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _hostCtrl;
  late final TextEditingController _portCtrl;
  late final TextEditingController _shareCtrl;
  late final TextEditingController _basePathCtrl;
  late final TextEditingController _usernameCtrl;
  late final TextEditingController _passwordCtrl;
  late final TextEditingController _domainCtrl;
  late final TextEditingController _whatsappKeyCtrl;
  late final TextEditingController _telegramApiIdCtrl;
  late final TextEditingController _telegramApiHashCtrl;
  late final TextEditingController _telegramPasswordCtrl;
  late final TextEditingController _deviceOverrideCtrl;

  late String _destinationType;
  bool _primaryDestinationEnabled = true;
  List<SmbDestinationConfig> _extraDestinations = const [];
  String _telegramAuthState = 'uninitialized';

  @override
  void initState() {
    super.initState();
    final s = widget.controller.settings;
    _destinationType = s.destinationType;
    _hostCtrl = TextEditingController(text: s.host);
    _portCtrl = TextEditingController(text: s.port.toString());
    _shareCtrl = TextEditingController(text: s.share);
    _basePathCtrl = TextEditingController(text: s.basePath);
    _usernameCtrl = TextEditingController(text: s.username);
    _passwordCtrl = TextEditingController(text: s.password);
    _domainCtrl = TextEditingController(text: s.domain);
    _whatsappKeyCtrl = TextEditingController(text: s.whatsappKey);
    _telegramApiIdCtrl = TextEditingController(text: s.telegramApiId);
    _telegramApiHashCtrl = TextEditingController(text: s.telegramApiHash);
    _telegramPasswordCtrl = TextEditingController(text: s.telegramPassword);
    _primaryDestinationEnabled = s.primaryDestinationEnabled;
    _extraDestinations = List<SmbDestinationConfig>.of(s.extraDestinations);
    _deviceOverrideCtrl = TextEditingController(text: s.deviceFolderOverride);
  }

  @override
  void dispose() {
    _hostCtrl.dispose();
    _portCtrl.dispose();
    _shareCtrl.dispose();
    _basePathCtrl.dispose();
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    _domainCtrl.dispose();
    _whatsappKeyCtrl.dispose();
    _telegramApiIdCtrl.dispose();
    _telegramApiHashCtrl.dispose();
    _telegramPasswordCtrl.dispose();
    _deviceOverrideCtrl.dispose();
    super.dispose();
  }

  AppSettings _collectSettings() => widget.controller.settings.copyWith(
        destinationType: _destinationType,
        host: _hostCtrl.text.trim(),
        port: int.tryParse(_portCtrl.text.trim()) ?? 445,
        share: _shareCtrl.text.trim(),
        basePath: _basePathCtrl.text.trim(),
        username: _usernameCtrl.text.trim(),
        password: _passwordCtrl.text,
        domain: _domainCtrl.text.trim(),
        whatsappKey: _whatsappKeyCtrl.text.trim(),
        telegramApiId: _telegramApiIdCtrl.text.trim(),
        telegramApiHash: _telegramApiHashCtrl.text.trim(),
        telegramPassword: _telegramPasswordCtrl.text,
        primaryDestinationEnabled: _primaryDestinationEnabled,
        extraDestinations: List<SmbDestinationConfig>.unmodifiable(_extraDestinations),
        deviceFolderOverride: _deviceOverrideCtrl.text.trim(),
      );

  void _applySettings(AppSettings s) {
    setState(() => _destinationType = s.destinationType);
    _hostCtrl.text = s.host;
    _portCtrl.text = s.port.toString();
    _shareCtrl.text = s.share;
    _basePathCtrl.text = s.basePath;
    _usernameCtrl.text = s.username;
    _passwordCtrl.text = s.password;
    _domainCtrl.text = s.domain;
    _whatsappKeyCtrl.text = s.whatsappKey;
    _telegramApiIdCtrl.text = s.telegramApiId;
    _telegramApiHashCtrl.text = s.telegramApiHash;
    _telegramPasswordCtrl.text = s.telegramPassword;
    setState(() {
      _primaryDestinationEnabled = s.primaryDestinationEnabled;
      _extraDestinations = List<SmbDestinationConfig>.of(s.extraDestinations);
    });
    _deviceOverrideCtrl.text = s.deviceFolderOverride;
  }

  Future<void> _save() async {
    await widget.controller.saveSettings(_collectSettings());
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Settings saved')));
    Navigator.of(context).pop();
  }

  Future<void> _resetDefaults() async {
    final defaults = await widget.controller.resetSettingsToDefaults();
    _applySettings(defaults);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Restored compile-time defaults')),
    );
  }

  Future<void> _showTelegramConnectDialog() async {
    final apiId = int.tryParse(_telegramApiIdCtrl.text.trim()) ?? 0;
    final apiHash = _telegramApiHashCtrl.text.trim();
    if (apiId <= 0 || apiHash.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter Telegram API ID and API Hash first.')),
      );
      return;
    }

    var res = await MethodChannelNativeBridge.telegramGetAuthState(apiId, apiHash);
    if (!mounted) return;
    setState(() => _telegramAuthState = res['state'] ?? 'uninitialized');
    if (_telegramAuthState == 'ready') return;

    final inputCtrl = TextEditingController();
    while (mounted) {
      final state = _telegramAuthState;
      if (state == 'ready') break;
      final label = switch (state) {
        'waitCode' => 'Telegram OTP Code',
        'waitPassword' => 'Telegram 2FA Password',
        _ => 'Phone Number (e.g. +5511999999999)',
      };
      final err = res['error'];
      if (state == 'waitPhoneNumber' || state == 'uninitialized') {
        inputCtrl.text = CompileTimeDefaults.telegramPhone;
      } else if (state == 'waitPassword') {
        inputCtrl.text = _telegramPasswordCtrl.text.trim();
      } else {
        inputCtrl.clear();
      }
      final submitted = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Connect Telegram'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (err != null && err.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(err, style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
                ),
              TextField(
                controller: inputCtrl,
                obscureText: state == 'waitPassword',
                decoration: InputDecoration(labelText: label),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, inputCtrl.text.trim()),
              child: const Text('Submit'),
            ),
          ],
        ),
      );
      if (submitted == null || submitted.isEmpty) break;
      res = switch (state) {
        'waitCode' => await MethodChannelNativeBridge.telegramSendCode(submitted),
        'waitPassword' => await MethodChannelNativeBridge.telegramSendPassword(submitted),
        _ => await MethodChannelNativeBridge.telegramSendPhone(submitted),
      };
      if (!mounted) break;
      setState(() => _telegramAuthState = res['state'] ?? _telegramAuthState);
    }
    inputCtrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final ctrl = widget.controller;
        final autoDevice = PathSanitizer.sanitizeDeviceName(ctrl.detectedDeviceName);

        return Scaffold(
          appBar: AppBar(
            title: const Text('Settings'),
            actions: [
              withTestId(
                AppTestKeys.settingsSaveId,
                child: TextButton(
                  key: AppTestKeys.settingsSave,
                  onPressed: _save,
                  child: const Text('SAVE'),
                ),
              ),
            ],
          ),
          body: AdaptiveTwoPaneLayout(
            portraitBuilder: (ctx) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ..._buildDestinationAndConnection(ctx, ctrl, autoDevice),
                const SizedBox(height: 24),
                ..._buildCustomFoldersAndPermissions(ctx, ctrl),
              ],
            ),
            leftPaneBuilder: (ctx) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: _buildDestinationAndConnection(ctx, ctrl, autoDevice),
            ),
            rightPaneBuilder: (ctx) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: _buildCustomFoldersAndPermissions(ctx, ctrl),
            ),
          ),
        );
      },
    );
  }

  List<Widget> _buildDestinationAndConnection(
    BuildContext context,
    BackupController ctrl,
    String autoDevice,
  ) =>
      [
        const SettingsSectionHeader(title: 'DEVICE'),
        const SizedBox(height: 10),
        withTestId(
          AppTestKeys.settingsDeviceOverrideId,
          child: TextField(
            key: AppTestKeys.settingsDeviceOverride,
            controller: _deviceOverrideCtrl,
            decoration: InputDecoration(
              labelText: 'Device Folder Override (optional)',
              helperText: 'Auto-detected: "${ctrl.detectedDeviceName}" -> $autoDevice',
            ),
          ),
        ),
        const SettingsSectionDivider(),
        const SettingsSectionHeader(title: 'DESTINATIONS'),
        const SizedBox(height: 10),
        DestinationFormCard(
          destinationType: _destinationType,
          availableDestinations: ctrl.availableDestinations,
          onDestinationTypeChanged: (val) => setState(() => _destinationType = val),
          enabled: _primaryDestinationEnabled,
          onEnabledChanged: (val) => setState(() => _primaryDestinationEnabled = val),
          hostCtrl: _hostCtrl,
          portCtrl: _portCtrl,
          shareCtrl: _shareCtrl,
          basePathCtrl: _basePathCtrl,
          usernameCtrl: _usernameCtrl,
          passwordCtrl: _passwordCtrl,
          domainCtrl: _domainCtrl,
          testingConnection: ctrl.testingConnection,
          onTestConnection: () => ctrl.testConnection(_collectSettings()),
        ),
        if (ctrl.connectionResult != null) ...[
          const SizedBox(height: 10),
          ConnectionBanner(result: ctrl.connectionResult!),
        ],
        const SizedBox(height: 12),
        ExtraDestinationsSection(
          destinations: _extraDestinations,
          onChanged: (updated) => setState(() => _extraDestinations = updated),
          onTest: (dest) => ctrl.testConnection(dest.toAppSettings(_collectSettings())),
        ),
        const SettingsSectionDivider(),
        ConnectorsSection(
          whatsappKeyCtrl: _whatsappKeyCtrl,
          onTestWhatsapp: () async {
            final res = await MethodChannelNativeBridge.testWhatsApp(_whatsappKeyCtrl.text.trim());
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(res['message']?.toString() ?? 'WhatsApp test complete')),
            );
          },
          telegramApiIdCtrl: _telegramApiIdCtrl,
          telegramApiHashCtrl: _telegramApiHashCtrl,
          telegramPasswordCtrl: _telegramPasswordCtrl,
          telegramAuthState: _telegramAuthState,
          onConnectTelegram: _showTelegramConnectDialog,
          onTestTelegram: () async {
            final apiId = int.tryParse(_telegramApiIdCtrl.text.trim()) ?? 0;
            final apiHash = _telegramApiHashCtrl.text.trim();
            final res = await MethodChannelNativeBridge.telegramGetAuthState(apiId, apiHash);
            if (!context.mounted) return;
            final st = res['state'] ?? 'uninitialized';
            setState(() => _telegramAuthState = st);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Telegram status: $st${res['error'] != null ? ' (${res['error']})' : ''}',
                ),
              ),
            );
          },
          onDisconnectTelegram: () async {
            final res = await MethodChannelNativeBridge.telegramLogout();
            if (mounted) {
              setState(() => _telegramAuthState = res['state'] ?? 'uninitialized');
            }
          },
        ),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerRight,
          child: withTestId(
            AppTestKeys.settingsResetDefaultsId,
            child: OutlinedButton(
              key: AppTestKeys.settingsResetDefaults,
              onPressed: _resetDefaults,
              child: const Text('Reset Defaults', maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ),
        ),
      ];

  List<Widget> _buildCustomFoldersAndPermissions(
    BuildContext context,
    BackupController ctrl,
  ) =>
      [
        const SettingsSectionDivider(),
        CustomFoldersSection(
          folders: ctrl.settings.customFolders,
          onBrowse: ctrl.pickCustomFolder,
          onAdd: (path, name) => ctrl.addCustomFolder(relativePath: path, displayName: name),
          onRemove: ctrl.removeCustomFolder,
        ),
        const SettingsSectionDivider(),
        SettingsPermissionsSection(
          hasAllFiles: ctrl.permissions.hasAllFiles,
          onOpenAllFilesAccess: ctrl.openAllFilesAccessSettings,
        ),
        const SizedBox(height: 20),
        Center(
          child: Text(
            ctrl.appVersionLabel,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ),
      ];
}
