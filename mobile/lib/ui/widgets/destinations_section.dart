import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/config/smb_destination_config.dart';
import '../../core/testing/test_keys.dart';

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
