import 'package:material_ui/material_ui.dart';

import '../../core/backup/media_exporter.dart';
import '../../core/testing/test_keys.dart';
import '../theme/app_theme.dart';

class ConnectionBanner extends StatelessWidget {
  final ConnectionTestResult result;

  const ConnectionBanner({super.key, required this.result});

  @override
  Widget build(BuildContext context) {
    final accent = result.ok ? AppTheme.successColor(context) : AppTheme.dangerColor(context);
    final fill = accent.withValues(alpha: 0.12);

    return withTestId(
      AppTestKeys.connectionStatusBannerId,
      child: Container(
        key: AppTestKeys.connectionStatusBanner,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: accent),
        ),
        child: Text(
          result.message,
          style: TextStyle(color: accent, fontSize: 13),
        ),
      ),
    );
  }
}
