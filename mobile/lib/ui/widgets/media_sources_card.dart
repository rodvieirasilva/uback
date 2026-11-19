import 'package:material_ui/material_ui.dart';

import '../../core/backup/media_source.dart';
import '../../core/testing/test_keys.dart';
import '../../core/utils/path_sanitizer.dart';

/// Displays all registered [MediaSource] toggles directly on the backup screen
/// along with live file-count / byte-size estimates and toggle impact.
class MediaSourcesCard extends StatelessWidget {
  final List<MediaSource> sources;
  final Set<String> enabledSourceIds;
  final Map<String, MediaSourceStats> stats;
  final bool estimating;
  final bool hasEstimated;
  final int selectedFiles;
  final int selectedBytes;
  final bool enabled;
  final void Function(String sourceId, bool value) onToggle;
  final VoidCallback onRefreshEstimate;

  const MediaSourcesCard({
    super.key,
    required this.sources,
    required this.enabledSourceIds,
    required this.stats,
    required this.estimating,
    required this.hasEstimated,
    required this.selectedFiles,
    required this.selectedBytes,
    required this.enabled,
    required this.onToggle,
    required this.onRefreshEstimate,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final labelStyle = Theme.of(context).textTheme.labelMedium?.copyWith(
          color: cs.onSurfaceVariant,
          letterSpacing: 1.0,
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('MEDIA SOURCES', style: labelStyle),
            if (estimating)
              withTestId(
                AppTestKeys.mediaSourcesEstimatingId,
                child: Row(
                  key: AppTestKeys.mediaSourcesEstimating,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(strokeWidth: 2, color: cs.primary),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Estimating size...',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.primary),
                    ),
                  ],
                ),
              )
            else
              InkWell(
                onTap: enabled ? onRefreshEstimate : null,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: withTestId(
                    AppTestKeys.mediaSourcesSummaryId,
                    child: Text(
                      hasEstimated
                          ? 'Selected: $selectedFiles files • ${PathSanitizer.formatBytes(selectedBytes)}'
                          : 'Tap to estimate size',
                      key: AppTestKeys.mediaSourcesSummary,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: cs.primary,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Card(
          child: Column(
            children: [
              for (var i = 0; i < sources.length; i++) ...[
                if (i > 0) const Divider(height: 1),
                _SourceRow(
                  source: sources[i],
                  selected: enabledSourceIds.contains(sources[i].id),
                  stat: stats[sources[i].id],
                  estimating: estimating,
                  hasEstimated: hasEstimated,
                  enabled: enabled,
                  onChanged: (v) => onToggle(sources[i].id, v),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _SourceRow extends StatelessWidget {
  final MediaSource source;
  final bool selected;
  final MediaSourceStats? stat;
  final bool estimating;
  final bool hasEstimated;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  const _SourceRow({
    required this.source,
    required this.selected,
    required this.stat,
    required this.estimating,
    required this.hasEstimated,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final estimateText = switch ((estimating, hasEstimated, stat)) {
      (true, false, _) => '${source.subtitle} • Estimating size...',
      (_, true, final s?) =>
        '${source.subtitle} • ${s.fileCount} files • ${PathSanitizer.formatBytes(s.totalBytes)}',
      _ => source.subtitle,
    };

    return withTestId(
      AppTestKeys.sourceToggleId(source.id),
      child: SwitchListTile(
        key: AppTestKeys.sourceToggle(source.id),
        value: selected,
        onChanged: enabled ? onChanged : null,
        title: Text(source.displayName, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: withTestId(
          AppTestKeys.sourceStatsId(source.id),
          child: Text(
            estimateText,
            key: AppTestKeys.sourceStats(source.id),
          ),
        ),
      ),
    );
  }
}
