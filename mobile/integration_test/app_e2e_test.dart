import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:uback/core/testing/test_keys.dart';
import 'package:uback/main.dart';

Future<void> _waitForFinder(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 20),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 250));
    if (finder.evaluate().isNotEmpty) {
      await tester.pumpAndSettle();
      return;
    }
  }
  fail('Timed out waiting for widget: $finder');
}

Future<void> _waitForTextContains(
  WidgetTester tester,
  Key key,
  String expected, {
  Duration timeout = const Duration(seconds: 20),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 250));
    final finder = find.byKey(key);
    if (finder.evaluate().isNotEmpty) {
      final text = tester.widget<Text>(finder).data ?? '';
      if (text.contains(expected)) {
        await tester.pumpAndSettle();
        return;
      }
    }
  }
  fail('Timed out waiting for $key to contain "$expected"');
}

Future<void> _waitForCompleted(
  WidgetTester tester, {
  int? expectedTotal,
  int? expectedSkipped,
  Duration timeout = const Duration(seconds: 120),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 500));
    final stateFinder = find.byKey(AppTestKeys.statusState);
    if (stateFinder.evaluate().isNotEmpty) {
      final text = tester.widget<Text>(stateFinder).data ?? '';
      if (text == 'Completed' || text == 'Finished with Errors' || text == 'Cancelled') {
        final totalText = find.byKey(AppTestKeys.statTotal).evaluate().isNotEmpty
            ? tester.widget<Text>(find.byKey(AppTestKeys.statTotal)).data
            : null;
        final skippedText = find.byKey(AppTestKeys.statSkipped).evaluate().isNotEmpty
            ? tester.widget<Text>(find.byKey(AppTestKeys.statSkipped)).data
            : null;
        final totalOk = expectedTotal == null || totalText == '$expectedTotal';
        final skippedOk = expectedSkipped == null || skippedText == '$expectedSkipped';
        if (text != 'Completed' || (totalOk && skippedOk)) {
          await tester.pumpAndSettle();
          return;
        }
      }
    }
  }
  fail('Timed out waiting for backup to finish.');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      'Full E2E: expanded MediaSources, Custom Folders, global oldest-first Copy, idempotent Copy, and Crop cleanup',
      (tester) async {
    await tester.pumpWidget(const UBackApp());
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // Verify clean Home UI: no destination banner, no phase jargon, zero file previews
    expect(find.textContaining('DESTINATION (OLDEST FIRST'), findsNothing);
    expect(find.byKey(AppTestKeys.appLogo), findsOneWidget);
    expect(find.byKey(AppTestKeys.appVersion), findsOneWidget);
    final versionText = tester.widget<Text>(find.byKey(AppTestKeys.appVersion)).data ?? '';
    expect(versionText, isNot(contains('+')));
    expect(versionText, contains(' • '));
    expect(find.textContaining('PHASE'), findsNothing);
    expect(find.textContaining('Phase'), findsNothing);
    final fileImages = find.byWidgetPredicate((w) => w is Image && w.image is FileImage);
    expect(fileImages, findsNothing);

    // Verify hierarchical Media Sources exist and estimate the 10 built-in seeded files
    expect(find.byKey(AppTestKeys.sourceToggle('camera')), findsOneWidget);
    expect(find.byKey(AppTestKeys.sourceToggle('screenshots')), findsOneWidget);
    expect(find.byKey(AppTestKeys.sourceToggle('screen_recordings')), findsOneWidget);
    expect(find.byKey(AppTestKeys.sourceToggle('whatsapp')), findsOneWidget);
    expect(find.byKey(AppTestKeys.sourceToggle('documents')), findsOneWidget);
    expect(find.byKey(AppTestKeys.sourceToggle('downloads')), findsOneWidget);
    expect(find.byKey(AppTestKeys.sourceToggle('snapshots')), findsOneWidget);
    await _waitForTextContains(tester, AppTestKeys.mediaSourcesSummary, 'Selected: 10 files');

    // Verify Device Snapshots shows non-zero Contacts + SMS + Call Logs (3 files) and toggle it ON
    await _waitForTextContains(tester, AppTestKeys.sourceStats('snapshots'), '3 files');
    await tester.ensureVisible(find.byKey(AppTestKeys.sourceToggle('snapshots')));
    await tester.tap(find.byKey(AppTestKeys.sourceToggle('snapshots')));
    await tester.pumpAndSettle();
    await _waitForTextContains(tester, AppTestKeys.mediaSourcesSummary, 'Selected: 13 files');

    // Verify expanding WhatsApp -> Received reveals Images/Videos/Audios/Documents
    await tester.ensureVisible(find.byKey(AppTestKeys.sourceExpand('whatsapp')));
    await tester.tap(find.byKey(AppTestKeys.sourceExpand('whatsapp')));
    await tester.pumpAndSettle();
    expect(find.byKey(AppTestKeys.sourceExpand('whatsapp.sent')), findsOneWidget);
    expect(find.byKey(AppTestKeys.sourceExpand('whatsapp.received')), findsOneWidget);

    // 1. Open Settings -> confirm Destination Type, add Custom Folder (DJI/Media), and Test Connection
    await tester.tap(find.byKey(AppTestKeys.openSettings));
    await tester.pumpAndSettle();

    expect(find.byKey(AppTestKeys.settingsDestinationType), findsOneWidget);
    final hostField = tester.widget<TextField>(find.byKey(AppTestKeys.settingsHost));
    expect(hostField.controller?.text, '10.0.2.2');

    await tester.ensureVisible(find.byKey(AppTestKeys.settingsBrowseCustomFolder));
    expect(find.byKey(AppTestKeys.settingsBrowseCustomFolder), findsOneWidget);
    await tester.ensureVisible(find.byKey(AppTestKeys.settingsCustomFolderPath));
    await tester.enterText(find.byKey(AppTestKeys.settingsCustomFolderPath), 'DJI/Media');
    await tester.enterText(find.byKey(AppTestKeys.settingsCustomFolderName), 'DJI Drone');
    await tester.ensureVisible(find.byKey(AppTestKeys.settingsAddCustomFolder));
    await tester.tap(find.byKey(AppTestKeys.settingsAddCustomFolder));
    await _waitForFinder(
      tester,
      find.byKey(AppTestKeys.settingsRemoveCustomFolder('custom.dji-media')),
    );

    await tester.ensureVisible(find.byKey(AppTestKeys.settingsTestConnection));
    await tester.tap(find.byKey(AppTestKeys.settingsTestConnection));
    await _waitForFinder(tester, find.byKey(AppTestKeys.connectionStatusBanner));

    expect(find.byKey(AppTestKeys.connectionStatusBanner), findsOneWidget);
    expect(find.textContaining('Connected to smb://10.0.2.2'), findsOneWidget);

    await tester.ensureVisible(find.byKey(AppTestKeys.settingsSave));
    await tester.tap(find.byKey(AppTestKeys.settingsSave));
    await _waitForFinder(tester, find.byKey(AppTestKeys.modeCopy));

    // Confirm Custom Folder bumped live count from 13 -> 14 files, then collapse Media Sources
    await _waitForTextContains(tester, AppTestKeys.mediaSourcesSummary, 'Selected: 14 files');
    await tester.ensureVisible(find.byKey(AppTestKeys.mediaSourcesCollapse));
    await tester.tap(find.byKey(AppTestKeys.mediaSourcesCollapse));
    await tester.pumpAndSettle();
    expect(find.byKey(AppTestKeys.sourceToggle('camera')), findsNothing);

    // 2. Copy Mode + Limit: Oldest 3 files globally across ALL sources
    // (WhatsApp Voice Note 2022 + Camera Image 2023-01 + WhatsApp Document 2023-02)
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
    await _waitForCompleted(tester, expectedTotal: 3, expectedSkipped: 0);

    expect(tester.widget<Text>(find.byKey(AppTestKeys.statusState)).data, 'Completed');
    expect(tester.widget<Text>(find.byKey(AppTestKeys.statTotal)).data, '3');
    expect(tester.widget<Text>(find.byKey(AppTestKeys.statTransferred)).data, '3');
    expect(tester.widget<Text>(find.byKey(AppTestKeys.statSkipped)).data, '0');
    expect(tester.widget<Text>(find.byKey(AppTestKeys.statRemaining)).data, '0');
    expect(tester.widget<Text>(find.byKey(AppTestKeys.statFailed)).data, '0');

    // 2b. Simulate full app restart (brand-new BackupController loading real Android SharedPreferences + Keystore)
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await tester.pumpWidget(UBackApp(key: UniqueKey()));
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // Verify saved session state restored: Copy mode, Limit=files(3), Media Sources collapsed,
    // custom folder DJI/Media persisted (11 files total), and expanded WhatsApp sub-group remembered!
    expect(find.text('Start Copy Backup'), findsOneWidget);
    expect(find.byKey(AppTestKeys.limitValueInput), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byKey(AppTestKeys.limitValueInput)).controller?.text,
      '3',
    );
    expect(find.byKey(AppTestKeys.sourceToggle('camera')), findsNothing);
    await _waitForTextContains(tester, AppTestKeys.mediaSourcesSummary, 'Selected: 14 files');

    // Expand Media Sources and verify custom folder + WhatsApp expanded sub-group were restored
    await tester.ensureVisible(find.byKey(AppTestKeys.mediaSourcesCollapse));
    await tester.tap(find.byKey(AppTestKeys.mediaSourcesCollapse));
    await tester.pumpAndSettle();
    expect(find.byKey(AppTestKeys.sourceExpand('whatsapp.sent')), findsOneWidget);
    expect(find.byKey(AppTestKeys.sourceToggle('custom')), findsOneWidget);

    // Re-collapse Media Sources for compact layout
    await tester.ensureVisible(find.byKey(AppTestKeys.mediaSourcesCollapse));
    await tester.tap(find.byKey(AppTestKeys.mediaSourcesCollapse));
    await tester.pumpAndSettle();

    // 3. Copy Mode + All files -> skips 3 already SHA-256 verified files, transfers remaining 11
    // (8 media/doc/custom files + 3 Device Snapshots: Contacts, SMS, Call Logs)
    await tester.ensureVisible(find.byKey(AppTestKeys.limitAll));
    await tester.tap(find.byKey(AppTestKeys.limitAll));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(AppTestKeys.startBackup));
    await tester.tap(find.byKey(AppTestKeys.startBackup));
    await _waitForCompleted(tester, expectedTotal: 14, expectedSkipped: 3);

    expect(tester.widget<Text>(find.byKey(AppTestKeys.statusState)).data, 'Completed');
    expect(tester.widget<Text>(find.byKey(AppTestKeys.statTotal)).data, '14');
    expect(tester.widget<Text>(find.byKey(AppTestKeys.statSkipped)).data, '3');
    expect(tester.widget<Text>(find.byKey(AppTestKeys.statTransferred)).data, '11');
    expect(tester.widget<Text>(find.byKey(AppTestKeys.statRemaining)).data, '0');
    expect(tester.widget<Text>(find.byKey(AppTestKeys.statFailed)).data, '0');

    // 4. Crop Mode + All files -> verifies all 14 on SMB, deletes 11 media/doc files locally,
    // and keeps Download + real Contacts/SMS/Call Logs strictly untouched!
    await tester.ensureVisible(find.byKey(AppTestKeys.modeCrop));
    await tester.tap(find.byKey(AppTestKeys.modeCrop));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(AppTestKeys.startBackup));
    await tester.tap(find.byKey(AppTestKeys.startBackup));
    await _waitForCompleted(tester, expectedTotal: 14, expectedSkipped: 14);

    expect(tester.widget<Text>(find.byKey(AppTestKeys.statusState)).data, 'Completed');
    expect(tester.widget<Text>(find.byKey(AppTestKeys.statTotal)).data, '14');
    expect(tester.widget<Text>(find.byKey(AppTestKeys.statSkipped)).data, '14');
    expect(tester.widget<Text>(find.byKey(AppTestKeys.statFailed)).data, '0');
    expect(tester.widget<Text>(find.byKey(AppTestKeys.statRemaining)).data, '0');

    // 5. Restart app once more -> confirm Crop Mode & Limit=All persisted across restart!
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await tester.pumpWidget(UBackApp(key: UniqueKey()));
    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(find.text('Start Crop Backup'), findsOneWidget);
    expect(find.byKey(AppTestKeys.limitValueInput), findsNothing);
  });
}
