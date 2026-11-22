import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/backup/backup_destination.dart';
import '../../core/config/smb_destination_config.dart';
import '../../core/testing/test_keys.dart';
import 'settings_components.dart';

/// Modular card for configuring an inline SMB or S3 destination with its own enable/disable toggle.
class DestinationFormCard extends StatelessWidget {
  final String destinationType;
  final List<BackupDestination> availableDestinations;
  final ValueChanged<String> onDestinationTypeChanged;
  final bool enabled;
  final ValueChanged<bool> onEnabledChanged;
  final bool parallelEnabled;
  final ValueChanged<bool> onParallelEnabledChanged;
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
    required this.parallelEnabled,
    required this.onParallelEnabledChanged,
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
    final isS3 = destinationType == S3BackupDestination.typeId;
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
                  child: Text(
                    isS3 ? 'S3 / S3-Compatible' : 'SMB',
                    style: theme.textTheme.titleSmall,
                  ),
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
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Destination Type'),
                items: [
                  for (final dest in availableDestinations)
                    DropdownMenuItem<String>(
                      value: dest.id,
                      child: Text(dest.displayName, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (val) {
                  if (val != null) onDestinationTypeChanged(val);
                },
              ),
            ),
            const SizedBox(height: 12),
            if (isS3)
              withTestId(
                AppTestKeys.settingsHostId,
                child: TextField(
                  key: AppTestKeys.settingsHost,
                  controller: hostCtrl,
                  decoration: const InputDecoration(
                    labelText: 'S3 Endpoint URL',
                    hintText: 'http://192.168.1.100:9000',
                  ),
                ),
              )
            else
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
                decoration: InputDecoration(
                  labelText: isS3 ? 'Bucket Name' : 'Share Name',
                  hintText: 'backup',
                ),
              ),
            ),
            const SizedBox(height: 12),
            withTestId(
              AppTestKeys.settingsBasePathId,
              child: TextField(
                key: AppTestKeys.settingsBasePath,
                controller: basePathCtrl,
                decoration: InputDecoration(
                  labelText: isS3 ? 'Key Prefix (optional)' : 'Base Path inside Share',
                  hintText: 'phones',
                ),
              ),
            ),
            const SizedBox(height: 12),
            withTestId(
              AppTestKeys.settingsUsernameId,
              child: TextField(
                key: AppTestKeys.settingsUsername,
                controller: usernameCtrl,
                decoration: InputDecoration(labelText: isS3 ? 'Access Key ID' : 'Username'),
              ),
            ),
            const SizedBox(height: 12),
            SecretTextField(
              testId: AppTestKeys.settingsPasswordId,
              fieldKey: AppTestKeys.settingsPassword,
              controller: passwordCtrl,
              labelText: isS3 ? 'Secret Access Key' : 'Password',
            ),
            const SizedBox(height: 12),
            withTestId(
              AppTestKeys.settingsDomainId,
              child: TextField(
                key: AppTestKeys.settingsDomain,
                controller: domainCtrl,
                decoration: InputDecoration(
                  labelText: isS3 ? 'Region (default: us-east-1)' : 'Domain / Workgroup (optional)',
                  hintText: isS3 ? 'us-east-1' : null,
                ),
              ),
            ),
            if (!isS3) ...[
              const SizedBox(height: 6),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text('Parallel small-file transfer'),
                subtitle: const Text('Upload small files (<= 5 MB) concurrently'),
                value: parallelEnabled,
                onChanged: onParallelEnabledChanged,
              ),
            ],
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
                      : Icon(isS3 ? Icons.cloud_outlined : Icons.lan_outlined, size: 18),
                  label: Text(
                    isS3 ? 'Test S3' : 'Test SMB',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Manages additional SMB / S3 destinations with add, enable/disable, test, and remove controls.
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
      builder: (_) => const _AddDestinationDialog(),
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
                              '${destinations[i].name} • ${destinations[i].typeLabel}',
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
                          icon: Icon(
                            destinations[i].isS3 ? Icons.cloud_outlined : Icons.lan_outlined,
                            size: 16,
                          ),
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

class _AddDestinationDialog extends StatefulWidget {
  const _AddDestinationDialog();

  @override
  State<_AddDestinationDialog> createState() => _AddDestinationDialogState();
}

class _AddDestinationDialogState extends State<_AddDestinationDialog> {
  String _type = SmbNasDestination.typeId;
  bool _parallelEnabled = false;
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
    final isS3 = _type == S3BackupDestination.typeId;
    return AlertDialog(
      title: const Text('Add Destination'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              initialValue: _type,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Destination Type'),
              items: const [
                DropdownMenuItem(
                  value: SmbNasDestination.typeId,
                  child: Text('SMB (Samba / Windows Share)', overflow: TextOverflow.ellipsis),
                ),
                DropdownMenuItem(
                  value: S3BackupDestination.typeId,
                  child: Text('S3 / S3-Compatible', overflow: TextOverflow.ellipsis),
                ),
              ],
              onChanged: (val) {
                if (val != null) setState(() => _type = val);
              },
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _nameCtrl,
              decoration: InputDecoration(
                labelText: isS3 ? 'Label (e.g. MinIO / B2)' : 'Label (e.g. Home Server)',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _hostCtrl,
              decoration: InputDecoration(
                labelText: isS3 ? 'S3 Endpoint URL' : 'SMB Host / IP',
                hintText: isS3 ? 'http://192.168.1.100:9000' : '192.168.1.100',
              ),
            ),
            if (!isS3) ...[
              const SizedBox(height: 8),
              TextField(
                controller: _portCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(labelText: 'Port'),
              ),
            ],
            const SizedBox(height: 8),
            TextField(
              controller: _shareCtrl,
              decoration: InputDecoration(labelText: isS3 ? 'Bucket Name' : 'Share Name'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _basePathCtrl,
              decoration: InputDecoration(
                labelText: isS3 ? 'Key Prefix (optional)' : 'Base Path (optional)',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _userCtrl,
              decoration: InputDecoration(labelText: isS3 ? 'Access Key ID' : 'Username'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _passCtrl,
              obscureText: true,
              decoration: InputDecoration(labelText: isS3 ? 'Secret Access Key' : 'Password'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _domainCtrl,
              decoration: InputDecoration(
                labelText: isS3 ? 'Region (default: us-east-1)' : 'Domain (optional)',
              ),
            ),
            if (!isS3)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text('Parallel small-file transfer'),
                value: _parallelEnabled,
                onChanged: (v) => setState(() => _parallelEnabled = v),
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
            final prefix = isS3 ? 's3' : 'smb';
            final id = '${prefix}_${DateTime.now().millisecondsSinceEpoch}';
            final name = _nameCtrl.text.trim().isEmpty ? '$host/$share' : _nameCtrl.text.trim();
            Navigator.pop(
              context,
              SmbDestinationConfig(
                id: id,
                type: _type,
                name: name,
                enabled: true,
                parallelEnabled: !isS3 && _parallelEnabled,
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
