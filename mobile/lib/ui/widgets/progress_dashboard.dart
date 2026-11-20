import 'package:material_ui/material_ui.dart';

import '../../core/backup/media_exporter.dart';
import '../../core/testing/test_keys.dart';
import '../../core/utils/path_sanitizer.dart';
import '../theme/app_theme.dart';

/// Text-and-counter progress dashboard designed for thousands of files with ZERO previews.
class ProgressDashboard extends StatelessWidget {
  final BackupProgress progress;
  final VoidCallback onViewErrors;

  const ProgressDashboard({
    super.key,
    required this.progress,
    required this.onViewErrors,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: withTestId(
                    AppTestKeys.statusStateId,
                    child: Text(
                      _stateLabel(progress.state),
                      key: AppTestKeys.statusState,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: withTestId(
                    AppTestKeys.statusStageId,
                    child: Text(
                      progress.stage.toUpperCase(),
                      key: AppTestKeys.statusStage,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.end,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: cs.primary,
                            letterSpacing: 1.0,
                          ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: progress.state == BackupRunState.scanning ? null : progress.fraction,
              minHeight: 8,
              borderRadius: BorderRadius.circular(4),
            ),
            const SizedBox(height: 8),
            withTestId(
              AppTestKeys.statBytesId,
              child: Text(
                '${PathSanitizer.formatBytes(progress.bytesTransferred)} / '
                '${PathSanitizer.formatBytes(progress.totalBytes)}',
                key: AppTestKeys.statBytes,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: withTestId(
                    AppTestKeys.statElapsedId,
                    child: Text(
                      'Elapsed: ${PathSanitizer.formatDuration(progress.elapsedMs)}',
                      key: AppTestKeys.statElapsed,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: withTestId(
                    AppTestKeys.statEtaId,
                    child: Text(
                      _etaLabel(progress),
                      key: AppTestKeys.statEta,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.end,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _StatCounter(
                    testId: AppTestKeys.statTransferredId,
                    valueKey: AppTestKeys.statTransferred,
                    label: 'Transferred',
                    value: progress.transferred,
                    color: AppTheme.successColor(context),
                  ),
                ),
                Expanded(
                  child: _StatCounter(
                    testId: AppTestKeys.statRemainingId,
                    valueKey: AppTestKeys.statRemaining,
                    label: 'Remaining',
                    value: progress.remaining,
                    color: cs.primary,
                  ),
                ),
                Expanded(
                  child: _StatCounter(
                    testId: AppTestKeys.statTotalId,
                    valueKey: AppTestKeys.statTotal,
                    label: 'Total',
                    value: progress.total,
                    color: cs.onSurface,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _StatCounter(
                    testId: AppTestKeys.statSkippedId,
                    valueKey: AppTestKeys.statSkipped,
                    label: 'Skipped (Verified)',
                    value: progress.skipped,
                    color: AppTheme.infoColor(context),
                  ),
                ),
                Expanded(
                  child: _StatCounter(
                    testId: AppTestKeys.statFailedId,
                    valueKey: AppTestKeys.statFailed,
                    label: 'Failed',
                    value: progress.failed,
                    color: progress.failed > 0 ? AppTheme.dangerColor(context) : cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            if (progress.currentFile.isNotEmpty) ...[
              const SizedBox(height: 12),
              withTestId(
                AppTestKeys.statusCurrentFileId,
                child: Text(
                  'Current: ${progress.currentFile}',
                  key: AppTestKeys.statusCurrentFile,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
              ),
              if (progress.showCurrentFileProgress) ...[
                const SizedBox(height: 6),
                LinearProgressIndicator(
                  value: progress.currentFileFraction,
                  minHeight: 5,
                  borderRadius: BorderRadius.circular(3),
                  color: cs.tertiary,
                  backgroundColor: cs.surfaceContainerHighest,
                ),
                const SizedBox(height: 4),
                withTestId(
                  AppTestKeys.statusCurrentFileProgressId,
                  child: Text(
                    _currentFileProgressLabel(progress),
                    key: AppTestKeys.statusCurrentFileProgress,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                          fontSize: 11.5,
                        ),
                  ),
                ),
              ],
            ],
            if (progress.errors.isNotEmpty) ...[
              const SizedBox(height: 10),
              withTestId(
                AppTestKeys.errorLogBtnId,
                child: OutlinedButton.icon(
                  key: AppTestKeys.errorLogBtn,
                  onPressed: onViewErrors,
                  icon: const Icon(Icons.error_outline, color: Colors.redAccent),
                  label: Text('View ${progress.errors.length} Error(s)'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _currentFileProgressLabel(BackupProgress progress) {
    final stageVerb = switch (progress.stage) {
      'hashing' => 'Hashing file',
      'uploading' => 'Uploading file',
      'verifying' => 'Verifying SHA-256',
      'cleaning_up' => 'Freeing local space',
      'retrying' => 'Retrying file',
      'paused' => 'Paused on file',
      _ => 'Processing file',
    };
    final pct = (progress.currentFileFraction * 100).round().clamp(0, 100);
    return '$stageVerb: $pct% '
        '(${PathSanitizer.formatBytes(progress.currentFileBytes)} / '
        '${PathSanitizer.formatBytes(progress.currentFileTotalBytes)} • '
        '${PathSanitizer.formatDuration(progress.currentFileElapsedMs)})';
  }

  static String _etaLabel(BackupProgress progress) {
    return switch (progress.state) {
      BackupRunState.paused => 'ETA: Paused',
      BackupRunState.completed => 'ETA: Done',
      BackupRunState.running when progress.etaMs != null =>
        'ETA: ~${PathSanitizer.formatDuration(progress.etaMs!)}',
      _ => 'ETA: --',
    };
  }

  static String _stateLabel(BackupRunState state) {
    return switch (state) {
      BackupRunState.idle => 'Ready',
      BackupRunState.scanning => 'Scanning Media...',
      BackupRunState.running => 'Backing Up...',
      BackupRunState.paused => 'Paused',
      BackupRunState.completed => 'Completed',
      BackupRunState.cancelled => 'Cancelled',
      BackupRunState.error => 'Finished with Errors',
    };
  }
}

class _StatCounter extends StatelessWidget {
  final String testId;
  final Key valueKey;
  final String label;
  final int value;
  final Color color;

  const _StatCounter({
    required this.testId,
    required this.valueKey,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        withTestId(
          testId,
          child: Text(
            value.toString(),
            key: valueKey,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
          ),
        ),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      ],
    );
  }
}
