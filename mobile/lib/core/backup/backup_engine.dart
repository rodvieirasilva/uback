import '../utils/path_sanitizer.dart';
import 'backup_planner.dart';
import 'media_exporter.dart';

/// Pure-Dart backup orchestration engine built strictly around [MediaExporter].
/// Guarantees:
/// - Oldest-first ordering & batch limiting via [BackupPlanner].
/// - Strict deletion gate in Crop Mode: `cleanUpItem` is NEVER called unless
///   `backupItem` returns `true` (post-transfer verification succeeded).
/// - Resumable / fault-tolerant continuation on single-file errors.
class BackupEngine {
  final MediaExporter exporter;

  BackupEngine({required this.exporter});

  Future<BackupProgress> run({
    required BackupMode mode,
    required String basePath,
    required String deviceFolder,
    BackupLimit? limit,
    void Function(BackupProgress progress)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final discovered = await exporter.discoverItems();
    final planned = BackupPlanner.plan(discovered, limit: limit);

    final total = planned.length;
    final totalBytes = planned.fold<int>(0, (sum, item) => sum + item.sizeBytes);
    var transferred = 0;
    var failed = 0;
    var bytesTransferred = 0;
    final errors = <BackupErrorEntry>[];

    BackupProgress snapshot(BackupRunState state, String stage, String currentFile) {
      final done = transferred + failed;
      final remaining = (total - done).clamp(0, total);
      final p = BackupProgress(
        state: state,
        stage: stage,
        total: total,
        transferred: transferred,
        skipped: 0,
        failed: failed,
        remaining: remaining,
        bytesTransferred: bytesTransferred,
        totalBytes: totalBytes,
        currentFile: currentFile,
        errors: List.unmodifiable(errors),
      );
      onProgress?.call(p);
      return p;
    }

    if (planned.isEmpty) {
      return snapshot(BackupRunState.completed, 'completed', '');
    }

    snapshot(BackupRunState.running, 'starting', '');

    for (final item in planned) {
      if (isCancelled?.call() == true) {
        return snapshot(BackupRunState.cancelled, 'cancelled', item.fileName);
      }

      final remoteDir = PathSanitizer.buildRelativeRemoteDir(
        basePath: basePath,
        deviceFolder: deviceFolder,
        sourceFolder: item.sourceFolder,
        createdAt: item.createdAt,
      );

      snapshot(BackupRunState.running, 'uploading', item.fileName);

      try {
        final verified = await exporter.backupItem(item, remoteDir);
        if (!verified) {
          failed++;
          errors.add(BackupErrorEntry(
            fileName: item.fileName,
            message: 'Transfer or SHA-256 verification failed; local file untouched.',
          ));
          snapshot(BackupRunState.running, 'error', item.fileName);
          continue;
        }

        if (mode == BackupMode.crop && !item.isSnapshot && !item.isReadOnly) {
          snapshot(BackupRunState.running, 'cleaning_up', item.fileName);
          final cleaned = await exporter.cleanUpItem(item);
          if (!cleaned) {
            failed++;
            errors.add(BackupErrorEntry(
              fileName: item.fileName,
              message: 'Verified on NAS, but local cleanup failed.',
            ));
            snapshot(BackupRunState.running, 'error', item.fileName);
            continue;
          }
        }

        transferred++;
        bytesTransferred += item.sizeBytes;
        snapshot(BackupRunState.running, 'verified', item.fileName);
      } catch (e) {
        failed++;
        errors.add(BackupErrorEntry(
          fileName: item.fileName,
          message: e.toString(),
        ));
        snapshot(BackupRunState.running, 'error', item.fileName);
      }
    }

    return snapshot(BackupRunState.completed, 'completed', '');
  }
}
