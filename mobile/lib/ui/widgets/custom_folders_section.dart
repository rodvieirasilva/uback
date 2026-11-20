import 'package:material_ui/material_ui.dart';

import '../../core/config/custom_folder_config.dart';
import '../../core/testing/test_keys.dart';

/// Settings card allowing users to add/remove custom `/sdcard/...` folders
/// that appear as toggleable [MediaSource] items on the backup screen.
class CustomFoldersSection extends StatefulWidget {
  final List<CustomFolderConfig> folders;
  final Future<void> Function(String relativePath, String? displayName) onAdd;
  final Future<void> Function(String folderId) onRemove;

  const CustomFoldersSection({
    super.key,
    required this.folders,
    required this.onAdd,
    required this.onRemove,
  });

  @override
  State<CustomFoldersSection> createState() => _CustomFoldersSectionState();
}

class _CustomFoldersSectionState extends State<CustomFoldersSection> {
  final TextEditingController _pathCtrl = TextEditingController();
  final TextEditingController _nameCtrl = TextEditingController();

  @override
  void dispose() {
    _pathCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final path = _pathCtrl.text.trim();
    if (path.isEmpty) return;
    await widget.onAdd(path, _nameCtrl.text.trim().isEmpty ? null : _nameCtrl.text.trim());
    _pathCtrl.clear();
    _nameCtrl.clear();
  }

  @override
  Widget build(BuildContext context) {
    final headerStyle = Theme.of(context).textTheme.labelMedium?.copyWith(
          color: Theme.of(context).colorScheme.primary,
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
                      'Add any folder under internal storage (e.g. DJI/Media, GoPro, Scans).',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
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
