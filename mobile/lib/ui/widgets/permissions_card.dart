import 'package:material_ui/material_ui.dart';

import '../../core/backup/media_exporter.dart';
import '../../core/testing/test_keys.dart';
import '../theme/app_theme.dart';

class PermissionsAlertCard extends StatelessWidget {
  final PermissionState permissions;
  final BackupMode mode;
  final VoidCallback onGrantMedia;
  final VoidCallback onGrantAllFiles;

  const PermissionsAlertCard({
    super.key,
    required this.permissions,
    required this.mode,
    required this.onGrantMedia,
    required this.onGrantAllFiles,
  });

  bool get isVisible => !permissions.hasMedia || (mode == BackupMode.crop && !permissions.hasAllFiles);

  @override
  Widget build(BuildContext context) {
    if (!isVisible) return const SizedBox.shrink();
    final warn = AppTheme.warningColor(context);

    return Card(
      color: warn.withValues(alpha: 0.12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Permissions Required',
              style: TextStyle(fontWeight: FontWeight.w600, color: warn),
            ),
            const SizedBox(height: 6),
            if (!permissions.hasMedia)
              withTestId(
                AppTestKeys.grantMediaPermId,
                child: TextButton.icon(
                  key: AppTestKeys.grantMediaPerm,
                  onPressed: onGrantMedia,
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const Text('Grant Photos & Videos Access'),
                ),
              ),
            if (mode == BackupMode.crop && !permissions.hasAllFiles)
              withTestId(
                AppTestKeys.grantAllFilesPermId,
                child: TextButton.icon(
                  key: AppTestKeys.grantAllFilesPerm,
                  onPressed: onGrantAllFiles,
                  icon: const Icon(Icons.folder_delete_outlined),
                  label: const Text('Grant All Files Access (for Crop Mode)'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
