import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../core/backup/backup_controller.dart';
import '../core/config/app_config.dart';
import '../core/testing/test_keys.dart';
import '../core/utils/path_sanitizer.dart';
import 'widgets/connection_banner.dart';
import 'widgets/custom_folders_section.dart';
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
  late final TextEditingController _deviceOverrideCtrl;

  late String _destinationType;
  bool _obscurePassword = true;

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
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'BACKUP DESTINATION',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                        letterSpacing: 1.1,
                      ),
                ),
                const SizedBox(height: 8),
                withTestId(
                  AppTestKeys.settingsDestinationTypeId,
                  child: DropdownButtonFormField<String>(
                    key: AppTestKeys.settingsDestinationType,
                    initialValue: _destinationType,
                    decoration: const InputDecoration(labelText: 'Destination Type'),
                    items: [
                      for (final dest in ctrl.availableDestinations)
                        DropdownMenuItem<String>(
                          value: dest.id,
                          child: Text(dest.displayName),
                        ),
                    ],
                    onChanged: (val) {
                      if (val != null) setState(() => _destinationType = val);
                    },
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  'SMB / NAS CONNECTION',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                        letterSpacing: 1.1,
                      ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: withTestId(
                        AppTestKeys.settingsHostId,
                        child: TextField(
                          key: AppTestKeys.settingsHost,
                          controller: _hostCtrl,
                          decoration: const InputDecoration(
                            labelText: 'SMB Host / IP',
                            hintText: '192.168.1.100',
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: withTestId(
                        AppTestKeys.settingsPortId,
                        child: TextField(
                          key: AppTestKeys.settingsPort,
                          controller: _portCtrl,
                          keyboardType: TextInputType.number,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          decoration: const InputDecoration(labelText: 'Port', hintText: '445'),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                withTestId(
                  AppTestKeys.settingsShareId,
                  child: TextField(
                    key: AppTestKeys.settingsShare,
                    controller: _shareCtrl,
                    decoration: const InputDecoration(labelText: 'Share Name', hintText: 'safe'),
                  ),
                ),
                const SizedBox(height: 12),
                withTestId(
                  AppTestKeys.settingsBasePathId,
                  child: TextField(
                    key: AppTestKeys.settingsBasePath,
                    controller: _basePathCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Base Path inside Share',
                      hintText: 'local/phone',
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                withTestId(
                  AppTestKeys.settingsUsernameId,
                  child: TextField(
                    key: AppTestKeys.settingsUsername,
                    controller: _usernameCtrl,
                    decoration: const InputDecoration(labelText: 'Username'),
                  ),
                ),
                const SizedBox(height: 12),
                withTestId(
                  AppTestKeys.settingsPasswordId,
                  child: TextField(
                    key: AppTestKeys.settingsPassword,
                    controller: _passwordCtrl,
                    obscureText: _obscurePassword,
                    decoration: InputDecoration(
                      labelText: 'Password',
                      suffixIcon: IconButton(
                        icon: Icon(_obscurePassword ? Icons.visibility : Icons.visibility_off),
                        onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                withTestId(
                  AppTestKeys.settingsDomainId,
                  child: TextField(
                    key: AppTestKeys.settingsDomain,
                    controller: _domainCtrl,
                    decoration: const InputDecoration(labelText: 'Domain / Workgroup (optional)'),
                  ),
                ),
                const SizedBox(height: 12),
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
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: withTestId(
                        AppTestKeys.settingsTestConnectionId,
                        child: OutlinedButton.icon(
                          key: AppTestKeys.settingsTestConnection,
                          onPressed: ctrl.testingConnection
                              ? null
                              : () => ctrl.testConnection(_collectSettings()),
                          icon: ctrl.testingConnection
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.wifi_tethering),
                          label: const Text('Test Connection'),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    withTestId(
                      AppTestKeys.settingsResetDefaultsId,
                      child: OutlinedButton(
                        key: AppTestKeys.settingsResetDefaults,
                        onPressed: _resetDefaults,
                        child: const Text('Reset Defaults'),
                      ),
                    ),
                  ],
                ),
                if (ctrl.connectionResult != null) ...[
                  const SizedBox(height: 12),
                  ConnectionBanner(result: ctrl.connectionResult!),
                ],
                const SizedBox(height: 24),
                CustomFoldersSection(
                  folders: ctrl.settings.customFolders,
                  onBrowse: ctrl.pickCustomFolder,
                  onAdd: (path, name) => ctrl.addCustomFolder(relativePath: path, displayName: name),
                  onRemove: ctrl.removeCustomFolder,
                ),
                const SizedBox(height: 24),
                SettingsPermissionsSection(
                  hasAllFiles: ctrl.permissions.hasAllFiles,
                  onOpenAllFilesAccess: ctrl.openAllFilesAccessSettings,
                ),
                const SizedBox(height: 20),
                Center(
                  child: Text(
                    'UBack v${ctrl.appVersion}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
