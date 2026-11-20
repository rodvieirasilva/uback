import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/backup/media_exporter.dart';
import '../../core/testing/test_keys.dart';

class BatchLimitSelector extends StatelessWidget {
  final BackupLimitType limitType;
  final TextEditingController valueController;
  final FocusNode? focusNode;
  final bool enabled;
  final ValueChanged<BackupLimitType> onSelectType;
  final ValueChanged<int> onChangeValue;

  const BatchLimitSelector({
    super.key,
    required this.limitType,
    required this.valueController,
    this.focusNode,
    required this.enabled,
    required this.onSelectType,
    required this.onChangeValue,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'BATCH LIMIT (OLDEST FILES FIRST)',
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: cs.onSurfaceVariant,
                letterSpacing: 1.0,
              ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            withTestId(
              AppTestKeys.limitAllId,
              child: ChoiceChip(
                key: AppTestKeys.limitAll,
                label: const Text('All files'),
                selected: limitType == BackupLimitType.all,
                onSelected: enabled ? (_) => onSelectType(BackupLimitType.all) : null,
              ),
            ),
            withTestId(
              AppTestKeys.limitFilesId,
              child: ChoiceChip(
                key: AppTestKeys.limitFiles,
                label: const Text('Oldest X files'),
                selected: limitType == BackupLimitType.files,
                onSelected: enabled ? (_) => onSelectType(BackupLimitType.files) : null,
              ),
            ),
            withTestId(
              AppTestKeys.limitMbId,
              child: ChoiceChip(
                key: AppTestKeys.limitMb,
                label: const Text('Oldest X MB'),
                selected: limitType == BackupLimitType.megabytes,
                onSelected: enabled ? (_) => onSelectType(BackupLimitType.megabytes) : null,
              ),
            ),
          ],
        ),
        if (limitType != BackupLimitType.all) ...[
          const SizedBox(height: 10),
          withTestId(
            AppTestKeys.limitValueInputId,
            child: TextField(
              key: AppTestKeys.limitValueInput,
              controller: valueController,
              focusNode: focusNode,
              enabled: enabled,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: limitType == BackupLimitType.files
                    ? 'Number of oldest files'
                    : 'Max batch size (MB)',
                suffixText: limitType == BackupLimitType.files ? 'files' : 'MB',
              ),
              onChanged: (val) {
                final parsed = int.tryParse(val);
                if (parsed != null && parsed > 0) {
                  onChangeValue(parsed);
                }
              },
            ),
          ),
        ],
      ],
    );
  }
}
