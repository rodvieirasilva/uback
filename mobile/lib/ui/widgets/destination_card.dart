import 'package:material_ui/material_ui.dart';

import '../../core/testing/test_keys.dart';

class DestinationCard extends StatelessWidget {
  final String destinationPreview;

  const DestinationCard({
    super.key,
    required this.destinationPreview,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.dns_outlined, size: 18, color: cs.primary),
                const SizedBox(width: 8),
                Text(
                  'DESTINATION (OLDEST FIRST • SHA-256 VERIFIED)',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: cs.primary,
                        letterSpacing: 0.8,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            withTestId(
              AppTestKeys.destinationPreviewId,
              child: Text(
                destinationPreview,
                key: AppTestKeys.destinationPreview,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
