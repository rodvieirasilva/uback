import 'package:material_ui/material_ui.dart';

import '../../core/backup/media_exporter.dart';
import '../../core/testing/test_keys.dart';
import '../theme/app_theme.dart';

class ModeSelector extends StatelessWidget {
  final BackupMode selectedMode;
  final bool enabled;
  final ValueChanged<BackupMode> onSelect;

  const ModeSelector({
    super.key,
    required this.selectedMode,
    required this.enabled,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'BACKUP MODE',
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: cs.onSurfaceVariant,
                letterSpacing: 1.0,
              ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _ModeTile(
                testId: AppTestKeys.modeCopyId,
                widgetKey: AppTestKeys.modeCopy,
                selected: selectedMode == BackupMode.copy,
                enabled: enabled,
                icon: Icons.copy_all_rounded,
                title: 'Copy',
                subtitle: 'Keep originals on phone',
                onTap: () => onSelect(BackupMode.copy),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _ModeTile(
                testId: AppTestKeys.modeCropId,
                widgetKey: AppTestKeys.modeCrop,
                selected: selectedMode == BackupMode.crop,
                enabled: enabled,
                icon: Icons.cleaning_services_rounded,
                title: 'Crop (Free Space)',
                subtitle: 'Delete after SHA-256 check',
                accentColor: AppTheme.warningColor(context),
                onTap: () => onSelect(BackupMode.crop),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ModeTile extends StatelessWidget {
  final String testId;
  final Key widgetKey;
  final bool selected;
  final bool enabled;
  final IconData icon;
  final String title;
  final String subtitle;
  final Color? accentColor;
  final VoidCallback onTap;

  const _ModeTile({
    required this.testId,
    required this.widgetKey,
    required this.selected,
    required this.enabled,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.accentColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final active = accentColor ?? cs.primary;
    return withTestId(
      testId,
      child: InkWell(
        key: widgetKey,
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: selected ? active.withValues(alpha: 0.14) : cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? active : cs.outlineVariant,
              width: selected ? 1.8 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: selected ? active : cs.onSurfaceVariant),
              const SizedBox(height: 6),
              Text(
                title,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: selected ? active : cs.onSurface,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                      fontSize: 11.5,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
