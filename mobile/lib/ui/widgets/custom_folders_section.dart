import 'package:material_ui/material_ui.dart';

import '../../core/backup/native_bridge.dart';
import '../../core/config/custom_folder_config.dart';
import '../../core/testing/test_keys.dart';

/// Settings card allowing users to pick or type custom `/sdcard/...` folders
/// that appear as toggleable [MediaSource] items on the backup screen.
class CustomFoldersSection extends StatefulWidget {
  final List<CustomFolderConfig> folders;
  final Future<FolderPickResult?> Function() onBrowse;
  final Future<void> Function(String relativePath, String? displayName) onAdd;
  final Future<void> Function(String folderId) onRemove;

  const CustomFoldersSection({
    super.key,
    required this.folders,
    required this.onBrowse,
    required this.onAdd,
    required this.onRemove,
  });

  @override
  State<CustomFoldersSection> createState() => _CustomFoldersSectionState();
}

class _CustomFoldersSectionState extends State<CustomFoldersSection> {
  final TextEditingController _pathCtrl = TextEditingController();
  final TextEditingController _nameCtrl = TextEditingController();
  String? _pickerError;
  bool _picking = false;

  @override
  void dispose() {
    _pathCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _browse() async {
    if (_picking) return;
    setState(() {
      _picking = true;
      _pickerError = null;
    });
    try {
      final result = await widget.onBrowse();
      if (!mounted || result == null) return;
      if (result.error != null && result.error!.isNotEmpty) {
        setState(() => _pickerError = result.error);
        return;
      }
      if (result.hasPath) {
        final path = result.relativePath!.trim();
        _pathCtrl.text = path;
        if (_nameCtrl.text.trim().isEmpty) {
          final fallback = path.split('/').where((s) => s.isNotEmpty).lastOrNull;
          if (fallback != null) {
            _nameCtrl.text = fallback;
          }
        }
        setState(() => _pickerError = null);
      }
    } finally {
      if (mounted) {
        setState(() => _picking = false);
      }
    }
  }

  Future<void> _submit() async {
    final path = _pathCtrl.text.trim();
    if (path.isEmpty) return;
    await widget.onAdd(path, _nameCtrl.text.trim().isEmpty ? null : _nameCtrl.text.trim());
    _pathCtrl.clear();
    _nameCtrl.clear();
    if (mounted) {
      setState(() => _pickerError = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final headerStyle = Theme.of(context).textTheme.labelMedium?.copyWith(
          color: cs.primary,
          letterSpacing: 1.1,
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('CUSTOM FOLDERS', style: headerStyle),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (widget.folders.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Text(
                      'Pick or enter any folder under internal storage (e.g. DJI/Media, GoPro, Scans).',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                    ),
                  )
                else ...[
                  for (final folder in widget.folders)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(folder.displayName, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(
                        folder.relativePath,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: withTestId(
                        AppTestKeys.settingsRemoveCustomFolderId(folder.id),
                        child: IconButton(
                          key: AppTestKeys.settingsRemoveCustomFolder(folder.id),
                          tooltip: 'Remove custom folder',
                          onPressed: () => widget.onRemove(folder.id),
                          icon: const Icon(Icons.delete_outline),
                        ),
                      ),
                    ),
                  const Divider(height: 16),
                ],
                withTestId(
                  AppTestKeys.settingsBrowseCustomFolderId,
                  child: OutlinedButton.icon(
                    key: AppTestKeys.settingsBrowseCustomFolder,
                    onPressed: _picking ? null : _browse,
                    icon: const Icon(Icons.folder_open_rounded),
                    label: const Text(
                      'Browse Device Folders',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                if (_pickerError != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _pickerError!,
                    style: TextStyle(color: cs.error, fontSize: 12),
                  ),
                ],
                const SizedBox(height: 10),
                withTestId(
                  AppTestKeys.settingsCustomFolderPathId,
                  child: TextField(
                    key: AppTestKeys.settingsCustomFolderPath,
                    controller: _pathCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Folder Path (relative to storage)',
                      hintText: 'DJI/Media',
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: withTestId(
                        AppTestKeys.settingsCustomFolderNameId,
                        child: TextField(
                          key: AppTestKeys.settingsCustomFolderName,
                          controller: _nameCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Display Name (optional)',
                            hintText: 'Drone Footage',
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    withTestId(
                      AppTestKeys.settingsAddCustomFolderId,
                      child: FilledButton.tonalIcon(
                        key: AppTestKeys.settingsAddCustomFolder,
                        onPressed: _submit,
                        icon: const Icon(Icons.add),
                        label: const Text('Add'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
