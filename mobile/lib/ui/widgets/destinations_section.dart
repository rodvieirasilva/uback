import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/backup/backup_destination.dart';
import '../../core/config/smb_destination_config.dart';
import '../../core/testing/test_keys.dart';
import 'settings_components.dart';

/// Modular card for configuring an inline SMB / NAS destination with its own enable/disable toggle.
class DestinationFormCard extends StatelessWidget {
  final String destinationType;
  final List<BackupDestination> availableDestinations;
  final ValueChanged<String> onDestinationTypeChanged;
  final bool enabled;
  final ValueChanged<bool> onEnabledChanged;
  final TextEditingController hostCtrl;
  final TextEditingController portCtrl;
  final TextEditingController shareCtrl;
  final TextEditingController basePathCtrl;
  final TextEditingController usernameCtrl;
  final TextEditingController passwordCtrl;
  final TextEditingController domainCtrl;
  final bool testingConnection;
  final VoidCallback onTestConnection;

  const DestinationFormCard({
    super.key,
    required this.destinationType,
    required this.availableDestinations,
    required this.onDestinationTypeChanged,
    required this.enabled,
    required this.onEnabledChanged,
    required this.hostCtrl,
    required this.portCtrl,
    required this.shareCtrl,
    required this.basePathCtrl,
    required this.usernameCtrl,
    required this.passwordCtrl,
    required this.domainCtrl,
    required this.testingConnection,
    required this.onTestConnection,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('SMB / NAS', style: theme.textTheme.titleSmall),
                ),
                withTestId(
                  AppTestKeys.settingsPrimaryDestToggleId,
                  child: Switch(
                    key: AppTestKeys.settingsPrimaryDestToggle,
                    value: enabled,
                    onChanged: onEnabledChanged,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            withTestId(
              AppTestKeys.settingsDestinationTypeId,
              child: DropdownButtonFormField<String>(
                key: AppTestKeys.settingsDestinationType,
                initialValue: destinationType,
                decoration: const InputDecoration(labelText: 'Destination Type'),
                items: [
                  for (final dest in availableDestinations)
                    DropdownMenuItem<String>(
                      value: dest.id,
                      child: Text(dest.displayName),
                    ),
                ],
                onChanged: (val) {
                  if (val != null) onDestinationTypeChanged(val);
                },
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
                      controller: hostCtrl,
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
                      controller: portCtrl,
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
                controller: shareCtrl,
                decoration: const InputDecoration(labelText: 'Share Name', hintText: 'safe'),
              ),
            ),
            const SizedBox(height: 12),
            withTestId(
              AppTestKeys.settingsBasePathId,
              child: TextField(
                key: AppTestKeys.settingsBasePath,
                controller: basePathCtrl,
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
                controller: usernameCtrl,
                decoration: const InputDecoration(labelText: 'Username'),
              ),
            ),
            const SizedBox(height: 12),
            SecretTextField(
              testId: AppTestKeys.settingsPasswordId,
              fieldKey: AppTestKeys.settingsPassword,
              controller: passwordCtrl,
              labelText: 'Password',
            ),
            const SizedBox(height: 12),
            withTestId(
              AppTestKeys.settingsDomainId,
              child: TextField(
                key: AppTestKeys.settingsDomain,
                controller: domainCtrl,
                decoration: const InputDecoration(labelText: 'Domain / Workgroup (optional)'),
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: withTestId(
                AppTestKeys.settingsTestConnectionId,
                child: OutlinedButton.icon(
                  key: AppTestKeys.settingsTestConnection,
                  onPressed: testingConnection ? null : onTestConnection,
                  icon: testingConnection
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.lan_outlined, size: 18),
                  label: const Text('Test SMB', maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Manages additional SMB NAS destinations with add, enable/disable, test, and remove controls.
class ExtraDestinationsSection extends StatelessWidget {
  final List<SmbDestinationConfig> destinations;
  final ValueChanged<List<SmbDestinationConfig>> onChanged;
  final Future<void> Function(SmbDestinationConfig dest) onTest;

  const ExtraDestinationsSection({
    super.key,
    required this.destinations,
    required this.onChanged,
    required this.onTest,
  });

  Future<void> _showAddDialog(BuildContext context) async {
    final created = await showDialog<SmbDestinationConfig>(
      context: context,
      builder: (_) => const _AddSmbDestinationDialog(),
    );
    if (created != null) {
      onChanged([...destinations, created]);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < destinations.length; i++)
          Card(
            margin: const EdgeInsets.only(bottom: 10),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${destinations[i].name} • SMB / NAS',
                              style: theme.textTheme.titleSmall,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              destinations[i].displaySummary,
                              style: theme.textTheme.bodySmall,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      withTestId(
                        AppTestKeys.settingsDestinationToggleId(destinations[i].id),
                        child: Switch(
                          key: AppTestKeys.settingsDestinationToggle(destinations[i].id),
                          value: destinations[i].enabled,
                          onChanged: (val) {
                            final updated = [...destinations];
                            updated[i] = updated[i].copyWith(enabled: val);
                            onChanged(updated);
                          },
                        ),
                      ),
                    ],
                  ),
                  Wrap(
                    spacing: 8,
                    alignment: WrapAlignment.end,
                    children: [
                      withTestId(
                        AppTestKeys.settingsDestinationTestId(destinations[i].id),
                        child: TextButton.icon(
                          key: AppTestKeys.settingsDestinationTest(destinations[i].id),
                          onPressed: () => onTest(destinations[i]),
                          icon: const Icon(Icons.lan_outlined, size: 16),
                          label: const Text('Test'),
                        ),
                      ),
                      withTestId(
                        AppTestKeys.settingsDestinationRemoveId(destinations[i].id),
                        child: TextButton.icon(
                          key: AppTestKeys.settingsDestinationRemove(destinations[i].id),
                          onPressed: () {
                            final updated = [...destinations]..removeAt(i);
                            onChanged(updated);
                          },
                          icon: const Icon(Icons.delete_outline, size: 16),
                          label: const Text('Remove'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: withTestId(
            AppTestKeys.settingsAddDestinationId,
            child: OutlinedButton.icon(
              key: AppTestKeys.settingsAddDestination,
              onPressed: () => _showAddDialog(context),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add Destination'),
            ),
          ),
        ),
      ],
    );
  }
}

class _AddSmbDestinationDialog extends StatefulWidget {
  const _AddSmbDestinationDialog();

  @override
  State<_AddSmbDestinationDialog> createState() => _AddSmbDestinationDialogState();
}

class _AddSmbDestinationDialogState extends State<_AddSmbDestinationDialog> {
  final _nameCtrl = TextEditingController();
  final _hostCtrl = TextEditingController();
  final _portCtrl = TextEditingController(text: '445');
  final _shareCtrl = TextEditingController();
  final _basePathCtrl = TextEditingController();
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _domainCtrl = TextEditingController();

  @override
  void dispose() {
    _nameCtrl.dispose();
    _hostCtrl.dispose();
    _portCtrl.dispose();
    _shareCtrl.dispose();
    _basePathCtrl.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    _domainCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add Destination'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              initialValue: 'smb_nas',
              decoration: const InputDecoration(labelText: 'Destination Type'),
              items: const [
                DropdownMenuItem(value: 'smb_nas', child: Text('SMB / NAS')),
              ],
              onChanged: (_) {},
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(labelText: 'Label (e.g. Offsite NAS)'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _hostCtrl,
              decoration: const InputDecoration(labelText: 'SMB Host / IP'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _portCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(labelText: 'Port'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _shareCtrl,
              decoration: const InputDecoration(labelText: 'Share Name'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _basePathCtrl,
              decoration: const InputDecoration(labelText: 'Base Path (optional)'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _userCtrl,
              decoration: const InputDecoration(labelText: 'Username'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _passCtrl,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Password'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _domainCtrl,
              decoration: const InputDecoration(labelText: 'Domain (optional)'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            final host = _hostCtrl.text.trim();
            final share = _shareCtrl.text.trim();
            if (host.isEmpty || share.isEmpty) return;
            final id = 'smb_${DateTime.now().millisecondsSinceEpoch}';
            final name = _nameCtrl.text.trim().isEmpty ? '$host/$share' : _nameCtrl.text.trim();
            Navigator.pop(
              context,
              SmbDestinationConfig(
                id: id,
                name: name,
                enabled: true,
                host: host,
                port: int.tryParse(_portCtrl.text.trim()) ?? 445,
                share: share,
                basePath: _basePathCtrl.text.trim(),
                username: _userCtrl.text.trim(),
                password: _passCtrl.text,
                domain: _domainCtrl.text.trim(),
              ),
            );
          },
          child: const Text('Add'),
        ),
      ],
    );
  }
}
