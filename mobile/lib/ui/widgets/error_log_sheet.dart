import 'package:material_ui/material_ui.dart';

import '../../core/backup/media_exporter.dart';
import '../../core/testing/test_keys.dart';

Future<void> showErrorLogSheet(BuildContext context, List<BackupErrorEntry> errors) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Transfer Errors (${errors.length})',
              style: Theme.of(ctx).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 360),
              child: withTestId(
                AppTestKeys.errorLogListId,
                child: ListView.separated(
                  key: AppTestKeys.errorLogList,
                  shrinkWrap: true,
                  itemCount: errors.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (_, idx) {
                    final err = errors[idx];
                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(err.fileName),
                      subtitle: Text(err.message),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
