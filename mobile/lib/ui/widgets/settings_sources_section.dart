import 'package:material_ui/material_ui.dart';

import '../../core/testing/test_keys.dart';

class SettingsPermissionsSection extends StatelessWidget {
  final bool hasAllFiles;
  final VoidCallback onOpenAllFilesAccess;

  const SettingsPermissionsSection({
    super.key,
    required this.hasAllFiles,
    required this.onOpenAllFilesAccess,
  });

  @override
  Widget build(BuildContext context) {
    final headerStyle = Theme.of(context).textTheme.labelMedium?.copyWith(
          color: Theme.of(context).colorScheme.primary,
          letterSpacing: 1.1,
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('ANDROID PERMISSIONS', style: headerStyle),
        const SizedBox(height: 8),
        Card(
          child: ListTile(
            title: const Text('All files access (Crop Mode)'),
            subtitle: Text(
              hasAllFiles
                  ? 'Granted — verified files can be deleted automatically'
                  : 'Required for silent per-file deletion in Crop Mode',
            ),
            trailing: withTestId(
              AppTestKeys.settingsAllFilesPermId,
              child: FilledButton.tonal(
                key: AppTestKeys.settingsAllFilesPerm,
                onPressed: onOpenAllFilesAccess,
                child: Text(hasAllFiles ? 'Open' : 'Grant'),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
