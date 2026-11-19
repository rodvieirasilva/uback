import 'package:material_ui/material_ui.dart';

import '../../core/testing/test_keys.dart';

class SettingsSourcesSection extends StatelessWidget {
  final bool includeCamera;
  final bool includeScreenshots;
  final int cameraCount;
  final int screenshotsCount;
  final bool hasAllFiles;
  final ValueChanged<bool> onCameraChanged;
  final ValueChanged<bool> onScreenshotsChanged;
  final VoidCallback onOpenAllFilesAccess;

  const SettingsSourcesSection({
    super.key,
    required this.includeCamera,
    required this.includeScreenshots,
    required this.cameraCount,
    required this.screenshotsCount,
    required this.hasAllFiles,
    required this.onCameraChanged,
    required this.onScreenshotsChanged,
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
        Text('PHASE 1 SOURCES (NO PREVIEWS)', style: headerStyle),
        const SizedBox(height: 8),
        Card(
          child: Column(
            children: [
              withTestId(
                AppTestKeys.settingsSourceCameraId,
                child: CheckboxListTile(
                  key: AppTestKeys.settingsSourceCamera,
                  value: includeCamera,
                  onChanged: (v) => onCameraChanged(v ?? true),
                  title: const Text('Camera (DCIM/Camera)'),
                  subtitle: Text('$cameraCount files -> /camera/YYYY/MM'),
                ),
              ),
              const Divider(height: 1),
              withTestId(
                AppTestKeys.settingsSourceScreenshotsId,
                child: CheckboxListTile(
                  key: AppTestKeys.settingsSourceScreenshots,
                  value: includeScreenshots,
                  onChanged: (v) => onScreenshotsChanged(v ?? true),
                  title: const Text('Screenshots'),
                  subtitle: Text('$screenshotsCount files -> /screenshots/YYYY/MM'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
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
