import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:uback/core/testing/test_keys.dart';
import 'package:uback/main.dart';

Future<void> _waitForCompleted(
  WidgetTester tester, {
  Duration timeout = const Duration(seconds: 120),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 500));
    final stateFinder = find.byKey(AppTestKeys.statusState);
    if (stateFinder.evaluate().isNotEmpty) {
      final text = tester.widget<Text>(stateFinder).data ?? '';
      if (text == 'Completed' || text == 'Finished with Errors' || text == 'Cancelled') {
        await tester.pumpAndSettle();
        return;
      }
    }
  }
  fail('Timed out waiting for backup to finish.');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      'Full E2E: collapsible MediaSources (Camera, Screenshots, WhatsApp, Recordings), global oldest-first Copy, idempotent Copy, and Crop cleanup',
      (tester) async {
    await tester.pumpWidget(const UBackApp());
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // Verify clean Home UI: no destination banner, no phase jargon, zero file previews
    expect(find.textContaining('DESTINATION (OLDEST FIRST'), findsNothing);
    expect(find.byKey(AppTestKeys.appLogo), findsOneWidget);
    expect(find.byKey(AppTestKeys.appVersion), findsOneWidget);
    expect(find.textContaining('PHASE'), findsNothing);
    expect(find.textContaining('Phase'), findsNothing);
    final fileImages = find.byWidgetPredicate((w) => w is Image && w.image is FileImage);
    expect(fileImages, findsNothing);

    // Verify hierarchical Media Sources exist and estimate all 7 seeded files across all sources
    expect(find.byKey(AppTestKeys.sourceToggle('camera')), findsOneWidget);
    expect(find.byKey(AppTestKeys.sourceToggle('screenshots')), findsOneWidget);
    expect(find.byKey(AppTestKeys.sourceToggle('whatsapp')), findsOneWidget);
    expect(find.byKey(AppTestKeys.sourceToggle('recordings')), findsOneWidget);
    expect(find.byKey(AppTestKeys.mediaSourcesSummary), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(AppTestKeys.mediaSourcesSummary)).data,
      contains('Selected: 7 files'),
    );

    // Verify expanding WhatsApp -> Sent reveals sub-items cleanly
    await tester.ensureVisible(find.byKey(AppTestKeys.sourceExpand('whatsapp')));
    await tester.tap(find.byKey(AppTestKeys.sourceExpand('whatsapp')));
    await tester.pumpAndSettle();
    expect(find.byKey(AppTestKeys.sourceExpand('whatsapp.sent')), findsOneWidget);
    expect(find.byKey(AppTestKeys.sourceExpand('whatsapp.received')), findsOneWidget);

    // Collapse Media Sources section so main action controls stay compact
    await tester.ensureVisible(find.byKey(AppTestKeys.mediaSourcesCollapse));
    await tester.tap(find.byKey(AppTestKeys.mediaSourcesCollapse));
    await tester.pumpAndSettle();
    expect(find.byKey(AppTestKeys.sourceToggle('camera')), findsNothing);

    // 1. Open Settings -> confirm Destination Type + compile-time defaults -> Test Connection
    await tester.tap(find.byKey(AppTestKeys.openSettings));
    await tester.pumpAndSettle();

    expect(find.byKey(AppTestKeys.settingsDestinationType), findsOneWidget);
    final hostField = tester.widget<TextField>(find.byKey(AppTestKeys.settingsHost));
    expect(hostField.controller?.text, '10.0.2.2');

    await tester.ensureVisible(find.byKey(AppTestKeys.settingsTestConnection));
    await tester.tap(find.byKey(AppTestKeys.settingsTestConnection));
    await tester.pumpAndSettle(const Duration(seconds: 5));

    expect(find.byKey(AppTestKeys.connectionStatusBanner), findsOneWidget);
    expect(find.textContaining('Connected to smb://10.0.2.2'), findsOneWidget);

    await tester.tap(find.byKey(AppTestKeys.settingsSave));
    await tester.pumpAndSettle();

    // 2. Copy Mode + Limit: Oldest 3 files globally across ALL sources
    // (WhatsApp Voice Note 2022 + Camera Image 2023-01 + Recorded Audio 2023-04)
    await tester.ensureVisible(find.byKey(AppTestKeys.modeCopy));
    await tester.tap(find.byKey(AppTestKeys.modeCopy));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(AppTestKeys.limitFiles));
    await tester.tap(find.byKey(AppTestKeys.limitFiles));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(AppTestKeys.limitValueInput), '3');
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(AppTestKeys.startBackup));
    await tester.tap(find.byKey(AppTestKeys.startBackup));
    await _waitForCompleted(tester);

    expect(tester.widget<Text>(find.byKey(AppTestKeys.statusState)).data, 'Completed');
    expect(tester.widget<Text>(find.byKey(AppTestKeys.statTotal)).data, '3');
    expect(tester.widget<Text>(find.byKey(AppTestKeys.statTransferred)).data, '3');
    expect(tester.widget<Text>(find.byKey(AppTestKeys.statSkipped)).data, '0');
    expect(tester.widget<Text>(find.byKey(AppTestKeys.statRemaining)).data, '0');
    expect(tester.widget<Text>(find.byKey(AppTestKeys.statFailed)).data, '0');

    // 3. Copy Mode + All files -> skips 3 already SHA-256 verified files, transfers remaining 4
    await tester.ensureVisible(find.byKey(AppTestKeys.limitAll));
    await tester.tap(find.byKey(AppTestKeys.limitAll));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(AppTestKeys.startBackup));
    await tester.tap(find.byKey(AppTestKeys.startBackup));
    await _waitForCompleted(tester);

    expect(tester.widget<Text>(find.byKey(AppTestKeys.statusState)).data, 'Completed');
    expect(tester.widget<Text>(find.byKey(AppTestKeys.statTotal)).data, '7');
    expect(tester.widget<Text>(find.byKey(AppTestKeys.statSkipped)).data, '3');
    expect(tester.widget<Text>(find.byKey(AppTestKeys.statTransferred)).data, '4');
    expect(tester.widget<Text>(find.byKey(AppTestKeys.statRemaining)).data, '0');
    expect(tester.widget<Text>(find.byKey(AppTestKeys.statFailed)).data, '0');

    // 4. Crop Mode + All files -> verifies all 7 on SMB and deletes them locally (Download untouched)
    await tester.ensureVisible(find.byKey(AppTestKeys.modeCrop));
    await tester.tap(find.byKey(AppTestKeys.modeCrop));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(AppTestKeys.startBackup));
    await tester.tap(find.byKey(AppTestKeys.startBackup));
    await _waitForCompleted(tester);

    expect(tester.widget<Text>(find.byKey(AppTestKeys.statusState)).data, 'Completed');
    expect(tester.widget<Text>(find.byKey(AppTestKeys.statTotal)).data, '7');
    expect(tester.widget<Text>(find.byKey(AppTestKeys.statSkipped)).data, '7');
    expect(tester.widget<Text>(find.byKey(AppTestKeys.statFailed)).data, '0');
    expect(tester.widget<Text>(find.byKey(AppTestKeys.statRemaining)).data, '0');
  });
}
